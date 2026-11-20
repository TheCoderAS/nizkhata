// Everything the server reads from its environment, checked once at start.

export interface Config {
  /** Where the server is reachable, e.g. https://nizkhata-connector.onrender.com */
  publicUrl: string;
  port: number;
  /** Firebase Web API key: a public client identifier, the same one the app ships. */
  firebaseApiKey: string;
  firebaseProjectId: string;
  /** Google OAuth Web client in the Firebase project, used to sign people in. */
  googleClientId: string;
  googleClientSecret: string;
  /** Seals every token the server hands out. Any long random string. */
  tokenSecret: string;
  /** How a bare date ("2026-11-20") is placed in time, as the app does on the phone. */
  timeZone: string;
  /** Overrides for tests: the Firestore and Identity Toolkit endpoints. */
  firestoreBaseUrl: string;
  identityBaseUrl: string;
  secureTokenBaseUrl: string;
  googleTokenUrl: string;
  googleAuthUrl: string;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const need = (name: string): string => {
    const v = env[name]?.trim();
    if (!v) throw new Error(`Missing environment variable ${name}`);
    return v;
  };
  const projectId = env.FIREBASE_PROJECT_ID?.trim() || 'nizkhata';
  const tokenSecret = need('TOKEN_SECRET');
  if (tokenSecret.length < 32) throw new Error('TOKEN_SECRET must be at least 32 characters');
  return {
    // Render sets RENDER_EXTERNAL_URL itself; PUBLIC_URL wins (a custom domain).
    publicUrl: (env.PUBLIC_URL?.trim() || env.RENDER_EXTERNAL_URL?.trim() || need('PUBLIC_URL')).replace(/\/+$/, ''),
    port: Number(env.PORT ?? 8080),
    firebaseApiKey: need('FIREBASE_API_KEY'),
    firebaseProjectId: projectId,
    googleClientId: need('GOOGLE_CLIENT_ID'),
    googleClientSecret: need('GOOGLE_CLIENT_SECRET'),
    tokenSecret,
    timeZone: env.APP_TIMEZONE?.trim() || 'Asia/Kolkata',
    firestoreBaseUrl:
      env.FIRESTORE_BASE_URL?.trim() ||
      `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`,
    identityBaseUrl: env.IDENTITY_BASE_URL?.trim() || 'https://identitytoolkit.googleapis.com/v1',
    secureTokenBaseUrl: env.SECURE_TOKEN_BASE_URL?.trim() || 'https://securetoken.googleapis.com/v1',
    googleTokenUrl: env.GOOGLE_TOKEN_URL?.trim() || 'https://oauth2.googleapis.com/token',
    googleAuthUrl: env.GOOGLE_AUTH_URL?.trim() || 'https://accounts.google.com/o/oauth2/v2/auth',
  };
}
