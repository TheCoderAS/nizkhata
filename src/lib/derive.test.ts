import { describe, it, expect } from "vitest";
import { compareTxnChrono } from "./derive";

const day = (iso: string) => new Date(iso);

describe("compareTxnChrono", () => {
  it("orders by date first", () => {
    const a = { date: day("2026-05-01"), createdAt: day("2026-05-10T10:00:00Z") };
    const b = { date: day("2026-05-02"), createdAt: day("2026-05-01T00:00:00Z") };
    expect(compareTxnChrono(a, b)).toBeLessThan(0); // a (earlier date) first
  });

  it("breaks same-date ties by full createdAt timestamp", () => {
    const earlierEntry = {
      date: day("2026-05-01"),
      createdAt: day("2026-05-01T09:00:00Z"),
    };
    const laterEntry = {
      date: day("2026-05-01"),
      createdAt: day("2026-05-03T23:30:00Z"), // entered 2 days later
    };
    expect(compareTxnChrono(earlierEntry, laterEntry)).toBeLessThan(0);
    // newest-first (negated) puts the later-created one on top
    expect(compareTxnChrono(laterEntry, earlierEntry)).toBeGreaterThan(0);
  });

  it("a later date always wins over a late-in-day createdAt on an earlier date", () => {
    const earlierDateLateCreate = {
      date: day("2026-05-01"),
      createdAt: day("2026-05-01T23:59:59Z"),
    };
    const laterDateEarlyCreate = {
      date: day("2026-05-02"),
      createdAt: day("2026-05-02T00:00:01Z"),
    };
    expect(compareTxnChrono(earlierDateLateCreate, laterDateEarlyCreate)).toBeLessThan(0);
  });

  it("treats a missing createdAt as earliest within the day", () => {
    const noCreated = { date: day("2026-05-01") };
    const withCreated = { date: day("2026-05-01"), createdAt: day("2026-05-01T00:00:01Z") };
    expect(compareTxnChrono(noCreated, withCreated)).toBeLessThan(0);
  });
});
