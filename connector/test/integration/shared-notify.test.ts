// Shared ledger notifications against the emulator: one push per action, to
// the other person only, never twice, and no replay of history on first run.

import { beforeAll, describe, expect, it } from 'vitest';

import { Firestore, SERVER_TIME, type Plain } from '../../src/firestore.js';
import { Push } from '../../src/jobs/push.js';
import { SharedNotifier } from '../../src/jobs/shared-notify.js';

const PROJECT = process.env.GCLOUD_PROJECT ?? 'rules-test';
const HOST = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
const admin = new Firestore(`http://${HOST}/v1/projects/${PROJECT}/databases/(default)/documents`, 'owner');

const sent: Array<{ token: string; title: string; body: string; route: string }> = [];
const fcm = (async (_url: string, init: RequestInit) => {
  const m = JSON.parse(String(init.body)).message;
  sent.push({ token: m.token, title: m.notification.title, body: m.notification.body, route: m.data.route });
  return new Response('{}', { status: 200 });
}) as unknown as typeof fetch;
const notifier = () => new SharedNotifier(async () => admin, new Push(PROJECT, async () => 't', fcm, 'http://fcm.test'), undefined, () => undefined);

const entry = (id: string, o: Plain = {}) => ({
  kind: 'set' as const,
  collection: 'sharedEntries',
  id,
  data: {
    id, connectionId: 'n_asha_n_ravi', kind: 'expense', uids: ['n_asha', 'n_ravi'], creatorUid: 'n_asha', counterpartyUid: 'n_ravi', payerUid: 'n_asha',
    names: { n_asha: 'Asha', n_ravi: 'Ravi' }, description: 'Dinner', amount: 1500, currency: 'INR', status: 'pending', pendingForUids: ['n_ravi'],
    createdBy: { uid: 'n_asha', name: 'Asha' }, updatedAt: SERVER_TIME, ...o,
  },
});

beforeAll(async () => {
  await admin.commit([
    { kind: 'delete', collection: 'schedulerState', id: 'shared' },
    { kind: 'set', collection: 'devices', id: 'n_asha_p1', data: { uid: 'n_asha', token: 'asha-phone', timeZone: 'Asia/Kolkata', locale: 'en_IN' } },
    { kind: 'set', collection: 'devices', id: 'n_ravi_p1', data: { uid: 'n_ravi', token: 'ravi-phone', timeZone: 'Asia/Kolkata', locale: 'en_IN' } },
    { kind: 'set', collection: 'devices', id: 'n_ravi_p2', data: { uid: 'n_ravi', token: 'ravi-tablet', timeZone: 'Asia/Kolkata', locale: 'en_IN' } },
    // Something that happened before the notifier ever ran: never replayed.
    entry('n_old'),
  ]);
});

describe('shared ledger notifications', () => {
  it('the first run starts from now and sends nothing old', async () => {
    expect((await notifier().run()).sent).toBe(0);
    expect((await admin.get('schedulerState', 'shared'))?.cursor).toBeInstanceOf(Date);
    expect((await notifier().run()).sent).toBe(0); // the old entry is before the first run: never sent
    sent.length = 0;
  });

  it('every action reaches the other person once, on each of their phones', async () => {
    await new Promise((r) => setTimeout(r, 20));
    // Five expenses in a row: five notifications to Ravi.
    await admin.commit([1, 2, 3, 4, 5].map((i) => entry(`n_e${i}`, { description: `Trip day ${i}`, amount: 100 * i })));
    const n = notifier();
    expect((await n.run()).sent).toBe(10); // 5 entries x 2 of Ravi's devices
    expect(sent.filter((s) => s.token === 'asha-phone')).toEqual([]);
    expect(sent.find((s) => s.token === 'ravi-phone' && s.route === '/shared?entry=n_e3')).toEqual({
      token: 'ravi-phone', title: 'Asha added a shared expense', body: 'Trip day 3: ₹300.00 for you to accept.', route: '/shared?entry=n_e3',
    });

    // Again, and from a "restarted" server: nothing more.
    expect((await n.run()).sent).toBe(0);
    expect((await notifier().run()).sent).toBe(0);

    // Ravi accepts one and rejects another: Asha hears about each.
    sent.length = 0;
    await admin.commit([
      { kind: 'update', collection: 'sharedEntries', id: 'n_e1', data: { status: 'accepted', pendingForUids: [], updatedAt: SERVER_TIME } },
      { kind: 'update', collection: 'sharedEntries', id: 'n_e2', data: { status: 'rejected', pendingForUids: [], updatedAt: SERVER_TIME } },
    ]);
    expect((await notifier().run()).sent).toBe(2);
    expect(sent.map((s) => [s.token, s.title]).sort()).toEqual([
      ['asha-phone', 'Ravi accepted Trip day 1'],
      ['asha-phone', 'Ravi rejected Trip day 2'],
    ]);
    expect(await admin.get('pushLog', 'shared_n_e1_accepted')).toMatchObject({ uid: 'n_asha', kind: 'shared' });
  });
});
