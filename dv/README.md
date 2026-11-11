# Reusing the P07 UVM foundation

Run the declared fixture with the common runner:

```sh
make setup JOBS=2
make regression RUN_ARGS='--profile E0 --test uvm-foundation --seed 17'
make regression RUN_ARGS='--profile I0 --test uvm-foundation --seed 23'
```

The suite compiles the real pinned UVM library and executes source/sink and
AXI sequencers/drivers, passive analysis monitors, RAL frontdoor reads/writes,
register prediction, three independent checkers and passive coverage.
`transactions.jsonl`, per-case manifests, logs, `coverage.dat`, readable coverage
reports and seeded-failure waveforms live in the unique `.build/runs` directory.
Build and run processes have the common runner's timeouts. Setup never occurs
implicitly during a regression.

For P08/P09, instantiate `tm_environment`, configure stream interfaces on
`env.rx0` ... `env.rxN`, `env.tx`, the bus interface on `env.axil`, and the
observation interface on `env` using `uvm_config_db`. Publish the P01 trace,
status and live records through a passive adapter. The generated bench package
uses the selected production profile and includes P01's exact packed types.
Hold reset for at least two rising edges and drive its release on a falling
edge. Reset abandons all packet, FIFO, policy, status and bus expectations.

`tm_stream_item` contains raw beats and gaps so malformed packets are preserved.
A stream agent can be passive (`is_active=UVM_PASSIVE`) or an active source/sink.
Monitors reconstruct signal transfers, including idle clocks, independently of
items. Source user fields are meaningful only at SOP. All valid lanes, final
keep, output metadata and exact surviving delivery count are checked.

`tm_axil_item` supports AW/W delays, byte strobes and B/R response stalls. The
agent queues read and write requests independently and returns sequencer
responses; raw sequences must call `get_response`, as does the RAL adapter.
Reset cancels outstanding/queued old-epoch bus requests with a failed response.
The passive monitor preserves the accepted AR address through response stalls.
The production register block is ready for frontdoor hookup but its production
slave behavior is not tested by the scratch-register fixture.

The coordinator takes one sample from each RX, output, AXI, status, trace and
reset monitor before running models. Direct analysis callbacks never update
model state. The byte model's identity is `(epoch, port, frame ordinal)`, not
tag. Service consumes only earlier captured FIFO beats. Admission uses pre-state
credits/limits, then combines all resource deltas. Dispatch consumes a pre-state
committed head, then applies the current commit; it cannot bypass an empty queue.

Set the model's static limits, WAIT mode and scheduling quantum explicitly when
configuring another component fixture. The current fixture qualifies DROP,
default limits, default/small DRR quanta and zero-cell malformed abort. It does
not implement the production configuration lifecycle, RAM read pipeline, serial
abort traversal, statistics snapshots, packet-RR variant or resource WAIT traffic.
These remain production integration checks under their original requirements.
See [the decision](../docs/decisions/0004-uvm-foundation.md) and
[executed results](../docs/results/P07-verification-foundation.md).

## Production CSR component bench

`make regression RUN_ARGS='--profile E0 --test csr --seed 17'` reuses the AXI
agent, bus interface SVA, production RAL map and passive predictor with the real
register/statistics modules. The separate `tm_csr_model` derives requests from
observed handshakes and statistics from independently driven P01 events, output
retirement and stall samples. It compares complete live/shadow state on every
clock and checks CSR read responses against the authoritative map.

The fixture represents ingress, RX, drain, cleanup, TX and outstanding-read
activity explicitly, in addition to resource/queue bookkeeping. Empty queues
alone cannot make its IDLE true. It does not validate packet processing or
production ownership. The suite tests normal 64-bit counters and reduced 8-bit
rollover with an unchanged 64-bit register ABI, then compiles a disposable
coupled-AW/W production defect. See the
[execution decision](../docs/decisions/0005-csr-events.md) and
[local proof boundary](../formal/csr/README.md).
