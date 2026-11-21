// The rest of what the app does: settle up with a contact, import a bank
// statement, the Reports tabs (tax, net worth, by contact), and deleting the
// whole account. Each follows the app's own code:
//   settle up       mobile/lib/data/settle_up.dart, contact_detail_screen.dart
//   import          import_screen.dart, mutations.dart importTransactions,
//                   statement_parser.dart importFingerprint, import_learning.dart
//   reports         reports_screen.dart, derive.dart netWorthSeries
//   delete account  services/account_eraser.dart eraseAccount
// The app reads statement files on the phone; here the assistant reads the
// statement and passes its rows.

import { z } from 'zod';

import { UserError, toTxn, type Books } from '../books.js';
import { FirestoreError, newDocId, SERVER_TIME, type Plain, type Write } from '../firestore.js';
import {
  accountDeltas, computeTotal, debtOutstanding, dueSettledAmount, dueStatusFromSettled, financialYearOf, localDate, parseWhen,
  type Debt, type Line, type Txn,
} from '../ledger.js';
import { DESTRUCTIVE, READ, WRITE, dateArg, run, workspaceArg, type Ctx, type Register } from './common.js';
import { settlement } from './dues.js';
import { eraseWorkspace } from './team.js';

const TAX_HEAD_LABELS: Record<string, string> = {
  salary: 'Salary', bonus: 'Bonus', overtime: 'Overtime', reimbursement: 'Reimbursement', perquisite: 'Perquisite',
  commission: 'Commission', professional_fees: 'Professional fees', rent: 'Rent', interest: 'Interest', dividend: 'Dividend',
  capital_gains: 'Capital gains', business: 'Business / profession', other: 'Other', exempt: 'Exempt',
};
const headLabel = (h: string) => TAX_HEAD_LABELS[h] ?? (h ? h[0]!.toUpperCase() + h.slice(1).replace(/_/g, ' ') : h);

/** The financial year named like "2026-27" (or "2026" when it starts in January), as [start, end). */
function fyRange(b: Books, fy: string | undefined) {
  const m = b.ws.fyStartMonth;
  const label = fy?.trim() || financialYearOf(new Date(), m, b.timeZone);
  const y = Number(/^(\d{4})/.exec(label)?.[1]);
  if (!y) throw new UserError(`"${fy}" is not a financial year. Use the form ${financialYearOf(new Date(), m, b.timeZone)}.`);
  const iso = (yy: number) => `${yy}-${String(m).padStart(2, '0')}-01`;
  return { fy: financialYearOf(parseWhen(iso(y), b.timeZone), m, b.timeZone), start: parseWhen(iso(y), b.timeZone), end: parseWhen(iso(y + 1), b.timeZone) };
}
const fyArg = z.string().optional().describe('Financial year, e.g. 2026-27 (or 2026 for a year starting in January). Defaults to the current one.');

// ---- import helpers (statement_parser.dart, import_learning.dart) ----

/** importFingerprint: account + day + signed amount + the normalised head of the reference or description. */
export function importFingerprint(accountId: string, day: string, amount: number, refOrDesc: string) {
  const norm = refOrDesc.toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 40);
  return `${accountId}|${day}|${amount.toFixed(2)}|${norm}`;
}

const NOISE = new Set(['upi', 'neft', 'imps', 'rtgs', 'ach', 'nach', 'pos', 'atm', 'wdl', 'txn', 'ref', 'pay', 'payment', 'paid',
  'transfer', 'trf', 'credit', 'debit', 'the', 'and', 'for', 'from', 'ltd', 'pvt', 'llp', 'india', 'bank']);
export function narrationTokens(text: string): Set<string> {
  const out = new Set<string>();
  for (const t of text.toLowerCase().match(/[a-z0-9]+/g) ?? []) {
    if (t.length < 3 || /^\d+$/.test(t) || NOISE.has(t)) continue;
    out.add(t);
  }
  return out;
}

