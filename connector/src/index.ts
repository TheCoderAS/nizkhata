import { loadConfig } from './config.js';
import { Firestore } from './firestore.js';
import { googleTokenSource, parseServiceAccount } from './jobs/google.js';
import { Push } from './jobs/push.js';
import { Scheduler } from './jobs/scheduler.js';
import { SharedNotifier } from './jobs/shared-notify.js';
import { buildApp } from './server.js';

const cfg = loadConfig();
buildApp(cfg).listen(cfg.port, () => {
  console.log(`Niz Khata connector on :${cfg.port}, public at ${cfg.publicUrl}/mcp`);
});

// Scheduled jobs (repeating dues, card bills, push reminders) need admin
// access; without a service account the server only serves the connector.
const sa = parseServiceAccount(cfg.serviceAccount);
if (sa) {
  const token = googleTokenSource(sa);
  const scheduler = new Scheduler({
    admin: async () => new Firestore(cfg.firestoreBaseUrl, await token()),
    push: new Push(sa.project_id, token, fetch, cfg.fcmBaseUrl),
    defaultTimeZone: cfg.timeZone,
  });
  scheduler.start(cfg.remindEveryMinutes * 60_000, cfg.duesEveryMinutes * 60_000);
  const admin = async () => new Firestore(cfg.firestoreBaseUrl, await token());
  const shared = new SharedNotifier(admin, new Push(sa.project_id, token, fetch, cfg.fcmBaseUrl));
  setInterval(() => void shared.run().catch((e) => console.log(`shared notify: ${(e as Error).message}`)), cfg.sharedEverySeconds * 1000);
  console.log(
    `Scheduled jobs on: reminders every ${cfg.remindEveryMinutes} min, dues every ${cfg.duesEveryMinutes} min, shared ledger every ${cfg.sharedEverySeconds} s`,
  );
} else {
  console.log('Scheduled jobs off: FIREBASE_SERVICE_ACCOUNT is not set');
}
