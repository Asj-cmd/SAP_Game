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
| `HOUSE_LAYOUT.md` | The buildable house spec — floors, vertical stacking, connections, lot | Current. Rewritten; §5 records what it replaced |
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
plumbing). Physics chaos. Characters and appearance. The verbs still owed —
slide and drop-from-height. Any art at all.

**Verbs built since.** Crouch (a smaller collision body, slower, fits gaps a
standing body cannot), jump (an impulse, capped to the headroom the VISIBLE
body has), and throw (a deterministic ballistic arc, not a physics body).
Vault was built and then removed: jump does the same traversal and cannot clip
by construction, which the vault could and did. The three of them are
simulation state that presentation reads, per ARCHITECTURE §9 - only the crouch
is drawn so far, and jump and throw still look like nothing in particular.

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

## 5. The house, and why it was rebuilt twice

**First rebuild.** The generated house - eighteen rooms, three storeys, built to
satisfy the routing gate - was replaced by a hand-drawn one. Coordinates chosen
and commented rather than solved for.

**Second rebuild, after playing it.** That house was three rooms in a line, one
room deep: 24 m by 8 m, which is a terrace. Every door was on the front, because
the front was the only long face - so there was no way to come round the back of
anything. And a flight of eleven treads is 704 long in a 755 room, so the
staircase filled the room, started hard against a wall, and had to be approached
by walking into a corner.

It is now **two rooms by two, sixteen metres square**, over two floors:

    hall / landing   full depth down one side, holds a staircase
    jail / bedroom   at the BACK, away from the enemy house
    kitchen / vault  at the front

Doors on three of the four faces; the fourth is left blank so the house has a
back to it. Two staircases, one in the hall and one in the jail, so no single
body holds the upstairs - a staircase is a single edge in the route graph, and
with one of them the vault has exactly one way in however the upper floor is
arranged.

**The storey came down from 330 to 240** - eight steps rather than eleven. That
is what makes a flight fit a room with floor to spare, and 2.4 m is what a real
ceiling is. Still a whole number of steps, which §12 requires.

Placement stays generated - two hand-written copies would drift. Rooms are
drawn.

**Two sampling rules were learned here and are in `WORLD_AUTHORING` §11.** The
world must be a whole number of fill cells or a turned copy is sampled at a
different phase and silently differs from its twin. And a floor tint must follow
the walkable footprint rather than the room rectangle, or it paints over the
stairwell and the player climbs through what looks like a solid floor.

**The principle:** scale a level after it plays well, not before. Eighteen rooms
existed before ten seconds of fun did.

`HOUSE_LAYOUT.md` describes the first one and should not be built from.

**Next: the layout is being specified by the player.** The house so far has been
drawn by whoever was building it, which is why it has been rebuilt twice. A
described plan is coming; treat this one as scaffolding to be replaced rather
than something to defend.

**One rule that is NOT a bug, and was measured to check.** A team can seize an
intruder anywhere on ground it owns - and cannot in the neutral garden, in the
other house, in its own pen, or in its own vault while the intruder's 5 s
safe-room grant is running. That last one bites hardest: the raider is protected
in the very room the defender most wants to catch them in. It is Variant B
working as specified (`DESIGN_DIRECTION` §4) and it reads from the chair as "I
cannot put the opponent in jail". Worth revisiting as a design question; it is
not a fault.

## 6. Live queue

Items 1-3 are done - see `55e0b9e` and the commit that added this line.

1. ~~Replace the trellis with a balcony drop.~~ **Done.** Both upstairs rooms
   have a one-way window onto the garden instead; no structure. Cutting the
   trellis outright would have left one staircase as the only vertical link, and
   a staircase is a single edge in the route graph - so with one of them the
   vault has exactly one way in however the upper floor is arranged. Upstairs
   vault, two ways in, one stair: any two of the three. There are two flights
   now, at opposite ends, and the vault sits between them.
2. ~~Check whether the trellis stall survives.~~ **It did not.** 232 stalls
   became 69 and the cluster of 201 at that one point ceased to exist. Nothing
   was debugged.
3. ~~Re-measure before the amortised flooding.~~ **Not needed.** p99 113 -> 41 ms
   and 80 -> 18 over-budget ticks in 600, from the smaller world alone.