/** CategoryMemory: the person's own categorised history suggests a category by shared narration words. */
export class CategoryMemory {
  private readonly entries: Array<{ tokens: Set<string>; categoryId: string; date: Date }> = [];
  constructor(txns: Txn[], cap = 1500) {
    for (const t of [...txns].sort((a, b) => b.date.getTime() - a.date.getTime())) {
      if (this.entries.length >= cap) break;
      if (!t.note?.trim()) continue;
      const cat = t.lines.find((l) => l.categoryId && (l.type === 'expense' || l.type === 'income'))?.categoryId;
      if (!cat) continue;
      const tokens = narrationTokens(t.note);
      if (tokens.size) this.entries.push({ tokens, categoryId: cat, date: t.date });
    }
  }
  suggest(description: string): string | undefined {
    const tokens = narrationTokens(description);
    if (!tokens.size) return undefined;
    let best: string | undefined;
    let bestScore = 0;
    let bestDate: Date | undefined;
    for (const e of this.entries) {
      let score = 0;
      for (const t of tokens) if (e.tokens.has(t)) score += t.length;
      if (score === 0) continue;
      if (score > bestScore || (score === bestScore && (!bestDate || e.date > bestDate))) {
        bestScore = score;
        best = e.categoryId;
        bestDate = e.date;
      }
    }
    return bestScore >= 4 ? best : undefined;
  }
}

const rowInput = z.object({
  date: dateArg('The statement date'),
  amount: z.number().refine((n) => n !== 0, 'amount cannot be 0').describe('Signed: negative is money out of the account (a debit), positive is money in.'),
  description: z.string().optional().describe('The narration as on the statement'),
  reference: z.string().optional().describe('The reference or cheque number, if the statement has one'),
  category_id: z.string().optional().describe('Leave out to use the category learned from past entries, else the default for its direction'),
  due_id: z.string().nullable().optional().describe('Record this row as the payment of that due. Leave out to match dues automatically; null to never link a due.'),
});

