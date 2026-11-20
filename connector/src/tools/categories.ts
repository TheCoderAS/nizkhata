import { z } from 'zod';

import { UserError } from '../books.js';
import type { Plain } from '../firestore.js';
import { periodRange, spendByCategory } from '../ledger.js';
import { DESTRUCTIVE, READ, WRITE, run, workspaceArg, type Register } from './common.js';

export const registerCategoryTools: Register = (server, ctx) => {
  // ---- categories ----
  server.registerTool(
    'list_categories',
    {
      title: 'List categories',
      description: 'Income and expense categories in the workspace. Built-in (system) ones cannot be deleted.',
      inputSchema: { ...workspaceArg, kind: z.enum(['income', 'expense']).optional() },
      annotations: READ,
    },
    ({ workspace_id, kind }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        return (await b.load('categories'))
          .filter((c) => !kind || c.kind === kind)
          .map((c) => ({ id: c.id, name: c.name, kind: c.kind, built_in: c.isSystem === true }));
      }),
  );

  server.registerTool(
    'create_category',
    {
      title: 'Create a category',
      description: 'Add an income or expense category.',
      inputSchema: { ...workspaceArg, name: z.string().min(1), kind: z.enum(['income', 'expense']) },
      annotations: WRITE,
    },
    ({ workspace_id, name, kind }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const { id, writes } = b.createWrites('categories', { name: name.trim(), kind, isSystem: false });
        await b.commit(writes, 'add categories');
        return { created: true, id, name: name.trim(), kind };
      }),
  );

  server.registerTool(
    'update_category',
    {
      title: 'Update a category',
      description: 'Rename a category or change whether it is for income or expense.',
      inputSchema: {
        ...workspaceArg,
        category_id: z.string(),
        name: z.string().min(1).optional(),
        kind: z.enum(['income', 'expense']).optional(),
      },
      annotations: WRITE,
    },
    ({ workspace_id, category_id, name, kind }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        await b.getOne('categories', category_id);
        const data: Plain = {};
        if (name !== undefined) data.name = name.trim();
        if (kind !== undefined) data.kind = kind;
        if (!Object.keys(data).length) throw new UserError('Nothing to change.');
        await b.commit(b.updateWrites('categories', category_id, data), 'edit categories');
        return { updated: true, id: category_id, changed: Object.keys(data) };
      }),
  );

  server.registerTool(
    'delete_category',
    {
      title: 'Delete a category',
      description: 'Remove a custom category. Built-in ones cannot be deleted. Cannot be undone from here.',
      inputSchema: { ...workspaceArg, category_id: z.string() },
      annotations: DESTRUCTIVE,
    },
    ({ workspace_id, category_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const c = await b.getOne('categories', category_id);
        if (c.isSystem === true) throw new UserError(`"${c.name}" is a built-in category and cannot be deleted.`);
        await b.commit(b.deleteWrites('categories', category_id), 'delete categories');
        return { deleted: true, id: category_id, name: c.name };
      }),
  );

  // ---- budgets ----
  server.registerTool(
    'list_budgets',
    {
      title: 'List budgets',
      description:
        'Budgets with what has been spent so far: monthly budgets cover this calendar month, yearly ones this financial year.',
      inputSchema: workspaceArg,
      annotations: READ,
    },
    ({ workspace_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const tz = ctx().timeZone;
        const [budgets, cats, txns] = await Promise.all([b.load('budgets'), b.load('categories'), b.txns()]);
        const names = new Map(cats.map((c) => [String(c.id), String(c.name)]));
        const now = new Date();
        return {
          currency: b.ws.currency,
          budgets: budgets.map((bd) => {
            const period = bd.period === 'yearly' ? 'yearly' : 'monthly';
            const r = periodRange(period, now, b.ws.fyStartMonth, tz);
            const spent = spendByCategory(txns, r.start, r.end, b.round).get(String(bd.categoryId)) ?? 0;
            const limit = Number(bd.amount ?? 0);
            return {
              id: bd.id, category_id: bd.categoryId, category: names.get(String(bd.categoryId)),
              period, limit, spent, left: b.round(limit - spent),
            };
          }),
        };
      }),
  );

  const budgetFields = {
    amount: z.number().positive(),
    period: z.enum(['monthly', 'yearly']).describe('monthly (calendar month) or yearly (financial year)'),
  };

  server.registerTool(
    'create_budget',
    {
      title: 'Create a budget',
      description: 'Set a spending limit for an expense category, monthly or yearly.',
      inputSchema: { ...workspaceArg, category_id: z.string(), ...budgetFields },
      annotations: WRITE,
    },
    ({ workspace_id, category_id, amount, period }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const c = await b.getOne('categories', category_id);
        if (c.kind !== 'expense') throw new UserError('Budgets are for expense categories.');
        const { id, writes } = b.createWrites('budgets', { categoryId: category_id, amount: b.round(amount), period });
        await b.commit(writes, 'add budgets');
        return { created: true, id, category: c.name, amount: b.round(amount), period };
      }),
  );

  server.registerTool(
    'update_budget',
    {
      title: 'Update a budget',
      description: "Change a budget's limit, period or category.",
      inputSchema: {
        ...workspaceArg,
        budget_id: z.string(),
        category_id: z.string().optional(),
        amount: budgetFields.amount.optional(),
        period: budgetFields.period.optional(),
      },
      annotations: WRITE,
    },
    ({ workspace_id, budget_id, category_id, amount, period }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        await b.getOne('budgets', budget_id);
        const data: Plain = {};
        if (category_id !== undefined) {
          const c = await b.getOne('categories', category_id);
          if (c.kind !== 'expense') throw new UserError('Budgets are for expense categories.');
          data.categoryId = category_id;
        }
        if (amount !== undefined) data.amount = b.round(amount);
        if (period !== undefined) data.period = period;
        if (!Object.keys(data).length) throw new UserError('Nothing to change.');
        await b.commit(b.updateWrites('budgets', budget_id, data), 'edit budgets');
        return { updated: true, id: budget_id, changed: Object.keys(data) };
      }),
  );

  server.registerTool(
    'delete_budget',
    {
      title: 'Delete a budget',
      description: 'Remove a budget. Spending is not affected. Cannot be undone from here.',
      inputSchema: { ...workspaceArg, budget_id: z.string() },
      annotations: DESTRUCTIVE,
    },
    ({ workspace_id, budget_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        await b.getOne('budgets', budget_id);
        await b.commit(b.deleteWrites('budgets', budget_id), 'delete budgets');
        return { deleted: true, id: budget_id };
      }),
  );
};
