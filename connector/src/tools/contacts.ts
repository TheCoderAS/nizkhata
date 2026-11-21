import { z } from 'zod';

import { UserError } from '../books.js';
import type { Plain } from '../firestore.js';
import { contactPosition, debtOutstanding } from '../ledger.js';
import { DESTRUCTIVE, READ, WRITE, OVERWRITE, day, run, workspaceArg, type Register } from './common.js';

/** The app's email shape: [{value, label}] with blanks dropped, plus the legacy single `email`. */
type EmailIn = string | { value: string; label?: 'Personal' | 'Work' | 'Other' };

/** The app's emails: each a value and a label (Personal, Work or Other); a bare address is Personal, as the form starts. */
function emailFields(emails: EmailIn[] | null | undefined): Plain {
  if (emails === undefined) return {};
  const clean = (emails ?? [])
    .map((e) => (typeof e === 'string' ? { value: e.trim(), label: 'Personal' } : { value: e.value.trim(), label: e.label ?? 'Personal' }))
    .filter((e) => e.value);
  return { emails: clean, email: clean.length ? clean[0]!.value : null };
}

const fields = {
  type: z.enum(['person', 'business']).describe('person (default) or business'),
  relationship: z.enum(['external', 'family']).describe('external (default) or family'),
  phone: z.string(),
  emails: z.array(
    z.union([z.string(), z.object({ value: z.string(), label: z.enum(['Personal', 'Work', 'Other']).optional() })]),
  ).describe('Addresses, plain or with a label (Personal, Work, Other), as in the app'),
  address: z.string(),
  notes: z.string(),
};

export const registerContactTools: Register = (server, ctx) => {
  server.registerTool(
    'list_contacts',
    {
      title: 'List contacts',
      description:
        'People and businesses in the workspace, with where each stands: net > 0 means money is due to you from them, net < 0 means you have it to pay them.',
      inputSchema: { ...workspaceArg, search: z.string().optional().describe('Match on name, phone or email') },
      annotations: READ,
    },
    ({ workspace_id, search }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const [contacts, debts, txns] = await Promise.all([b.load('contacts'), b.debts(), b.txns()]);
        const q = search?.trim().toLowerCase();
        return {
          currency: b.ws.currency,
          contacts: contacts
            .filter((c) => !c.connectionUid)
            .filter((c) => !q || [c.name, c.phone, c.email].some((v) => String(v ?? '').toLowerCase().includes(q)))
            .map((c) => {
              const p = contactPosition(String(c.id), debts, txns, b.round);
              return { id: c.id, name: c.name, type: c.type, phone: c.phone, email: c.email, net: p.net };
            }),
        };
      }),
  );

  server.registerTool(
    'get_contact',
    {
      title: 'Get a contact',
      description: "One contact's details, their debts with what is outstanding, and their recent transactions.",
      inputSchema: { ...workspaceArg, contact_id: z.string() },
      annotations: READ,
    },
    ({ workspace_id, contact_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const c = await b.getOne('contacts', contact_id);
        const [debts, txns] = await Promise.all([b.debts(), b.txns()]);
        const tz = b.timeZone;
        const p = contactPosition(contact_id, debts, txns, b.round);
        return {
          currency: b.ws.currency,
          contact: {
            id: c.id, name: c.name, type: c.type, relationship: c.relationship, phone: c.phone,
            emails: ((c.emails as Plain[] | undefined) ?? []).map((e) => ({ value: e.value, label: e.label ?? 'Other' })), address: c.address, notes: c.notes,
          },
          position: { net: p.net, total_in: p.totalIn, total_out: p.totalOut },
          debts: debts
            .filter((d) => d.contactId === contact_id)
            .map((d) => ({ id: d.id, label: d.label, direction: d.direction, outstanding: debtOutstanding(d, txns, b.round) })),
          recent_transactions: txns
            .filter((t) => t.contactId === contact_id)
            .sort((x, y) => y.date.getTime() - x.date.getTime())
            .slice(0, 15)
            .map((t) => ({ id: t.id, date: day(t.date, tz), note: t.note, total: t.totalAmount })),
        };
      }),
  );

  server.registerTool(
    'create_contact',
    {
      title: 'Create a contact',
      description: 'Add a person or business to the workspace.',
      inputSchema: {
        ...workspaceArg,
        name: z.string().min(1),
        type: fields.type.optional(),
        relationship: fields.relationship.optional(),
        phone: fields.phone.optional(),
        emails: fields.emails.optional(),
        address: fields.address.optional(),
        notes: fields.notes.optional(),
      },
      annotations: WRITE,
    },
    (a) =>
      run(async () => {
        const b = await ctx().books(a.workspace_id);
        const data: Plain = {
          name: a.name.trim(),
          type: a.type ?? 'person',
          relationship: a.relationship ?? 'external',
          phone: a.phone?.trim() || null,
          address: a.address?.trim() || null,
          notes: a.notes?.trim() || null,
          ...emailFields(a.emails ?? []),
        };
        const { id, writes } = b.createWrites('contacts', data);
        await b.commit(writes, 'add contacts');
        return { created: true, id, name: data.name };
      }),
  );

  server.registerTool(
    'update_contact',
    {
      title: 'Update a contact',
      description: 'Change a contact. Only the fields given change; pass null to clear an optional field.',
      inputSchema: {
        ...workspaceArg,
        contact_id: z.string(),
        name: z.string().min(1).optional(),
        type: fields.type.optional(),
        relationship: fields.relationship.optional(),
        phone: fields.phone.nullable().optional(),
        emails: fields.emails.nullable().optional(),
        address: fields.address.nullable().optional(),
        notes: fields.notes.nullable().optional(),
      },
      annotations: OVERWRITE,
    },
    (a) =>
      run(async () => {
        const b = await ctx().books(a.workspace_id);
        await b.getOne('contacts', a.contact_id);
        const data: Plain = {};
        for (const k of ['name', 'type', 'relationship', 'phone', 'address', 'notes'] as const) {
          if (a[k] !== undefined) data[k] = typeof a[k] === 'string' ? (a[k] as string).trim() || null : a[k];
        }
        Object.assign(data, emailFields(a.emails));
        if (Object.keys(data).length === 0) throw new UserError('Nothing to change.');
        await b.commit(b.updateWrites('contacts', a.contact_id, data), 'edit contacts');
        return { updated: true, id: a.contact_id, changed: Object.keys(data) };
      }),
  );

  server.registerTool(
    'delete_contact',
    {
      title: 'Delete a contact',
      description: 'Remove a contact. Their transactions are kept. It can be brought back with restore_deleted.',
      inputSchema: { ...workspaceArg, contact_id: z.string() },
      annotations: DESTRUCTIVE,
    },
    ({ workspace_id, contact_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const c = await b.getOne('contacts', contact_id);
        await b.commit(b.deleteWrites('contacts', contact_id, c), 'delete contacts');
        return { deleted: true, id: contact_id, name: c.name };
      }),
  );
};
