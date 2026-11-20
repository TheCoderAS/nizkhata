# Directory listings

These are drafts for the Claude Connectors Directory and the ChatGPT app directory. Character limits are noted.

## Shared

- **Name:** Niz Khata
- **Server URL:** `https://nizkhata-api.valorumlabs.com/mcp`
- **Authentication:** OAuth 2.1. Sign-in is with Google. Clients register themselves through dynamic client registration and use PKCE.
- **Website / documentation:** https://nizkhata.valorumlabs.com
- **Privacy policy:** https://nizkhata.valorumlabs.com/privacy
- **Terms:** https://nizkhata.valorumlabs.com/terms
- **Support:** hello@valorumlabs.com
- **Developer:** Valorum Labs (https://valorumlabs.com)
- **Category:** Finance (and Productivity, where a second category is allowed)
- **Icon:** `landing/logo.png` (square). The 180 px version is served at `https://nizkhata-api.valorumlabs.com/icon-180.png`.

## Claude

- **One-liner (200 max):** Keep your Niz Khata money ledger by chat: add expenses and income, track dues and debts, and check budgets and balances.
- **Description (2,000 max):**

  > Niz Khata is a personal and shared money ledger for Android. With this connector, Claude can read and update your books for you, as you, in the workspaces you belong to and within the role you have there.
  >
  > Ask things like "how much did I spend on food this month?", "add 450 for lunch from my HDFC account", "Ravi paid back 5,000 of the bike loan", "what bills are due this week?" or "set a 6,000 monthly budget for groceries".
  >
  > What it covers: accounts and balances; transactions, including splits and transfers between your accounts; categories and budgets; dues (bills to pay and money to receive on a date, with part payments); debts with each person, including repayments; and contacts.
  >
  > Niz Khata is a record-keeping app. It never moves real money and never connects to a bank. Every change Claude makes appears in the app with its history, under your name. Deleting anything asks for confirmation first. Your workspace roles and the app's database security rules apply to every request, and the connector itself stores none of your records.

- **Use cases:** logging expenses and income by chat; month-end spending review; tracking money lent and borrowed; reminders of what is due; budget check-ins.

## ChatGPT

- **displayName (30 max):** Niz Khata
- **shortDescription (30 max):** Your money ledger, by chat
- **longDescription (4,000 max):** use the Claude description above, with "Claude" replaced by "ChatGPT".
- **developerName:** Valorum Labs
- **Commerce:** none. The app sells nothing and executes no payments or transfers.

### Positive test cases (5)

1. "List my Niz Khata accounts with balances."
   - Expected: `list_accounts`.
2. "Add an expense of 450 for lunch from HDFC Savings today, category Food."
   - Expected: `list_accounts` and `list_categories`, then `create_transaction`.
3. "How much have I spent on Food this month, and how much of my budget is left?"
   - Expected: `list_budgets`.
4. "I lent Ravi 16,000 from HDFC Savings for a bike. He has paid back 15,000. What does he still owe?"
   - Expected: `create_debt`, then `record_debt_repayment`. The answer is 1,000, and the debt stays open.
5. "What bills are due in the next 7 days?"
   - Expected: `list_dues`.

### Negative test cases (3)

1. "Send 5,000 to Ravi's bank account."
   - Expected: ChatGPT explains that Niz Khata only records entries and cannot move money. At most it offers to record the payment.
2. "Delete all my transactions."
   - Expected: ChatGPT asks for confirmation before any `delete_transaction` call, because those tools are marked destructive.
3. "Show me another user's ledger" (a workspace the account is not a member of).
   - Expected: the connector refuses with "No workspace with id ...". Firestore security rules enforce this.

### Demo account

1. Create a new Google account for reviewers, with no 2-step verification.
2. Sign in to Niz Khata on Android with it.
3. Add sample data: two accounts, about 20 transactions, a budget, one due and one debt.
4. Enter the credentials only in the portal's Review details.

### Domain verification

1. Copy the token the portal shows.
2. In Render, set the environment variable `OPENAI_APPS_CHALLENGE` to that token.
3. After the service redeploys, check that `https://nizkhata-api.valorumlabs.com/.well-known/openai-apps-challenge` returns the token as plain text.
