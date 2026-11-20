# Niz Khata connector

An MCP server that lets Claude and ChatGPT read and write a person's Niz Khata books.
It runs as a Docker web service, for example on Render.

## How it works

- **The assistant acts as the person.** They sign in with Google. The server swaps that sign-in for the person's own Firebase session and calls Firestore with it. The app's Security Rules apply to every read and write, exactly as they do on the phone.
  - A member with a view-only role can read but cannot change anything.
  - The server holds no service account and has no database.
- **Writes look like the app's own.** Each write uses the same document shapes, the same `createdBy`/`updatedBy` and server timestamps, and the same `revisions` entry in the same atomic commit. So the app shows the change, with its history, as if it had been made on the phone.
- **Tokens are sealed.** Every token the server hands out is sealed with AES-256-GCM under `TOKEN_SECRET`. This covers client ids, authorization codes, and access and refresh tokens. Nothing is stored on the server.
  - The person's Firebase refresh token travels sealed inside their connector token.
  - Changing `TOKEN_SECRET` signs everyone out.

### Tools

| Area | Read | Write |
| --- | --- | --- |
| Workspaces | `list_workspaces`, `list_accounts` (with balances) | |
| Contacts | `list_contacts` (with net position), `get_contact` | `create_contact`, `update_contact`, `delete_contact` |
| Transactions | `list_transactions`, `get_transaction` | `create_transaction`, `update_transaction`, `delete_transaction` |
| Categories | `list_categories` | `create_category`, `update_category`, `delete_category` |
| Budgets | `list_budgets` (spent and left this period) | `create_budget`, `update_budget`, `delete_budget` |
| Dues | `list_dues` | `create_due`, `update_due`, `delete_due`, `record_due_payment` |
| Debts | `list_debts` | `create_debt`, `update_debt`, `delete_debt`, `record_debt_repayment` |

All `delete_*` tools are marked destructive, so assistants ask before running them.

## Deploy on Render

### 1. Google OAuth client

This is a one-time step, done in Google Cloud console > APIs & Services > Credentials, in the `nizkhata` project.

1. Open the **Web client** (the one Firebase created for Google sign-in), or create a new Web client.
2. Under **Authorized redirect URIs**, add `https://<your-service>.onrender.com/oauth/google/callback`. If you use a custom domain, add that address instead.
3. Copy the **Client ID** and the **Client secret**.

### 2. Blueprint

In Render, open **New > Blueprint** and pick this repository. Render reads `render.yaml` from the repository root.

When asked, fill in:

- `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`, from step 1.
- `PUBLIC_URL`: leave it empty to use the `onrender.com` address, or set a custom domain.

Render generates `TOKEN_SECRET` itself.

The free plan sleeps when idle, and the first call after a nap can time out in the assistant. The blueprint therefore uses `starter`.

### 3. Connect an assistant

The server URL is `https://<your-service>.onrender.com/mcp`.

- **Claude:** go to Settings > Connectors > Add custom connector and paste the URL. Claude registers itself, then opens the Google sign-in.
- **ChatGPT:** go to Settings > Apps & Connectors, turn on Developer mode, then Create and paste the URL. For authentication, choose OAuth.

## Environment

| Variable | Required | Default |
| --- | --- | --- |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | yes | |
| `TOKEN_SECRET` (32+ characters) | yes | |
| `FIREBASE_API_KEY` | yes | |
| `PUBLIC_URL` | on Render, no | `RENDER_EXTERNAL_URL` |
| `FIREBASE_PROJECT_ID` | no | `nizkhata` |
| `APP_TIMEZONE` (where a bare date falls) | no | `Asia/Kolkata` |
| `PORT` | no | `8080` |

## Develop

```sh
npm ci
npm run typecheck
npm test                      # unit tests, including the full OAuth flow
# The tools against the Firestore emulator, running the real firestore.rules (run from the repo root):
npx firebase-tools emulators:exec --only firestore --project rules-test "cd connector && npm run test:emulator"
docker build -t nizkhata-connector .
```
