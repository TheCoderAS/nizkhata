# Google Play store listing

Everything the Play Console's **Main store listing** and **Store settings**
pages ask for. Copy the text fields as they are; upload the images from this
folder.

## Main store listing

| Field | Value |
|---|---|
| App name (max 30) | `Niz Khata: Khata Book & Ledger` |
| Short description (max 80) | `Track expenses, dues, debts and card bills. Share with family, any currency.` |
| Full description (max 4000) | the contents of [`full-description.txt`](full-description.txt) |
| App icon | [`play-icon-512.png`](play-icon-512.png) (512 × 512, 32-bit PNG) |
| Feature graphic | [`play-feature-graphic-1024x500.png`](play-feature-graphic-1024x500.png) (1024 × 500, 24-bit PNG) |
| Phone screenshots | 2 to 8 real screenshots from the app, see below |

## Store settings

| Field | Value |
|---|---|
| App category | Finance |
| Tags (up to 5) | Personal finance, Budgeting, Expense tracker, Bill reminders, Money management |
| Email | hello@valorumlabs.com |
| Website | https://nizkhata.valorumlabs.com |
| Privacy policy | https://nizkhata.valorumlabs.com/privacy |
| Account deletion URL | https://nizkhata.valorumlabs.com/delete-account |

Tag names must be picked from Play's own list; choose the closest it offers.

## Screenshots

[`screenshots/`](screenshots) holds eight phone screenshots, 1080 x 1920
(9:16), ready to upload in this order:

1. Dashboard: "Your money, at a glance."
2. Transactions: "Every entry, written down."
3. Dues: "Know what's due, before it's late."
4. Credit card statement: "Card bills that raise themselves."
5. A person's ledger: "Every person has a page."
6. Debts: "Lent and borrowed, kept straight."
7. Reports: "See the year, and the story."
8. Budgets: "Budgets that keep you on track."

Each is the app's real screen, rendered from its own widgets with sample
data (the "Sharma Household" workspace) by
`mobile/test_store/store_screenshots_test.dart`, then placed on a branded
frame (`frame.html`). The unframed captures, 1080 x 2340, are in
[`raw/`](raw); Play does not accept them directly, as they are taller than
2:1.

## Regenerating the graphics

`icon.html` and `feature.html` are the sources. Render them at 512 × 512 and
1024 × 500 (the icon needs an alpha channel, which Play requires even though
it is fully opaque).

Screenshots: run the harness (its header says how), copy the PNGs into
`raw/`, then render `frame.html?img=<name>&a=<line 1>&b=<line 2>` at
1080 x 1920 for each.
