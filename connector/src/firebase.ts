// Firebase sign-in over REST: turn a Google sign-in into the person's own
// Firebase session, and keep a short-lived ID token fresh from its refresh
// token. The same Firebase account the app uses, so the same uid, the same
// workspaces, the same rules.

import type { Config } from './config.js';
import type { Actor } from './books.js';

export interface FirebaseSession {
  uid: string;
  refreshToken: string;
  name: string;
  email: string;
}

/** The app's Actor.fromUser: display name, else email, else a uid prefix. */
export function actorName(displayName: string | undefined, email: string | undefined, uid: string): string {
  const d = displayName?.trim();
  if (d) return d;
  if (email) return email.toLowerCase();
  return `${uid.slice(0, 8)}…`;
}

export class FirebaseAuth {
  private readonly cache = new Map<string, { idToken: string; exp: number }>();

  constructor(
    private readonly cfg: Config,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  /** Sign in to Firebase with a Google ID token, as the app's Google sign-in does. */
  async signInWithGoogle(googleIdToken: string): Promise<FirebaseSession> {
    const res = await this.fetchImpl(
      `${this.cfg.identityBaseUrl}/accounts:signInWithIdp?key=${encodeURIComponent(this.cfg.firebaseApiKey)}`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          postBody: `id_token=${encodeURIComponent(googleIdToken)}&providerId=google.com`,
          requestUri: this.cfg.publicUrl,
          returnSecureToken: true,
          returnIdpCredential: true,
        }),
      },
    );
    const j = (await res.json()) as Record<string, string> & { error?: { message?: string } };
    if (!res.ok || !j.refreshToken || !j.localId) {
      throw new Error(`Firebase sign-in failed: ${j.error?.message ?? res.status}`);
    }
    if (j.idToken && j.expiresIn) {
      this.cache.set(j.refreshToken, { idToken: j.idToken, exp: Date.now() + (Number(j.expiresIn) - 120) * 1000 });
    }
    return {
      uid: j.localId,
      refreshToken: j.refreshToken,
      email: (j.email ?? '').toLowerCase(),
      name: actorName(j.displayName, j.email, j.localId),
    };
  }

  /** A current Firebase ID token for the session, refreshed when it is near expiry. */
  async idToken(refreshToken: string): Promise<string> {
    const hit = this.cache.get(refreshToken);
    if (hit && hit.exp > Date.now()) return hit.idToken;
    const res = await this.fetchImpl(
      `${this.cfg.secureTokenBaseUrl}/token?key=${encodeURIComponent(this.cfg.firebaseApiKey)}`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: refreshToken }).toString(),
      },
    );
    const j = (await res.json()) as Record<string, string>;
    if (!res.ok || !j.id_token) throw new SessionExpired();
    this.cache.set(refreshToken, { idToken: j.id_token, exp: Date.now() + (Number(j.expires_in ?? 3600) - 120) * 1000 });
    if (this.cache.size > 5000) this.cache.delete(this.cache.keys().next().value as string);
    return j.id_token;
  }

  /** Delete the signed-in Firebase user (needs a recent sign-in). */
  async deleteAccount(idToken: string): Promise<void> {
    const res = await this.fetchImpl(`${this.cfg.identityBaseUrl}/accounts:delete?key=${encodeURIComponent(this.cfg.firebaseApiKey)}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ idToken }),
    });
    if (!res.ok) {
      const j = (await res.json().catch(() => ({}))) as { error?: { message?: string } };
      throw new Error(
        /CREDENTIAL_TOO_OLD/.test(j.error?.message ?? '')
          ? 'Your data is deleted, but removing the sign-in needs a fresh one: reconnect the connector and ask again.'
          : `Could not delete the sign-in: ${j.error?.message ?? res.status}`,
      );
    }
  }
}

/** When the ID token's sign-in happened, in seconds (its auth_time claim). */
export function authTimeOf(idToken: string): number | undefined {
  try {
    const claims = JSON.parse(Buffer.from(idToken.split('.')[1] ?? '', 'base64url').toString('utf8')) as { auth_time?: number };
    return typeof claims.auth_time === 'number' ? claims.auth_time : undefined;
  } catch {
    return undefined;
  }
}

/** The Firebase session behind a token no longer works (signed out, account deleted). */
export class SessionExpired extends Error {
  constructor() {
    super('The Niz Khata sign-in has expired. Reconnect the connector.');
  }
}

export function actorOf(s: Pick<FirebaseSession, 'uid' | 'name'>): Actor {
  return { uid: s.uid, name: s.name };
}
