import { defineConfig } from "vitest/config";
import path from "node:path";

// Pure-logic unit tests (no Firebase). These run anywhere.
// Security-rules tests need the emulator + Java — see vitest.rules.config.ts.
export default defineConfig({
  resolve: {
    alias: { "@": path.resolve(__dirname, "src") },
  },
  test: {
    include: ["src/**/*.test.ts"],
    environment: "node",
  },
});
