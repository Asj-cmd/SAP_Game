# Project memory

Written to close a two-session split: design review happened in one place and
building in another, and a person had to carry context between them. This is
that context.

Read it alongside the other docs. It carries what none of them do — the working
method, the mistakes and what they cost, and where things actually stand.

---

## 1. Document map

| Document | What it is | Trust |
|---|---|---|
| `ARCHITECTURE.md` | How the code is structured, and why. §3 contract, §6 decisions, §9 extension points | Current |
| `WORLD_AUTHORING.md` | Collision, validator, thresholds, the authoring pipeline | Current |
| `DESIGN_DIRECTION.md` | What the game is trying to be. Settled decisions, verbs, distribution | Current |
| `CLAUDE.md` | Testing policy, looking-at-the-screen rule, conventions | Current — binding |
| `HOUSE_LAYOUT.md` | The eighteen-room three-storey proposal | **Superseded.** See §5 |
| `PROJECT_MEMORY.md` | This file | Current |

## 2. Where things stand

**Complete and working.** The simulation layer — core, capture, movement,
scoring, match flow, carry — all deterministic, all content-driven. Collision
with swept segment tests and a broadphase. A walkable surface, nav graph and
bot director. Networking end to end: command codec, ENet transport behind a
session-shaped interface, prediction with rollback, snapshot reconciliation,
lobby with seats that outlive their occupants, reconnect by token. A grey-box
playable with a third-person camera, and capture tooling that can look anywhere.

**Not started.** The Steam transport backend (interface proven, backend is
plumbing). Physics chaos. Characters and appearance. The verbs — throw, crouch,
vault, slide, drop. Any art at all.

**Known constraint.** The development machine is a GeForce GT 730M, which cannot
run Godot's Forward+ renderer — it crashes during shader-cache load. Compatibility
only, which rules out the ambient occlusion and post-processing the Three.js MVP
had. This will matter at the art phase and is not a bug to fix.

## 3. The working method

These were learned expensively. Each is a rule because ignoring it cost a
session.

**Measure before changing.** Three times a plausible theory was overturned by
measurement, and each time acting on the theory would have masked the real cause:

- The doorway stall looked like a steering problem. Implementing the fix moved
  the number from 558 to 582. The real cause was a constant bias re-rolled per
  errand rather than per tick.
- Zero captures looked like the houses being too far apart. Teams met eighteen
  times — all of them on neutral ground where capture is illegal.
- A behaviour change from an indexed predicate looked like a broadphase bug. The
  index was exact; the *old hand-copy* was wrong.

**Build the instrument before the investigation.** The validator before the
level, the stall metric before the doorway fix, the encounter counter before the
layout argument, look-anywhere capture before the wall joins, the audit harness
before the predicate swap. Every one found something the direct approach missed.

**A check that can't fail is indistinguishable from one that passes.** The desync
trigger read zero for weeks because packet loss leaves a guest *behind*, not
*wrong*. Prove a scanner can see by planting an offender. Pin expected check
counts, because a smaller green number is not a passing one. A validator row that
silently skips is not a validator row.

**Sample the workload, not a model of it.** Random segments missed the real
query distribution. Lattice-aligned segments — a considered second attempt —
missed it too. Running both implementations on live match traffic found it in
one match.

**Watch for one field doing two jobs.** It only becomes visible when the two jobs
disagree. Zones inferring "outdoors" from neutrality. `AABB.intersects` used as
both containment and overlap. A periodic re-plan that was also the stuck-recovery
mechanism — cache it away and every bot pins at a french window for 662 seconds
with a green suite.

**When the symptom is invisible to the instrument, measure the cause.** A
screenshot cannot show z-fighting. Counting shared blocker volumes can: 42 pairs
to 0.

**The mean is the wrong statistic for feel.** Median tick 1.6 ms, p99 113 ms.
Not slow — hitching several times a second.

**Read the log before theorising.** A blank game window produced two plausible
theories, both real bugs, neither the cause. Godot had printed the exact error at
startup: a camera reparented into a viewport it already had a parent in.

