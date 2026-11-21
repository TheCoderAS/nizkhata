// The ported rules, checked against the cases in the app's own tests
// (mobile/test/recurrence_test.dart, statement_cycle_test.dart,
// title_tokens_test.dart), so the backend writes what the app would have.

import { describe, expect, it } from 'vitest';

import { makeRound, type Txn } from '../../src/ledger.js';
import type { Plain } from '../../src/firestore.js';
import {
  atMidnight,
  calOf,
  closedDay,
  formatDate,
  iso,
  missingDueInstances,
  nextDueDoc,
  nextOccurrence,
  renderTokens,
  statementDuePlans,
  statementDueId,
  statementOutstanding,
  cardOf,
  type Cal,
} from '../../src/jobs/rules.js';

const TZ = 'Asia/Kolkata';
const c = (y: number, m: number, d: number): Cal => ({ y, m, d });
const at = (y: number, m: number, d: number) => atMidnight(c(y, m, d), TZ);
const round = makeRound('INR');

describe('nextOccurrence', () => {
  it('monthly clamps month-end overflow', () => {
    expect(nextOccurrence(c(2026, 1, 31), 'monthly')).toEqual(c(2026, 2, 28));
    expect(nextOccurrence(c(2026, 8, 31), 'monthly')).toEqual(c(2026, 9, 30));
    expect(nextOccurrence(c(2026, 12, 15), 'monthly')).toEqual(c(2027, 1, 15));
  });
  it('weekly and yearly', () => {
    expect(nextOccurrence(c(2026, 8, 31), 'weekly')).toEqual(c(2026, 9, 7));
    expect(nextOccurrence(c(2024, 2, 29), 'yearly')).toEqual(c(2025, 2, 28));
  });
});

describe('closedDay: scheduled work happens at the end of the day', () => {
  it('a day counts as over from 23:55 in the workspace time zone', () => {
    // 23:54 and 23:55 in Kolkata on 30 Nov.
    expect(closedDay(new Date('2026-11-30T18:24:00Z'), TZ)).toEqual(c(2026, 11, 29));
    expect(closedDay(new Date('2026-11-30T18:25:00Z'), TZ)).toEqual(c(2026, 11, 30));
    // The same instant is still the afternoon of the 30th in New York.
    expect(closedDay(new Date('2026-11-30T18:25:00Z'), 'America/New_York')).toEqual(c(2026, 11, 29));
  });
});

