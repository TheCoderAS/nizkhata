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
| Workspaces | `list_workspaces` | |
| Accounts | `list_accounts` (with balances) | `create_account`, `update_account`, `delete_account` |
| Reports | `get_summary` (income, expense, by category, per account, trend) | |
| History | `list_activity` | `restore_deleted` |
| Shared ledger | `list_shared` | `add_shared_expense`, `record_shared_settlement`, `respond_shared_entry` |
| Contacts | `list_contacts` (with net position), `get_contact` | `create_contact`, `update_contact`, `delete_contact` |
| Transactions | `list_transactions`, `get_transaction` | `create_transaction`, `update_transaction`, `delete_transaction`, `recategorise_transactions` |
| Categories | `list_categories` | `create_category`, `update_category`, `delete_category` |
| Budgets | `list_budgets` (spent and left this period) | `create_budget`, `update_budget`, `delete_budget` |
| Dues | `list_dues` | `create_due`, `update_due`, `delete_due`, `record_due_payment` |
| Debts | `list_debts` | `create_debt`, `update_debt`, `delete_debt`, `record_debt_repayment` |

Every tool states all three hints explicitly. `list_*` and `get_*` are read-only. `create_*` and `record_*` only add, so they are not destructive. `update_*` (which changes what is there) and `delete_*` are marked destructive, so assistants ask before running them.

Listing texts for the Claude and ChatGPT directories are in [LISTING.md](LISTING.md).

## Deploy on Render

The connector is served at **https://nizkhata-api.valorumlabs.com**.

### 1. Google OAuth client

This is a one-time step. In Google Cloud console, go to APIs & Services > Credentials, in the `nizkhata` project.

1. Open the **Web client** that Firebase created for Google sign-in.
2. Under **Authorized redirect URIs**, add `https://nizkhata-api.valorumlabs.com/oauth/google/callback`.
3. Copy the **Client ID** and the **Client secret**.

### 2. Docker Hub (private image)

GitHub Actions builds the image and pushes it to a private Docker Hub repository. The workflow is `.github/workflows/connector-image.yml`, and it runs on every merge to `main` that changes `connector/`.

1. On Docker Hub, create a **private** repository named `nizkhata-connector`.
2. Under Account settings > Personal access tokens, create two tokens:
   - **Read & Write**, for GitHub;
   - **Read-only**, for Render.
3. In GitHub, go to Settings > Secrets and variables > Actions and add these secrets:
   - `DOCKERHUB_USERNAME`
   - `DOCKERHUB_TOKEN` (the Read & Write token)
4. Run the **Connector image** workflow once from the Actions tab. This pushes `docker.io/<user>/nizkhata-connector:latest`.

To use another repository name, set the repository variable `DOCKERHUB_REPOSITORY`, for example `myname/nizkhata-api`.

### 3. Web Service

In Render, first add a registry credential: Workspace Settings > Registry Credentials, with registry Docker Hub, your username, and the Read-only token.

Then go to **New > Web Service > Existing Image**.

| Setting | Value |
| --- | --- |
| Image URL | `docker.io/<user>/nizkhata-connector:latest` |
| Credential | the Docker Hub credential above |
| Instance type | Free, or Starter (see the note below) |
| Health Check Path | `/healthz` (under Advanced) |

Add these **environment variables**:

| Key | Value |
| --- | --- |
| `PUBLIC_URL` | `https://nizkhata-api.valorumlabs.com` |
| `GOOGLE_CLIENT_ID` | from step 1 |
| `GOOGLE_CLIENT_SECRET` | from step 1 |
| `TOKEN_SECRET` | the output of `openssl rand -hex 32`. Keep it; changing it signs everyone out. |
| `FIREBASE_API_KEY` | `AIzaSyBUNKeUYJ_3M8u3h4IJER7eflq2C8kd-AU` |
| `FIREBASE_PROJECT_ID` | `nizkhata` |
| `APP_TIMEZONE` | `Asia/Kolkata` |

**Auto-deploy:** Render does not watch Docker Hub. Copy the service's **Deploy Hook** (Settings > Deploy Hook) into the GitHub secret `RENDER_DEPLOY_HOOK_URL`. After each push, the workflow then deploys that exact image, tagged `sha-<commit>`. Without the secret, the image is only pushed, and you deploy it from Render with Manual Deploy.

