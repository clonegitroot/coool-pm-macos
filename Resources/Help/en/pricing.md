# Calculations, day rates and rebates

Open **Estimate** and generate Pre-Production, Production, Post-Production, and Data-Handling phases, or add your own. Each phase supports multiple people and items, quantities, rates, costs, and relevant day lengths.

| Method | Selling calculation | Cost treatment | Rebate |
| --- | --- | --- | --- |
| Own progressive | Your eligible days advance the configured tiers | Internal | Included |
| Own fixed rate | Quantity × agreed rate | Internal | Included |
| Internal crew | Quantity × agreed rate | Internal | Included |
| External crew | Quantity × agreed rate | External | Excluded |
| Fixed fee | Quantity × fee | Internal | Included |
| Owned equipment | Quantity × rate | Internal | Included |
| Expense | Quantity × rate | External | Excluded |

Fixed-rate producer days can optionally count toward later progressive tiers. External and internal crew keep their agreed selling rates. Set your own rates in setup, **Settings → Day rates**, or the project estimate. A new project without a saved schedule starts with an unconfigured producer rate. Older projects retain their calculation basis. Save named schedules in Settings for reuse. Applying a schedule copies its values to the project.

Set a client default rebate in the client editor. A project rebate overrides it. Leave the project field blank to inherit the client default, or enter zero to waive it. Rebates reduce eligible selling amounts while underlying costs retain their entered values. Changing a client rebate updates unapproved draft projects. Approved proposal values remain frozen.

Under **Settings → Pricing categories**, rename the built-in labels or create a custom category based on an existing method. Its saved calculation method stays fixed. This lets labels match your workflow while rate and margin behavior remains defined.

[Use local AI to prepare a reviewed draft](help://local-ai).
