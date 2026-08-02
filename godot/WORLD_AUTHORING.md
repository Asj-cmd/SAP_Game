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
| No zone overlap without distinct `priority` | Ambiguous "which room am I in" |
| No walkable point inside a blocker | Spawning or landing inside a wall |
| Min gap between blockers > max per-tick displacement | Tunnelling headroom |
| Every spawn, jail and cash point is on walkable ground | Falling out of the map |

Reachability is a flood fill over the walkable volume at actor size — the same
traversal the bots will want later, so the work is not spent twice.

The validator runs in the headless runner and is a hard gate: **content that
fails does not load.** A broken house must be impossible to play, not something
discovered mid-match.

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

**Every route must be walkable, because there is no jump.** An edge exists
between two standing places only when the height difference is within
`TuningDef.step_up_height`. A drop larger than that is not an edge *in either
direction* — deliberately, because a ledge you can fall off but not climb back
onto is a one-way trip, and a route that only works downhill is how a level ends
up with a basement nobody can leave. If a room is below ground, it needs stairs
or a ramp whose individual steps are within the allowance. A hole in the floor
is not an entrance.

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
