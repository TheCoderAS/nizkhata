import { createHash } from 'node:crypto';
import { describe, expect, it, vi } from 'vitest';
import { pkceChallenge, Sealer } from '../../src/crypto.js';
import { DELETE, decodeFields, encodeValue, Firestore, newDocId, SERVER_TIME } from '../../src/firestore.js';

describe('sealed tokens', () => {
  const s = new Sealer('x'.repeat(40));

  it('round-trips, and only as the kind it was sealed as', () => {
    const t = s.seal('access', { uid: 'u1' }, 60);
    expect(s.open('access', t)).toEqual({ uid: 'u1' });
    expect(s.open('refresh', t)).toBeNull();
  });

  it('refuses tampering, other keys and expiry', () => {
    const t = s.seal('code', { a: 1 }, 60);
    const raw = Buffer.from(t, 'base64url');
    raw[raw.length - 1] ^= 0x01; // one bit of the ciphertext
    const flipped = raw.toString('base64url');
    expect(s.open('code', flipped)).toBeNull();
    expect(new Sealer('y'.repeat(40)).open('code', t)).toBeNull();
    const short = s.seal('code', { a: 1 }, 60);
    vi.useFakeTimers();
    vi.setSystemTime(Date.now() + 61_000);
    expect(s.open('code', short)).toBeNull();
    vi.useRealTimers();
  });

  it('PKCE S256 is base64url(sha256(verifier)), unpadded', () => {
    const v = 'a-verifier-of-at-least-43-characters-0123456789';
    const expected = createHash('sha256').update(v).digest('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    expect(pkceChallenge(v)).toBe(expected);
    expect(pkceChallenge(v)).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });
});

describe('Firestore values', () => {
  it('round-trips the shapes the app stores', () => {
    const doc = { n: 3, d: 4.5, s: 'x', b: true, at: new Date('2026-11-20T00:00:00Z'), lines: [{ amount: 450, type: 'expense' }], z: null };
    const enc = Object.fromEntries(Object.entries(doc).map(([k, v]) => [k, encodeValue(v)]));
    expect(decodeFields(enc as never)).toEqual(doc);
    expect(encodeValue(450)).toEqual({ integerValue: '450' });
    expect(encodeValue(4.5)).toEqual({ doubleValue: 4.5 });
  });

  it('ids look like Firestore auto ids', () => {
    expect(newDocId()).toMatch(/^[A-Za-z0-9]{20}$/);
  });

  it('an update writes only its fields, deletes cleared ones and stamps server time', async () => {
    let body: any;
    const fake = (async (_u: string, init: any) => {
      body = JSON.parse(init.body);
      return new Response('{}', { status: 200 });
    }) as typeof fetch;
    const fs = new Firestore('https://firestore.googleapis.com/v1/projects/p/databases/(default)/documents', 't', fake);
    await fs.commit([{ kind: 'update', collection: 'dues', id: 'd1', data: { title: 'Rent', note: DELETE, updatedAt: SERVER_TIME } }]);
    const w = body.writes[0];
    expect(w.update.name).toBe('projects/p/databases/(default)/documents/dues/d1');
    expect(Object.keys(w.update.fields)).toEqual(['title']);
    expect(w.updateMask.fieldPaths).toEqual(['title', 'note']);
    expect(w.updateTransforms).toEqual([{ fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME' }]);
    expect(w.currentDocument).toEqual({ exists: true });
  });
});
