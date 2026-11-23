# Local AI and reference projects

Drafts organize work in production order and state client deliverables, assumptions and open questions. Calculation review runs separately from drafting. It uses the app’s computed amounts and shows progress, errors or confirmation when the model returns no additional findings.

Open **Settings → Local AI** and enable the assistant. Model cards show download sizes, estimated memory requirements and limitations. The recommendation depends on your Mac’s unified memory. Available memory, project size and other apps affect performance.

Select a model and choose **Download model…**. Downloads retrieve pinned, integrity-checked files from Hugging Face. After downloading, inference works locally. Weights are stored in the local Application Support/Coool PM/AIModels folder.

In a project, choose **Local AI…**. **Draft from brief** proposes an editable introduction, phases, roles and quantities. Review assumptions, questions and quantities, then select what to apply. Coool PM calculates amounts using its own engine and your saved rates. Review copied reference rates or enter agreed selling rates yourself. Unpriced drafts can be applied for completion later. **Review calculation** adds advisory scope findings alongside exact app checks. Approved projects support review. Applying new drafts requires an editable inquiry/proposal project.

The context disclosure lists the data used. Client contact records, attachments and unselected projects are excluded. Selected reference summaries are explicitly listed. Pasted briefs may include information you supply. Applied drafts can be undone while affected fields are unchanged and have no linked activity.

Starting an action loads the selected model automatically. Settings shows loading, ready, generating, unloading and error states. Cancel tasks, load or unload manually, release after each task, choose an idle timeout or keep loaded while open. Memory pressure releases idle models and may interrupt an active task. Unloading stops the inference process. Downloads remain until removed. Switching models releases the previous model first.

The three options use Qwen3 at 4-bit precision. The lightweight model is intended for short wording and draft assistance. Complex estimates and nuanced scope reviews require careful review, particularly with the small model. Model descriptions provide guidance. Output can be incomplete or incorrect.

Encrypted backups include the selected model ID and idle policy. Weights are downloaded again on a new Mac. AI enablement is a local device preference, independent of external MCP access.

### Pricing and reference projects in AI drafts

The assistant receives all available calculation methods and renamed/custom categories: own progressive days, own fixed days, internal crew, external supplier crew, fixed fees, expenses and owned equipment. It receives the project’s fixed-day tier-count setting and rebate. Crew never uses the owner’s progressive tiers. Internal crew is rebate eligible and its cost belongs to DB2; external crew and expense costs belong to DB1 and receive no rebate.

Each generated position has an editable role and pricing picker. A role names the service or job; it is independent of how it is priced. Enter agreed fixed rates and unit costs yourself. The app ignores model-supplied prices and calculates totals from reviewed inputs. Switching calculation methods clears rates and costs; switching between categories with the same method keeps them.

Expand **Reference projects (optional)** and choose up to two other projects, including archived projects. Search by title or project number. Nothing is selected initially. The prompt includes only selected historical scope/calculation summaries, limited to the first three phases, four entries per phase and short scope/deliverable excerpts. Contacts, documents and terms are excluded. The current brief takes priority. Historical quantities and rates are examples that need review, not new agreements. Large current projects plus references may exceed a model’s context limit; shorten the brief or remove a reference.

Responses containing the old placeholder sentences are rejected and retried once. Review mode accepts findings/questions without proposing new phases. Small local models can still misclassify positions or estimate effort incorrectly. Always check the selected method, quantities and scope before applying.

### Reusing reference rates and finishing prices later

Selecting a reference also makes its saved line rates available. The assistant can identify a source position with its reference ID; an exact role/method match is also accepted when unambiguous. Coool PM copies the recorded selling rate, cost and day length directly from that position. Model-authored monetary values remain ignored. Positions with a different method, an unknown source or conflicting matching prices remain unpriced. Cost values are included only with cost controlling enabled.

Choose **Own day-rate schedule** to reuse one selected reference’s progressive tiers, or choose **Keep current project rates**. The first selected reference is the initial schedule choice. The preview lists the copied schedule. Applying it with own progressive positions changes the project-wide schedule, including existing own progressive positions; the confirmation explains this and Undo restores the previous schedule.

A missing price never blocks applying an editable AI draft. The preview warns that its total is incomplete; fill in prices later in the project calculation. Each numeric field has a visible label: days/units, selling rate or unit price, and internal or supplier cost, with EUR and day/unit shown explicitly.

[Briefing checklist and copyable prompting examples](help://ai-prompting).
