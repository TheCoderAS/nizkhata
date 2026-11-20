// The scheduled jobs against the emulator: repeating dues catch up, card bills
// are raised once, and reminders go out once per slot, even across a restart.

import { beforeAll, describe, expect, it } from 'vitest';

import { Firestore, type Plain } from '../../src/firestore.js';
import { Push } from '../../src/jobs/push.js';
import { Scheduler } from '../../src/jobs/scheduler.js';
import { atMidnight, calOf, iso } from '../../src/jobs/rules.js';

const PROJECT = process.env.GCLOUD_PROJECT ?? 'rules-test';
const HOST = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
const BASE = `http://${HOST}/v1/projects/${PROJECT}/databases/(default)/documents`;
const TZ = 'Asia/Kolkata';
const admin = new Firestore(BASE, 'owner');
const set = (collection: string, id: string, data: Plain) => ({ kind: 'set' as const, collection, id, data: { id, ...data } });

// 12:30 in Kolkata on 20 Nov 2026.
const NOW = new Date('2026-11-20T07:00:00Z');
const day = (y: number, m: number, d: number) => atMidnight({ y, m, d }, TZ);

const sent: Array<{ token: string; body: any }> = [];
const fcm: typeof fetch = async (url, init) => {
  const body = JSON.parse(String((init as RequestInit).body));
  sent.push({ token: body.message.token, body: body.message });
  if (body.message.token === 'dead-token') return new Response(JSON.stringify({ error: { status: 'NOT_FOUND', message: 'UNREGISTERED' } }), { status: 404 });
  return new Response('{}', { status: 200 });
};
const scheduler = () =>
  new Scheduler({
    admin: async () => admin,
    push: new Push(PROJECT, async () => 'test', fcm, 'http://fcm.test'),
    defaultTimeZone: TZ,
    now: () => NOW,
    log: () => undefined,
  });

beforeAll(async () => {
  await admin.commit([
    set('workspaces', 'ws_s', { name: 'Sched', ownerId: 'sch', baseCurrency: 'INR', fyStartMonth: 4 }),
    set('roles', 'ws_s_owner', { workspaceId: 'ws_s', name: 'Owner', isSystem: true, permissions: { 'dues.view': true, 'dues.manage': true } }),
    set('roles', 'ws_s_blind', { workspaceId: 'ws_s', name: 'No dues', isSystem: false, permissions: { 'dues.view': false } }),
    set('memberships', 'ws_s_sch', { workspaceId: 'ws_s', uid: 'sch', roleId: 'ws_s_owner', status: 'active' }),
    set('memberships', 'ws_s_blind', { workspaceId: 'ws_s', uid: 'blind', roleId: 'ws_s_blind', status: 'active' }),
    set('devices', 'sch_phone', { uid: 'sch', token: 'tok-1', timeZone: TZ, locale: 'en_IN', updatedAt: new Date() }),
    set('devices', 'sch_old', { uid: 'sch', token: 'dead-token', timeZone: TZ, locale: 'en_IN', updatedAt: new Date(0) }),
    set('devices', 'blind_phone', { uid: 'blind', token: 'tok-blind', timeZone: TZ, updatedAt: new Date() }),
    // A monthly rent paid in September: October and November are owed, and catch up.
    set('dues', 'rent', {
      workspaceId: 'ws_s', direction: 'payable', title: 'Rent', titlePattern: 'Rent {MMM}', amount: 25000, dueDate: day(2026, 9, 20), status: 'settled',
      recurrence: 'monthly', occurrence: 1, lines: [{ lineId: 'l0', type: 'expense', amount: 25000 }],
    }),
    // Two dues today, one part paid; one tomorrow.
    set('dues', 'school', { workspaceId: 'ws_s', direction: 'payable', title: 'School', amount: 18000, dueDate: day(2026, 11, 20), status: 'open' }),
    set('dues', 'gym', { workspaceId: 'ws_s', direction: 'payable', title: 'Gym', amount: 1500, dueDate: day(2026, 11, 20), status: 'open' }),
    set('dues', 'later', { workspaceId: 'ws_s', direction: 'payable', title: 'Later', amount: 100, dueDate: day(2026, 11, 21), status: 'open' }),
    set('transactions', 'gym_part', { workspaceId: 'ws_s', accountId: 'bank', dueId: 'gym', totalAmount: -500, date: day(2026, 11, 19), lines: [{ lineId: 'x', type: 'expense', amount: 500 }] }),
    // A card billed on the 5th, due on the 25th, with spending before the 5th.
    set('accounts', 'card_s', { workspaceId: 'ws_s', name: 'Visa', type: 'credit_card', openingBalance: 0, statementDay: 5, paymentDueDay: 25 }),
    set('transactions', 'card_spend', { workspaceId: 'ws_s', accountId: 'card_s', totalAmount: -4200, date: day(2026, 11, 2), lines: [{ lineId: 'y', type: 'expense', amount: 4200 }] }),
  ]);
});

