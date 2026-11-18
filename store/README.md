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

Play requires screenshots of the real app (mock-ups are rejected). Take
them on a phone, in a workspace with realistic sample entries and no real
personal data:

1. Dashboard
2. Transactions list, or a split transaction
3. Dues with the calendar
4. A credit card's ledger showing its statement bill
5. A contact's ledger with a part repayment
6. Statement import, reviewing rows
7. Reports or budgets
8. Shared ledger

Phone screenshots: PNG or JPEG, 9:16 portrait, each side between 320 px and
3840 px. A normal Android screenshot fits.

## Regenerating the graphics

`icon.html` and `feature.html` are the sources. Render them at 512 × 512 and
1024 × 500 (the icon needs an alpha channel, which Play requires even though
it is fully opaque).