export const registerExtraTools: Register = (server, ctx) => {
  // ---- settle up ----
  server.registerTool(
    'settle_up',
    {
      title: 'Settle up with a contact',
      description:
        "One transaction that closes every open debt with a contact: a repayment line for each debt's outstanding, so the total is the net (money in when they were to pay you more, out when you were to pay them more). Call with confirm false first to see the plan.",
      inputSchema: {
        ...workspaceArg,
        contact_id: z.string(),
        account_id: z.string().describe('The account the net money moves through'),
        date: dateArg('When').optional(),
        confirm: z.boolean().describe('false shows what would be posted; true posts it'),
      },
      annotations: WRITE,
    },
    ({ workspace_id, contact_id, account_id, date, confirm }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const contact = await b.getOne('contacts', contact_id);
        await b.getOne('accounts', account_id);
        const [debts, txns] = await Promise.all([b.debts(), b.txns()]);
        const seed = Date.now();
        const lines: Line[] = [];
        const closing: Array<Debt & Plain> = [];
        for (const d of debts) {
          if (d.contactId !== contact_id || d.status !== 'open') continue;
          const out = debtOutstanding(d, txns, b.round);
          if (out <= 0.005) continue;
          closing.push(d);
          lines.push({ lineId: `settle_${seed}_l${lines.length}`, type: 'repayment', amount: b.round(out), debtId: d.id, note: 'Settle-up' });
        }
        if (!lines.length) throw new UserError(`Nothing is open with ${contact.name}.`);
        const total = computeTotal(lines, new Map(closing.map((d) => [d.id, d])), b.round);
        const plan = {
          contact: contact.name,
          debts: closing.map((d) => ({ debt_id: d.id, label: d.label ?? d.purpose, kind: d.direction === 'owed' ? 'receivable' : 'payable', outstanding: lines.find((l) => l.debtId === d.id)!.amount })),
          net: total,
          meaning: total > 0 ? `you collect ${Math.abs(total)}` : `you pay ${Math.abs(total)}`,
          currency: b.ws.currency,
        };
        if (!confirm) return { preview: true, ...plan };
        const when = parseWhen(date, b.timeZone);
        const id = newDocId();
        const doc = b.txnDoc(id, { date: when, accountId: account_id, totalAmount: total, lines, note: `Settle-up with ${contact.name ?? ''}`, contactId: contact_id });
        doc.financialYear = financialYearOf(when, b.ws.fyStartMonth, b.timeZone);
        await b.commit([{ kind: 'set', collection: 'transactions', id, data: doc }, b.revision('transactions', id, 'create')], 'add transactions');
        return { posted: true, transaction_id: id, ...plan };
      }),
  );

  // ---- statement import ----
  server.registerTool(
    'import_transactions',
    {
      title: 'Import a bank statement',
      description:
        "Add a statement's rows to one account, as the app's Import does: one income or expense per row by its sign, duplicates of what the account already has skipped, a category learned from past entries, and a row that equals an open due's remainder (within 92 days) recorded as that due's payment. Call with dry_run true first and show the person the result.",
      inputSchema: {
        ...workspaceArg,
        account_id: z.string(),
        rows: z.array(rowInput).min(1).max(2000),
        duplicates: z
          .enum(['strict', 'date_amount', 'off'])
          .optional()
          .describe('strict (default): same day, amount and description; date_amount: same day and amount; off: import everything'),
        default_expense_category_id: z.string().optional(),
        default_income_category_id: z.string().optional(),
        dry_run: z.boolean().describe('true: only report what would happen'),
      },
      annotations: WRITE,
    },
    (a) =>
      run(async () => {
        const b = await ctx().books(a.workspace_id);
        const tz = b.timeZone;
        await b.getOne('accounts', a.account_id);
        const [rawTxns, categories, dues, debts] = await Promise.all([b.load('transactions'), b.load('categories'), b.dues(), b.debts()]);
        const txns = rawTxns.map(toTxn);
        const catKind = new Map(categories.map((c) => [String(c.id), String(c.kind)]));
        const catName = new Map(categories.map((c) => [String(c.id), String(c.name)]));
        for (const [id, kind] of [[a.default_expense_category_id, 'expense'], [a.default_income_category_id, 'income']] as const) {
          if (id && catKind.get(id) !== kind) throw new UserError(`${id} is not an ${kind} category.`);
        }

        // What the account already has: stored importKeys plus fingerprints of every entry.
        const strict = new Set<string>();
        const dateAmount = new Set<string>();
        for (const t of rawTxns) {
          if (t.accountId !== a.account_id) continue;
          const tt = toTxn(t);
          const d = localDate(tt.date, tz);
          if (typeof t.importKey === 'string' && t.importKey) strict.add(t.importKey);
          strict.add(importFingerprint(a.account_id, d, tt.totalAmount, tt.note ?? ''));
          dateAmount.add(importFingerprint(a.account_id, d, tt.totalAmount, ''));
        }
        const mode = a.duplicates ?? 'strict';
        const memory = new CategoryMemory(txns);
        const settled = new Map(dues.map((d) => [d.id, dueSettledAmount(d, txns, b.round)]));

        const rows = a.rows.map((r, i) => {
          const date = parseWhen(r.date, tz);
          const day = localDate(date, tz);
          const amount = b.round(r.amount);
          const ref = r.reference?.trim() || r.description?.trim() || '';
          const key = importFingerprint(a.account_id, day, amount, ref);
          const duplicate =
            mode === 'strict' ? strict.has(key) : mode === 'date_amount' ? dateAmount.has(importFingerprint(a.account_id, day, amount, '')) : false;
          const want = amount < 0 ? 'expense' : 'income';
          let categoryId = r.category_id;
          let learned = false;
          if (categoryId) {
            if (catKind.get(categoryId) !== want) throw new UserError(`Row ${i + 1}: ${catName.get(categoryId) ?? categoryId} is not an ${want} category.`);
          } else {
            const s = memory.suggest(r.description?.trim() || r.reference?.trim() || '');
            if (s && catKind.get(s) === want) {
              categoryId = s;
              learned = true;
            }
          }
          const note = r.description?.trim() || r.reference?.trim() || undefined;
          return { i, date, day, amount, key, duplicate, categoryId, learned, note, dueId: r.due_id as string | null | undefined };
        });

        // Dues: given, or matched as the app does (sign, remainder to the paisa, closest within 92 days, one row each).
        const used = new Set<string>();
        for (const r of rows) if (r.dueId) {
          const due = dues.find((d) => d.id === r.dueId);
          if (!due) throw new UserError(`Row ${r.i + 1}: no due ${r.dueId}.`);
          used.add(due.id);
        }
        const open = dues.filter((d) => d.status === 'open' || d.status === 'partial');
        for (const r of [...rows].sort((x, y) => x.date.getTime() - y.date.getTime())) {
          if (r.dueId !== undefined || r.duplicate) continue;
          let best: (typeof open)[number] | undefined;
          let gap = Infinity;
          for (const d of open) {
            if (used.has(d.id)) continue;
            const left = d.amount - (settled.get(d.id) ?? 0);
            if (left <= 0.005) continue;
            if (d.direction === 'payable' ? r.amount >= 0 : r.amount <= 0) continue;
            if (Math.abs(Math.abs(r.amount) - left) > 0.01) continue;
            const g = Math.abs(r.date.getTime() - (d.dueDate instanceof Date ? d.dueDate.getTime() : 0));
            if (g > 92 * 86_400_000 || g >= gap) continue;
            best = d;
            gap = g;
          }
          if (best) {
            used.add(best.id);
            r.dueId = best.id;
          }
        }

        const toImport = rows.filter((r) => !r.duplicate);
        const report = rows.map((r) => ({
          row: r.i + 1,
          date: r.day,
          amount: r.amount,
          ...(r.duplicate ? { duplicate: true } : {}),
          ...(r.dueId ? { pays_due: dues.find((d) => d.id === r.dueId)?.title ?? r.dueId, due_id: r.dueId } : {}),
          ...(!r.dueId && !r.duplicate
            ? { category: catName.get(r.categoryId ?? (r.amount < 0 ? a.default_expense_category_id : a.default_income_category_id) ?? '') ?? null, ...(r.learned ? { learned: true } : {}) }
            : {}),
        }));
        const summary = {
          rows: rows.length,
          to_import: toImport.length,
          duplicates_skipped: rows.length - toImport.length,
          due_payments: toImport.filter((r) => r.dueId).length,
        };
        if (a.dry_run) return { dry_run: true, ...summary, detail: report };

        const debtsById = new Map(debts.map((d) => [d.id, d]));
        const writes: Write[] = [];
        const runningSettled = new Map(settled);
        for (const r of toImport) {
          const id = newDocId();
          let doc: Plain;
          if (r.dueId) {
            const due = dues.find((d) => d.id === r.dueId)!;
            const amount = Math.abs(r.amount);
            const s = settlement(b, due, amount, debtsById as Map<string, never>, r.date.getTime() * 1000 + writes.length);
            doc = b.txnDoc(id, { date: r.date, accountId: a.account_id, totalAmount: s.signedTotal, lines: s.lines, note: r.note ?? String(due.title ?? ''), contactId: (due.contactId as string | undefined) ?? null, dueId: due.id });
            const now = (runningSettled.get(due.id) ?? 0) + amount;
            runningSettled.set(due.id, now);
            writes.push({ kind: 'update', collection: 'dues', id: due.id, data: { status: dueStatusFromSettled(due, now), updatedBy: { uid: b.actor.uid, name: b.actor.name }, updatedAt: SERVER_TIME } });
            writes.push(b.revision('dues', due.id, 'update', undefined, ['status']));
          } else {
            const categoryId = r.categoryId ?? (r.amount < 0 ? a.default_expense_category_id : a.default_income_category_id);
            const line: Line = { lineId: `${id}_l0`, type: r.amount >= 0 ? 'income' : 'expense', amount: b.round(Math.abs(r.amount)), ...(categoryId ? { categoryId } : {}) };
            doc = b.txnDoc(id, { date: r.date, accountId: a.account_id, totalAmount: r.amount, lines: [line], note: r.note });
          }
          doc.financialYear = financialYearOf(r.date, b.ws.fyStartMonth, tz);
          doc.importKey = r.key;
          writes.push({ kind: 'set', collection: 'transactions', id, data: doc }, b.revision('transactions', id, 'create'));
        }
        // Chunks well under Firestore's 500 writes, as the app's 200 rows.
        for (let i = 0; i < writes.length; i += 400) await b.commit(writes.slice(i, i + 400), 'add transactions');
        return { imported: true, ...summary, detail: report };
      }),
  );

  // ---- reports ----
  server.registerTool(
    'get_tax_summary',
    {
      title: 'Tax summary',
      description:
        "The Reports Tax tab for a financial year: taxable income by tax head. For books in INR, also TDS by head, taxable and TDS by contact (to check against Form 26AS), and every taxable line: the tax pack's contents.",
      inputSchema: { ...workspaceArg, fy: fyArg },
      annotations: READ,
    },
    ({ workspace_id, fy }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const r = fyRange(b, fy);
        const india = b.ws.currency === 'INR';
        const [txns, contacts] = await Promise.all([b.txns(), b.load('contacts')]);
        const contactName = new Map(contacts.map((c) => [String(c.id), String(c.name ?? '')]));
        const heads = new Map<string, { taxable: number; tds: number; lines: number }>();
        const byContact = new Map<string, { taxable: number; tds: number }>();
        const register: Array<Record<string, unknown>> = [];
        let totalTaxable = 0;
        let totalTds = 0;
        for (const t of txns) {
          if (t.date < r.start || t.date >= r.end) continue;
          const who = t.contactId ? (contactName.get(t.contactId) ?? 'Unknown') : '(no contact)';
          for (const l of t.lines) {
            const tax = l.tax;
            if (!tax || tax.taxable !== true) continue;
            const head = typeof tax.head === 'string' ? tax.head : 'other';
            const tds = typeof tax.tdsAmount === 'number' ? tax.tdsAmount : 0;
            const h = heads.get(head) ?? { taxable: 0, tds: 0, lines: 0 };
            h.taxable += l.amount;
            h.tds += tds;
            h.lines++;
            heads.set(head, h);
            const c = byContact.get(who) ?? { taxable: 0, tds: 0 };
            c.taxable += l.amount;
            c.tds += tds;
            byContact.set(who, c);
            totalTaxable += l.amount;
            totalTds += tds;
            register.push({ date: localDate(t.date, b.timeZone), description: t.note || 'Transaction', head: headLabel(head), taxable: b.round(l.amount), tds: b.round(tds), transaction_id: t.id });
          }
        }
        register.sort((x, y) => String(x.date).localeCompare(String(y.date)));
        return {
          fy: r.fy,
          currency: b.ws.currency,
          total_taxable: b.round(totalTaxable),
          ...(india ? { total_tds: b.round(totalTds) } : {}),
          by_head: [...heads.entries()]
            .sort(([, x], [, y]) => y.taxable - x.taxable)
            .map(([head, h]) => ({ head, label: headLabel(head), taxable: b.round(h.taxable), ...(india ? { tds: b.round(h.tds) } : {}), lines: h.lines })),
          ...(india
            ? {
                by_contact: [...byContact.entries()]
                  .sort(([, x], [, y]) => y.tds - x.tds)
                  .map(([contact, c]) => ({ contact, taxable: b.round(c.taxable), tds: b.round(c.tds) })),
                lines: register,
              }
            : {}),
        };
      }),
  );

  server.registerTool(
    'get_net_worth',
    {
      title: 'Net worth by month',
      description: "Month-end net worth across a financial year, as the Reports chart draws it: every account's balance, less what you are to pay, plus what you are to receive. Months not yet begun are left out.",
      inputSchema: { ...workspaceArg, fy: fyArg },
      annotations: READ,
    },
    ({ workspace_id, fy }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const r = fyRange(b, fy);
        const tz = b.timeZone;
        const [accounts, debts, txns] = await Promise.all([b.load('accounts'), b.debts(), b.txns()]);
        const debtsById = new Map(debts.map((d) => [d.id, d]));
        const sorted = [...txns].sort((x, y) => x.date.getTime() - y.date.getTime());
        let total = accounts.reduce((s, a) => s + Number(a.openingBalance ?? 0), 0);
        const out = new Map<string, number>();
        const now = new Date();
        const points: Array<{ month: string; net_worth: number; accounts: number; to_pay: number; to_receive: number }> = [];
        let idx = 0;
        const [sy, sm] = localDate(r.start, tz).split('-').map(Number) as [number, number];
        for (let k = 0; k < 12; k++) {
          const y = sy + Math.floor((sm - 1 + k) / 12);
          const m = ((sm - 1 + k) % 12) + 1;
          const monthStart = parseWhen(`${y}-${String(m).padStart(2, '0')}-01`, tz);
          if (monthStart > now) break;
          const ny = y + Math.floor(m / 12);
          const nm = (m % 12) + 1;
          const cutoff = parseWhen(`${ny}-${String(nm).padStart(2, '0')}-01`, tz);
          while (idx < sorted.length && sorted[idx]!.date < cutoff) {
            const t = sorted[idx]!;
            for (const v of accountDeltas(t, debtsById, b.round).values()) total += v;
            for (const l of t.lines) {
              const d = l.debtId ? debtsById.get(l.debtId) : undefined;
              if (!d) continue;
              const establishing = d.direction === 'owe' ? 'borrow' : 'lend';
              if (l.type === establishing) out.set(d.id, (out.get(d.id) ?? 0) + l.amount);
              else if (l.type === 'repayment') out.set(d.id, (out.get(d.id) ?? 0) - l.amount);
            }
            idx++;
          }
          let pay = 0;
          let receive = 0;
          for (const d of debts) {
            const o = out.get(d.id) ?? 0;
            if (d.direction === 'owe') pay += o;
            else receive += o;
          }
          points.push({ month: `${y}-${String(m).padStart(2, '0')}`, net_worth: b.round(total - pay + receive), accounts: b.round(total), to_pay: b.round(pay), to_receive: b.round(receive) });
        }
        return { fy: r.fy, currency: b.ws.currency, months: points };
      }),
  );

  server.registerTool(
    'get_contact_report',
    {
      title: 'Money by contact',
      description: 'The Reports By contact tab for a financial year: per contact, what came in and what went out in transactions with them.',
      inputSchema: { ...workspaceArg, fy: fyArg },
      annotations: READ,
    },
    ({ workspace_id, fy }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const r = fyRange(b, fy);
        const [txns, contacts] = await Promise.all([b.txns(), b.load('contacts')]);
        const name = new Map(contacts.map((c) => [String(c.id), String(c.name ?? '')]));
        const m = new Map<string, { received: number; paid: number }>();
        for (const t of txns) {
          if (!t.contactId || t.date < r.start || t.date >= r.end) continue;
          const x = m.get(t.contactId) ?? { received: 0, paid: 0 };
          if (t.totalAmount >= 0) x.received += t.totalAmount;
          else x.paid -= t.totalAmount;
          m.set(t.contactId, x);
        }
        return {
          fy: r.fy,
          currency: b.ws.currency,
          contacts: [...m.entries()]
            .map(([id, x]) => ({ contact_id: id, contact: name.get(id) ?? 'Unknown', received: b.round(x.received), paid: b.round(x.paid) }))
            .sort((x, y) => y.received + y.paid - (x.received + x.paid)),
        };
      }),
  );

  // ---- leaving for good ----
  server.registerTool(
    'delete_my_account',
    {
      title: 'Delete my Niz Khata account',
      description:
        'Permanently delete the signed-in person\'s account: every workspace they own with everything in it (for all its members), their place in workspaces others own, their shared ledger entries, connections and invites, their devices and profile, and the sign-in itself. It cannot be undone. Only when the person asks for it in so many words; confirm must be "DELETE". It needs a sign-in from the last 5 minutes: if refused, the person reconnects the connector and asks again.',
      inputSchema: { confirm: z.literal('DELETE') },
      annotations: DESTRUCTIVE,
    },
    () =>
      run(async () => {
        const c = ctx();
        if (!c.deleteSignIn || c.authTime === undefined) throw new UserError('Deleting the account is not available here. Use Profile > Delete account in the app.');
        if (Date.now() / 1000 - c.authTime > 300) {
          throw new UserError('For safety this needs a fresh sign-in. Disconnect and reconnect the Niz Khata connector, then ask again within 5 minutes. Nothing was deleted.');
        }
        const report = await eraseAccount(c);
        await c.deleteSignIn();
        return { deleted: true, ...report };
      }),
  );
};

