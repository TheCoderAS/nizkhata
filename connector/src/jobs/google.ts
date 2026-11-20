// Admin access for the scheduled jobs: a Firebase service account, exchanged
// for a short-lived Google OAuth token (the JWT bearer grant), for Firestore
// and Firebase Cloud Messaging.
//
// This is the ONLY place the backend holds more than one person's access, and
// only the scheduled jobs use it. The assistant's tools never see it: they act
// with the signed-in person's own Firebase token, under the security rules.

import { createSign } from 'node:crypto';

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
}

/** FIREBASE_SERVICE_ACCOUNT as raw JSON or base64 of it. */
export function parseServiceAccount(raw: string | undefined): ServiceAccount | null {
  let v = raw?.trim();
  if (!v) return null;
  // Pasted with its surrounding quotes, as some dashboards keep them.
  if (v.startsWith("'") && v.endsWith("'")) v = v.slice(1, -1).trim();
  if (v.startsWith('"')) {
    try {
      const inner = JSON.parse(v) as unknown; // the key file as a quoted JSON string
      if (typeof inner === 'string') v = inner.trim();
    } catch {
      /* not a quoted string; parsed below */
    }
  }
  const json = v.startsWith('{') ? v : Buffer.from(v, 'base64').toString('utf8');
  let sa: ServiceAccount;
  try {
    sa = JSON.parse(json) as ServiceAccount;
  } catch {
    throw new Error('not valid JSON (paste the whole key file, or its base64)');
  }
  // A key whose line breaks arrived as the two characters \ and n.
  if (typeof sa.private_key === 'string' && !sa.private_key.includes('\n') && sa.private_key.includes('\\n')) {
    sa.private_key = sa.private_key.replace(/\\n/g, '\n');
  }
  if (!sa.client_email || !sa.private_key || !sa.project_id) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT is missing client_email, private_key or project_id');
  }
  return sa;
}

const SCOPES = ['https://www.googleapis.com/auth/datastore', 'https://www.googleapis.com/auth/firebase.messaging'];

/** A cached access token for [sa], renewed a few minutes before it lapses. */
export function googleTokenSource(sa: ServiceAccount, fetchImpl: typeof fetch = fetch): () => Promise<string> {
  let cached: { token: string; exp: number } | null = null;
  return async () => {
    const now = Math.floor(Date.now() / 1000);
    if (cached && cached.exp - 300 > now) return cached.token;
    const aud = sa.token_uri ?? 'https://oauth2.googleapis.com/token';
    const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
    const unsigned = `${b64({ alg: 'RS256', typ: 'JWT' })}.${b64({ iss: sa.client_email, scope: SCOPES.join(' '), aud, iat: now, exp: now + 3600 })}`;
    const signature = createSign('RSA-SHA256').update(unsigned).sign(sa.private_key).toString('base64url');
    const res = await fetchImpl(aud, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${signature}` }),
    });
    const body = (await res.json()) as { access_token?: string; expires_in?: number; error_description?: string };
    if (!res.ok || !body.access_token) throw new Error(`Service account sign-in failed: ${body.error_description ?? res.status}`);
    cached = { token: body.access_token, exp: now + (body.expires_in ?? 3600) };
    return cached.token;
  };
}
