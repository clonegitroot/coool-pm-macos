# Writing useful AI briefs

The local assistant prepares a draft or reviews the current calculation. It does not send documents, issue invoices, approve proposals, inspect attached media or search every project automatically. Its context is shown in the disclosure. You choose up to two older projects explicitly.

## Before you generate

1. Enable and download a suitable model in **Settings → Local AI**. Hardware recommendations and memory figures are estimates. The small model works best with short, focused requests.
2. In the project, choose **Local AI…**, then **Draft from brief** or **Review calculation** and the output language.
3. Select references if needed. Choose the own day-rate schedule to copy, or keep the current project's schedule.
4. Describe the new work in plain language. Use actual roles, exact days and explicit pricing methods. Start with a small scope instead of a long client email.

## A useful brief includes

- **Deliverables:** number, duration or format of outputs; versions, subtitles and feedback rounds where known.
- **Work:** what you do yourself and what other people do. State days per role; the model should not convert days to hours.
- **Pricing:** your own progressive or fixed days, internal crew included in your fee, external suppliers, service packages, purchases and owned equipment.
- **Boundaries:** what is included, excluded, supplied by the client or still unknown.
- **References:** what to reuse and what to change. Old quantities, agreements and dates are not automatically valid for the new job.

If you mention a fixed rate, enter or check its actual amount in the preview. Model-authored monetary values are ignored. Matching selected reference positions can provide their saved rates and costs directly.

## Example: a small solo production

```text
Draft a proposal for one 60-second film and three 15-second cutdowns.
I do the work myself: one filming day at my own fixed day rate,
and two editing days using my progressive schedule.
Include one feedback round. The client supplies the location.
Do not add crew or extra positions. Ask only about missing requirements.
Leave unknown prices unfilled; I will complete them in the preview.
```

After generation, verify the filming line uses **Own fixed rate**, the editing line uses **Own progressive**, and the quantities remain one and two days.

## Example: distinguish internal and external crew

```text
Plan two filming days and two editing days.
I produce the project myself using my progressive schedule.
A camera operator works two days as INTERNAL crew integrated in my fee.
An external sound supplier works two days as EXTERNAL crew.
Add one purchased music licence as an expense and two units of my owned camera kit.
Do not apply my progressive tiers to crew. Do not invent additional positions or prices.
```

Check **Internal crew** versus **External crew** carefully. They affect rebates and the DB stages differently. A job title such as Editor or Photographer does not determine whether someone is the owner or crew; say who performs the work.

## Example: reuse a selected project and its rates

First select the older project in the reference picker, then write:

```text
Use the selected reference as the structure and rate reference.
The new job has one interview, one filming day and two editing days.
Reuse saved prices only for matching roles and pricing methods.
Keep the new quantities above. Do not carry over old deadlines or extra crew.
Leave unmatched prices at zero and ask about genuinely missing deliverables.
```

The app copies rates only from selected, matching records. Translated roles can be linked by the model to a reference position; exact unambiguous role/method matches are also supported. Different methods, conflicting matches or unknown sources can remain unpriced. You can still apply the draft and complete prices later. Copying a reference's own progressive schedule affects existing own progressive positions too; inspect the preview and confirmation.

Only compact summaries are included: up to three phases and four lines per phase, short scope/deliverable text, tiers and relevant calculation values. The model does not see the complete old proposal, attachments, client contacts or terms. Supply any missing context explicitly rather than asking it to infer unseen material.

## Example: review an existing calculation

Choose **Review calculation**, then write:

```text
Check the current calculation against this scope:
one filming day for three interviews, two editing days, one feedback round,
one final 60-second film with subtitles.
Look for duplicated work, missing sound/data-handling effort,
unclear internal versus external crew, and mismatched quantities.
Return concrete findings and unanswered questions. Do not create new phases.
```

The app's displayed totals and deterministic checks come from its calculation engine. The model's findings are advisory. Do not treat an unmentioned issue as proof that everything is correct.

## Reviewing and refining

Check the introduction, scope, actual role names, pricing methods, days/units, selling rates and costs. Numeric labels distinguish per-day and per-unit amounts. Verify the reference source and your own rate schedule. Select only the phases you want to add; they append to the current calculation. Selected introduction text replaces that language's current proposal introduction.

Missing prices show an incomplete-total note but do not block an editable draft. **Undo applied draft** restores the affected fields while unchanged and unlinked. Approved projects support review; they do not accept new AI draft calculations.

For a weak result, try one smaller, more specific brief. State the correction directly: “The camera operator is internal crew; I do the editing myself.” Generating again replaces the preview. There is no ongoing chat memory. Re-enter the relevant facts in each request; applied project data can be used as current context on a later request. Shorten the brief or remove a reference if the context limit is exceeded.

[Model downloads and memory controls](help://local-ai) · [Pricing methods](help://pricing) · [Data protection](help://privacy).
