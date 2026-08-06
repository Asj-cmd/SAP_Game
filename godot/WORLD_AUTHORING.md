# World authoring plan

How a real multi-room house becomes something the simulation can run, without
gaps, leaks, or unreachable rooms. Written before the world exists, because
every failure mode below is cheap to prevent and expensive to retrofit.

Companion to `ARCHITECTURE.md`. Applies from Phase 3 (world) onward.

---

## 1. The placeholder that must not survive

`MovementSystem._is_passable()` currently asks one question: *is the destination
inside some zone?* Everything outside the union of zones is out of bounds.

That is correct for an open plane and wrong for a building. Two adjacent zones
share a face, and that entire face is walkable — so an actor crosses between
bedroom and hallway anywhere along the wall, not only at the doorway. There is
nothing solid in the world, because solidity was never represented.

The fix is to separate two concerns the placeholder conflates.

## 2. Zones mean; blockers block

**A zone answers "where am I, and what rules apply?"** Ownership, role, safety,
scoring. It is semantic. It may be generous and approximate — a zone AABB can
comfortably contain its room without tracing its walls.

**A blocker answers "can I physically be here?"** It is geometric and has no
rules attached. A doorway is not a thing; it is an absence of blocker.

Neither derives from the other. A wall may be moved without changing what a room
*means*; a room may change owner without moving a wall. Conflating them is what
makes level edits break gameplay in most codebases, and it is the single most
important boundary in this document.

Consequences worth stating plainly:

- Zones may overlap freely — that is what `ZoneDef.priority` is for.
- Zones no longer define the playable area. Blockers and the world bounds do.
- An actor is always in exactly one zone, or none (which is legal — a corridor
  nobody bothered to zone still has walls and is still walkable).

## 3. Blocker representation

**Axis-aligned boxes, authored as content.** A suburban house is almost entirely
right angles, and AABB tests are exactly representable in float32, which keeps
movement inside the §6 arithmetic subset.

```
WorldCollisionDef (Resource)
  blockers: Array[AABB]     # walls, closed doors, furniture that stops you
  bounds:   AABB            # the outer shell; outside is out of bounds
```

Non-axis-aligned geometry (a diagonal staircase wall, a slanted attic ceiling) is
a deliberate future extension — oriented boxes, or a convex-hull list. It is not
needed for the first house and must not be added speculatively.

A door that can open and close is a blocker the simulation may toggle. That is
also how a locked door becomes a rule rather than a hole in the map.

## 4. Swept movement, not point tests

The current test samples the destination point only. At 30 ticks per second a
sprinting actor covers a real distance per tick, and a slide covers more — enough
to pass straight through a thin wall in a single step, because neither the start
nor the end point was inside it.

Movement must test the **segment** from current position to destination against
each blocker, not the endpoint. Segment-versus-AABB is cheap and exact, and it
removes tunnelling as a class of bug rather than as a tuning problem.

Axis-separated sliding stays exactly as it is. It is what makes a diagonal press
near a doorway slip through the gap instead of sticking, and it is the difference
between doorways feeling generous and feeling broken.

## 5. Floors, gravity, and multiple storeys

Movement is currently free in all three axes: an actor floats wherever intent
points. A flat plane hides this; a two-storey house does not.

The simulation needs a **minimal kinematic character controller** — not a physics
engine, and not a contradiction of §6. Physics stays out of the rules; standing
on a floor is a rule.

- Constant downward acceleration, integrated at the fixed timestep.
- Ground resolved against the same blocker set (floors are blockers).
- A step-up allowance so stairs and thresholds do not require a jump.
- Jump as an impulse, if and when the jump verb lands.

Deterministic, headless, and identical on server and client — which is exactly
what `MovementSystem` already guarantees for horizontal movement.

## 6. Authoring pipeline: art and collision are separate

The house is modelled in Blender. Collision must **not** be derived from the art
mesh — auto-generated collision inherits every modelling artefact, and re-exporting
a decorative change silently alters gameplay.

Author collision explicitly, by convention, in the same Blender file:

- Empties or boxes named `zone_<id>` → exported to `ZoneDef` bounds.
- Boxes named `blocker_*` → exported to `WorldCollisionDef.blockers`.
- Empties named `spawn_<team>_<slot>`, `jail_<team>`, `cash_<team>` → placement.

A headless export script reads those objects and writes `.tres` content. Art
changes freely; gameplay geometry changes only when someone deliberately moves a
box named `blocker_`.