/** AccountEraser.eraseAccount: owned workspaces deleted, others left, then shared, devices and profile. */
export async function eraseAccount(c: Ctx) {
  const fs = c.fs;
  const uid = c.actor.uid;
  const report = { workspaces_deleted: 0, workspaces_left: 0, documents_deleted: 0 };
  const del = async (collection: string, ids: string[]) => {
    for (let i = 0; i < ids.length; i += 400) await fs.commit(ids.slice(i, i + 400).map((id) => ({ kind: 'delete' as const, collection, id })));
    return ids.length;
  };
  for (const m of await fs.where('memberships', 'uid', uid)) {
    const wsId = String(m.workspaceId ?? '');
    if (!wsId) continue;
    const ws = await fs.get('workspaces', wsId).catch(() => null);
    if (ws && ws.ownerId === uid) {
      const b = await c.books(wsId);
      report.documents_deleted += await eraseWorkspace(b);
      report.workspaces_deleted++;
    } else if (!ws) {
      for (const col of ['transactions', 'dues', 'debts', 'budgets', 'contacts', 'accounts', 'invites', 'revisions', 'categories', 'roles']) {
        try {
          report.documents_deleted += await del(col, (await fs.where(col, 'workspaceId', wsId)).map((d) => String(d.id)));
        } catch (e) {
          if (!(e instanceof FirestoreError && e.status === 403)) throw e;
        }
      }
      await del('memberships', [String(m.id)]);
    } else {
      await del('memberships', [String(m.id)]);
      report.workspaces_left++;
    }
  }
  const entries = await fs.where('sharedEntries', 'uids', uid, 'ARRAY_CONTAINS');
  report.documents_deleted += await del('sharedEntries', entries.filter((e) => e.creatorUid === uid).map((e) => String(e.id)));
  report.documents_deleted += await del('sharedConnections', (await fs.where('sharedConnections', 'uids', uid, 'ARRAY_CONTAINS')).map((d) => String(d.id)));
  report.documents_deleted += await del('shareInvites', (await fs.where('shareInvites', 'fromUid', uid)).map((d) => String(d.id)));
  report.documents_deleted += await del('devices', (await fs.where('devices', 'uid', uid)).map((d) => String(d.id)));
  report.documents_deleted += await del('users', [uid]);
  return report;
}
