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
Every amount is in its workspace's currency (list_workspaces). Amounts you send are always positive; the line type or direction decides which way money moves.
To add a transaction you need an account_id (list_accounts) and, for income or expense, a category_id (list_categories). Look ids up instead of guessing them.
Before deleting anything, or writing on the person's behalf, say what you are about to do.`;

export function buildMcpServer(ctx: () => Ctx): McpServer {
  const server = new McpServer({ name: 'niz-khata', version: '1.0.0' }, { instructions: INSTRUCTIONS });
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
  app.get('/', (_req, res) => res.type('text').send('Niz Khata connector. Add this server to Claude or ChatGPT: ' + `${cfg.publicUrl}/mcp`));
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
    const server = buildMcpServer(() => ctx);
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
