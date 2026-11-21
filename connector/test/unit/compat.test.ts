// Chats that started before a connector update: old inputs are translated
// where they still mean one thing, and everything else is refused with the
// tool's current inputs spelled out.

import { describe, expect, it } from 'vitest';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';

import { buildMcpServer } from '../../src/server.js';
import type { Ctx } from '../../src/tools/common.js';

async function client() {
  // No books behind it: every call here must be settled before a tool runs.
  const ctx = () => {
    throw new Error('a tool ran');
  };
  const [a, b] = InMemoryTransport.createLinkedPair();
  await buildMcpServer(ctx as unknown as () => Ctx).connect(a);
  const c = new Client({ name: 'old-chat', version: '1' });
  await c.connect(b);
  return async (name: string, args: Record<string, unknown>) => {
    const r = (await c.callTool({ name, arguments: args })) as { content: Array<{ text: string }>; isError?: boolean };
    return { error: r.isError === true, text: r.content[0]!.text };
  };
}

describe('an out-of-date chat', () => {
  it('calling a tool that no longer exists hears what the tools are now', async () => {
    const call = await client();
    const r = await call('add_reminder', { title: 'x' });
    expect(r.error).toBe(true);
    expect(r.text).toMatch(/out of date/);
    expect(r.text).toMatch(/no tool add_reminder now/);
    expect(r.text).toMatch(/create_due/);
    expect(r.text).toMatch(/start a new chat/);
  });

  it('a field the tool no longer has is refused, not silently ignored, with its current inputs', async () => {
    const call = await client();
    const r = await call('list_accounts', { include_archived: true });
    expect(r.error).toBe(true);
    expect(r.text).toMatch(/list_accounts has no include_archived/);
    expect(r.text).toMatch(/list_accounts takes: workspace_id \(string\)/);
  });

  it('a due given the old way (one amount and a direction) becomes one line; a missing account is asked for', async () => {
    const call = await client();
    const r = await call('create_due', { title: 'Gym', direction: 'payable', amount: 1500, due_date: '2026-12-05', category_id: 'c1' });
    expect(r.error).toBe(true);
    // Translated: what is missing is only the account a due now needs, as a transaction does.
    expect(r.text).toMatch(/account_id/);
    expect(r.text).not.toMatch(/has no (amount|direction|category_id)/);
    expect(r.text).toMatch(/create_due takes: .*account_id \(string, required\).*lines \(array, required\)/);
  });

  it('update_due with an amount is told to give lines, as update_transaction takes', async () => {
    const call = await client();
    const r = await call('update_due', { due_id: 'd1', amount: 20000 });
    expect(r.error).toBe(true);
    expect(r.text).toMatch(/no longer takes amount or category_id\. Give lines instead/);
    expect(r.text).toMatch(/start a new chat/);
  });

  it('a missing required input says what the tool takes', async () => {
    const call = await client();
    const r = await call('create_transaction', { lines: [{ type: 'income', amount: 1 }] });
    expect(r.error).toBe(true);
    expect(r.text).toMatch(/create_transaction takes: .*account_id \(string, required\)/);
  });
});
