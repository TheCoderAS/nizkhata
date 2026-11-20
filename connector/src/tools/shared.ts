// The shared ledger: entries kept with another Niz Khata user (Splitwise
// style), ported from mobile/lib/data/shared_mutations.dart.
//
// The model, as in the app:
//   - An entry is between two people. The creator already paid, so their own
//     books record the money now (a lend against a hidden "shared" debt with
//     the partner). The partner consents: accepting records an account-less
//     debt in their books; rejecting leaves a conflict on the creator's side.
//   - A settlement is the payer saying "I paid you": their outflow is recorded
//     now, the partner's inflow when they accept.
//   - Each side writes only to its own workspace. The cross-user sharedEntries
//     document is the only thing both can see, and the other person sees it
//     as soon as it is written.
//   - Amounts are in the creator's workspace currency and are never converted:
//     an entry is only recorded in books kept in its own currency.

import { z } from 'zod';

import { UserError, strip, type Books } from '../books.js';
import { newDocId, SERVER_TIME, type Plain, type Write } from '../firestore.js';
import { financialYearOf, makeRound, parseWhen } from '../ledger.js';
import { READ, WRITE, run, workspaceArg, type Ctx, type Register } from './common.js';

const EXTERNAL_ACCOUNT = '__external__';

interface Partner {
  uid: string;
  name: string;
  email: string;
  connectionId: string;
}

async function partners(c: Ctx): Promise<Partner[]> {
  const me = c.actor.uid;
  const conns = await c.fs.where('sharedConnections', 'uids', me, 'ARRAY_CONTAINS');
  return conns
    .filter((x) => x.status !== 'revoked')
    .map((x) => {
      const uids = (x.uids as string[]) ?? [];
      const other = uids.find((u) => u !== me) ?? '';
      const names = (x.names as Record<string, string>) ?? {};
      const emails = (x.emails as Record<string, string>) ?? {};
      return { uid: other, name: names[other] ?? emails[other] ?? 'Partner', email: emails[other] ?? '', connectionId: String(x.id) };
    })
    .filter((p) => p.uid);
}

function findPartner(all: Partner[], idOrName: string): Partner {
  const q = idOrName.trim().toLowerCase();
  const hit =
    all.find((p) => p.uid === idOrName || p.connectionId === idOrName) ??
    all.find((p) => p.email.toLowerCase() === q) ??
    all.filter((p) => p.name.toLowerCase() === q).at(0);
  if (!hit) {
    throw new UserError(
      all.length
        ? `No shared ledger with "${idOrName}". You share with: ${all.map((p) => `${p.name} (${p.uid})`).join(', ')}.`
        : 'You do not share a ledger with anyone yet. Invite someone from Shared in the app first.',
    );
  }
  return hit;
}

/** The currency a stored entry is in; entries from before the field existed came from INR books. */
const entryCurrency = (v: unknown) => (typeof v === 'string' && /^[A-Za-z]{3}$/.test(v) ? v.toUpperCase() : 'INR');

function sameCurrency(entry: string, books: string) {
  if (entry !== books) {
    throw new UserError(
      `This is in ${entry}, and this workspace keeps its books in ${books}. Amounts are never converted, so to record it, use a workspace kept in ${entry}.`,
    );
  }
}

/**
 * Find or create, in one batch, the hidden contact that stands for a partner
 * and the aggregate "shared" debt per direction, as _ReflectionCtx does.
 */
class Reflection {
  private readonly newContacts = new Map<string, string>();
  private readonly newDebts = new Map<string, string>();
  constructor(
    private readonly b: Books,
    private readonly contacts: Plain[],
    private readonly debts: Plain[],
    readonly writes: Write[],
  ) {}

  static async open(b: Books, writes: Write[] = []) {
    const [contacts, debts] = await Promise.all([b.load('contacts'), b.load('debts')]);
    return new Reflection(b, contacts, debts, writes);
  }

  contact(uid: string, name: string): string {
    const hit = this.contacts.find((c) => c.connectionUid === uid)?.id ?? this.newContacts.get(uid);
    if (hit) return String(hit);
    const { id, writes } = this.b.createWrites('contacts', { name, type: 'person', connectionUid: uid });
    this.writes.push(...writes);
    this.newContacts.set(uid, id);
    return id;
  }

  debt(contactId: string, direction: 'owe' | 'owed'): string {
    const key = `${contactId}|${direction}`;
    const hit =
      this.debts.find((d) => d.purpose === 'shared' && d.contactId === contactId && d.direction === direction)?.id ??
      this.newDebts.get(key);
    if (hit) return String(hit);
    const { id, writes } = this.b.createWrites('debts', { contactId, direction, purpose: 'shared', principal: 0, status: 'open' });
    this.writes.push(...writes);
    this.newDebts.set(key, id);
    return id;
  }