This also keeps the §4 promise intact: a new room is content, not code.

## 7. The validator — the actual answer to "no imperfections"

Correctness here cannot rest on care, because the failure modes are invisible by
inspection. A headless validator runs over authored content and fails loudly.

It must catch at least:

| Check | Failure it prevents |
|---|---|
| Blocker shell is closed | Walking out of the world through a seam |
| No blocker overlaps a doorway gap | A door that looks open and is not |
| Every doorway gap ≥ actor width + margin | A door nobody can fit through |
| Every zone reachable from every spawn | A room the match can never use |
| Every cash room and jail reachable | An unwinnable or unescapable round |
| Every role-bearing zone **escapable** | A room you fall into and never leave |
| Min cut from outdoors to every role-bearing zone ≥ 2 | One door, one defender, round over |
| No zone overlap without distinct `priority` | Ambiguous "which room am I in" |
| No walkable point inside a blocker | Spawning or landing inside a wall |
| Min gap between blockers > max per-tick displacement | Tunnelling headroom |
| Every spawn, jail and cash point is on walkable ground | Falling out of the map |

Reachability is a flood fill over the walkable volume at actor size — the same
traversal the bots will want later, so the work is not spent twice.

The validator runs in the headless runner and is a hard gate: **content that
fails does not load.** A broken house must be impossible to play, not something
discovered mid-match.

Two of those rows are worth stating precisely, because both were got wrong once.

**Escapability is a separate question from reachability**, and only became one
when edges turned directed (§12). A drop is one-way. A room whose only exit is
the way you fell in is perfectly reachable and completely broken, so the gate
floods *backwards* from a spawn as well as forwards: every role-bearing zone must
be somewhere you can get to and somewhere you can get out of.

**Ways into a room are counted as a min cut from outdoors** — Menger read
backwards: the fewest doorways you would have to close to seal a room off *is*
the number of independent ways into it. Max-flow, on a graph of a few dozen
regions, so the cost does not register.

Below `routes_required` (2) the level does not load. Below `routes_wanted` (3)
the bake prints a note and carries on. Both are `TuningDef` values, because three
is an aspiration and failing everything below it would refuse every level anyone
has yet drawn, including the one being played.

Three details make the count mean what it should:

- **The unit of capacity is an aperture, not a room and not a cell.** A doorway
  is what a defender holds. Cells are far too fine — a door is forty cells wide,
  so any cell-level cut passes everything. Room adjacency is too coarse the other
  way — two separate front doors into one hall are two ways in, and counting
  rooms calls them one. An aperture is a connected stretch of the boundary
  between two regions.
- **Outdoors is the source, and a source is never cut.** This is what stops the
  garden between two houses reporting as a chokepoint. It is a cut vertex by
  construction, so a check that flags it is unsatisfiable rather than the map
  being bad — it could only ever be answered by inventing a second garden.
- **Unzoned space is a region like any other.** Door thresholds and side passages
  usually belong to no room, and leaving them out silently merges the rooms they
  separate.
- **Outdoors is `ZoneDef.outdoor`, not neutrality.** They look like the same
  thing and they are not, and conflating them cost the game its captures. A
  seizure is only legal on ground your team owns, so tying "outdoors" to
  neutrality forced every garden to be unowned — and an unowned garden is
  where the two sides meet and can do nothing about each other. Measured: 18
  encounters in a six-minute bot match, every one outdoors, not one where a
  capture was legal, and zero captures. Ownership says who may seize; `outdoor`
  says what the gate counts ways in from. See §13.

**Open plan scores low, and that is the answer rather than a bug.** A wide
knocked-through opening is one connected stretch of boundary, so it is one
aperture and one route — however wide it is. Knocking two rooms together does
not give the far one a second way in, because you still have to come through
the adjoining room to use it. If a downstairs reports 1, look for a single
opening before looking for a defect.

**A level with no neutral space fails closed.** There is no outdoors to count
from, so the row cannot answer — and silently not checking is the same as
passing. Content that is genuinely a rig for one rule says so on itself
(`WorldCollisionDef.is_fixture`) and is exempted by name; anything else is
refused with *cannot validate routes: no outdoor source*. The flag is
declared by hand and never written by the baker, so a level cannot acquire
the exemption by accident.

