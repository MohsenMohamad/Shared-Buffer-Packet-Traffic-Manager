# Tooling guidance

Use toolchain.md and automation.md. Preserve pinned dependencies, bounded subprocesses, source/profile/seed provenance and explicit result categories. Capture stdout/stderr separately from machine-readable summaries. No PASS from empty selection, ignored errors or an unavailable tool. Keep external credentials optional, outside Git and out of ordinary CI. Installation and test execution are separate commands.

## Registration ownership

Independent DV owns test/proof/coverage handlers and its entries in
`verification/suites.json`, `verification/formal.json`,
`verification/sources/*.json`, `verification/requirements.json`, runner dispatch
in `tools/run.py` / `tools/formal_storage.py`, and affected workflow suite
selections. Production source membership is coordinated with the RTL owner.
Keep independent selections distinct from designer smoke and capability fixtures;
registration alone creates no evidence. Toolchain/setup inputs remain tooling
ownership and are not changed to bypass doctor or a failing DV check.
