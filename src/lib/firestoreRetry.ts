// Resilient Firestore listeners.
//
// When a batch write (e.g. creating a workspace + its membership) is applied,
// Firestore optimistically re-fires active listeners against the LOCAL cache
// before the server commits. The server can then briefly evaluate Security
// Rules (isMember / can) against not-yet-committed state and return
// `permission-denied`. A listener that errors is torn down permanently, which
// would surface as a fatal app error even though the data becomes readable a
// moment later.
//
// `subscribeWithRetry` treats `permission-denied` (and the transient
// `unavailable`) as retryable: it re-subscribes a few times with backoff before
// giving up and reporting the error. Returns an unsubscribe function that also
// cancels any pending retry.

import {
  onSnapshot,
  type DocumentData,
  type DocumentReference,
  type DocumentSnapshot,
  type FirestoreError,
  type Query,
  type QuerySnapshot,
} from "firebase/firestore";

const RETRYABLE = new Set(["permission-denied", "unavailable"]);
const MAX_RETRIES = 6;
const BASE_DELAY_MS = 250; // 250, 500, 1000, … capped at 4s

/** Retrying listener for a Query. */
export function subscribeWithRetry(
  source: Query,
  onData: (snap: QuerySnapshot<DocumentData>) => void,
  onError: (e: FirestoreError) => void,
): () => void;
/** Retrying listener for a DocumentReference. */
export function subscribeWithRetry(
  source: DocumentReference,
  onData: (snap: DocumentSnapshot<DocumentData>) => void,
  onError: (e: FirestoreError) => void,
): () => void;
export function subscribeWithRetry(
  source: Query | DocumentReference,
  onData: (snap: never) => void,
  onError: (e: FirestoreError) => void,
): () => void {
  let cancelled = false;
  let unsub: (() => void) | null = null;
  let timer: ReturnType<typeof setTimeout> | null = null;
  let attempt = 0;

  const start = () => {
    if (cancelled) return;
    // onSnapshot is overloaded for Query and DocumentReference; both accept the
    // same (next, error) observer shape.
    unsub = onSnapshot(
      source as Query,
      (snap) => {
        attempt = 0; // a successful emission resets the backoff
        onData(snap as never);
      },
      (e) => {
        if (RETRYABLE.has(e.code) && attempt < MAX_RETRIES) {
          const delay = Math.min(BASE_DELAY_MS * 2 ** attempt, 4000);
          attempt += 1;
          timer = setTimeout(start, delay);
        } else {
          onError(e);
        }
      },
    );
  };

  start();

  return () => {
    cancelled = true;
    if (timer) clearTimeout(timer);
    if (unsub) unsub();
  };
}
