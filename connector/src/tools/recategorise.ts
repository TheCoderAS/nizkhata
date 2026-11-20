// recategorise_transactions: the app's bulk categorise (bulkSetTxnCategory),
// one commit per 200 entries, each with its revision. By default only lines
// without a category are filled in, exactly as the app does; from_category_id
// moves lines out of one category into another instead.

import { z } from 'zod';

import { UserError } from '../books.js';
import type { Plain, Write } from '../firestore.js';
import { strip } from '../books.js';
import { OVERWRITE, run, workspaceArg, type Register } from './common.js';

const CHUNK = 200;

export const registerRecategoriseTools: Register = (server, ctx) => {
  server.registerTool(
    'recategorise_transactions',
    {
      title: 'Recategorise transactions',
      description:
        'Set the category on many transactions at once. By default only uncategorised lines of the matching kind (expense lines for an expense category, income lines for an income one) are changed. With from_category_id, lines in that category are moved to category_id instead.',
      inputSchema: {
        ...workspaceArg,
        transaction_ids: z.array(z.string()).min(1).max(2000),
        category_id: z.string(),
        from_category_id: z.string().optional(),
      },
      annotations: OVERWRITE,
    },
    ({ workspace_id, transaction_ids, category_id, from_category_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const cat = await b.getOne('categories', category_id);
        const lineType = cat.kind === 'income' ? 'income' : 'expense';
        if (from_category_id) {
          const from = await b.getOne('categories', from_category_id);
          if (from.kind !== cat.kind) throw new UserError(`${from.name} and ${cat.name} are not the same kind of category.`);
        }
        const wanted = new Set(transaction_ids);
        const txns = (await b.load('transactions')).filter((t) => wanted.has(String(t.id)));
        const missing = [...wanted].filter((id) => !txns.some((t) => t.id === id));

        const changed: string[] = [];
        let linesChanged = 0;
        const writes: Write[] = [];
        for (const t of txns) {
          let touched = 0;
          const lines = ((t.lines as Plain[] | undefined) ?? []).map((l) => {
            if (l.type !== lineType) return strip(l);
            const match = from_category_id ? l.categoryId === from_category_id : !l.categoryId;
            if (!match) return strip(l);
            touched++;
            return strip({ ...l, categoryId: category_id });
          });
          if (!touched) continue;
          linesChanged += touched;
          changed.push(String(t.id));
          // The app's bulk write: lines only, no snapshot, changedFields ['lines'].
          const [update, rev] = b.updateWrites('transactions', String(t.id), { lines }, false);
          rev!.data!.changedFields = ['lines'];
          writes.push(update!, rev!);
        }
        for (let i = 0; i < writes.length; i += CHUNK * 2) {
          await b.commit(writes.slice(i, i + CHUNK * 2), 'edit transactions');
        }
        return {
          category: cat.name,
          transactions_changed: changed.length,
          lines_changed: linesChanged,
          unchanged: txns.length - changed.length,
          ...(missing.length ? { not_found: missing } : {}),
        };
      }),
  );
};
