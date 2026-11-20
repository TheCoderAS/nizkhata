import { loadConfig } from './config.js';
import { Firestore } from './firestore.js';
import { googleTokenSource, parseServiceAccount } from './jobs/google.js';
import { Push } from './jobs/push.js';
import { Scheduler } from './jobs/scheduler.js';
import { SharedNotifier } from './jobs/shared-notify.js';
import { buildApp } from './server.js';
import { status } from './status.js';

const cfg = loadConfig();
buildApp(cfg).listen(cfg.port, () => {
  console.log(`Niz Khata connector on :${cfg.port}, public at ${cfg.publicUrl}/mcp`);
});

// Scheduled jobs (repeating dues, card bills, push reminders) need admin
// access; without a service account the server only serves the connector.
// A key that cannot be read turns the jobs off; it must never stop the
// connector from serving.
let sa: ReturnType<typeof parseServiceAccount> = null;
try {
  sa = parseServiceAccount(cfg.serviceAccount);
} catch (e) {
  status.jobs = 'error';
  status.jobsDetail = `FIREBASE_SERVICE_ACCOUNT could not be read: ${(e as Error).message}`;
  console.error(status.jobsDetail);
}
if (sa) {
  status.jobs = 'on';
  status.jobsDetail = undefined;
  const source = googleTokenSource(sa);
  // A key Google refuses (revoked, wrong project) shows on /healthz too.
  const token = async () => {
    try {
      const t = await source();
      if (status.jobs === 'error') {
        status.jobs = 'on';
        status.jobsDetail = undefined;
      }
      return t;
    } catch (e) {
      status.jobs = 'error';
      status.jobsDetail = (e as Error).message;
      throw e;
    }
  };
  const scheduler = new Scheduler({
    admin: async () => new Firestore(cfg.firestoreBaseUrl, await token()),
    push: new Push(sa.project_id, token, fetch, cfg.fcmBaseUrl),
    defaultTimeZone: cfg.timeZone,
  });
  scheduler.start(cfg.remindEveryMinutes * 60_000, cfg.duesEveryMinutes * 60_000);
  const admin = async () => new Firestore(cfg.firestoreBaseUrl, await token());
  const shared = new SharedNotifier(admin, new Push(sa.project_id, token, fetch, cfg.fcmBaseUrl));
  status.runs = () => ({ dues: scheduler.lastDues, reminders: scheduler.lastReminders, shared_ledger: shared.last });
  setInterval(() => void shared.run().catch((e) => console.log(`shared notify: ${(e as Error).message}`)), cfg.sharedEverySeconds * 1000);
  console.log(
    `Scheduled jobs on: reminders every ${cfg.remindEveryMinutes} min, dues every ${cfg.duesEveryMinutes} min, shared ledger every ${cfg.sharedEverySeconds} s`,
  );
} else if (status.jobs === 'off') {
  console.log('Scheduled jobs off: FIREBASE_SERVICE_ACCOUNT is not set');
}
