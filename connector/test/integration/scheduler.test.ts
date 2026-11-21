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
const scheduler = (now: Date = NOW) =>
  new Scheduler({
    admin: async () => admin,
    push: new Push(PROJECT, async () => 'test', fcm, 'http://fcm.test'),
    defaultTimeZone: TZ,
    now: () => now,
    log: () => undefined,
  });

beforeAll(async () => {
  await admin.commit([
    set('workspaces', 'ws_s', { name: 'Sched', ownerId: 'sch', baseCurrency: 'INR', fyStartMonth: 4 }),
    set('roles', 'ws_s_owner', { workspaceId: 'ws_s', name: 'Owner', isSystem: true, permissions: { 'dues.view': true, 'dues.manage': true } }),
    set('roles', 'ws_s_blind', { workspaceId: 'ws_s', name: 'No dues', isSystem: false, permissions: { 'dues.view': false } }),
    set('memberships', 'ws_s_sch', { workspaceId: 'ws_s', uid: 'sch', roleId: 'ws_s_owner', status: 'active' }),
    set('memberships', 'ws_s_blind', { workspaceId: 'ws_s', uid: 'blind', roleId: 'ws_s_blind', status: 'active' }),
    set('pushLog', 'sch_2026-09-01_9', { uid: 'sch', date: '2026-09-01', slot: 9, count: 1 }),
    set('pushLog', 'sch_2026-11-01_9', { uid: 'sch', date: '2026-11-01', slot: 9, count: 1 }),
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
    // Reminder log older than 30 days is gone; recent entries stay.
    expect(await admin.get('pushLog', 'sch_2026-09-01_9')).toBeNull();
    expect(await admin.get('pushLog', 'sch_2026-11-01_9')).not.toBeNull();
  });

  it('sends one reminder for the 12:00 slot, never twice, and forgets a dead device', async () => {
    const r = await scheduler().remind();
    // School, Gym (part paid) and the November rent are due today; "Later" is tomorrow.
    expect(r.sent).toBe(1);
    const mine = sent.filter((x) => x.token === 'tok-1');
    expect(mine).toHaveLength(1);
    expect(mine[0]!.body).toMatchObject({
      notification: { title: 'Sched: 3 dues to clear today', body: "Tap to see what's due" },
      data: { route: '/dues-day?date=2026-11-20&ws=ws_s' },
      android: { notification: { channel_id: 'due_reminders', tag: 'dues_ws_s_2026-11-20' } },
    });
    expect(sent.some((x) => x.token === 'tok-blind')).toBe(false); // no dues.view, no reminder
    expect(await admin.get('devices', 'sch_old')).toBeNull();
    expect(await admin.get('pushLog', 'sch_ws_s_2026-11-20_12')).toMatchObject({ uid: 'sch', count: 3, slot: 12 });

    // The same process again, and a fresh one after a restart: nothing more.
    const before = sent.length;
    const s = scheduler();
    await s.remind();
    await s.remind();
    expect(sent.length).toBe(before);
  });

  it('the next repeating due appears at the end of the current one\'s day, in the workspace\'s time zone', async () => {
    // 23:50 in Kolkata on 20 Nov: November's rent is today, its day not yet over.
    expect((await scheduler(new Date('2026-11-20T18:20:00Z')).materialise()).created).toBe(0);
    expect(await admin.get('dues', 'rec_rent_20261220')).toBeNull();
    // 23:56: the day is over, so December's appears, though November's is unpaid.
    expect((await scheduler(new Date('2026-11-20T18:26:00Z')).materialise()).created).toBe(1);
    expect(await admin.get('dues', 'rec_rent_20261220')).toMatchObject({ title: 'Rent Dec', status: 'open', occurrence: 4 });
  });

  it('a deleted due is never made again, so deleting the newest ends the series', async () => {
    await admin.commit([
      { kind: 'delete', collection: 'dues', id: 'rec_rent_20261220' },
      set('revisions', 'del_dec_rent', { workspaceId: 'ws_s', entityType: 'dues', entityId: 'rec_rent_20261220', action: 'delete', by: { uid: 'sch', name: 'Sch' }, at: new Date() }),
    ]);
    await scheduler(new Date('2026-12-25T10:00:00Z')).materialise();
    expect(await admin.get('dues', 'rec_rent_20261220')).toBeNull();
    expect(await admin.get('dues', 'rec_rent_20270120')).toBeNull();
    // The card's December statement is still billed: only the deleted due stays gone.
    expect(await admin.get('dues', 'stmt_card_s_20261205')).toMatchObject({ title: 'Visa bill', amount: 4200 });
  });

  it('a workspace in New York runs on New York\'s days and clock', async () => {
    await admin.commit([
      set('workspaces', 'ws_ny', { name: 'NY', ownerId: 'nyo', baseCurrency: 'USD', fyStartMonth: 1, timeZone: 'America/New_York' }),
      set('roles', 'ws_ny_owner', { workspaceId: 'ws_ny', name: 'Owner', isSystem: true, permissions: { 'dues.view': true } }),
      set('memberships', 'ws_ny_nyo', { workspaceId: 'ws_ny', uid: 'nyo', roleId: 'ws_ny_owner', status: 'active' }),
      // Her phone is in Kolkata, but the books are New York's.
      set('devices', 'nyo_phone', { uid: 'nyo', token: 'ny-phone', timeZone: 'Asia/Kolkata', updatedAt: new Date() }),
      set('dues', 'ny_gym', {
        workspaceId: 'ws_ny', direction: 'payable', title: 'Gym', amount: 40, status: 'open', recurrence: 'monthly', occurrence: 1,
        dueDate: atMidnight({ y: 2026, m: 11, d: 20 }, 'America/New_York'),
      }),
    ]);
    // 23:56 on the 20th in Kolkata is only 13:26 in New York: its day is not over.
    expect((await scheduler(new Date('2026-11-20T18:26:00Z')).materialise()).created).toBe(0);
    // 23:56 in New York.
    expect((await scheduler(new Date('2026-11-21T04:56:00Z')).materialise()).created).toBeGreaterThanOrEqual(1);
    const dec = await admin.get('dues', 'rec_ny_gym_20261220');
    expect(iso(calOf(dec!.dueDate as Date, 'America/New_York'))).toBe('2026-12-20');

    // The 9:00 reminder is New York's 9:00, not the phone's.
    sent.length = 0;
    await scheduler(new Date('2026-11-20T09:30:00Z')).remind(); // 15:00 in Kolkata, 04:30 in New York
    expect(sent.filter((x) => x.token === 'ny-phone')).toEqual([]);
    await scheduler(new Date('2026-11-20T14:05:00Z')).remind(); // 09:05 in New York
    expect(sent.filter((x) => x.token === 'ny-phone')).toHaveLength(1);
  });

  it('one reminder per workspace, each named and opening its own workspace', async () => {
    await admin.commit([
      set('workspaces', 'ws_t', { name: 'Trip', ownerId: 'sch', baseCurrency: 'INR', fyStartMonth: 4 }),
      set('roles', 'ws_t_owner', { workspaceId: 'ws_t', name: 'Owner', isSystem: true, permissions: { 'dues.view': true } }),
      set('memberships', 'ws_t_sch', { workspaceId: 'ws_t', uid: 'sch', roleId: 'ws_t_owner', status: 'active' }),
      set('dues', 'trip_hotel', { workspaceId: 'ws_t', direction: 'payable', title: 'Hotel', amount: 9000, dueDate: day(2026, 11, 22), status: 'open' }),
    ]);
    sent.length = 0;
    await scheduler(new Date('2026-11-22T04:00:00Z')).remind(); // 09:30 on the 22nd in Kolkata
    expect(sent.filter((x) => x.token === 'tok-1').map((x) => [x.body.notification.title, x.body.data.route])).toEqual([
      ['Trip: a due to clear today', '/dues-day?date=2026-11-22&ws=ws_t'],
    ]);
  });

  it('a phone that changed hands notifies only whoever signed in last', async () => {
    // "sch" signed out while offline, so his record stayed; then "pat" signed in on the same phone.
    await admin.commit([
      set('workspaces', 'ws_p', { name: 'Pat home', ownerId: 'pat', baseCurrency: 'INR', fyStartMonth: 4 }),
      set('roles', 'ws_p_owner', { workspaceId: 'ws_p', name: 'Owner', isSystem: true, permissions: { 'dues.view': true } }),
      set('memberships', 'ws_p_pat', { workspaceId: 'ws_p', uid: 'pat', roleId: 'ws_p_owner', status: 'active' }),
      set('dues', 'pat_rent', { workspaceId: 'ws_p', direction: 'payable', title: 'Rent', amount: 1, dueDate: day(2026, 11, 23), status: 'open' }),
      set('dues', 'sch_bill', { workspaceId: 'ws_s', direction: 'payable', title: 'Bill', amount: 1, dueDate: day(2026, 11, 23), status: 'open' }),
      set('devices', 'pat_phone', { uid: 'pat', token: 'tok-1', timeZone: TZ, updatedAt: new Date() }),
    ]);
    sent.length = 0;
    await scheduler(new Date('2026-11-23T04:00:00Z')).remind();
    const toPhone = sent.filter((x) => x.token === 'tok-1').map((x) => x.body.notification.title);
    expect(toPhone).toEqual(['Pat home: a due to clear today']); // nothing of sch's
    expect(await admin.get('devices', 'sch_phone')).toBeNull(); // the stale record is gone
  });
});