3b. ~~Routing floods most of the house.~~ **Halved.** The search runs from both
   ends now, meeting in the middle: 59% of the nodes settled, p99 93 -> 73 ms,
   over-budget ticks 58 -> 44. Note that the ROUTES CHANGED - same length,
   different tie-breaks on 2,908 of 6,599 pairs - which is documented in
   `NavGraph._trace` and means a replay saved before it will not reproduce.

3c. ~~Routing costs more than a tick.~~ **Cut by a third.** 38 -> 25 ms a
   route, p99 68 -> 57 ms, from two changes that turned out to be the only ones
   that mattered: the surface now keeps its adjacency FLAT (the baked format was
   already compressed-sparse-row; it was being unpacked into a Dictionary on
   load and re-packed on save), and the router's queues are PackedInt32Array
   rather than Array[int].

   **The profile is the useful part, because it contradicts the obvious
   guesses.** Of a 38 ms route: full-graph allocations 0.02 ms, smoothing 0.9,
   neighbour lookups 11, and the rest the loop body. The Dictionary lookup was
   the single biggest line - `Dictionary.get` with a default allocates a fresh
   array on every miss, once per settled node.

   **Three cleverer things were built, measured and thrown away**, all recorded
   in `NavGraph` so they are not rebuilt:
   - accessor methods over the flat arrays - 48 ms, WORSE than the dictionary,
     because three GDScript dispatches beat one hash lookup;
   - A* with a bucketed frontier - halves the nodes settled, 10,354 -> 5,414,
     and is still slower at 35.6 ms because rescanning lanes costs more than the
     expansions it saves. An admissible heuristic does exist: horizontal cell
     distance, floored, zero overestimates over 380 pairs. Adding height
     overestimates by 50% - a stair gains height WHILE moving horizontally;
   - stopping the distance flood once it reaches a bot's candidates - 30%
     SLOWER, because the errands are scattered across both houses and reaching
     them all means visiting 15,839 of 15,987 stances anyway.

   At this size the per-node BOOKKEEPING is the cost, not the node count.
   Anything clever has to be nearly free to be worth it.

   **What is left.** A route is ~25 ms against a 33 ms tick and a bot decision
   also floods distances (~14 ms), so a tick doing both still goes over - 43-47
   of 600. The remaining fix is not a faster search: it is not doing both in one
   tick, by spreading a decision across several. That is a scheduling change to
   BotDirector, not an algorithm change to NavGraph.
4. **Bot route variety** - it takes the same approach every time, which is
   solvable after two rounds. **Attempted twice, reverted twice. Do not try a
   third time without a different idea.**

   The mechanism works and is three lines: the search settles ties by neighbour
   visiting order, so rotating that order per bot varies the line without
   lengthening it. Measured 1 -> 3 distinct approaches into each cash room from
   eight seats, every seat perfectly repeatable, routes staying 19-21 legs.

   It costs more than it is worth. The rotation lands in the innermost loop of
   the router - once per settled node, twelve thousand times per route - and
   every way of writing it made the tick worse than not having it:

   | version | p99 | worst |
   |---|---|---|
   | no variety (current) | 73-78 ms | ~120 ms |
   | rotated copy per node | 130 ms | 748 ms |
   | index with a modulo | 86 ms | 129 ms |
   | branch hoisted, two loops | 117 ms | 198 ms |

   Against a 33 ms budget, where the baseline is already over 44 ticks in 600.
   The next real move is making routing cheap enough that this is affordable -
   see below - not another way to write the rotation.
5. **Encounter to seizure conversion.** Held until a human has played: 14% may
   be a bot deficiency rather than a game problem, and tuning the game to fix the
   bots would make it worse for people.

Also closed: the two houses were measurably different despite one being an exact
turn of the other. The world was not a whole number of sampling cells, so the
turned copy landed at a different phase against the grid - 4,072 stances against
3,986, different route counts, and raiding at 89% against 28%. Fixed by sizing
the world in whole cells; the builder now refuses to write a scene that breaks
it. See `WORLD_AUTHORING.md` §11.

## 6a. The storey is 360, and the house is proportional

Raised from 300 (ten steps) to **360 (twelve)**, before the Blender work, because
it is a constant here and would be a re-model there.

**It was too MEAN, not too tall.** A 1000-unit room with the old 260 clear
height was 3.85 wide for every 1 tall, against about 1.67 for a real room - the
house read as a wide flat box. No horizontal change was needed or made: raising
the storey moved the room to 3.12 and the whole house to 2.90 : 1, which is
still generously wide for the camera (§8) without being a corridor with a lid.

