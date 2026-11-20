import { z } from 'zod';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';

import { Books, UserError, type Actor } from '../books.js';
import type { Firestore } from '../firestore.js';
import { localDate } from '../ledger.js';

/** What every tool call has: the person, their Firestore access, and a way into a workspace. */
export interface Ctx {
  fs: Firestore;
  actor: Actor;
  timeZone: string;
  books(workspaceId?: string): Promise<Books>;
}

export type Register = (server: McpServer, ctx: () => Ctx) => void;

export const workspaceArg = {
  workspace_id: z
    .string()
    .optional()
    .describe('Workspace to use, from list_workspaces. Required when the account has more than one; keep using the same one for the rest of the conversation unless the person names another.'),
};

export const dateArg = (what: string) =>
  z.string().describe(`${what}: YYYY-MM-DD (taken as midnight in the workspace's time zone) or a full ISO date-time.`);

type Result = { content: Array<{ type: 'text'; text: string }>; isError?: boolean };

/** Run a tool body, returning its value as JSON or a readable error. */
export async function run(body: () => Promise<unknown>): Promise<Result> {
  try {
    const value = await body();
    return { content: [{ type: 'text', text: JSON.stringify(value, jsonDates, 2) }] };
  } catch (e) {
    const message = e instanceof UserError ? e.message : `Something went wrong: ${(e as Error).message}`;
    return { content: [{ type: 'text', text: message }], isError: true };
  }
}

function jsonDates(this: unknown, _key: string, value: unknown) {
  return value;
}

/** A date for output, as the person's calendar date. */
export function day(d: unknown, timeZone: string): string | undefined {
  return d instanceof Date ? localDate(d, timeZone) : undefined;
}

export function requireFound<T>(v: T | undefined, what: string): T {
  if (v === undefined) throw new UserError(what);
  return v;
}

export const READ = { readOnlyHint: true, destructiveHint: false, openWorldHint: false } as const;
export const WRITE = { readOnlyHint: false, destructiveHint: false, openWorldHint: false } as const;
export const DESTRUCTIVE = { readOnlyHint: false, destructiveHint: true, openWorldHint: false } as const;