describe('missingDueInstances', () => {
  // The last day that has ended: 1 Sep (it is some time on 2 Sep before 23:55).
  const closed = c(2026, 9, 1);
  const due = (id: string, date: Date, status: string, o: Plain = {}): Plain => ({
    id, direction: 'payable', title: 'RD', amount: 5000, dueDate: date, status, ...o,
  });
  it('at the end of its own day a due creates the next one, paid or not', () => {
    for (const status of ['open', 'settled', 'cancelled']) {
      const m = missingDueInstances([due('d1', at(2026, 8, 31), status, { recurrence: 'monthly' })], closed, TZ);
      expect(m.map((x) => [x.id, iso(x.dueDate)])).toEqual([['rec_d1_20260930', '2026-09-30']]);
    }
  });
  it('not before its day has ended, even if it is paid early', () => {
    expect(missingDueInstances([due('d1', at(2026, 9, 2), 'settled', { recurrence: 'monthly' })], closed, TZ)).toEqual([]);
    expect(missingDueInstances([due('d1', at(2026, 9, 30), 'settled', { recurrence: 'monthly' })], closed, TZ)).toEqual([]);
    // Once 2 Sep is over, it does.
    expect(missingDueInstances([due('d1', at(2026, 9, 2), 'open', { recurrence: 'monthly' })], c(2026, 9, 2), TZ)).toHaveLength(1);
  });
  it('is idempotent: the existing instance suppresses re-creation', () => {
    const dues = [
      due('d1', at(2026, 8, 31), 'settled', { recurrence: 'monthly' }),
      due('rec_d1_20260930', at(2026, 9, 30), 'open', { recurrence: 'monthly', recurrenceId: 'd1' }),
    ];
    expect(missingDueInstances(dues, closed, TZ)).toEqual([]);
  });
  it('only the newest instance of a series spawns', () => {
    const dues = [
      due('d1', at(2026, 7, 31), 'settled', { recurrence: 'monthly' }),
      due('rec_d1_20260831', at(2026, 8, 31), 'open', { recurrence: 'monthly', recurrenceId: 'd1' }),
    ];
    expect(missingDueInstances(dues, closed, TZ).map((x) => x.id)).toEqual(['rec_d1_20260930']);
  });
  it('a deleted instance is never made again, which ends the series', () => {
    const dues = [due('d1', at(2026, 8, 31), 'open', { recurrence: 'monthly' })];
    expect(missingDueInstances(dues, closed, TZ, new Set(['rec_d1_20260930']))).toEqual([]);
  });
  it('a series whose newest due stopped repeating has ended; non-recurring dues never spawn', () => {
    const dues = [
      due('d1', at(2026, 7, 31), 'settled', { recurrence: 'monthly' }),
      due('rec_d1_20260831', at(2026, 8, 31), 'open', { recurrenceId: 'd1' }),
    ];
    // The July one is not the newest, and the August one no longer repeats.
    expect(missingDueInstances(dues, closed, TZ)).toEqual([]);
    expect(missingDueInstances([due('d1', at(2026, 8, 1), 'settled')], closed, TZ)).toEqual([]);
  });
  it('the next document re-renders its title and carries the series forward', () => {
    const [inst] = missingDueInstances(
      [due('d1', at(2026, 8, 31), 'settled', { recurrence: 'monthly', titlePattern: 'RD Payment - {MMM}', occurrence: 3, lines: [{ lineId: 'l0', type: 'expense', amount: 5000 }] })],
      closed,
      TZ,
    );
    const doc = nextDueDoc(inst!, { fyStartMonth: 4, tz: TZ });
    expect(doc).toMatchObject({ title: 'RD Payment - Sept', occurrence: 4, recurrenceId: 'd1', recurrence: 'monthly', amount: 5000, titlePattern: 'RD Payment - {MMM}' });
    expect(calOf(doc.dueDate as Date, TZ)).toEqual(c(2026, 9, 30));
  });
  it('dates are days in the workspace time zone, wherever the server is', () => {
    const ny = 'America/New_York';
    const nyMidnight = atMidnight(c(2026, 8, 31), ny);
    const [inst] = missingDueInstances([due('d1', nyMidnight, 'open', { recurrence: 'monthly' })], c(2026, 9, 1), ny);
    const doc = nextDueDoc(inst!, { fyStartMonth: 4, tz: ny });
    expect(iso(calOf(doc.dueDate as Date, ny))).toBe('2026-09-30');
    expect((doc.dueDate as Date).toISOString()).toBe('2026-09-30T04:00:00.000Z');
  });
});

describe('renderTokens', () => {
  const sep = c(2026, 9, 3);
  it('renders the tokens as the app does for en_IN', () => {
    expect(renderTokens('RD Payment - {MMM}', sep)).toBe('RD Payment - Sept');
    expect(renderTokens('{MMMM} {YYYY}', sep)).toBe('September 2026');
    expect(renderTokens('{MM}/{YY}', sep)).toBe('09/26');
    expect(renderTokens('{D} and {DD}', sep)).toBe('3 and 03');
    expect(renderTokens('{DATE}', sep)).toBe('3 Sept 2026');
    expect(renderTokens('{Q}', sep)).toBe('Q3');
    expect(renderTokens('{mmm} {yyyy}', sep)).toBe('Sept 2026');
  });
  it('offsets', () => {
    expect(renderTokens('{MMM-1}', sep)).toBe('Aug');
    expect(renderTokens('{MMM-1} {YYYY}', c(2027, 1, 5))).toBe('Dec 2027');
    expect(renderTokens('{MM-1}', c(2026, 1, 5))).toBe('12');
    expect(renderTokens('{DD-3}', sep)).toBe('31');
    expect(renderTokens('{DATE+1}', sep)).toBe('4 Sept 2026');
    expect(renderTokens('{Q+1}', c(2026, 12, 1))).toBe('Q1');
    expect(renderTokens('{#+1}', sep, { occurrence: 7 })).toBe('8');
  });
  it('financial year, literal braces and unknown tokens', () => {
    expect(renderTokens('{FY}', sep)).toBe('2026-27');
    expect(renderTokens('{FY}', sep, { fyStartMonth: 1 })).toBe('2026');
    expect(renderTokens('{FY}', c(2026, 3, 31))).toBe('2025-26');
    expect(renderTokens('{FY-1}', sep)).toBe('2025-26');
    expect(renderTokens('{{MMM}', sep)).toBe('{MMM}');
    expect(renderTokens('{NOPE}', sep)).toBe('{NOPE}');
  });
  it('an American phone spells the month its own way', () => {
    expect(renderTokens('{MMM}', sep, { locale: 'en_US' })).toBe('Sep');
    expect(formatDate(sep, 'en_US')).toBe('Sep 3, 2026');
  });
});

