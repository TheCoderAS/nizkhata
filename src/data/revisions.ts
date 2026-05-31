// Revision-log helpers. Each entity mutation also appends an append-only
// `revisions` doc capturing who changed what and when. Written client-side in
// the same batch as the mutation; the schema matches what a future Firestore-
// trigger Cloud Function would write, so it can be migrated to server-authored
// history without changing readers.

import {
  collection,
  doc,
  serverTimestamp,
  type WriteBatch,
} from "firebase/firestore";
import { db } from "@/firebase/config";
import type { Actor, RevisionAction } from "@/types/models";

function newRevisionId(): string {
  return doc(collection(db, "revisions")).id;
}

// Fields that are noise in a revision snapshot/diff.
const IGNORED_FIELDS = new Set([
  "id",
  "workspaceId",
  "createdAt",
  "createdBy",
  "updatedAt",
  "updatedBy",
]);

/** Shallow list of changed top-level fields between two doc states. */
export function diffFields(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown>,
): string[] {
  const keys = new Set([
    ...Object.keys(before ?? {}),
    ...Object.keys(after),
  ]);
  const changed: string[] = [];
  for (const k of keys) {
    if (IGNORED_FIELDS.has(k)) continue;
    if (JSON.stringify(before?.[k]) !== JSON.stringify(after[k])) changed.push(k);
  }
  return changed;
}

/** Add a revision entry to an existing batch. */
export function appendRevision(
  batch: WriteBatch,
  params: {
    workspaceId: string;
    entityType: string;
    entityId: string;
    action: RevisionAction;
    by: Actor;
    snapshot?: Record<string, unknown>;
    changedFields?: string[];
  },
): void {
  const id = newRevisionId();
  const rev: Record<string, unknown> = {
    id,
    workspaceId: params.workspaceId,
    entityType: params.entityType,
    entityId: params.entityId,
    action: params.action,
    by: params.by,
    at: serverTimestamp(),
  };
  if (params.snapshot) rev.snapshot = sanitize(params.snapshot);
  if (params.changedFields && params.changedFields.length > 0)
    rev.changedFields = params.changedFields;
  batch.set(doc(db, "revisions", id), rev);
}

// Drop undefined + non-serializable bits from a snapshot (Firestore rejects
// undefined; serverTimestamp sentinels shouldn't be copied into snapshots).
function sanitize(obj: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === undefined) continue;
    if (IGNORED_FIELDS.has(k)) continue;
    out[k] = v;
  }
  return out;
}
