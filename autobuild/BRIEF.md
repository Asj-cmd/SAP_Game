# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## P6-1 — Loss and lag

**Approach**
1. New `LinkConditions` (new, `godot/net/link_conditions.gd`, RefCounted): `latency_ms` (one way),
   `jitter_ms` (0 default), `loss` (0..1), `seed`, and a `clock: Callable` (default
   `Time.get_ticks_msec`) so a test can drive time by hand.
2. `LoopbackTransport` gains `var conditions: LinkConditions = null`. Null = today's immediate,
   lossless behaviour, unchanged byte for byte (it is the reference; keep its doc comment true by
   saying the conditions are opt-in). With conditions, `send` puts `{due_ms, payload, from}` in the
   receiver's pending queue; `poll` moves due entries to the inbox.
   - UNRELIABLE: dropped with probability `loss` (own seeded RNG), may arrive out of order with jitter.
   - RELIABLE (everything today: nothing in the code sends UNRELIABLE): never dropped; a "lost" packet
     arrives one extra round trip later (2 × latency, ENet-like resend), and delivery stays in order
     per sender (due = max(due, previous due from that sender)).
   - Session/peer events (ready, joined, left) are not delayed.
3. `tools/net_loopback.gd`: accept `--latency-ms=` `--loss=` `--jitter-ms=` and give both ends the
   conditions (loopback backend only). Its per-packet wait is 2000 ms, which is enough. Run it at
   `--latency-ms=100 --loss=0.05` and expect IN LOCKSTEP with the same scores as without.
4. `tools/net_prediction.gd` already takes `--latency=` in ticks (30 Hz: 100 ms = 3 ticks). Add
   `--loss=` there with the same reliable model (a lost packet arrives 2 × latency ticks later, in
   order; seeded). Run at `--latency=3 --loss=0.05` and `--latency=6 --loss=0.05`; expect CONSISTENT,
   record the own-position prediction error it prints in PROGRESS.md.
5. If either diverges: that is a real defect; find the first disagreeing tick (both tools print it),
   fix it in `net/` (two attempts max, then BLOCKED.md and `[~]`).
6. Add rows to the EXISTING `tests/transport_test.gd` (table-driven, loopback only, fake clock):
   nothing before latency, delivered at latency, reliable never lost and in order under loss 1.0,
   unreliable dropped at loss 1.0 and kept at 0.0, null conditions = immediate. Ratchet
   `transport_test` in `autobuild/test_baseline.json` (now 28).
7. Add one line to the Network block of `autobuild/verify.mjs`: net_loopback with
   `--latency-ms=100 --loss=0.05`, verdict "IN LOCKSTEP" (full verify only, not `--quick`).
8. Note in `godot/ARCHITECTURE.md` (net section, two lines) that loopback can simulate lag/loss and
   that every channel is reliable today. Full verify once at the end; commit.

**Already decided**
- Latency in wall-clock ms on the transport (the lockstep harness waits on the wall clock); in ticks
  in net_prediction (it has no transport). Log it.
- Reliable-under-loss = later, never missing (ENet reliable model); unreliable = dropped. Log it.
- The gate condition is 100 ms one way + 5% loss, as PLAN.md says. Log it.
- ENet and net_smoke get no loss injection (ENet has none built in; out of scope). Log it.

**Files likely touched**
- `godot/net/link_conditions.gd` (new)
- `godot/net/loopback_transport.gd`
- `godot/tools/net_loopback.gd`, `godot/tools/net_prediction.gd`
- `godot/tests/transport_test.gd`, `autobuild/test_baseline.json`
- `autobuild/verify.mjs`
- `godot/ARCHITECTURE.md`, `DECISIONS.md`, `PLAN.md`, `PROGRESS.md`

**Done means**
- `transport_test` passes with its new count pinned; the null-conditions rows prove the reference
  path is unchanged.
- net_loopback at 100 ms / 5 % prints IN LOCKSTEP with the same host/guest scores as the plain run.
- net_prediction at 3 and 6 ticks with 5 % loss prints CONSISTENT; its error numbers are in PROGRESS.md.
- Full `node autobuild/verify.mjs` healthy, run ONCE at the end, including the new network line.

**Do NOT**
- Change the default (no-conditions) loopback behaviour, the snapshot format or the command codec
  unless a divergence proves it necessary.
- Start the Steam transport (P6-3) or host modes (P6-2).
- Switch any channel to UNRELIABLE as an "optimisation".
- Touch `sim/`, bots, or run sweeps; no frames.
