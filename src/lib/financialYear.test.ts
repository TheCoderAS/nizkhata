import { describe, it, expect } from "vitest";
import { financialYearOf, financialYearRange } from "./financialYear";

describe("financialYearOf (April start, India)", () => {
  it("labels a post-April date with the starting year", () => {
    expect(financialYearOf(new Date(2025, 4, 15), 4)).toBe("2025-26"); // May 2025
  });
  it("labels a pre-April date with the previous starting year", () => {
    expect(financialYearOf(new Date(2025, 1, 10), 4)).toBe("2024-25"); // Feb 2025
  });
  it("April 1 is the boundary into the new FY", () => {
    expect(financialYearOf(new Date(2025, 3, 1), 4)).toBe("2025-26"); // Apr 2025
  });
  it("March 31 is still the prior FY", () => {
    expect(financialYearOf(new Date(2025, 2, 31), 4)).toBe("2024-25"); // Mar 2025
  });
  it("pads the end year to two digits across a century", () => {
    expect(financialYearOf(new Date(2099, 5, 1), 4)).toBe("2099-00");
  });
});

describe("financialYearOf (January start)", () => {
  it("uses a single-year label", () => {
    expect(financialYearOf(new Date(2025, 5, 1), 1)).toBe("2025");
    expect(financialYearOf(new Date(2025, 0, 1), 1)).toBe("2025");
  });
});

describe("financialYearRange", () => {
  it("returns April..April for a May date", () => {
    const { start, end } = financialYearRange(new Date(2025, 4, 15), 4);
    expect(start.getFullYear()).toBe(2025);
    expect(start.getMonth()).toBe(3); // April
    expect(end.getFullYear()).toBe(2026);
    expect(end.getMonth()).toBe(3);
  });
});
