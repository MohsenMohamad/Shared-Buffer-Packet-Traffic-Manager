# P05 fresh RTL task entry

This handoff provides public APIs, commands and scope only. Preparation merge
establishes no hardware acceptance and does not automatically start RTL.
The maintainer assigns a fresh RTL task under the
[root workflow](../../AGENTS.md#preparation-implementation-and-independent-qualification).

Use the current `origin/main` after the scoped preparation PR is merged.
Freeze the exact base and new RTL head in that task. The initial preparation
base is `8d66a92768f2c72236171731262563814e875352`; the initial expected-behavior
commit is `db8bbec`. The preparation PR head supplies the later DV source identity.
Do not consult withdrawn work or independent DV internals/implementation reports.

Public APIs are `tm_packet_ram_api`, `tm_metadata_api` and `tm_tx_api` in
`rtl/include/tm_module_ports.sv`, using `tm_fixed.sv`, `tm_types.svh`,
`tm_parameters.svh` and `tm_validate.svh`. Behavioral authority remains the
P05 card and its linked specifications. RAM requests at edge e respond at e+L,
L=1/2, with no response ready. Metadata uses the documented finite write/read
ports and pre-state reads. Read issue and external retirement are distinct;
cell/descriptor release follows external cell/packet-final transfer.

Opaque preparation commands:

```sh
make regression RUN_ARGS='--profile E0 --test memory-tx-oracle --seed 17 --timeout 120'
make regression RUN_ARGS='--profile I1 --test memory-tx-bench --seed 17 --timeout 120 --build-timeout 600'
make regression RUN_ARGS='--profile I1 --test memory-tx --seed 17 --timeout 120'
```

The last command must return NOT_IMPLEMENTED during preparation. A future DV
owner enables it only with an actual-source binding and exact RTL/DV identities.
No natural RTL symptom has been discovered in this preparation; no RTL ran.
Model/tool failures and planted faults do not establish a hardware defect.

Candidate DV combines named RTL/DV commits in an isolated worktree and records
the resulting tree plus any resolution/dirty diff. Keep unmerged RTL repairs on
its RTL PR; merged-source defects use a fix PR. Candidate qualification precedes
RTL merge, followed by merged-source confirmation. Only independently qualified
scope can satisfy an acceptance gate; preparation tests cannot substitute.
