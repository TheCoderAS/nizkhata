import { fileURLToPath } from 'node:url';
import express, { type Express } from 'express';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';

import { Books } from './books.js';
import type { Config } from './config.js';
import { Sealer } from './crypto.js';
import { actorOf, FirebaseAuth, SessionExpired } from './firebase.js';
import { Firestore } from './firestore.js';
import { oauthRouter, type AccessPayload } from './oauth.js';
import type { Ctx } from './tools/common.js';
import { registerCategoryTools } from './tools/categories.js';
import { registerContactTools } from './tools/contacts.js';
import { registerDebtTools } from './tools/debts.js';
import { registerDueTools } from './tools/dues.js';
import { registerTransactionTools } from './tools/transactions.js';
import { registerWorkspaceTools } from './tools/workspaces.js';

const INSTRUCTIONS = `Niz Khata is a money ledger: accounts, transactions, dues (bills to pay and money to receive on a date), debts (money lent and borrowed, per person), contacts, categories and budgets, kept in workspaces.
If the person has more than one workspace, call list_workspaces, ask which one they mean, and pass that workspace_id on every call; switch only when they name another.
Every amount is in its workspace's currency (list_workspaces). Amounts you send are always positive; the line type or direction decides which way money moves.
To add a transaction you need an account_id (list_accounts) and, for income or expense, a category_id (list_categories). Look ids up instead of guessing them.
Before deleting anything, or writing on the person's behalf, say what you are about to do.`;

/** The app icon, served from public/, so assistants show Niz Khata rather than the parent domain's. */
const PUBLIC_DIR = fileURLToPath(new URL('../public', import.meta.url));

export function icons(publicUrl: string) {
  return [
    { src: `${publicUrl}/icon-180.png`, mimeType: 'image/png', sizes: ['180x180'] },
    { src: `${publicUrl}/icon-48.png`, mimeType: 'image/png', sizes: ['48x48'] },
  ];
}

export function buildMcpServer(ctx: () => Ctx, publicUrl?: string): McpServer {
  const server = new McpServer(
    {
      name: 'niz-khata',
      title: 'Niz Khata',
      version: '1.0.0',
      websiteUrl: 'https://nizkhata.valorumlabs.com',
      ...(publicUrl ? { icons: icons(publicUrl) } : {}),
    },
    { instructions: INSTRUCTIONS },
  );
  for (const register of [
    registerWorkspaceTools,
    registerContactTools,
    registerCategoryTools,
    registerDueTools,
    registerDebtTools,
    registerTransactionTools,
  ]) {
    register(server, ctx);
  }
  return server;
}

export function buildApp(cfg: Config, fetchImpl: typeof fetch = fetch): Express {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', true);
  const sealer = new Sealer(cfg.tokenSecret);
  const auth = new FirebaseAuth(cfg, fetchImpl);

  app.get('/healthz', (_req, res) => res.json({ ok: true }));
  app.use(express.static(PUBLIC_DIR, { index: false, maxAge: '7d' }));
  app.get('/', (_req, res) =>
    res.type('html').send(
      `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">` +
        `<title>Niz Khata connector</title><link rel="icon" href="/favicon.ico" sizes="any"><link rel="icon" type="image/png" sizes="48x48" href="/icon-48.png">` +
        `<link rel="apple-touch-icon" href="/icon-180.png"></head><body style="font-family:system-ui,sans-serif;max-width:36rem;margin:3rem auto;padding:0 1rem;line-height:1.5">` +
        `<img src="/icon-180.png" alt="" width="64" height="64"><h1>Niz Khata connector</h1>` +
        `<p>Add this server to Claude or ChatGPT as a custom connector:</p><p><code>${cfg.publicUrl}/mcp</code></p>` +
        `<p><a href="https://nizkhata.valorumlabs.com">Niz Khata</a> by <a href="https://valorumlabs.com">Valorum Labs</a> · <a href="https://nizkhata.valorumlabs.com/privacy">Privacy</a></p></body></html>`,
    ),
  );
  app.use(oauthRouter(cfg, sealer, auth, fetchImpl));

  const unauthorized = (res: express.Response, message: string) => {
    res
      .status(401)
      .set('WWW-Authenticate', `Bearer resource_metadata="${cfg.publicUrl}/.well-known/oauth-protected-resource", error="invalid_token"`)
      .json({ error: 'invalid_token', error_description: message });
  };

  app.post('/mcp', express.json({ limit: '1mb' }), async (req, res) => {
    const header = req.get('authorization') ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    const p = token ? sealer.open<AccessPayload>('access', token) : null;
    if (!p) return unauthorized(res, 'Sign in to Niz Khata to use this connector.');
    let idToken: string;
    try {
      idToken = await auth.idToken(p.rt);
    } catch (e) {
      if (e instanceof SessionExpired) return unauthorized(res, e.message);
      res.status(502).json({ error: 'upstream', error_description: 'Could not reach Firebase.' });
      return;
    }
    const fs = new Firestore(cfg.firestoreBaseUrl, idToken, fetchImpl);
    const actor = actorOf(p);
    const ctx: Ctx = {
      fs,
      actor,
      timeZone: cfg.timeZone,
      books: (workspaceId?: string) => Books.open(fs, actor, cfg.timeZone, workspaceId),
    };
    // Stateless: a fresh server and transport per request, as the SDK
    // recommends, so no person's state can leak into another's.
    const server = buildMcpServer(() => ctx, cfg.publicUrl);
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
    res.on('close', () => {
      void transport.close();
      void server.close();
    });
    try {
      await server.connect(transport);
      await transport.handleRequest(req, res, req.body);
    } catch {
      if (!res.headersSent) res.status(500).json({ jsonrpc: '2.0', error: { code: -32603, message: 'Internal error' }, id: null });
    }
  });
  // Stateless server: no event stream to open, no session to end.
  app.get('/mcp', (_req, res) => res.status(405).set('allow', 'POST').end());
  app.delete('/mcp', (_req, res) => res.status(405).set('allow', 'POST').end());

  return app;
}