This replaced an articulation-point search, which is a weaker question wearing
the same clothes: *is there one room whose removal cuts this off* answers **no**
for a garage with a single door onto the garden, because there is no third room
to remove. One approach, one defender, and the check says nothing. Min cut
subsumes the articulation case and has no such blind spot.
`tests/content_validator_test.gd` pins the garage, one/two/three routes, and that
the floor is a content value rather than a constant.

Both rows found real defects the hour they existed. The shipped grey box had one
way into every room.

## 8. Order of work

1. `WorldCollisionDef` + swept segment tests, proven on a trivial two-room box.
2. The validator, with the two-room box as its first passing fixture.
3. Kinematic ground and step-up, proven on a two-storey box with a staircase.
4. The Blender export convention and script.
5. The real house — authored against a validator that already works.

The validator comes second deliberately. Building it after the real house means
debugging the tool and the content simultaneously, with no known-good fixture to
calibrate against.

## 9. Presentation restates nothing

Tuned numbers live in content and are read from it at display time. Presentation
may show a safe room's remaining shelter, but it must take that value from the
`ZoneDef` — never from a constant, and never from prose.

The concrete case is the safe-room variant. Today, switching between

- **A** — `safe_duration_seconds = -1`, `safe_ends_on_pickup = true`
- **B** — `safe_duration_seconds = 5`, `safe_ends_on_pickup = false`

is one `.tres` edit and nothing else, which is exactly what makes it settleable
by playing rather than by arguing. A tutorial hint reading "you are safe for 5
seconds", a HUD ring with a hardcoded 5-second sweep, or an achievement string
naming the rule would each quietly convert that into a code change — and the
variant stops being a question play can answer.

The test is mechanical: **grep the number.** If a value authored in content
appears anywhere outside it, that is the defect, whatever the value happens to
be at the time.

This generalises past safe rooms to every tuned quantity — round length, capture
duration, carry speed. It is written here rather than left to habit because the
failure is invisible until someone changes the content and the UI keeps
confidently stating the old value.

## 10. Room dimensions come from the camera, not from realism

**A real-scale domestic interior cannot host a third-person camera.** This is a
constraint, not a preference, and it decides the floor plan before anything else
does.

A third-person camera sits roughly 3.5 m behind the character. A real bedroom is
3 m across. The camera is therefore permanently inside a wall, and a spring arm
"fixes" that by compressing to nothing — which is a first-person view with extra
steps, and no view of the character the player is supposed to be reading.

So rooms are sized from the arm outward:

| Quantity | Value | Why |
|---|---|---|
| Unit | 1 unit = 1 cm | Fixed by actor radius; everything else follows |
| Camera arm | ~3.5 m | Standard third-person standoff |
| Room | 7–8 m | Several arm-lengths, so the camera is in the room |
| Doorway | ~2.4 m | Wide enough to run through mid-chase, not to sidle through |
| Wall height | ~2.8 m | Tall enough to read as a room, cheap to raise |

The first blockout was built at domestic scale — 2.2 m rooms — and was unusable
the moment a real camera was attached. Rebuilding it cost an afternoon. Rebuilding
a modelled house would cost considerably more, which is why this is written down
before the Blender work starts (§6, §8 step 4).

**The rule: when the camera and realism disagree, the camera wins.** A house that
reads as slightly too large is invisible to players. A house the camera cannot fit
in is unplayable, and no amount of art fixes it.

Two consequences worth stating:

- **Furniture and props scale with the room, not with reality.** A sofa in a 7 m
  room is a 3 m sofa. Nobody notices; everybody notices a camera in a wall.
- **The validator's fill resolution is tied to level size and to body size.**
  Rescaling a level changes the cell size, so a doorway that was several cells
  wide can quietly become one. Re-run the gate after any rescale — the rescale
  above needed exactly that fix. See §11 for the resolution rule itself.


## 11. What the level must be walkable *on*

Reachability is no longer "is there space for a body here". It is **"can a body
stand here, and step from here to there"** — a walkable-surface fill
(`WalkableSurface`), shared by the load gate and by the bots. One graph, so the
gate cannot certify a route the bots are unable to follow, and the bots cannot
find one the gate never checked.

This changes what content has to provide.

**Up is not down.** An edge exists upward only within `TuningDef.step_up_height`,
and downward as far as `max_drop_height`, so a ledge is a route one way and a
wall the other. That asymmetry is deliberate, and it is what the escapability
row in §7 exists to police: a room whose only exit is the way you fell into it is
perfectly reachable and completely broken. If a room is below ground and meant
to be left, it needs stairs or a ramp whose individual steps are within the step
allowance. A hole in the floor is an entrance and not an exit.