// ---- card bills ----

const card = (o: Plain = {}): Plain => ({ id: 'cc1', name: 'HDFC Regalia', type: 'credit_card', openingBalance: 0, statementDay: 5, paymentDueDay: 25, ...o });
const spend = (id: string, date: Date, amount: number, account = 'cc1'): Txn => ({
  id, date, accountId: account, totalAmount: -amount, lines: [{ lineId: `${id}l`, type: 'expense', amount }],
});
const payment = (id: string, date: Date, amount: number): Txn => ({
  id, date, accountId: 'bank', totalAmount: -amount,
  lines: [
    { lineId: `${id}a`, type: 'transfer_out', amount, toAccountId: 'cc1' },
    { lineId: `${id}b`, type: 'transfer_in', amount, toAccountId: 'cc1' },
  ],
});
const cardCredit = (id: string, date: Date, amount: number): Txn => ({
  id, date, accountId: 'cc1', totalAmount: amount, lines: [{ lineId: `${id}l`, type: 'income', amount }],
});

function plans(o: { dues?: Plain[]; txns?: Txn[]; settled?: number; accounts?: Plain[]; today?: Cal }) {
  return statementDuePlans({
    accounts: o.accounts ?? [card()],
    dues: o.dues ?? [],
    txns: o.txns ?? [spend('t1', at(2026, 8, 20), 3000)],
    debts: new Map(),
    settledOf: () => o.settled ?? 0,
    today: o.today ?? c(2026, 9, 20),
    tz: TZ,
    round,
  });
}

