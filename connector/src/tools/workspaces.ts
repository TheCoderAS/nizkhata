import { listWorkspaces } from '../books.js';
import { accountBalances } from '../ledger.js';
import { READ, run, workspaceArg, type Register } from './common.js';

export const registerWorkspaceTools: Register = (server, ctx) => {
  server.registerTool(
    'list_workspaces',
    {
      title: 'List workspaces',
      description:
        "The person's Niz Khata workspaces (separate books: a household, a shop, a trip), each with its currency. Amounts in a workspace are always in its currency.",
      annotations: READ,
    },
    () =>
      run(async () => {
        const { fs, actor } = ctx();
        return (await listWorkspaces(fs, actor.uid)).map((w) => ({
          id: w.id,
          name: w.name,
          currency: w.currency,
          financial_year_starts_month: w.fyStartMonth,
          you_own_it: w.ownerId === actor.uid,
        }));
      }),
  );

  server.registerTool(
    'list_accounts',
    {
      title: 'List accounts',
      description:
        'Bank accounts, cash and credit cards in a workspace, with current balances. Transactions need an account_id from here. A credit card balance below zero is what is used on the card.',
      inputSchema: workspaceArg,
      annotations: READ,
    },
    ({ workspace_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const [accounts, txns, debts] = await Promise.all([b.load('accounts'), b.txns(), b.debts()]);
        const balances = accountBalances(
          accounts.map((a) => ({ id: String(a.id), openingBalance: Number(a.openingBalance ?? 0) })),
          txns,
          new Map(debts.map((d) => [d.id, d])),
          b.round,
        );
        return {
          currency: b.ws.currency,
          accounts: accounts.map((a) => ({
            id: a.id,
            name: a.name,
            type: a.type,
            balance: balances.get(String(a.id)) ?? 0,
            ...(a.type === 'credit_card' && a.creditLimit ? { credit_limit: a.creditLimit } : {}),
          })),
        };
      }),
  );
};
