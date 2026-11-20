// OAuth 2.1 for MCP clients (Claude, ChatGPT): metadata discovery, dynamic
// client registration, authorization with PKCE, and tokens.
//
// Signing in is Google sign-in into the person's own Firebase account. The
// tokens handed to the AI client are sealed (see crypto.ts) and carry that
// Firebase session; nothing is stored on the server.

import express, { type Request, type Response, type Router } from 'express';

import type { Config } from './config.js';
import { pkceChallenge, Sealer } from './crypto.js';
import type { FirebaseAuth } from './firebase.js';

export const ACCESS_TTL = 3600;
export const REFRESH_TTL = 90 * 24 * 3600;
const CODE_TTL = 300;
const STATE_TTL = 600;

interface ClientInfo { r: string[]; n: string }
interface AuthState { cid: string; ru: string; cc: string; st?: string; scope?: string }
interface CodePayload { rt: string; uid: string; name: string; email: string; cid: string; ru: string; cc: string }
export interface AccessPayload { rt: string; uid: string; name: string; email: string }
interface RefreshPayload extends AccessPayload { cid: string }

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

/** Redirect URIs a client may register: https anywhere, or http on the loopback interface. */
export function allowedRedirect(uri: string): boolean {
  try {
    const u = new URL(uri);
    if (u.hash) return false;
    if (u.protocol === 'https:') return true;
    return u.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(u.hostname);
  } catch {
    return false;
  }
}

