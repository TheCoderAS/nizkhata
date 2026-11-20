import { loadConfig } from './config.js';
import { buildApp } from './server.js';

const cfg = loadConfig();
buildApp(cfg).listen(cfg.port, () => {
  console.log(`Niz Khata connector on :${cfg.port}, public at ${cfg.publicUrl}/mcp`);
});