**Free plan:** the service sleeps after 15 idle minutes. The first request after that takes about a minute while it wakes, and the assistant may time out once; ask again and it works. Starter does not sleep.

### 4. Custom domain

1. In the service, go to **Settings > Custom Domains** and add `nizkhata-api.valorumlabs.com`.
2. At your DNS provider, add a **CNAME** record:
   - name `nizkhata-api`
   - target `<your-service>.onrender.com`, the address Render shows
   - proxy off, if you use Cloudflare
3. Wait until Render shows the domain as verified and the certificate as issued.
4. Check that `https://nizkhata-api.valorumlabs.com/healthz` answers `{"ok":true}`.

### 5. Connect an assistant

The server URL is `https://nizkhata-api.valorumlabs.com/mcp`.

- **Claude:** go to Settings > Connectors > Add custom connector and paste the URL. Claude registers itself, then opens the Google sign-in.
- **ChatGPT:** go to Settings > Apps & Connectors and turn on Developer mode. Then choose Create, paste the URL and pick OAuth for authentication.

## Scheduled jobs

The phone used to schedule these itself. The backend now does it, so they happen even when nobody opens the app:

- **Repeating dues:** the next instance of each repeating due is created once the current one is paid, cancelled or past its date. It catches up if the service was down.
- **Card bills:** each credit card's current bill is raised from its statement day and payment due day. Its amount is kept in step with the card's ledger.
- **Shared ledger notifications:** every action on a shared entry is pushed to the other person within about 20 seconds, at any hour, one notification per action. That covers a new expense, a new settlement, an acceptance and a rejection. The server looks for shared entries whose `updatedAt` moved since its last look. Each (entry, status) is logged in `pushLog` before it is sent, so none is sent twice. History from before the first run is never replayed.
- **Due reminders:** pushes go out through Firebase Cloud Messaging at 9:00, 12:00, 15:00, 18:00 and 21:00 local time, on days with unsettled dues. The time zone comes from each phone's `devices` record. A reminder is logged in `pushLog` before it is sent, so none is sent twice. The log is cleared after 30 days.

These jobs run only with `FIREBASE_SERVICE_ACCOUNT`, a service account of the `nizkhata` project. Set it up once:

1. In Google Cloud, go to IAM & Admin > Service accounts and create a service account, for example `nizkhata-jobs`.
2. Give it two roles: **Cloud Datastore User** and **Firebase Cloud Messaging API Admin**.
3. Under Keys, choose **Add key > JSON**.
4. Paste the whole JSON into Render as `FIREBASE_SERVICE_ACCOUNT`.
5. Make sure the **Firebase Cloud Messaging API (V1)** is enabled in the project.

The assistant's tools never use this key. They act with the signed-in person's own token, under the security rules.

## Environment

| Variable | Required | Default |
| --- | --- | --- |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | yes | |
| `TOKEN_SECRET` (32+ characters) | yes | |
| `FIREBASE_API_KEY` | yes | |
| `PUBLIC_URL` (set it to the custom domain) | on Render, no | `RENDER_EXTERNAL_URL` |
| `FIREBASE_PROJECT_ID` | no | `nizkhata` |
| `APP_TIMEZONE` (where a bare date falls) | no | `Asia/Kolkata` |
| `PORT` | no | `8080` |
| `FIREBASE_SERVICE_ACCOUNT` (JSON or base64 of it; turns on the scheduled jobs) | for reminders, repeating dues and card bills | |
| `SCHEDULER_REMIND_MINUTES`, `SCHEDULER_DUES_MINUTES`, `SCHEDULER_SHARED_SECONDS` | no | `5`, `30`, `20` |
| `OPENAI_APPS_CHALLENGE` (ChatGPT domain check, served at `/.well-known/openai-apps-challenge`) | for ChatGPT review | |

## Develop

```sh
npm ci
npm run typecheck
npm test                      # unit tests, including the full OAuth flow
# The tools against the Firestore emulator, running the real firestore.rules (run from the repo root):
npx firebase-tools emulators:exec --only firestore --project rules-test "cd connector && npm run test:emulator"
docker build -t nizkhata-connector .
```
