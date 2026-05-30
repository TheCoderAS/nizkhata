import { defineConfig } from "vitest/config";

// Security-rules tests. Require a running Firestore emulator + Java:
//   firebase emulators:exec --only firestore "npm run test:rules"
// or start the emulator separately and run `npm run test:rules`.
export default defineConfig({
  test: {
    include: ["test/rules/**/*.test.ts"],
    environment: "node",
    testTimeout: 20000,
    hookTimeout: 20000,
    fileParallelism: false,
  },
});