**It also fixed the verbs.** 320 of clear height over a 180 body is 140 of
headroom, and landing on a `vault_height` ledge needs 300 of clear. The indoor
jump went 71 -> 128 and now gets on top of waist-high things; it could not
before, and the jump's ceiling cap still holds at zero clipped ticks.

**Three numbers stopped being hand-written.** `UPPER` and `ROOF` were hardcoded
at 600/900 while `STOREY` said 300 - three values agreeing by hand, which is the
drift that let `carry_speed_scale` sit wrong for months. They derive now, as does
`FLIGHT_STEPS` (was a literal `10` in the loop and a `RUN * 10.0` constant).

**Checked, because the point was to break nothing:** both houses still bake to
4481 stances each (difference 0, so the turned copy still samples in phase);
raid distances 21 vs 20 legs; escape drop 360 against a max_drop of 480, so the
one-way balcony still works; the flight is 696 of a 1000 room, leaving 304 of
floor; lot, margins and corridor untouched; `sim/` and tuning have zero diff.
458 tests, bot_match DETERMINISTIC with a winner, netcode digests identical.

**One real cost.** Over-budget ticks went 43-47 -> 67-71 of 600, measured three
times. p99 is about the same (57 -> 65 ms) but more ticks cross the line: taller
storeys mean longer flights and more stances per column, so bots decide more
often. Routing is the same speed per route. This does not change the conclusion
in §6b - the fix is scheduling, not a faster search - but the pressure is higher
than it was.

## 6b. What is actually left before Blender

Asked directly, and answered by measuring rather than from memory.

**Nothing BLOCKS the art work.** The export convention WORLD_AUTHORING §6
specifies is already implemented in `blockout_baker.gd` - it reads `blocker_*`,
`shell`, `spawn_<team>_<slot>`, `cash_<team>_<index>` and zone nodes out of any
scene, and nothing in it cares whether that scene came from Godot or a `.glb`.
Swapping the source changes where the boxes come from and nothing about what
they mean. Art and collision stay separate by naming, so scenery can never
silently change what a player walks through.

**One thing gets WORSE after art, not better, and is the strongest candidate
for doing first.** Routing: p99 68 ms against a 33 ms budget, 48 of 600 ticks
over, one re-route settling 12,052 of 15,987 stances at 35 ms. The frame has no
art in it yet. Every prop, light and material lands on top of that, and a
stutter that is currently "the bots think too hard" becomes indistinguishable
from "the art is too heavy" once both are true. Diagnosing it now is cheap;
diagnosing it through a renderer is not.

**Three things that are genuinely optional first**, in the order I would do
them:

1. Make routing affordable (above). Unblocks queue item 4 as a side effect.
2. Draw the verbs. Jump and throw are simulation-correct and read as nothing -
   a thrown bundle moves, but no arc is legible. Cheap, and it makes a
   playtest worth more.
3. The scale rule in WORLD_AUTHORING §8 - rooms 7-8 m, doorways 2.4 m, "when
   the camera and realism disagree, the camera wins". The current house already
   obeys it. Worth re-reading before modelling, because rebuilding a modelled
   house costs considerably more than rebuilding a blockout did.

## 6c. Teams are built but not switched on

`team_size` is 1 in the grey box and the whole roster machinery already handles
more: `SimWorld.populate_roster` spawns a body per slot, `TeamDef` carries a
spawn point for each, and the house bakes THREE spawns per team. 3v3 is one
line, not a feature.

Tried it, to see rather than guess. It is dramatically livelier - 47 pick-ups
against 12, 24 seizures against 6, 53 encounters against 12 - and still
deterministic. It also ran the full six minutes without a winner, where 1v1
finishes in four, because more bodies means more rescues and cash changing
hands faster than either side can bank it.

So it is a TUNING job, not a plumbing one: round length, capture sentence and
cash-per-team all assume a single raider. Left at 1 until somebody has played
it, since those numbers are a feel judgement and the bots cannot make it.

## 7. Two things still owed to the user

**A real two-machine playtest.** Everything network has been proven headless and
in two windows on one desk. Nobody has played this over a wire with a friend.
`PLAYTEST.md` covers Tailscale and the build; ENet cannot traverse home routers,
which is what the Steam backend eventually fixes.

**A house that is fun for ten seconds.** That has not happened yet, and it is the
only measure that matters. Everything in §2 is scaffolding for it.
