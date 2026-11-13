# P05 memory and TX control

The production store exposes one 64-bit synchronous read and one write per
edge. A request at edge e produces a response sampled at e+L, with L=1 or 2.
The second latency is a response register stage. A physically banked comparison
remains P12 work; this stage makes no claim about banking or area improvement.

## Finite metadata ports

`tm_metadata_api` owns one cell-next array with one RX-extension writer and two
combinational read muxes (TX and abort). It owns one descriptor-info array with
one reservation writer and N_Q combinational head queries. The P03
`tm_desc_links` child is instantiated once as the sole descriptor-next owner,
with one queue-enqueue writer and one dispatched-head query. There is no reset
or write-through bypass. All three arrays and their read muxes belong in future
area accounting.

## Read credit and lifetime

For buffered count B, outstanding count O, issued read I, tagged response R and
external retirement T, one update computes:

```
B' = B + R - T
O' = O + I - R
B' + O' = B + O + I - T <= TX_FIFO_DEPTH
```

Issue is admitted only when B+O-T is below depth. A response consumes its
already-reserved slot. The current sink transfer can fund a new read; a response
alone cannot. Pending valid bits advance exactly L stages alongside keep,
packet-final, cell-final and cell ID. The FIFO stores those fields with payload
and repeated packet metadata.

The fetch cursor advances at issue. At a nonfinal cell boundary it captures the
combinational next link on that issue edge, before the old cell's final response
can reach the external output. Cell return uses the FIFO entry's ID at its last
external handshake. Only a final packet handshake emits `tx_done`; integration
wires it to the descriptor pool's TX return lane. No descriptor pool return is
implied by dispatch, fetch completion or RAM response.

## Reset and assumptions

Reset clears active state, FIFO counts/pointers and pending tag validity. It
clears no payload, link, descriptor-info or FIFO data array. Untagged RAM
responses are ignored. Because reset spans at least two rising edges and L<=2,
old unreset RAM pipeline responses drain while tags are invalid. No epoch
counter is needed under that public reset contract.

The unreset RAM/metadata APIs have no reset input. Their owners must suppress
writes and read requests during reset. Dispatch requires a committed, legal
acyclic cell chain whose contents remain owned until external retirement.
The RAM asserts against same-word read/write collisions; no simulator collision
value is used. Embedded TX assertions check merged credit, tag count, required
response timing, stalled stability, duplicate cell retirement, reads of retired
cells and final resource accounting. These are designer assertions, not an
independent proof.