**Do not butt a zone flush against a drop.** A standing place is a body-width
thing, so the outermost places you can stand on a ledge sit slightly *past* its
edge — up to a cell beyond, out over the fall. A zone whose boundary is the drop
swallows those places, and the room below then contains stances that are
actually on the balcony above it. Everything downstream reads wrong: the room
reports as escapable because part of it never fell, and its ways-in count picks
up apertures belonging to the floor above. **Start the lower zone a body clear
of the edge.** This bites the moment a house has balconies, and it was found
the hard way — the first ledge fixture looked correct and the check quietly
agreed with it.

**Air is not a route.** The old fill was volumetric and connected cells
vertically, so it would happily walk over the top of a wall through the open air
above it and declare two sealed houses connected. The current fill requires
something solid underfoot. A wall taller than a step now separates what it looks
like it separates.

**Gaps must be wider than the grid, not merely wider than a body.** A doorway
registers only where a sample column lands inside it, so the cell size is the
finer of two bounds: one body across (`CELL_RADII`), and 1/64 of the level's
longest axis (`SHELL_DIVISIONS`). Neither alone is sufficient and no sampled fill
can guarantee finding an arbitrarily tight gap. Missing one reports *unreachable*,
which is the safe direction — a false alarm costs a look, a missed gap ships a
room nobody can enter. In practice: **do not author a doorway at the minimum
width a body fits through.** Leave it a body wider, which §10 wants anyway.

**A ledge needs headroom to be found at all.** A standing place is detected where
there is a free cell above it, so a shelf with less than a step-height of
clearance is invisible to the fill. That is correct — it is not somewhere to walk
— but it means a mezzanine tucked right under a ceiling will not register as
floor. Give walkable upper storeys real headroom.

**A stair costs a room, and the run per tread is set by the grid.** A tread is
only standable where a sample column lands on it, and the next tread up — grown
by the body radius — eats 20 off the front of this one. So a tread offers
`run - 20` of standable depth, and that has to be at least one cell (40) or some
tread in the flight gets no sample at all. **Run 64 or more.** Eleven treads of
64 is 704, which is most of a 755 room: a staircase IS a room, and the house is
laid out with a stair bay rather than stairs tucked into a corner.

**Open the floor above a flight one tread earlier than the clear height says.**
A body does not stand at its rest height in the grid — it occupies the layer
whose CENTRE is the first one above that height, and the layer is as tall as a
step, so the rounding is worth a whole tread. Sizing the stairwell opening from
the clear height left exactly one tread of each flight buried in the slab.
`tools/build_house.gd:_covered_from` works it out the way the fill will see it.

**A mirrored or turned level is only symmetric if the world is a whole number
of cells across.** The fill samples at cell centres, so a turn `x' = W - x`
sends a sampled point to another sampled point only when `W` is a multiple of
the cell. Otherwise the copy lands at a different PHASE against the grid and
identical geometry produces a different surface.

It did, and it was invisible: every blocker in the house had an exact rotated
partner, and the two copies still came out at 4,072 stances against 3,986,
with different route counts for the same rooms - hall 3 against 2, landing 3
against 2. In play the two teams raided at 89% and 28%. The world was 3185 x
3430; at 3200 x 3440 the counts match exactly and the raiding evened to 35%
and 38%.

So: pick the world size as a multiple of the cell FIRST and let the margins
fall out of it. `tools/build_house.gd` refuses to write a scene that breaks
this, because a silently asymmetric level is a balance bug nobody can see.

**The surface is baked, not built.** It is a pure function of static geometry
and a body size, so the baker computes it and stores it in the level `.tres`
(`WalkableSurfaceDef`); loading reads two flat arrays. For the grey-box house
that took load-time cost from ~800 ms to ~68 ms, and the saving grows with the
level rather than shrinking.

Two consequences for authoring:

- **Re-bake after moving anything solid.** A stored surface records a
  fingerprint of the geometry and body it was computed from. A level whose
  fingerprint no longer matches is *rebuilt at load with a warning* rather than
  trusted — correct, but it silently costs the time baking was meant to save, so
  a warning in the log means "you forgot to re-bake".
- **A bake is only valid for one body size.** `actor_radius` and
  `step_up_height` are part of the fingerprint, because they decide what counts
  as standable and what counts as a step. Changing either invalidates every
  baked level, by design.

