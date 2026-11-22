# Results

- [Public multi-egress ABI](TM03-multi-egress-declarations.md)
- [Datapath feasibility](multi-egress-datapath-feasibility.md)
- [Queue and control feasibility](TM04-queue-control.md), [timing follow-up](TM04-control-timing.md), and [composed timing](TM04-composed-timing.md)
- [Live pool checking](TM05-live-pool-checking.md) and [original DV preparation](TM05-pool-dv-preparation.md)
- [Toolchain qualification](toolchain-qualification.md) and [symbolic input recipe](F01-formal-symbols.md)

## Historical baseline

The [retired single-egress tree](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/tree/4634d5a4dacb00304635ddb64a3f83747d8b03e8)
preserves the original RTL, specifications, regressions, proofs, commands
and tracked evidence. The [historical results index](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/4634d5a4dacb00304635ddb64a3f83747d8b03e8/docs/results/README.md)
links the component studies. Historical reports keep their own tested
revisions and qualifications. The baseline commit identifies the archived
files and does not identify a new run.

To recover any retired file byte for byte, use its original path at
`4634d5a4dacb00304635ddb64a3f83747d8b03e8`. To replay an experiment, use
the tested source and commands from its report.

```sh
git show 4634d5a4dacb00304635ddb64a3f83747d8b03e8:docs/results/TM04-composed-timing.json
```
