// The money rules must agree with the app's (mobile/lib/data/derive.dart).
// Cases mirror the app's own tests where one exists.
import { describe, expect, it } from 'vitest';
import {
  accountBalances, computeTotal, currencyDecimals, debtOutstanding, debtStatusFrom, dueSettledAmount,
  dueStatusFromSettled, financialYearOf, localDate, makeRound, parseWhen, periodRange, type Debt, type Txn,
} from '../../src/ledger.js';

const r2 = makeRound('INR');
const IST = 'Asia/Kolkata';
const txn = (id: string, accountId: string, totalAmount: number, lines: Txn['lines'], extra: Partial<Txn> = {}): Txn =>
  ({ id, date: new Date('2026-11-01T00:00:00Z'), accountId, totalAmount, lines, ...extra });

describe('rounding follows the currency', () => {
  it('rupees to paise, yen and rupiah whole, dinars to three places', () => {
    expect(r2(0.1 + 0.2)).toBe(0.3);
    expect(currencyDecimals('JPY')).toBe(0);
    expect(currencyDecimals('IDR')).toBe(0);
    expect(makeRound('JPY')(33.6)).toBe(34);
    expect(makeRound('KWD')(1.2345)).toBe(1.235);
  });
});

describe('totals and balances', () => {
  const debts = new Map<string, Debt>([
    ['owe1', { id: 'owe1', contactId: 'c', direction: 'owe', status: 'open', principal: 0 }],
    ['owed1', { id: 'owed1', contactId: 'c', direction: 'owed', status: 'open', principal: 0 }],
  ]);

  it('expense out, income in, a transfer moves money between accounts', () => {
    expect(computeTotal([{ lineId: 'a', type: 'expense', amount: 450 }], debts, r2)).toBe(-450);
    expect(computeTotal([{ lineId: 'a', type: 'income', amount: 85000 }], debts, r2)).toBe(85000);
    const t = txn('t', 'bank', -500, [
      { lineId: 'o', type: 'transfer_out', amount: 500 },
      { lineId: 'i', type: 'transfer_in', amount: 500, toAccountId: 'card' },
    ]);
    const bal = accountBalances([{ id: 'bank', openingBalance: 1000 }, { id: 'card', openingBalance: -800 }], [t], debts, r2);
    expect(bal.get('bank')).toBe(500);
    expect(bal.get('card')).toBe(-300);
  });

  it('a repayment follows the debt: paying back what you borrowed is money out', () => {
    expect(computeTotal([{ lineId: 'a', type: 'repayment', amount: 100, debtId: 'owe1' }], debts, r2)).toBe(-100);
    expect(computeTotal([{ lineId: 'a', type: 'repayment', amount: 100, debtId: 'owed1' }], debts, r2)).toBe(100);
  });

  it('external lines never touch an account', () => {
    expect(computeTotal([{ lineId: 'a', type: 'lend', amount: 100, external: true }], debts, r2)).toBe(0);
  });
});

describe('debts', () => {
  const debt: Debt = { id: 'd', contactId: 'c', direction: 'owed', status: 'open', principal: 16000 };
  const lent = txn('t1', 'bank', -16000, [{ lineId: 'a', type: 'lend', amount: 16000, debtId: 'd' }]);
  const repaid = txn('t2', 'bank', 15000, [{ lineId: 'b', type: 'repayment', amount: 15000, debtId: 'd' }]);

  it('outstanding is what was lent less what came back', () => {
    expect(debtOutstanding(debt, [lent, repaid], r2)).toBe(1000);
  });

  it('a part repayment leaves it open; the balance decides', () => {
    expect(debtStatusFrom(debt, 1000)).toBe('open');
    expect(debtStatusFrom(debt, 0)).toBe('settled');
  });
});

describe('dues', () => {
  it('part paid, then settled', () => {
    const due = { id: 'due', amount: 18000, status: 'open' };
    const p = txn('p', 'bank', -5000, [{ lineId: 'a', type: 'expense', amount: 5000 }], { dueId: 'due' });
    expect(dueSettledAmount(due, [p], r2)).toBe(5000);
    expect(dueStatusFromSettled(due, 5000)).toBe('partial');
    expect(dueStatusFromSettled(due, 18000)).toBe('settled');
    expect(dueStatusFromSettled({ ...due, status: 'cancelled' }, 0)).toBe('cancelled');
  });
});

describe('dates are placed as the app places them', () => {
  it('a bare date is midnight in the workspace time zone', () => {
    const d = parseWhen('2026-11-20', IST);
    expect(d.toISOString()).toBe('2026-11-19T18:30:00.000Z');
    expect(localDate(d, IST)).toBe('2026-11-20');
  });

  it('financial year: April start spans two years, a January start is one', () => {
    expect(financialYearOf(parseWhen('2026-03-31', IST), 4, IST)).toBe('2025-26');
    expect(financialYearOf(parseWhen('2026-04-01', IST), 4, IST)).toBe('2026-27');
    expect(financialYearOf(parseWhen('2026-04-01', IST), 1, IST)).toBe('2026');
  });

  it('budget periods: the calendar month, or the financial year', () => {
    const m = periodRange('monthly', parseWhen('2026-11-20', IST), 4, IST);
    expect([localDate(m.start, IST), localDate(m.end, IST)]).toEqual(['2026-11-01', '2026-12-01']);
    const y = periodRange('yearly', parseWhen('2026-02-10', IST), 4, IST);
    expect([localDate(y.start, IST), localDate(y.end, IST)]).toEqual(['2025-04-01', '2026-04-01']);
  });
});
