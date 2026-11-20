import { listWorkspaces } from '../books.js';
import { READ, run, workspaceArg, type Register } from './common.js';

export const registerWorkspaceTools: Register = (server, ctx) => {
  server.registerTool(
    'list_workspaces',
    {
      title: 'List workspaces',
      description:
        "The person's Niz Khata workspaces (separate books: a household, a shop, a trip), each with its currency and time zone. Amounts in a workspace are always in its currency; its dates are days in its time zone.",
      annotations: READ,
    },
    () =>
      run(async () => {
        const { fs, actor } = ctx();
        return (await listWorkspaces(fs, actor.uid)).map((w) => ({
          id: w.id,
          name: w.name,
          currency: w.currency,
          time_zone: w.timeZone,
          financial_year_starts_month: w.fyStartMonth,
          you_own_it: w.ownerId === actor.uid,
        }));
      }),
  );
};
