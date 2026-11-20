// Firestore over its REST API, always with the signed-in person's Firebase ID
// token. The server holds no service account, so it can do nothing the
// person could not do in the app: the same security rules apply to every
// read and write.

import { randomBytes } from 'node:crypto';

/** Marks a field to be set to the server's commit time. */
export const SERVER_TIME = Symbol('serverTime');
/** Marks a field to be removed (on update). */
export const DELETE = Symbol('delete');

export type Plain = Record<string, unknown>;

export interface Write {
  kind: 'set' | 'update' | 'delete';
  collection: string;
  id: string;
  data?: Plain;
}

export class FirestoreError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

/** A document id the way Firestore makes them: 20 characters, A-Z a-z 0-9. */
export function newDocId(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  const bytes = randomBytes(40);
  let out = '';
  for (let i = 0; out.length < 20; i++) {
    const b = bytes[i % bytes.length]!;
    if (b < 248) out += chars[b % 62]; // 248 = 4 * 62, so no bias
    if (i > 200) break;
  }
  return out;
}

// ---- values ----------------------------------------------------------------

type FsValue = Record<string, unknown>;

export function encodeValue(v: unknown): FsValue {
  if (v === null || v === undefined) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encodeValue) } };
  if (typeof v === 'object') return { mapValue: { fields: encodeFields(v as Plain) } };
  throw new Error(`Cannot store value of type ${typeof v}`);
}

function encodeFields(o: Plain): Record<string, FsValue> {
  const out: Record<string, FsValue> = {};
  for (const [k, v] of Object.entries(o)) {
    if (v === SERVER_TIME || v === DELETE || v === undefined) continue;
    out[k] = encodeValue(v);
  }
  return out;
}

export function decodeValue(v: FsValue): unknown {
  if ('nullValue' in v) return null;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return Number(v.doubleValue);
  if ('stringValue' in v) return v.stringValue;
  if ('timestampValue' in v) return new Date(String(v.timestampValue));
  if ('referenceValue' in v) return v.referenceValue;
  if ('arrayValue' in v) {
    const vals = ((v.arrayValue as { values?: FsValue[] }).values ?? []) as FsValue[];
    return vals.map(decodeValue);
  }
  if ('mapValue' in v) return decodeFields(((v.mapValue as { fields?: Record<string, FsValue> }).fields ?? {}));
  return null;
}

export function decodeFields(f: Record<string, FsValue>): Plain {
  const out: Plain = {};
  for (const [k, v] of Object.entries(f)) out[k] = decodeValue(v);
  return out;
}

// ---- client ----------------------------------------------------------------

export class Firestore {
  constructor(
    private readonly baseUrl: string,
    private readonly idToken: string,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  private docName(collection: string, id: string): string {
    // baseUrl ends in .../databases/(default)/documents
    const root = this.baseUrl.replace(/^https?:\/\/[^/]+\/v1\//, '');
    return `${root}/${collection}/${id}`;
  }

  private async call(path: string, body?: unknown, method = 'POST'): Promise<unknown> {
    const res = await this.fetchImpl(`${this.baseUrl}${path}`, {
      method,
      headers: {
        authorization: `Bearer ${this.idToken}`,
        'content-type': 'application/json',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    const json = text ? (JSON.parse(text) as unknown) : {};
    if (!res.ok) {
      const err = (Array.isArray(json) ? json[0] : json) as { error?: { status?: string; message?: string } };
      throw new FirestoreError(res.status, err?.error?.status ?? 'UNKNOWN', err?.error?.message ?? text);
    }
    return json;
  }

  /** One document, or null if it does not exist. */
  async get(collection: string, id: string): Promise<Plain | null> {
    try {
      const doc = (await this.call(`/${collection}/${encodeURIComponent(id)}`, undefined, 'GET')) as {
        fields?: Record<string, FsValue>;
      };
      return { ...decodeFields(doc.fields ?? {}), id };
    } catch (e) {
      if (e instanceof FirestoreError && e.status === 404) return null;
      throw e;
    }
  }

  /** Every document in [collection] whose [field] equals [value]. */
  async where(collection: string, field: string, value: unknown, op = 'EQUAL'): Promise<Plain[]> {
    const rows = (await this.call(':runQuery', {
      structuredQuery: {
        from: [{ collectionId: collection }],
        where: { fieldFilter: { field: { fieldPath: field }, op, value: encodeValue(value) } },
      },
    })) as Array<{ document?: { name: string; fields?: Record<string, FsValue> } }>;
    return rows
      .filter((r) => r.document)
      .map((r) => {
        const name = r.document!.name;
        return { ...decodeFields(r.document!.fields ?? {}), id: name.slice(name.lastIndexOf('/') + 1) };
      });
  }

  /** Apply [writes] atomically, as the app's batched writes do. */
  async commit(writes: Write[]): Promise<void> {
    await this.call(':commit', {
      writes: writes.map((w) => {
        const name = this.docName(w.collection, w.id);
        if (w.kind === 'delete') return { delete: name };
        const data = w.data ?? {};
        const transforms = Object.entries(data)
          .filter(([, v]) => v === SERVER_TIME)
          .map(([k]) => ({ fieldPath: k, setToServerValue: 'REQUEST_TIME' }));
        const out: Record<string, unknown> = {
          update: { name, fields: encodeFields(data) },
        };
        if (transforms.length) out.updateTransforms = transforms;
        if (w.kind === 'update') {
          // Only the named fields change; a DELETE marker removes its field.
          out.updateMask = {
            fieldPaths: Object.entries(data)
              .filter(([, v]) => v !== SERVER_TIME)
              .map(([k]) => (/^[A-Za-z_][A-Za-z0-9_]*$/.test(k) ? k : `\`${k}\``)),
          };
          out.currentDocument = { exists: true };
        }
        return out;
      }),
    });
  }
}
