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
