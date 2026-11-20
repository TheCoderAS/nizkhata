import { createVerify, generateKeyPairSync } from 'node:crypto';
import { describe, expect, it } from 'vitest';

import { googleTokenSource, parseServiceAccount } from '../../src/jobs/google.js';

describe('service account', () => {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const sa = {
    project_id: 'nizkhata',
    client_email: 'jobs@nizkhata.iam.gserviceaccount.com',
    private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
    token_uri: 'https://oauth2.googleapis.com/token',
  };

  it('reads raw or base64 JSON, and refuses an incomplete one', () => {
    expect(parseServiceAccount(JSON.stringify(sa))?.client_email).toBe(sa.client_email);
    expect(parseServiceAccount(Buffer.from(JSON.stringify(sa)).toString('base64'))?.project_id).toBe('nizkhata');
    expect(parseServiceAccount('')).toBeNull();
    expect(() => parseServiceAccount('{"project_id":"x"}')).toThrow(/missing/);
    expect(() => parseServiceAccount('{not json')).toThrow(/not valid JSON/);
    // Pasted in quotes, or as a quoted JSON string, or with its line breaks flattened.
    expect(parseServiceAccount(`'${JSON.stringify(sa)}'`)?.client_email).toBe(sa.client_email);
    expect(parseServiceAccount(JSON.stringify(JSON.stringify(sa)))?.client_email).toBe(sa.client_email);
    const flat = parseServiceAccount(JSON.stringify({ ...sa, private_key: sa.private_key.replace(/\n/g, '\\n') }));
    expect(flat?.private_key).toBe(sa.private_key);
  });

  it('signs a JWT bearer grant Google can verify, and caches the token', async () => {
    let calls = 0;
    let assertion = '';
    const fetchImpl = (async (_url: string, init: RequestInit) => {
      calls++;
      const form = new URLSearchParams(String(init.body));
      expect(form.get('grant_type')).toBe('urn:ietf:params:oauth:grant-type:jwt-bearer');
      assertion = form.get('assertion')!;
      return new Response(JSON.stringify({ access_token: 'ya29.test', expires_in: 3600 }), { status: 200 });
    }) as unknown as typeof fetch;
    const token = googleTokenSource(sa, fetchImpl);
    expect(await token()).toBe('ya29.test');
    expect(await token()).toBe('ya29.test');
    expect(calls).toBe(1);

    const [h, p, s] = assertion.split('.');
    const claims = JSON.parse(Buffer.from(p!, 'base64url').toString());
    expect(claims).toMatchObject({ iss: sa.client_email, aud: sa.token_uri });
    expect(claims.scope).toContain('auth/datastore');
    expect(claims.scope).toContain('auth/firebase.messaging');
    expect(createVerify('RSA-SHA256').update(`${h}.${p}`).verify(publicKey, Buffer.from(s!, 'base64url'))).toBe(true);
  });
});