  /** A single-line reflection transaction linked back to the shared entry. */
  txn(o: { sharedEntryId: string; contactId: string; accountId: string; line: Plain; totalAmount: number; date: Date; note: string }) {
    const id = newDocId();
    this.writes.push(
      {
        kind: 'set',
        collection: 'transactions',
        id,
        data: {
          ...this.b.txnDoc(id, {
            date: o.date,
            accountId: o.accountId,
            totalAmount: o.totalAmount,
            lines: [strip(o.line) as never],
            note: o.note,
            contactId: o.contactId,
          }),
          sharedEntryId: o.sharedEntryId,
          financialYear: financialYearOf(o.date, this.b.ws.fyStartMonth, this.b.timeZone),
        },
      },
      this.b.revision('transactions', id, 'create'),
    );
    return id;
  }
}

export const registerSharedTools: Register = (server, ctx) => {
  server.registerTool(
    'list_shared',
    {
      title: 'Shared ledger',
      description:
        'The people you keep a shared ledger with, what each owes the other (per currency), and recent shared entries. Entries waiting_for_you need your answer (respond_shared_entry); a conflict is an entry of yours the other person rejected.',
      inputSchema: { partner: z.string().optional().describe('A partner id, email or name, to see only entries with them.'), limit: z.number().int().min(1).max(200).optional() },
      annotations: READ,
    },
    ({ partner, limit }) =>
      run(async () => {
        const c = ctx();
        const me = c.actor.uid;
        const all = await partners(c);
        const only = partner ? findPartner(all, partner) : undefined;
        const entries = (await c.fs.where('sharedEntries', 'uids', me, 'ARRAY_CONTAINS'))
          .filter((e) => !only || (e.uids as string[]).includes(only.uid))
          .sort((a, b) => (b.date as Date).getTime() - (a.date as Date).getTime());

        // sharedBalances: accepted entries, plus pending ones on the side that already moved money.
        const net = new Map<string, number>();
        for (const e of entries) {
          if (e.status === 'rejected') continue;
          if (e.status === 'pending' && e.creatorUid !== me) continue;
          const other = e.creatorUid === me ? String(e.counterpartyUid) : String(e.creatorUid);
          const key = `${other}|${entryCurrency(e.currency)}`;
          net.set(key, (net.get(key) ?? 0) + (e.payerUid === me ? Number(e.amount) : -Number(e.amount)));
        }
        const nameOf = (uid: string) => all.find((p) => p.uid === uid)?.name ?? uid;
        const balances = [...net.entries()]
          .map(([key, n]) => {
            const [uid, currency] = key.split('|') as [string, string];
            const rounded = makeRound(currency)(n);
            return { partner_id: uid, partner: nameOf(uid), currency, net: rounded };
          })
          .filter((x) => Math.abs(x.net) >= 0.005)
          .map((x) => ({ ...x, meaning: x.net > 0 ? `${x.partner} is to pay you` : `you are to pay ${x.partner}` }));

        return {
          partners: (only ? [only] : all).map((p) => ({ partner_id: p.uid, name: p.name, email: p.email })),
          balances,
          entries: entries.slice(0, limit ?? 30).map((e) => {
            const other = e.creatorUid === me ? String(e.counterpartyUid) : String(e.creatorUid);
            return {
              id: e.id,
              kind: e.kind,
              with: nameOf(other),
              description: e.description,
              amount: e.amount,
              currency: entryCurrency(e.currency),
              date: e.date instanceof Date ? e.date.toISOString().slice(0, 10) : undefined,
              status: e.status,
              you_created_it: e.creatorUid === me,
              you_paid: e.payerUid === me,
              ...(((e.pendingForUids as string[]) ?? []).includes(me) ? { waiting_for_you: true } : {}),
              ...(e.status === 'rejected' && e.creatorUid === me && e.resolved !== true ? { conflict: true } : {}),
            };
          }),
        };
      }),
  );

  server.registerTool(
    'add_shared_expense',
    {
      title: 'Add a shared expense',
      description:
        'Record an expense you paid and split with one or more people you share a ledger with. Your account is debited the full amount now; each person is asked to accept their share and sees it straight away. Shares default to an equal split between you and them.',
      inputSchema: {
        ...workspaceArg,
        description: z.string().min(1),
        amount: z.number().positive().describe('The total you paid.'),
        account_id: z.string().describe('The account you paid from.'),
        partners: z
          .array(z.object({ partner: z.string().describe('Partner id, email or name.'), share: z.number().positive().optional() }))
          .min(1),
        my_category_id: z.string().optional().describe('Expense category for your own share.'),
        date: z.string().optional(),
      },
      annotations: WRITE,
    },
    ({ workspace_id, description, amount, account_id, partners: wanted, my_category_id, date }) =>
      run(async () => {
        const c = ctx();
        const b = await c.books(workspace_id);
        const me = c.actor.uid;
        await b.getOne('accounts', account_id);
        if (my_category_id) {
          const cat = await b.getOne('categories', my_category_id);
          if (cat.kind !== 'expense') throw new UserError(`${cat.name} is not an expense category.`);
        }
        const all = await partners(c);
        const people = wanted.map((w) => ({ p: findPartner(all, w.partner), share: w.share }));
        if (new Set(people.map((x) => x.p.uid)).size !== people.length) throw new UserError('A person is listed twice.');
        const unset = people.filter((x) => x.share === undefined).length;
        const given = people.reduce((s, x) => s + (x.share ?? 0), 0);
        const each = unset ? b.round((amount - given) / (unset + 1)) : 0;
        const shares = people.map((x) => ({ ...x, share: x.share ?? each }));
        const myShare = b.round(amount - shares.reduce((s, x) => s + x.share, 0));
        if (myShare < -0.005 || shares.some((x) => x.share <= 0)) throw new UserError('The shares add up to more than the amount.');

        const when = parseWhen(date, b.timeZone);
        const r = await Reflection.open(b);
        const name = c.actor.name;
        if (myShare > 0.005) {
          const id = newDocId();
          r.writes.push(
            {
              kind: 'set',
              collection: 'transactions',
              id,
              data: {
                ...b.txnDoc(id, {
                  date: when,
                  accountId: account_id,
                  totalAmount: -myShare,
                  note: `${description} (my share)`,
                  lines: [strip({ lineId: `share_${Date.now()}`, type: 'expense', amount: myShare, categoryId: my_category_id, note: 'My share' }) as never],
                }),
                financialYear: financialYearOf(when, b.ws.fyStartMonth, b.timeZone),
              },
            },
            b.revision('transactions', id, 'create'),
          );
        }
        const created: Array<{ entry_id: string; with: string; share: number }> = [];
        for (const { p, share } of shares) {
          const entryId = newDocId();
          r.writes.push({
            kind: 'set',
            collection: 'sharedEntries',
            id: entryId,
            data: {
              id: entryId,
              connectionId: p.connectionId,
              kind: 'expense',
              uids: [me, p.uid],
              creatorUid: me,
              counterpartyUid: p.uid,
              names: { [me]: name, [p.uid]: p.name },
              payerUid: me,
              description,
              amount: share,
              currency: b.ws.currency,
              date: when,
              status: 'pending',
              pendingForUids: [p.uid],
              createdBy: c.actor,
              createdAt: SERVER_TIME,
              updatedBy: c.actor,
              updatedAt: SERVER_TIME,
            },
          });
          const contactId = r.contact(p.uid, p.name);
          const debtId = r.debt(contactId, 'owed');
          r.txn({
            sharedEntryId: entryId,
            contactId,
            accountId: account_id,
            line: { lineId: `lend_${entryId}`, type: 'lend', amount: share, debtId, note: description },
            totalAmount: -share,
            date: when,
            note: description,
          });
          created.push({ entry_id: entryId, with: p.name, share });
        }
        await b.commit(r.writes, 'add shared entries');
        return { created: true, currency: b.ws.currency, my_share: Math.max(myShare, 0), entries: created, status: 'waiting for them to accept' };
      }),
  );

  server.registerTool(
    'record_shared_settlement',
    {
      title: 'Record paying someone back',
      description:
        'Record that you paid a person you share a ledger with, to settle up. Your account is debited now; they are asked to confirm it and see it straight away.',
      inputSchema: {
        ...workspaceArg,
        partner: z.string(),
        amount: z.number().positive(),
        account_id: z.string().describe('The account you paid from.'),
        description: z.string().optional(),
        date: z.string().optional(),
      },
      annotations: WRITE,
    },
    ({ workspace_id, partner, amount, account_id, description, date }) =>
      run(async () => {
        const c = ctx();
        const b = await c.books(workspace_id);
        const me = c.actor.uid;
        await b.getOne('accounts', account_id);
        const p = findPartner(await partners(c), partner);
        const when = parseWhen(date, b.timeZone);
        const note = description?.trim() || 'Settlement';
        const r = await Reflection.open(b);
        const entryId = newDocId();
        r.writes.push({
          kind: 'set',
          collection: 'sharedEntries',
          id: entryId,
          data: {
            id: entryId,
            connectionId: p.connectionId,
            kind: 'settlement',
            uids: [me, p.uid],
            creatorUid: me,
            counterpartyUid: p.uid,
            names: { [me]: c.actor.name, [p.uid]: p.name },
            payerUid: me,
            description: note,
            amount: b.round(amount),
            currency: b.ws.currency,
            date: when,
            status: 'pending',
            pendingForUids: [p.uid],
            createdBy: c.actor,
            createdAt: SERVER_TIME,
            updatedBy: c.actor,
            updatedAt: SERVER_TIME,
          },
        });
        const contactId = r.contact(p.uid, p.name);
        const debtId = r.debt(contactId, 'owe');
        r.txn({
          sharedEntryId: entryId,
          contactId,
          accountId: account_id,
          line: { lineId: `settle_${entryId}`, type: 'repayment', amount: b.round(amount), debtId, note },
          totalAmount: -b.round(amount),
          date: when,
          note,
        });
        await b.commit(r.writes, 'add shared entries');
        return { created: true, entry_id: entryId, with: p.name, amount: b.round(amount), currency: b.ws.currency, status: 'waiting for them to confirm' };
      }),
  );

  server.registerTool(
    'respond_shared_entry',
    {
      title: 'Accept or reject a shared entry',
      description:
        'Answer a shared expense or settlement someone else added (marked waiting_for_you in list_shared). Accepting records it in your books; for a settlement, account_id is where the money arrived (without it, only the balance changes).',
      inputSchema: {
        ...workspaceArg,
        entry_id: z.string(),
        accept: z.boolean(),
        account_id: z.string().optional(),
      },
      annotations: WRITE,
    },
    ({ workspace_id, entry_id, accept, account_id }) =>
      run(async () => {
        const c = ctx();
        const me = c.actor.uid;
        const e = await c.fs.get('sharedEntries', entry_id).catch(() => null);
        if (!e || !((e.uids as string[]) ?? []).includes(me)) throw new UserError(`No shared entry ${entry_id}.`);
        if (e.counterpartyUid !== me) throw new UserError('You created this entry; only the other person can answer it.');
        if (e.status !== 'pending') throw new UserError(`This entry is already ${e.status}.`);
        const stamp = { updatedBy: c.actor, updatedAt: SERVER_TIME };
        if (!accept) {
          await c.fs.commit([{ kind: 'update', collection: 'sharedEntries', id: entry_id, data: { status: 'rejected', pendingForUids: [], ...stamp } }]);
          return { rejected: true, entry_id };
        }
        const b = await c.books(workspace_id);
        const currency = entryCurrency(e.currency);
        sameCurrency(currency, b.ws.currency);
        const amount = Number(e.amount);
        const date = e.date instanceof Date ? e.date : new Date();
        const names = (e.names as Record<string, string>) ?? {};
        const r = await Reflection.open(b, [
          { kind: 'update', collection: 'sharedEntries', id: entry_id, data: { status: 'accepted', pendingForUids: [], ...stamp } },
        ]);
        const description = String(e.description ?? '');
        if (e.kind === 'settlement') {
          if (account_id) await b.getOne('accounts', account_id);
          const payer = String(e.payerUid);
          const contactId = r.contact(payer, names[payer] ?? 'Partner');
          const debtId = r.debt(contactId, 'owed');
          r.txn({
            sharedEntryId: entry_id,
            contactId,
            accountId: account_id ?? EXTERNAL_ACCOUNT,
            line: { lineId: `settle_${entry_id}`, type: 'repayment', amount, debtId, note: description, ...(account_id ? {} : { external: true }) },
            totalAmount: account_id ? amount : 0,
            date,
            note: description,
          });
        } else {
          const creator = String(e.creatorUid);
          const contactId = r.contact(creator, names[creator] ?? 'Partner');
          const debtId = r.debt(contactId, 'owe');
          r.txn({
            sharedEntryId: entry_id,
            contactId,
            accountId: EXTERNAL_ACCOUNT, // balance-only until you actually settle
            line: { lineId: `borrow_${entry_id}`, type: 'borrow', amount, debtId, note: description, external: true },
            totalAmount: 0,
            date,
            note: description,
          });
        }
        await b.commit(r.writes, 'add shared entries');
        return { accepted: true, entry_id, kind: e.kind, amount, currency };
      }),
  );
};
