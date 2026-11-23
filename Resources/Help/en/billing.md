# Invoices and payments

Choose **Create invoice** for a client invoice. Start with the recipient, milestone, service period, document date and VAT. Red checklist items explain what you still need to issue the invoice. Expand **Document text** or **Export and billing options** for additional wording and format choices.

Set payment deadlines and split billing in **Billing → Payment terms…**. Choose percentage or fixed instalments that reconcile to the agreed fee. The client’s default payment deadline comes from **Settings → Business → Client defaults** when the client is created. Override it for the client or project as needed. Invoice titles and cover text describe the partial invoice. The payment terms on an invoice show its deadline. Proposal terms can include the full instalment schedule.

Create an invoice from the planned instalment or remaining balance. The issue action records its number, amounts, recipient, and document. The export checklist explains missing data. Enter a reason for agreed amount adjustments. For expenses flagged **Bill at cost**, select the amounts to add as separate invoice positions. They stay separate from the service instalment. A custom Word invoice template can position the PO and itemization using `{{purchase_order}}` and `{{invoice_positions}}`.

To record a sent invoice, import its file and copy the original invoice number, dates, net amount, VAT rate, and VAT amount. Match it to an instalment where appropriate. An imported file becomes part of financial totals after it is recorded in Billing.

Record dated payments, including partial receipts. **Mark paid** records the outstanding gross amount. If an invoice was issued by mistake and has no send, acceptance, payment or correction activity, use **Undo invoice creation…**. The app retains its audit copy and reserves its number. For an invoice with subsequent activity, issue a linked correction. You can also discard eligible unsent document drafts while keeping the next version number moving forward.
