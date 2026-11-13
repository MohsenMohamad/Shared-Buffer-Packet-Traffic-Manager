# Tooling guidance

Use toolchain.md and automation.md. Preserve pinned dependencies, bounded subprocesses, source/profile/seed provenance and explicit result categories. Capture stdout/stderr separately from machine-readable summaries. No PASS from empty selection, ignored errors or an unavailable tool. Keep external credentials optional, outside Git and out of ordinary CI. Installation and test execution are separate commands.

Follow the [root ownership and preparation policy](../AGENTS.md#separate-rtl-and-independent-dv-ownership)
for role-specific source access and task gates.