## 12. The threshold set

Five numbers describe every height in the game. Everything built anywhere is
built to one of them.

| Threshold | Value | Verb | Reads as |
|---|---|---|---|
| `step_up_height` | 30 | none — you walk over it | a sill, a stair tread, a kerb |
| `vault_height` | 120 | vault | a counter, a windowsill, a low wall, a railing |
| `crouch_gap` | 130 | crouch | under a counter, a serving hatch, a crawl space |
| `max_drop_height` | 480 | drop | a first-floor window, a balcony, a stairwell |
| storey | 330 | stairs | one floor to the next |

**A storey is a whole number of steps, and that is not a rounding.** It was 320,
which is eleven treads of 29.09, and eleven treads of 29.09 do not make a
staircase. The fill quantises height at `layer_height` — 30, the step allowance —
so a tread is only found when a layer centre falls between its top and the next
tread's. A 29.09 window in a 30 grid misses sometimes, and it missed two treads
out of twenty-two: two staircases with a step nobody could climb, in a level
that otherwise passed every check. At exactly 30 every window contains exactly
one centre, always. **330 = 11 × 30.**

**No exceptions, ever.** Not one ledge at 140 because it looked better there.

This is the load-bearing rule of the whole world, and it is not about tidiness.
The strategy space this game is trying to produce comes from *verbs × space*:
a small set of general verbs, applied to a layout rich enough that players
invent methods nobody authored. That only works while players TRUST the
thresholds — while a thing that looks vaultable is vaultable, everywhere,
without having to be tested first.

One hand-placed exception destroys that. A player who is caught out once stops
trusting the rule, and a player who does not trust the rule stops improvising
and starts checking. The emergent play depends entirely on the trust, so the
uniformity is worth more than any individual piece of geometry it costs
(ARCHITECTURE.md §9).

**Sizing comes before the verbs.** Crouch, vault, slide, drop and throw are not
built. The geometry is built for them now anyway: low gaps a crouching body
fits, ledges at vault height, drops that are survivable, and window openings
and sightlines wide enough for a carriable to arc between two players.
Retrofitting those dimensions into a finished house is the expensive version of
this, and the reason the blockout is dimensioned before anything is modelled.

**A consequence for the fill.** A drop is a ONE-WAY route: you can leave a
balcony and you cannot climb back onto it. That is why WalkableSurface carries
directed edges and why the gate checks reachable *and* escapable — see §11 and
§13.

## 13. Encounters are a layout metric too

Ways-in stops a room being campable. It says nothing about whether the two teams
ever meet, and a map optimised for one and blind to the other is how the house
arrived at **three ways into all eighteen rooms and zero captures in six
minutes**. The core interaction simply was not happening.

`tools/bot_match.gd` now reports it:

```
encounters  28 within reach, 18 of them where a seizure was legal, 28 within sight
raiding     team_b 38%, team_a 43% of the match on enemy ground
encounters  10 places; the worst 4 hold 19 of 28
```

Three numbers, and the split between them is what makes it a diagnosis rather
than a complaint:

- **Encounters within reach** — opponents close enough that seizing was
  physically available. Edge-triggered with hysteresis, so a five-second standoff
  is one encounter, not a hundred ticks of one.
- **How many were legal** — both bodies in one room, owned by one of them, not a
  pen: the same conditions `CaptureSystem` enforces. The gap between this and the
  previous number is opportunities the *rules* refused, not ones the bots missed.
- **Raiding** — share of the match each side spends on enemy ground. Near zero
  means the teams are not crossing at all and the encounter count says nothing
  about the layout; healthy means they cross, and a low encounter count is then a
  real layout result.

**What it found the first time it ran, which was not what anyone predicted.** The
plausible story was that min-cut 3 had spread the houses apart and compartmented
them until the two teams never met. The measurement said otherwise: they met 18
times. Every single one was outdoors, on neutral ground, where a seizure is
illegal by rule. Not a distance problem and not a routing problem — the teams
were meeting exclusively in the one place the game refuses to let anything
happen.

Making the ground round each house belong to it turned 0 legal encounters into
18, 0 seizures into 3, raiding from 8% into 40%, and a match that ran out of
clock into one that was won. No geometry moved.

**Read them together or not at all.** Ways-in alone builds a house nobody can
camp and nobody fights in. Encounters alone builds a corridor.
