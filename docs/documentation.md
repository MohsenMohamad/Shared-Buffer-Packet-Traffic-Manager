# Documentation conventions

Write each document for a specific reader task. Lead with its purpose or result, then provide the detail needed to act on or assess it. Preserve precise contracts, reproducible evidence and material limitations.

## Where information belongs

| Location | Primary purpose | Content |
| --- | --- | --- |
| README | Orient contributors | Purpose, supported scope, entry commands and links |
| Specification | Define behavior | Interfaces, requirements, invariants and corner cases |
| Task card | Bound one change | Dependencies, deliverables and acceptance checks |
| PR description | Support review | Behavior changed, important changes, validation summary and limits |
| Results report | Substantiate a result | Tested revision, configuration, commands, outcomes and reproduction |
| Decision record | Preserve a consequential choice | Decision, alternatives, rationale and consequences |
| Handoff | Resume unfinished work | Current revision, verified state, blocker and next action |
| Build or CI artifact | Preserve raw execution data | Logs, waveforms, coverage databases and generated outputs |

Keep one authoritative location for each fact and link to it from summaries. A summary may repeat an essential result or limitation; it should not duplicate the full report. Do not introduce a new document when an existing focused document can hold the information clearly.

## Writing and layout

- Give each paragraph, bullet and table row one primary purpose. Separate behavior, results and reproduction instructions.
- Use short paragraphs, descriptive headings and shallow lists. Add headings when they help navigation, rather than for every sentence.
- Use tables for comparable checks, parameters or mappings. Keep cells concise; move procedural detail into ordinary text or code blocks.
- Use inline code for identifiers, paths and short command names. Put executable sequences in fenced blocks. Use bold sparingly.
- Describe the final state. Include debugging history only when it explains a material decision, reproducible unresolved issue or remaining risk.
- Keep neutral technical language. Do not include conversation history, personal context, generated-by banners or invented results.
- Scale detail to purpose. A specification must retain complete behavior and corner cases; a concise PR must link to the necessary evidence.

Avoid fixed word counts, mandatory empty sections, decorative formatting and long paragraphs hidden in table cells.

## Pull requests

Use the repository PR template as a default, adapting it to the size of the change.

1. **Summary:** Explain the concrete problem and resulting behavior in one short paragraph. Link the work item when relevant.
2. **Changes:** List the important changes in a few focused bullets. Omit this section when the summary is sufficient.
3. **Validation:** Summarize checks by capability or behavior, with their actual result and essential qualification. Link the supporting report or CI run.
4. **Limitations:** State boundaries that affect interpretation, including unsupported or unexecuted checks. Omit this section when there are none.

Use a small validation table when it improves comparison. A single check may be clearer in a sentence. Keep a result's essential qualification beside it even if the limitations section adds detail.

Full hashes, seed lists, digests, command transcripts, long artifact paths and detailed measurements belong in the results report. Include a number or short command in the PR when it materially helps assess the change. Do not compress all evidence into a long bullet.

An expected seeded-defect detection is a successful negative check only if the intended violation was detected. A generic crash, unrelated assertion or missing executable does not establish that result. Label the expected detection explicitly.

Do not equate fixture qualification with traffic-manager validation, bounded checking with an unbounded proof, or pre-layout timing with physical signoff. Coverage collection does not establish coverage closure. Use each check's actual recorded status, such as PASS, FAIL, UNSUPPORTED, NOT_RUN, TIMEOUT or INCONCLUSIVE; do not replace these with optimistic wording.

## Results and reproduction

A supporting results report should make the result traceable without reading a development transcript:

- State the purpose and validation boundary first.
- Identify the tested source revision and relevant dependency, configuration and constraint versions or digests.
- Give a concise result table, with limitations that affect the interpretation of each result.
- Put exact reproduction commands, profiles, seeds and required setup in a separate section. Keep command blocks executable; place explanatory prose outside them.
- Link raw artifacts and identify how to regenerate outputs after hosted artifacts expire.
- Separate successful positive checks, expected negative detections, unexpected failures and unsupported or unexecuted checks.

Never infer a pass from an existing prose claim alone. Distinguish recorded prior results from checks executed for the current change. If an earlier executable revision is cited, identify it and verify whether later changes affect the result; do not imply execution on a later revision without evidence.

Do not copy raw logs into narrative documentation. A short error excerpt is appropriate when it is needed to identify or reproduce a problem. Preserve important numeric measurements and proof assumptions in their authoritative report or specification.

## Before delivery

Check Markdown structure, tables, code fences and relative links, including files under `.github`. Inspect rendered output when a suitable preview is available. Ensure result summaries lead to the actual evidence and that material limitations remain visible. Run relevant existing lightweight checks; a prose-only change does not itself require rerunning expensive hardware qualification.

## Durable evidence for new work

Commit compact durable revision/configuration/tool/result/measurement and reproduction records to Git. Keep bulky per-process detail, raw logs, waves, databases and generated outputs in build/CI artifacts. Preserve enough numeric measurements, assumptions, expected-negative identities and limitations in the durable report to explain the result after artifacts expire. This policy applies to new work; existing results JSON, including P01/P02, remain unchanged and are not retrospectively compacted, relocated or deleted.

Record the actual tested SHA and dirty state, configuration/dependency/constraint digests, exact commands and tool identities. Associate the PR and workflow/run references when available. An integration SHA on merged main may be added as metadata; it must not replace the tested SHA or imply execution on that untested revision. For historical dirty runs, retain the recorded base SHA and behavioral hashes; do not invent a clean tested commit.

To retrieve historical sources, fetch the recorded tested commit (or the associated PR head ref when needed), then check it out in a separate worktree. Use `gh pr view NUMBER --json commits,mergeCommit,url` and `gh run view RUN_ID` where references exist to distinguish tested heads from merge metadata. For example:

```sh
git fetch origin TESTED_SHA
git worktree add --detach ../historical-result TESTED_SHA
# If the commit is reachable only through the recorded PR:
git fetch origin pull/NUMBER/head:refs/remotes/origin/pr-NUMBER
```

Substitute actual recorded values. Consult the report's commands, locks and source hashes before replaying; a dirty historical base alone cannot reconstruct missing edits. Record unavailable artifacts or unrecoverable source differences explicitly. Expiring artifacts must never be the only explanation of a result.
