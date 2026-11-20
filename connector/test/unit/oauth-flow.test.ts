// The whole connection flow an AI assistant goes through, over real HTTP,
// with Google and Firebase stubbed: register, authorize, sign in, exchange
// the code with PKCE, refresh, then call the MCP endpoint.
import { createHash, randomBytes } from 'node:crypto';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

import { loadConfig } from '../../src/config.js';
import { buildApp } from '../../src/server.js';

let base = '';
let server: Server;
const upstreamCalls: string[] = [];

const upstream = (async (url: string | URL, init?: RequestInit) => {
  const u = String(url);
  upstreamCalls.push(u);
  if (u.startsWith('https://oauth2.googleapis.com/token')) {
    const body = new URLSearchParams(String(init?.body));
    if (body.get('code') !== 'google-code') return new Response('{"error":"invalid_grant"}', { status: 400 });
    return Response.json({ id_token: 'google-id-token' });
  }
  if (u.includes('accounts:signInWithIdp')) {
    return Response.json({ localId: 'uid-1', refreshToken: 'fb-refresh', idToken: 'fb-id', expiresIn: '3600', email: 'A@Example.com', displayName: 'Asha' });
  }
  if (u.includes('securetoken')) return Response.json({ id_token: 'fb-id-2', expires_in: '3600' });
  return new Response('not stubbed', { status: 500 });
}) as typeof fetch;

beforeAll(async () => {
  // Listen first, so the server can be told its real public address.
  server = createServer();
  server.listen(0);
  await new Promise((r) => server.once('listening', r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const cfg = loadConfig({
    PUBLIC_URL: base,
    FIREBASE_API_KEY: 'k', GOOGLE_CLIENT_ID: 'gcid', GOOGLE_CLIENT_SECRET: 'gsecret',
    TOKEN_SECRET: 's'.repeat(40),
  } as NodeJS.ProcessEnv);
  server.on('request', buildApp(cfg, upstream));
});
afterAll(() => server.close());

const pkce = () => {
  const verifier = randomBytes(32).toString('base64url');
  return { verifier, challenge: createHash('sha256').update(verifier).digest('base64url') };
};

async function connect() {
  const reg = await fetch(`${base}/register`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ client_name: 'Claude', redirect_uris: ['https://claude.ai/api/mcp/auth_callback'] }),
  });
  expect(reg.status).toBe(201);
  const { client_id } = await reg.json();
  const { verifier, challenge } = pkce();
  const auth = await fetch(`${base}/authorize?` + new URLSearchParams({
    response_type: 'code', client_id, redirect_uri: 'https://claude.ai/api/mcp/auth_callback',
    code_challenge: challenge, code_challenge_method: 'S256', state: 'xyz',
  }));
  const html = await auth.text();
  expect(auth.status).toBe(200);
  expect(html).toContain('Claude</b> wants to read and update your Niz Khata books');
  const googleUrl = new URL(html.match(/href="([^"]+)"/)![1]!.replace(/&amp;/g, '&'));
  expect(googleUrl.origin + googleUrl.pathname).toBe('https://accounts.google.com/o/oauth2/v2/auth');
  expect(googleUrl.searchParams.get('redirect_uri')).toBe(`${base}/oauth/google/callback`);
  const cb = await fetch(`${base}/oauth/google/callback?` + new URLSearchParams({ code: 'google-code', state: googleUrl.searchParams.get('state')! }), { redirect: 'manual' });
  expect(cb.status).toBe(302);
  const back = new URL(cb.headers.get('location')!);
  expect(back.origin + back.pathname).toBe('https://claude.ai/api/mcp/auth_callback');
  expect(back.searchParams.get('state')).toBe('xyz');
  return { client_id, verifier, code: back.searchParams.get('code')! };
}

const token = (params: Record<string, string>) =>
  fetch(`${base}/token`, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(params) });

describe('discovery', () => {
  it('points an unauthenticated MCP call at the metadata', async () => {
    const r = await fetch(`${base}/mcp`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
    expect(r.status).toBe(401);
    expect(r.headers.get('www-authenticate')).toContain(`resource_metadata="${base}/.well-known/oauth-protected-resource"`);
    const meta = await (await fetch(`${base}/.well-known/oauth-authorization-server`)).json();
    expect(meta.code_challenge_methods_supported).toEqual(['S256']);
    expect(meta.registration_endpoint).toBe(`${base}/register`);
  });

  it('refuses a redirect to a plain http address that is not this machine', async () => {
    const r = await fetch(`${base}/register`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ redirect_uris: ['http://evil.example/cb'] }) });
    expect(r.status).toBe(400);
  });
});

describe('signing in', () => {
  it('a wrong PKCE verifier gets nothing', async () => {
    const { client_id, code } = await connect();
    const r = await token({ grant_type: 'authorization_code', code, client_id, code_verifier: 'wrong'.repeat(10), redirect_uri: 'https://claude.ai/api/mcp/auth_callback' });
    expect(r.status).toBe(400);
    expect((await r.json()).error).toBe('invalid_grant');
  });

  it('the right one gets tokens, refresh works, and the MCP endpoint answers', async () => {
    const { client_id, verifier, code } = await connect();
    const r = await token({ grant_type: 'authorization_code', code, client_id, code_verifier: verifier, redirect_uri: 'https://claude.ai/api/mcp/auth_callback' });
    expect(r.status).toBe(200);
    const t = await r.json();
    expect(t.token_type).toBe('Bearer');
    // Nothing secret is readable in the tokens handed to the assistant.
    expect(t.access_token).not.toContain('fb-refresh');

    const again = await (await token({ grant_type: 'refresh_token', refresh_token: t.refresh_token, client_id })).json();
    expect(again.access_token).toBeTruthy();

    const client = new Client({ name: 'test', version: '1' });
    await client.connect(new StreamableHTTPClientTransport(new URL(`${base}/mcp`), {
      requestInit: { headers: { authorization: `Bearer ${again.access_token}` } },
    }));
    const tools = (await client.listTools()).tools.map((x) => x.name).sort();
    expect(tools).toEqual([
      'create_budget', 'create_category', 'create_contact', 'create_debt', 'create_due', 'create_transaction',
      'delete_budget', 'delete_category', 'delete_contact', 'delete_debt', 'delete_due', 'delete_transaction',
      'get_contact', 'get_transaction',
      'list_accounts', 'list_budgets', 'list_categories', 'list_contacts', 'list_debts', 'list_dues', 'list_transactions', 'list_workspaces',
      'record_debt_repayment', 'record_due_payment',
      'update_budget', 'update_category', 'update_contact', 'update_debt', 'update_due', 'update_transaction',
    ]);
    const deletes = (await client.listTools()).tools.filter((x) => x.name.startsWith('delete_'));
    expect(deletes.every((x) => x.annotations?.destructiveHint === true)).toBe(true);
    // The assistant shows Niz Khata's own icon, not the parent domain's.
    const info = client.getServerVersion();
    expect(info?.title).toBe('Niz Khata');
    expect(info?.icons?.[0]?.src).toBe(`${base}/icon-180.png`);
    await client.close();
  });

  it('serves its own favicon and icons', async () => {
    for (const [path, type] of [['/favicon.ico', 'image/'], ['/icon-48.png', 'image/png'], ['/icon-180.png', 'image/png']] as const) {
      const r = await fetch(base + path);
      expect(r.status, path).toBe(200);
      expect(r.headers.get('content-type'), path).toContain(type);
    }
    const home = await (await fetch(base + '/')).text();
    expect(home).toContain('rel="icon"');
    expect(home).toContain(`${base}/mcp`);
  });
});
