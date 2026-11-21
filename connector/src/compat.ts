// Keeping chats that started before a connector update working.
//
// An assistant loads the tool list when a conversation starts and keeps it,
// so after an update an open chat can still call a tool the old way. Two
// things make that recoverable instead of a dead end:
//
//   1. Old inputs that still have an unambiguous meaning are translated to
//      the current ones before validation (e.g. a due given as one amount and
//      a direction becomes one line). The schema new chats see is unchanged.
//   2. Anything else that no longer fits (a removed field, a missing new
//      required one, a renamed tool) is refused with the tool's current
//      inputs spelled out, so the assistant can retry correctly at once, and
//      told to suggest a new chat if it cannot.
//
// Unknown fields are refused rather than silently dropped: ignoring an "amount"
// an old chat thought it was setting would leave the books wrong and the
// person told it worked.

import { z } from 'zod';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { ErrorCode, McpError } from '@modelcontextprotocol/sdk/types.js';

type Args = Record<string, unknown> | undefined;

/** Old input shapes, per tool, mapped onto the current ones. */
const ADAPTERS: Record<string, (a: Record<string, unknown>) => Record<string, unknown>> = {
  // Until dues took transaction-style lines: one amount, a direction, a category.
  create_due: (a) => {
    if (a.lines !== undefined || (a.amount === undefined && a.direction === undefined && a.category_id === undefined)) {
      const { direction: _d, ...rest } = a; // a direction next to lines adds nothing: the lines decide
      return a.lines !== undefined ? rest : a;
    }
    const { amount, direction, category_id, ...rest } = a;
    if (amount === undefined) return a; // nothing to build a line from; validation says what is missing
    return {
      ...rest,
      lines: [{ type: direction === 'receivable' ? 'income' : 'expense', amount, ...(category_id ? { category_id } : {}) }],
    };
  },
  update_due: (a) => {
    if (a.amount !== undefined || a.category_id !== undefined) {
      throw new McpError(
        ErrorCode.InvalidParams,
        'update_due no longer takes amount or category_id. Give lines instead, exactly as for update_transaction ' +
          '(e.g. lines: [{ type: "expense", amount: 20000, category_id: "..." }]); they replace the due\'s lines.',
      );
    }
    return a;
  },
};

interface ToolLike {
  inputSchema?: unknown;
}

function shapeOf(schema: unknown): Record<string, z.ZodType> | null {
  const s = schema as { shape?: Record<string, z.ZodType> } | undefined;
  return s && typeof s === 'object' && s.shape ? s.shape : null;
}

/** "title (string, required), lines (array, required), note (string)" for a tool. */
export function describeInputs(schema: unknown): string {
  const shape = shapeOf(schema);
  if (!shape) return 'no inputs';
  let json: { properties?: Record<string, { type?: string; description?: string }>; required?: string[] };
  try {
    json = z.toJSONSchema(z.object(shape), { unrepresentable: 'any' }) as typeof json;
  } catch {
    return Object.keys(shape).join(', ');
  }
  const required = new Set(json.required ?? []);
  return Object.entries(json.properties ?? {})
    .map(([k, v]) => `${k} (${v.type ?? 'value'}${required.has(k) ? ', required' : ''})`)
    .join(', ');
}

const OUT_OF_DATE =
  "This conversation's copy of the Niz Khata tools is out of date (the connector was updated after the chat started).";
const IF_STUCK = 'Retry with these inputs; if that still fails, ask the person to start a new chat, which loads the current tools.';

export function installCompat(server: McpServer): void {
  const s = server as unknown as {
    _registeredTools: Record<string, ToolLike>;
    validateToolInput: (tool: ToolLike, args: Args, name: string) => Promise<unknown>;
    createToolError: (message: string) => unknown;
  };
  const validate = s.validateToolInput.bind(server);
  s.validateToolInput = async (tool, args, name) => {
    let a = args ?? {};
    const adapt = ADAPTERS[name];
    if (adapt) a = adapt({ ...a });
    // Fields this tool does not have any more are refused, not ignored.
    const shape = shapeOf(tool.inputSchema);
    if (shape) {
      const unknown = Object.keys(a).filter((k) => !(k in shape));
      if (unknown.length) {
        throw new McpError(ErrorCode.InvalidParams, `Input validation error: ${name} has no ${unknown.join(', ')}.`);
      }
    }
    return validate(tool, a, name);
  };

  const toolError = s.createToolError.bind(server);
  s.createToolError = (message: string) => {
    const notFound = /^MCP error -?\d+: Tool (\S+) not found/.exec(message);
    if (notFound) {
      return toolError(
        `${OUT_OF_DATE} There is no tool ${notFound[1]} now. The tools are: ${Object.keys(s._registeredTools).sort().join(', ')}. ${IF_STUCK}`,
      );
    }
    const invalid = /Input validation error: (?:Invalid arguments for tool )?(\w+)/.exec(message);
    if (invalid && s._registeredTools[invalid[1]!]) {
      const name = invalid[1]!;
      return toolError(`${message}\n${OUT_OF_DATE} ${name} takes: ${describeInputs(s._registeredTools[name]!.inputSchema)}. ${IF_STUCK}`);
    }
    if (/update_due no longer takes/.test(message)) return toolError(`${message}\n${IF_STUCK}`);
    return toolError(message);
  };
}