**Never put the safest place on the busiest route.** The neutral strip between
the houses was both the crossroads and the only place capture was illegal, so
every encounter happened where nothing could come of it.

## 4. Review errors, and what they cost

Recorded so the next reviewer is calibrated, and so these aren't repeated.

**Min-cut 3 as a hard gate was the expensive one.** Requiring three independent
routes into every room was pushed as a design rule and made a load-bearing check.
It was flagged at the time — *"that's the rule shaping the architecture, a
pressure toward compartmented houses"* — and waved through. A generator
satisfying a graph inequality builds whatever satisfies the inequality: eighteen
compartmented rooms across three floors, light wells, two staircases, and a house
nobody had designed. The floor is now 2. Three was an aspiration that ended up
commissioning a maze.

**A\* was recommended and lost on measurement.** Three implementations, all
slower than the flood they replaced. At 13,778 nodes GDScript's constant factors
beat the asymptotics — the flood's inner loop is an append and a cursor bump.
Caching, the other half of the suggestion, is what worked.

**Smaller misses.** "Humans self-heal from latched intent" — they don't; a player
holding one direction had the identical bug. The headless hang attributed to an
autoload — it was a full best-of-three running inside `_initialize()`. Two
candidate causes for the blank window — both real defects, neither responsible.

The pattern: reviewer hypotheses about *mechanism* have been wrong more often
than right. Reviewer suggestions about *method* — measure this, build that
instrument first, separate those concerns — have held up. Weight them
accordingly.

## 5. The house, and why it was rebuilt

The first house was generated to satisfy the routing gate: eighteen rooms, three
storeys, technically flawless and never fun. Playing it produced sticking, random
falls into the basement through invisible light wells, and no sense of place.

It was replaced by a hand-drawn one: **six rooms, two floors, one staircase,
vault upstairs, jail on the ground, two fronts facing each other across a
garden.** Coordinates chosen and commented rather than solved for. Ways in: hall
3, kitchen 3, landing 3, vault 3, jail 2, bedroom 2.

Placement stays generated — two hand-written copies would drift, and asymmetry
between the houses is a balance bug nobody can see. Rooms are drawn.

Smaller was also faster: p99 73 → 36 ms, over-budget ticks 74 → 11, from nothing
but a smaller world.

**The principle:** scale a level after it plays well, not before. Eighteen rooms
existed before ten seconds of fun did.

`HOUSE_LAYOUT.md` describes the old one and should not be built from.

## 6. Live queue

In order, as last agreed:

1. **Replace the trellis with a balcony drop.** The trellis is 704 units of
   external staircase for one window, and the only climb in the house. A driven
   body climbs it in all three lanes; the bot follow cannot — 201 of 232 stalls
   at that one point. Cutting it outright would leave the staircase as the only
   vertical link, and one defender on those stairs holds the whole robbery. A
   one-way downward drop from bedroom or landing costs no structure, is visible
   from below, and gives the up-slow/down-fast asymmetry an upstairs vault wants.
   Bedroom's second entrance becomes internal.
2. **Check whether the trellis stall survives the change** before debugging it.
   It may cease to exist.
3. **Re-measure before the amortised flooding.** The queued p99 work may now be
   solving a problem the smaller world already solved.
4. **Bot route variety** — it takes the same approach every time, which is
   solvable after two rounds.
5. **Encounter→seizure conversion.** The bottleneck moved: teams now meet on
   legal ground and don't convert. Hold this until a human has played, because
   14% may be a bot deficiency rather than a game problem — and tuning the game
   to fix the bots would make it worse for people.

## 7. Two things still owed to the user

**A real two-machine playtest.** Everything network has been proven headless and
in two windows on one desk. Nobody has played this over a wire with a friend.
`PLAYTEST.md` covers Tailscale and the build; ENet cannot traverse home routers,
which is what the Steam backend eventually fixes.

**A house that is fun for ten seconds.** That has not happened yet, and it is the
only measure that matters. Everything in §2 is scaffolding for it.
