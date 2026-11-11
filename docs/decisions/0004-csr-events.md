# CSR execution and independent event qualification

P06 retains the P01 packed AXI, configuration, live-state and statistics APIs.
The register slave owns configuration and three independent channel holds.
Statistics has one writer for live counters/high-water and separate shadow
state. Neither module depends on a CPU platform or packet-memory implementation.

Write execution follows capture of both AW and W. Read execution follows AR
capture. Captures cannot bypass into execution on the same edge. Read and write
execution may coincide and read pre-write state. Commands are combinational
functions of held state and execute on that edge, so SNAPSHOT captures pre-event
counters rather than a registered command delayed by another clock.

Address decode first identifies the aligned word. A mapped misaligned address
is SLVERR, including zero-strobe writes. Unknown aligned words and invalid queue
indices are DECERR. After address validation, a mapped zero-strobe write is a
successful no-op, including RO words and locked configuration. Other writes
merge all four selected bytes before full-width range checks; rejected writes
cannot partially modify configuration. CTRL ignores reserved bits, command
registers use bit zero only, and ADMISSION_MODE rejects merged values above one.

The fixture supplies independent P01 architectural actions, output retirement,
external stall samples and six explicit busy-context inputs. It accounts for
resource deltas solely to drive live CSR inputs and computes fixture IDLE from
those contexts plus restored resources and empty queues. It contains no packet
datapath. The passive model predicts commands from observed bus handshakes and
statistics from fixture inputs; no DUT statistic or command generates expected
events. A snapshot collision is scheduled from accepted AW/W, not DUT command
feedback. P09/P10 must reconnect real validated events and reverify actual IDLE.

`COUNTER_W` is a statistics-only qualification parameter, default 64, bounded
1..64. The 8-bit regression wraps actual production arithmetic, zero extending
values into the unchanged 64-bit P01/CSR ABI. It is not a production profile or
a claim of executing 2^64 events. Resource counts/high-water keep their normal
profile widths. Snapshot and clear do not reset the invariant-error latch.