export function oauthRouter(cfg: Config, sealer: Sealer, auth: FirebaseAuth, fetchImpl: typeof fetch = fetch): Router {
  const r = express.Router();
  const base = cfg.publicUrl;
  const googleCallback = `${base}/oauth/google/callback`;

  const resourceMeta = (_req: Request, res: Response) =>
    res.json({
      resource: `${base}/mcp`,
      authorization_servers: [base],
      scopes_supported: ['books'],
      bearer_methods_supported: ['header'],
      resource_name: 'Niz Khata',
    });
  r.get('/.well-known/oauth-protected-resource', resourceMeta);
  r.get('/.well-known/oauth-protected-resource/mcp', resourceMeta);

  r.get('/.well-known/oauth-authorization-server', (_req, res) =>
    res.json({
      issuer: base,
      authorization_endpoint: `${base}/authorize`,
      token_endpoint: `${base}/token`,
      registration_endpoint: `${base}/register`,
      response_types_supported: ['code'],
      grant_types_supported: ['authorization_code', 'refresh_token'],
      code_challenge_methods_supported: ['S256'],
      token_endpoint_auth_methods_supported: ['none'],
      scopes_supported: ['books'],
      service_documentation: 'https://nizkhata.valorumlabs.com',
    }),
  );

  // Dynamic client registration (RFC 7591). The client id IS the sealed
  // registration, so there is nothing to store.
  r.post('/register', express.json(), (req, res) => {
    const uris = (req.body?.redirect_uris ?? []) as unknown;
    if (!Array.isArray(uris) || uris.length === 0 || uris.length > 10 || !uris.every((u) => typeof u === 'string' && allowedRedirect(u))) {
      res.status(400).json({ error: 'invalid_redirect_uri', error_description: 'redirect_uris must be https URLs (or http on localhost).' });
      return;
    }
    const name = String(req.body?.client_name ?? 'AI assistant').slice(0, 80);
    const clientId = sealer.seal<ClientInfo>('client', { r: uris as string[], n: name }, 0);
    res.status(201).json({
      client_id: clientId,
      client_id_issued_at: Math.floor(Date.now() / 1000),
      client_name: name,
      redirect_uris: uris,
      token_endpoint_auth_method: 'none',
      grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'],
    });
  });

  r.get('/authorize', (req, res) => {
    const q = req.query as Record<string, string | undefined>;
    const client = q.client_id ? sealer.open<ClientInfo>('client', q.client_id) : null;
    if (!client) return void res.status(400).send(page('Unknown app', 'This connection request did not come from a registered app. Start again from your AI assistant.'));
    if (!q.redirect_uri || !client.r.includes(q.redirect_uri)) {
      return void res.status(400).send(page('Wrong return address', 'The app asked to return somewhere it did not register.'));
    }
    const back = (params: Record<string, string>) => {
      const u = new URL(q.redirect_uri!);
      for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
      if (q.state) u.searchParams.set('state', q.state);
      res.redirect(302, u.toString());
    };
    if (q.response_type !== 'code') return back({ error: 'unsupported_response_type' });
    if (!q.code_challenge || (q.code_challenge_method ?? 'S256') !== 'S256') {
      return back({ error: 'invalid_request', error_description: 'PKCE with S256 is required.' });
    }
    const state = sealer.seal<AuthState>('state', { cid: q.client_id!, ru: q.redirect_uri, cc: q.code_challenge, st: q.state, scope: q.scope }, STATE_TTL);
    const google = new URL(cfg.googleAuthUrl);
    google.search = new URLSearchParams({
      client_id: cfg.googleClientId,
      redirect_uri: googleCallback,
      response_type: 'code',
      scope: 'openid email profile',
      prompt: 'select_account',
      state,
    }).toString();
    res
      .status(200)
      .type('html')
      .send(
        page(
          'Connect Niz Khata',
          `<p><b>${esc(client.n)}</b> wants to read and update your Niz Khata books: accounts, transactions, dues, debts, contacts, categories and budgets.</p>
           <p>It acts as you, so it can only see and change what your role in each workspace allows. You can disconnect it from the assistant at any time.</p>
           <p><a class="btn" href="${esc(google.toString())}">Continue with Google</a></p>
           <p class="small">Sign in with the Google account you use in Niz Khata.</p>`,
        ),
      );
  });

  r.get('/oauth/google/callback', async (req, res) => {
    const q = req.query as Record<string, string | undefined>;
    const st = q.state ? sealer.open<AuthState>('state', q.state) : null;
    if (!st) return void res.status(400).send(page('Sign-in expired', 'That sign-in took too long or was already used. Start again from your AI assistant.'));
    const back = (params: Record<string, string>) => {
      const u = new URL(st.ru);
      for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
      if (st.st) u.searchParams.set('state', st.st);
      res.redirect(302, u.toString());
    };
    if (q.error || !q.code) return back({ error: 'access_denied' });
    try {
      const tr = await fetchImpl(cfg.googleTokenUrl, {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          code: q.code,
          client_id: cfg.googleClientId,
          client_secret: cfg.googleClientSecret,
          redirect_uri: googleCallback,
          grant_type: 'authorization_code',
        }).toString(),
      });
      const tj = (await tr.json()) as { id_token?: string };
      if (!tr.ok || !tj.id_token) throw new Error('Google sign-in failed');
      const session = await auth.signInWithGoogle(tj.id_token);
      const code = sealer.seal<CodePayload>(
        'code',
        { rt: session.refreshToken, uid: session.uid, name: session.name, email: session.email, cid: st.cid, ru: st.ru, cc: st.cc },
        CODE_TTL,
      );
      back({ code });
    } catch {
      back({ error: 'server_error', error_description: 'Signing in with Google did not complete.' });
    }
  });

  r.post('/token', express.urlencoded({ extended: false }), express.json(), (req, res) => {
    const b = (req.body ?? {}) as Record<string, string | undefined>;
    const fail = (error: string, description: string, status = 400) =>
      res.status(status).json({ error, error_description: description });
    res.setHeader('cache-control', 'no-store');
    if (b.grant_type === 'authorization_code') {
      const c = b.code ? sealer.open<CodePayload>('code', b.code) : null;
      if (!c) return fail('invalid_grant', 'The code is invalid or has expired.');
      if (b.client_id && b.client_id !== c.cid) return fail('invalid_grant', 'The code was issued to another app.');
      if (b.redirect_uri && b.redirect_uri !== c.ru) return fail('invalid_grant', 'redirect_uri does not match.');
      if (!b.code_verifier || pkceChallenge(b.code_verifier) !== c.cc) return fail('invalid_grant', 'PKCE verification failed.');
      return res.json(issue({ rt: c.rt, uid: c.uid, name: c.name, email: c.email }, c.cid));
    }
    if (b.grant_type === 'refresh_token') {
      const p = b.refresh_token ? sealer.open<RefreshPayload>('refresh', b.refresh_token) : null;
      if (!p) return fail('invalid_grant', 'The refresh token is invalid or has expired.');
      if (b.client_id && b.client_id !== p.cid) return fail('invalid_grant', 'The token was issued to another app.');
      return res.json(issue({ rt: p.rt, uid: p.uid, name: p.name, email: p.email }, p.cid));
    }
    return fail('unsupported_grant_type', 'Use authorization_code or refresh_token.');
  });

  function issue(p: AccessPayload, cid: string) {
    return {
      access_token: sealer.seal<AccessPayload>('access', p, ACCESS_TTL),
      token_type: 'Bearer',
      expires_in: ACCESS_TTL,
      refresh_token: sealer.seal<RefreshPayload>('refresh', { ...p, cid }, REFRESH_TTL),
      scope: 'books',
    };
  }

  return r;
}

function page(title: string, body: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)} · Niz Khata</title>
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0B0F1C;color:#ECEEF6;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:440px;margin:24px 16px;padding:32px;border-radius:24px;background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.1)}
h1{margin:0 0 14px;font-size:24px}p{color:#C9CEDD;line-height:1.55}.small{font-size:13px;color:#9AA3B8}
.btn{display:inline-block;margin-top:6px;padding:13px 22px;border-radius:14px;color:#fff;text-decoration:none;font-weight:600;background:linear-gradient(90deg,#4F46E5,#7C3AED)}</style>
</head><body><main><h1>${esc(title)}</h1>${body}</main></body></html>`;
}