describe('scheduled jobs', () => {
  it('repeating dues catch up to today, and the card bill is raised, once', async () => {
    const s = scheduler();
    const first = await s.materialise();
    expect(first.created).toBe(3); // rent Oct, rent Nov, the Visa bill

    const oct = await admin.get('dues', 'rec_rent_20261020');
    expect(oct).toMatchObject({ title: 'Rent Oct', amount: 25000, status: 'open', recurrenceId: 'rent', occurrence: 2, createdBy: { uid: 'system', name: 'Niz Khata' } });
    expect(iso(calOf(oct!.dueDate as Date, TZ))).toBe('2026-10-20');
    // November's is due today, not past, so December's waits.
    expect(await admin.get('dues', 'rec_rent_20261120')).toMatchObject({ title: 'Rent Nov', occurrence: 3 });
    expect(await admin.get('dues', 'rec_rent_20261220')).toBeNull();

    const bill = await admin.get('dues', 'stmt_card_s_20261105');
    expect(bill).toMatchObject({ title: 'Visa bill', amount: 4200, status: 'open', note: 'Statement of 5 Nov 2026', statementAccountId: 'card_s' });
    expect(iso(calOf(bill!.dueDate as Date, TZ))).toBe('2026-11-25');

    const revs = await admin.where('revisions', 'entityId', 'rec_rent_20261020');
    expect(revs[0]).toMatchObject({ action: 'create', by: { uid: 'system', name: 'Niz Khata' }, workspaceId: 'ws_s' });

    expect((await scheduler().materialise()).created).toBe(0);
  });

  it('sends one reminder for the 12:00 slot, never twice, and forgets a dead device', async () => {
    const r = await scheduler().remind();
    // School, Gym (part paid) and the November rent are due today; "Later" is tomorrow.
    expect(r.sent).toBe(1);
    const mine = sent.filter((x) => x.token === 'tok-1');
    expect(mine).toHaveLength(1);
    expect(mine[0]!.body).toMatchObject({
      notification: { title: 'You have 3 dues to clear today', body: "Tap to see what's due" },
      data: { route: '/dues-day?date=2026-11-20' },
      android: { notification: { channel_id: 'due_reminders', tag: 'dues_2026-11-20' } },
    });
    expect(sent.some((x) => x.token === 'tok-blind')).toBe(false); // no dues.view, no reminder
    expect(await admin.get('devices', 'sch_old')).toBeNull();
    expect(await admin.get('pushLog', 'sch_2026-11-20_12')).toMatchObject({ uid: 'sch', count: 3, slot: 12 });

    // The same process again, and a fresh one after a restart: nothing more.
    const before = sent.length;
    const s = scheduler();
    await s.remind();
    await s.remind();
    expect(sent.length).toBe(before);
  });
});