describe('statementDuePlans', () => {
  const bill = (o: Plain = {}): Plain => ({ id: statementDueId('cc1', c(2026, 9, 5)), amount: 3000, status: 'open', dueDate: at(2026, 9, 25), ...o });
  const augBill = spend('t1', at(2026, 7, 20), 5000);
  const before5th = c(2026, 9, 4);

  it('raises the bill for a card that owes something, as a transfer to the card', () => {
    const [p] = plans({});
    expect(p).toMatchObject({ dueId: 'stmt_cc1_20260905', kind: 'create' });
    expect(p!.doc).toMatchObject({
      direction: 'payable', title: 'HDFC Regalia bill', amount: 3000, note: 'Statement of 5 Sept 2026', statementAccountId: 'cc1',
      lines: [
        { lineId: 'stmt_cc1_20260905_out', type: 'transfer_out', amount: 3000, toAccountId: 'cc1' },
        { lineId: 'stmt_cc1_20260905_in', type: 'transfer_in', amount: 3000, toAccountId: 'cc1' },
      ],
    });
    expect(calOf(p!.doc.dueDate as Date, TZ)).toEqual(c(2026, 9, 25));
  });
  it('raises nothing twice', () => expect(plans({ dues: [bill()] })).toEqual([]));
  it('corrects the amount when a purchase lands late', () => {
    const [p] = plans({ dues: [bill()], txns: [spend('t1', at(2026, 8, 20), 3000), spend('t2', at(2026, 9, 1), 500)] });
    expect(p).toMatchObject({ kind: 'update', doc: { amount: 3500 } });
  });
  it('leaves a part paid bill alone, and one you cancelled', () => {
    const later = [spend('t1', at(2026, 8, 20), 3000), spend('t2', at(2026, 9, 1), 500)];
    expect(plans({ dues: [bill()], txns: later, settled: 1000 })).toEqual([]);
    expect(plans({ dues: [bill({ status: 'cancelled' })], txns: later })).toEqual([]);
  });
  it('nothing for a card that owes nothing', () => {
    expect(plans({ txns: [spend('t1', at(2026, 8, 20), 3000), payment('p1', at(2026, 8, 25), 3000)] })).toEqual([]);
  });
  it('last month\'s unpaid bill is raised; a paid one is not; spending after does not revive it', () => {
    expect(plans({ txns: [augBill], today: before5th })[0]).toMatchObject({ dueId: 'stmt_cc1_20260805', doc: { amount: 5000 } });
    expect(plans({ txns: [augBill, payment('p1', at(2026, 8, 20), 5000)], today: before5th })).toEqual([]);
    expect(plans({ txns: [augBill, payment('p1', at(2026, 8, 20), 3000)], today: before5th })[0]!.doc.amount).toBe(5000);
    expect(plans({ txns: [augBill, payment('p1', at(2026, 8, 20), 5000), spend('t2', at(2026, 8, 28), 2000)], today: before5th })).toEqual([]);
  });
  it('only the current statement, never a backlog', () => {
    const old = [4, 5, 6, 7, 8, 9].map((m) => spend(`t${m}`, at(2026, m, 2), 1000));
    expect(plans({ txns: old }).map((p) => p.dueId)).toEqual(['stmt_cc1_20260905']);
  });
  it('ignores non-cards and cards without a cycle; two cards independently', () => {
    expect(plans({ accounts: [card({ statementDay: null }), { id: 'bank', type: 'bank', openingBalance: -5000 }] })).toEqual([]);
    const both = plans({
      accounts: [card(), card({ id: 'cc2', name: 'Amex', statementDay: 18, paymentDueDay: 8 })],
      txns: [spend('t1', at(2026, 8, 20), 3000), spend('t9', at(2026, 9, 10), 800, 'cc2')],
    });
    expect(both.map((p) => p.dueId)).toEqual(['stmt_cc1_20260905', 'stmt_cc2_20260918']);
    expect(calOf(both[1]!.doc.dueDate as Date, TZ)).toEqual(c(2026, 10, 8));
  });
  it('a late cashback withdraws the bill; a withdrawn bill owed again comes back; yours stays cancelled', () => {
    const fk = card({ name: 'Flipkart Axis', statementDay: 14, paymentDueDay: 30 });
    const billed = [spend('dress', at(2026, 8, 15), 626), spend('jeans', at(2026, 9, 6), 608), spend('drill', at(2026, 9, 12), 1584), cardCredit('refund', at(2026, 9, 12), 585)];
    const cashback = cardCredit('cashback', at(2026, 9, 10), 3794);
    expect(statementOutstanding(cardOf(fk)!, billed, new Map(), c(2026, 9, 14), TZ, round)).toBe(2233);
    expect(statementOutstanding(cardOf(fk)!, [...billed, cashback], new Map(), c(2026, 9, 14), TZ, round)).toBe(-1561);
    const raised = { id: statementDueId('cc1', c(2026, 9, 14)), amount: 2233, status: 'open', dueDate: at(2026, 9, 30) };
    expect(plans({ accounts: [fk], dues: [raised], txns: [...billed, cashback], today: c(2026, 9, 27) })).toEqual([
      { dueId: raised.id, doc: { status: 'cancelled', autoWithdrawn: true }, kind: 'cancel' },
    ]);
    expect(plans({ accounts: [fk], dues: [raised], txns: [...billed, cashback], settled: 500, today: c(2026, 9, 27) })).toEqual([]);

    const owing = [spend('t1', at(2026, 8, 20), 3000)];
    expect(plans({ dues: [bill({ status: 'cancelled', autoWithdrawn: true })], txns: owing })[0]).toMatchObject({ kind: 'restore', doc: { status: 'open', amount: 3000 } });
    expect(plans({ dues: [bill({ status: 'cancelled' })], txns: owing })).toEqual([]);
  });
  it('a payment entered ahead of its date does not count as paid yet', () => {
    const txns = [augBill, payment('p1', at(2026, 9, 10), 5000)];
    expect(plans({ txns, today: before5th })[0]).toMatchObject({ dueId: 'stmt_cc1_20260805' });
  });
});
