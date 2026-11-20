// What /healthz reports, so a deploy can be checked from outside: which build
// is running, how many tools it serves, and whether the scheduled jobs are on.

export const status: {
  version: string;
  jobs: 'off' | 'on' | 'error';
  jobsDetail?: string;
  /** The last run of each job: counts and error kinds. */
  runs?: () => Record<string, unknown>;
} = {
  version: process.env.GIT_SHA?.slice(0, 7) || 'dev',
  jobs: 'off',
  jobsDetail: 'FIREBASE_SERVICE_ACCOUNT is not set',
};
