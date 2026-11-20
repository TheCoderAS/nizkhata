// Sealed tokens.
//
// The server keeps no database. Everything it hands out (client ids,
// authorization codes, access and refresh tokens) is a small JSON payload,
// encrypted and authenticated with AES-256-GCM under TOKEN_SECRET, so only
// this server can read or forge one. A payload carries its kind and expiry,
// and a token of one kind is never accepted as another.

import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';

export type TokenKind = 'client' | 'code' | 'access' | 'refresh' | 'state';

interface Envelope<T> {
  k: TokenKind;
  exp: number; // seconds since epoch; 0 = never
  d: T;
}

export class Sealer {
  private readonly key: Buffer;

  constructor(secret: string) {
    // Any string becomes a 32-byte key; Render's generated values are base64.
    this.key = createHash('sha256').update(`nizkhata-connector:${secret}`).digest();
  }

  seal<T>(kind: TokenKind, data: T, ttlSeconds: number): string {
    const env: Envelope<T> = { k: kind, exp: ttlSeconds > 0 ? now() + ttlSeconds : 0, d: data };
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const body = Buffer.concat([cipher.update(JSON.stringify(env), 'utf8'), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), body]).toString('base64url');
  }

  /** The payload, or null if the token is malformed, forged, expired or of another kind. */
  open<T>(kind: TokenKind, token: string): T | null {
    try {
      const raw = Buffer.from(token, 'base64url');
      if (raw.length < 29) return null;
      const decipher = createDecipheriv('aes-256-gcm', this.key, raw.subarray(0, 12));
      decipher.setAuthTag(raw.subarray(12, 28));
      const json = Buffer.concat([decipher.update(raw.subarray(28)), decipher.final()]).toString('utf8');
      const env = JSON.parse(json) as Envelope<T>;
      if (env.k !== kind) return null;
      if (env.exp !== 0 && env.exp < now()) return null;
      return env.d;
    } catch {
      return null;
    }
  }
}

export function now(): number {
  return Math.floor(Date.now() / 1000);
}

/** PKCE S256: base64url(sha256(verifier)). */
export function pkceChallenge(verifier: string): string {
  return createHash('sha256').update(verifier).digest('base64url');
}
