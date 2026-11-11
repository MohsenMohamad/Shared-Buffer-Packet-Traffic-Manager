# Modern toolchain qualification

Qualification is in progress. The modern stack is not yet accepted; required
checks without completed execution remain NOT_RUN. Production RTL and historical
P00/P01/P02/P06/P07 result files are unchanged.

Starting `origin/main`: `66f6d0d730238709e2a11faab221f24dc5a81ee9`.
Inventory/criteria were committed and pushed first at `e09e28a`. Exact candidate
source/transitive/download identities are in [the inventory](../implementation/modern-toolchain-plan.md)
and [dependency lock](../../tools/dependencies.json). [PR #7](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/7)
remains draft during qualification.

| Check | Executed status | Scope |
| --- | --- | --- |
| Old-control frontend synthesis | PASS: ten expected outcomes matched | Yosys 0.52 exact old pin; five accepted synthesis cases and five intended syntax rejections |
| Old-control named-width formal | PASS: prove/cover and expected mutation detection | Original production-derived FIFO/snapshot fixture, unchanged source hashes/reset/properties |
| Independent feature simulation development check | PASS | Existing Verilator 5.054; two typed memories, 16 checked reads, latency 1/2, signed/unpacked/interface cases; not modern-installation qualification |
| Runner unit checks | PASS: 40 tests | Includes strict numbered timing-diagnostic rejection and cache generation/integrity contracts |
| Modern install / formal / UVM / production regressions / shared hosted consumers | NOT_RUN | Source build and hosted preparation in progress; no capability acceptance yet |

The old-control comparison uses sources archived from the starting revision and
the exact audit scripts from `a48286d51b9dd195b18388e9ee3c70c8403ccc0b`, with
byte-preservation checks. The external `/workspace/toolchain` installation is
preserved as control; the modern build uses repository-local ignored directories.

Raw control results are `.build/old-frontend/{synthesis,formal}/summary.json`.
Commands use the preserved probe's `generate.py`, `run.py --phase synthesis` and
`formal_run.py named_widths --timeout 300`, with explicit `--repo-root`,
`--generated` and fresh `--output` paths. The final report will replace this
in-progress status with exact tested-source/tool identities, commands and actual
hosted links; it will retain failures and limitations honestly.
