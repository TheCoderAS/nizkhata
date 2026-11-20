// get_summary: the app's Reports numbers for any period, in one call, so an
// assistant answering "how did I do this month?" doesn't fetch every entry and
// add them up itself. Income and expense follow derive.dart's trendSeries
// (income + interest income; expense + interest expense + fee + tax), and the
// category breakdown follows spendByCategoryInRange.

import { z } from 'zod';

import { UserError } from '../books.js';
import { accountDeltas, localDate, localParts, parseWhen, periodRange } from '../ledger.js';
import { READ, run, workspaceArg, type Register } from './common.js';

function impact(type: string): 'income' | 'expense' | null {
  if (type === 'income' || type === 'interest_income') return 'income';
  if (type === 'expense' || type === 'interest_expense' || type === 'fee' || type === 'tax') return 'expense';
  return null;
}

/** The calendar day after YYYY-MM-DD. */
function nextDay(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso.trim());
  if (!m) throw new UserError(`"to" must be a date, YYYY-MM-DD: ${iso}`);
  return new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]) + 1)).toISOString().slice(0, 10);
}

export const registerReportTools: Register = (server, ctx) => {
  server.registerTool(
    'get_summary',
    {
      title: 'Summarise a period',
      description:
        'Income, expense and net for a period, spending and income by category, money in and out of each account, and a day-by-day (up to 45 days) or month-by-month trend. Defaults to the current month. Transfers between your own accounts and loans are not income or expense.',
      inputSchema: {
        ...workspaceArg,
        from: z.string().optional().describe('First day, YYYY-MM-DD. Defaults to the start of this month (or this financial year with period "financial_year").'),
        to: z.string().optional().describe('Last day, included, YYYY-MM-DD. Defaults to the end of the period.'),
        period: z.enum(['month', 'financial_year']).optional(),
      },
      annotations: READ,
    },
    ({ workspace_id, from, to, period }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const tz = b.timeZone;
        const range = periodRange(period === 'financial_year' ? 'yearly' : 'monthly', new Date(), b.ws.fyStartMonth, tz);
        const start = from ? parseWhen(from, tz) : range.start;
        // [to] is a day included in full: the range ends at the next midnight.
        const endExclusive = to ? parseWhen(nextDay(to), tz) : range.end;
        if (endExclusive <= start) throw new UserError('"to" must be on or after "from".');

        const [txns, debts, categories, accounts] = await Promise.all([
          b.txns(),
          b.debts(),
          b.load('categories'),
          b.load('accounts'),
        ]);
        const catName = new Map(categories.map((c) => [String(c.id), String(c.name ?? '')]));
        const acctName = new Map(accounts.map((a) => [String(a.id), String(a.name ?? '')]));
        const debtsById = new Map(debts.map((d) => [d.id, d]));

        const days = (endExclusive.getTime() - start.getTime()) / 86_400_000;
        const byDay = days <= 45;
        const bucketKey = (d: Date) => {
          const p = localParts(d, tz);
          return byDay ? localDate(d, tz) : `${p.year}-${String(p.month).padStart(2, '0')}`;
        };

        let income = 0;
        let expense = 0;
        let count = 0;
        let uncategorised = 0;
        const spend = new Map<string, number>();
        const earned = new Map<string, number>();
        const flows = new Map<string, { in: number; out: number }>();
        const trend = new Map<string, { income: number; expense: number }>();

        for (const t of txns) {
          if (t.date < start || t.date >= endExclusive) continue;
          count++;
          const key = bucketKey(t.date);
          const bucket = trend.get(key) ?? { income: 0, expense: 0 };
          for (const l of t.lines) {
            const kind = impact(l.type);
            if (kind === 'income') {
              income += l.amount;
              bucket.income += l.amount;
              if (l.categoryId) earned.set(l.categoryId, (earned.get(l.categoryId) ?? 0) + l.amount);
            } else if (kind === 'expense') {
              expense += l.amount;
              bucket.expense += l.amount;
              if (l.categoryId) spend.set(l.categoryId, (spend.get(l.categoryId) ?? 0) + l.amount);
              else uncategorised += l.amount;
            }
          }
          trend.set(key, bucket);
          for (const [acct, delta] of accountDeltas(t, debtsById, b.round)) {
            if (acct === '__external__') continue;
            const f = flows.get(acct) ?? { in: 0, out: 0 };
            if (delta > 0) f.in += delta;
            else f.out -= delta;
            flows.set(acct, f);
          }
        }

        const r = b.round;
        const ranked = (m: Map<string, number>) =>
          [...m.entries()]
            .map(([id, amount]) => ({ category_id: id, category: catName.get(id) ?? 'Uncategorized', amount: r(amount) }))
            .sort((a, c) => c.amount - a.amount);

        return {
          currency: b.ws.currency,
          from: localDate(start, tz),
          to: localDate(new Date(endExclusive.getTime() - 1), tz),
          transactions: count,
          income: r(income),
          expense: r(expense),
          net: r(income - expense),
          spending_by_category: ranked(spend),
          ...(uncategorised > 0.005 ? { spending_uncategorised: r(uncategorised) } : {}),
          income_by_category: ranked(earned),
          accounts: [...flows.entries()].map(([id, f]) => ({
            account_id: id,
            account: acctName.get(id) ?? id,
            money_in: r(f.in),
            money_out: r(f.out),
            net: r(f.in - f.out),
          })),
          trend: {
            by: byDay ? 'day' : 'month',
            buckets: [...trend.entries()]
              .sort(([a], [c]) => (a < c ? -1 : 1))
              .map(([k, v]) => ({ [byDay ? 'day' : 'month']: k, income: r(v.income), expense: r(v.expense), net: r(v.income - v.expense) })),
          },
        };
      }),
  );
};
