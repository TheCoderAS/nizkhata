import { listWorkspaces } from '../books.js';
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
};
