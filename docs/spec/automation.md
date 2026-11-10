# Automation and run evidence

Recommended starting tiers:

| Tier | Contents | Trigger |
|---|---|---|
| Smoke | Directed vertical path, queue collision, short reset, CSR handshake and a few constrained-random seeds | Integration change |
| Control proof | Fast local invariants and reachable covers in the smallest production-module proof configurations | Control RTL change |
| Functional regression | Full directed matrix plus at least 20 diverse seeds/configuration for the main functional profiles; expand based on coverage gaps | Longer scheduled/manual run |
| Parameter regression | Focused scenarios for every required profile | Parameter/interface change and delivery |
| Traffic benchmark | Recorded workloads, stable configurations and reference-policy comparisons | Performance change and delivery |
| Implementation | Mapped synthesis/STA for I0/I1 under matched analysis conditions | Microarchitecture change and delivery |

Seed count is a starting execution budget, not evidence of completeness. Record packet/cycle counts and distributions. Serial execution and bounded worker pools are supported. Size parallel work to measured memory and CPU limits.

Each run stores test name, seed, configuration, RTL/bench revision, simulator/UVM version, command, start/end times, result category, first failure and artifact paths. A regression distinguishes functional assertion failure from timeout, license exhaustion, missing executable, malformed input and report-generation error. Tool failure is not a functional PASS or FAIL.

Waveforms should be generated on a failing rerun with the identical revision/seed/configuration. Preserve transaction traces around the first meaningful failure rather than uploading every raw waveform to an LLM.



## Stable command interface

P00 establishes `make doctor`, `make repo-check`, `make lint`, `make test-unit`, `make test-uvm-smoke`, `make formal-smoke`, `make synth-smoke` and `make ci`. Later tasks add `make regression`, `make coverage`, `make benchmark`, `make synthesis` and `make sta`. Commands take explicit configuration/test/seed options through the common Python runner. Until implemented, a command fails with NOT_IMPLEMENTED; it never reports an empty PASS.

The bootstrap `make repo-check` validates repository documents and requirement data only. It is not a hardware check. The bootstrap workflow is named accordingly. P00 adds real tool-capability jobs; subsystem jobs are added as their implementations land. Final CI must exercise the implemented RTL and UVM environment.

Each case writes a JSON manifest containing schema version, UTC times, test/seed/profile, source revision and dirty state, source/dependency/constraint digests, tool versions, argv, result, first failure and artifact paths. Result categories are PASS, FAIL, TIMEOUT, INCONCLUSIVE, UNSUPPORTED, TOOL_ERROR, NOT_RUN and NOT_IMPLEMENTED. Only executed checks can produce PASS. A nonzero tool status, UVM_ERROR/UVM_FATAL or missing completion marker cannot be silently reclassified as PASS.

Use a separate build directory per tool/profile/feature-set. A passing cache from another source revision or feature set is not evidence. Bound subprocess timeouts and parallel compilation. Retain stdout/stderr and transaction traces; collect FST/VCD on failing reruns with the same revision, seed and profile.

GitHub Actions may run the same open-source commands on hosted Linux runners. Core commands must also run in the cloud development workspace. CI does not require an LLM key, a hardware server, a GUI or a container daemon. Retain routine raw artifacts for a finite configured period, and curate the evidence needed for release results. Build outputs are not committed to source control.
