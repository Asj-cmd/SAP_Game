# The house — layout proposal

For review before anything is modelled. WORLD_AUTHORING.md §8 steps 4–5.

The current blockout is deliberately minimal: four rooms a side, one floor, laid
flat. It existed to answer "does the camera fit" and it did. **It is not the
house scaled up** — a bigger version of it would be a bigger version of a
diagram.

What follows is dense and vertical instead: a smaller footprint, three floors,
and more ways between them than there are rooms.

---

## 1. What the engineering already decided

These are not preferences. They fall out of things already built and measured.

| Constraint | Value | Where from |
|---|---|---|
| Room, minimum | ~755 u (7.5 m) | Camera arm is 350 u; below this it lives in a wall (§10) |
| Doorway | 240 u (2.4 m) | Run through mid-chase, not sidle through (§10) |
| Storey height | 330 u | 11 × the step. A storey must be a whole number of steps (§12) |
| Step, maximum | 30 u | `TuningDef.step_up_height`, and the fill's edge rule (§11) |
| Body | 40 u across | `actor_radius` 20; doorways are measured against it |

**A staircase costs a whole room.** 330 u of climb at 30 u a step is eleven
treads, and a tread needs 64 u of run, not 40: the next tread up, grown by the
body radius, eats 20 off the front of this one, so only `run - 20` is standable
and that has to clear a 40 u sample cell. Eleven × 64 = **704**, against a 755 u
room. So a stairwell IS a room and should be worth fighting in — and a second
staircase costs a second room, which is why the built house has one stair bay
and buys its remaining connectivity with doorways and drops instead (§8).

~~**Every route must work in both directions.**~~ *Superseded — edges are
directed now (WORLD_AUTHORING §12). A drop you cannot climb back up is a route,
and the gate asks reachable* and *escapable rather than merely connected. §5
below is the argument that led here; it is kept for the reasoning, not the
conclusion.*

---

## 2. Footprint

Two houses, mirrored, with a shared garden. Per house, roughly 2400 × 2400 u —
about a third of the current sprawl, three times the height.

```
        UPPER (y 640–960)              GROUND (y 320–640)           BASEMENT (y 0–320)

  ┌────────┬─────────┬───────┐    ┌────────┬────────┬───────┐   ┌───────┬────────┬──────┐
  │ BED    │ LANDING │ STUDY │    │ KITCHEN│  HALL  │ LIVING│   │ COAL  │ CELLAR │ JAIL │
  │        │  ╱╲     │ ▓VAULT│    │        │  ╱╲    │       │   │ STORE │ STAIR  │      │
  │  ┌─────┤ stair   │       │    │   ┌────┤ stair  │       │   │       │  ╱╲    │      │
  │  │BATH │         │       │    │   │UTIL│        │       │   │       │        │      │
  └──┴─────┴─────────┴───────┘    └───┴────┴────────┴───────┘   └───────┴────────┴──────┘
        │                              │                             │
     BALCONY ──── trellis ──── GARDEN ─┴─ porch ── crawl ────────────┘
```

The vault is **upstairs**, not on the ground floor. That is the single biggest
change: it makes the climb part of the robbery, gives the defender a choke worth
holding, and means a carrier has to come *down* with the money.

The jail stays in the basement, two floors from the vault. A rescue is now a
journey.

---

## 3. Three ways into everything

The design rule is that no important room has a single approach. Anything with
one door is a room where a defender stands still and the round stops.

**Into the vault (upper study)**
1. Main stair from the hall, through the landing
2. Back stair from the kitchen, through the landing — a second entrance to the
   same landing, so holding the landing holds both
3. Trellis from the garden → balcony → bedroom → landing
4. Loft hatch over the garage → bedroom (a fourth, and the slowest)

**Into the jail (basement)**
1. Cellar stair from the hall
2. Coal hatch from the side of the house, sloped, straight into the coal store
3. Crawl space under the porch → utility room → cellar stair
4. Laundry chute from the upper landing — **one-way, see §5**

**Into the house at all**
1. Front door, off the garden
2. Back door, through the kitchen
3. Garage side door, into the utility room
4. Bedroom window from the trellis (skips the ground floor entirely)

Note that these are not four *independent* routes — several converge on the
landing or the utility room. That is deliberate: a choke should exist, it just
should not be the only thing.

---

## 4. Named in domestic terms

Traversal reads as house, not as level. Each of these is a real feature that
happens to be a route:

- **trellis** — garden to balcony. A climb, so it needs treatable steps: a
  trellis is a ladder, and a ladder is stairs with a bad aspect ratio.
- **coal hatch** — a sloped chute from the side yard into the coal store. Slope,
  not drop, so it works both ways.
- **under the porch** — a crawl space. Low ceiling, full-height body: this must
  be a *duck-height corridor*, which the fill will only find if there is
  head-room for the body. See the question in §6.
- **laundry chute** — upper landing to basement. One-way by nature.
- **loft hatch** — over the garage, into the back bedroom.
- **dumbwaiter** — kitchen to study. Cargo only: a way to move *cash* between
  floors without moving a body. Possibly the most interesting one, because it
  separates the two things a raider currently has to do at once.

Deliberately not: vents, ducts, maintenance shafts, anything that reads as an
office building.

---

## 5. Two of these need engine work, and I would rather say so now

**The laundry chute is one-way, and the walkable surface has no such thing.**
Edges are symmetric by design, which is what lets reachability be a single flood
rather than a strong-connectivity search (§11). A chute is a drop you cannot
climb back up — exactly the shape the current rule refuses on purpose.

Supporting it needs: directed edges in `WalkableSurface`, and a validator that
checks every important zone is reachable *and escapable* rather than merely
connected. That is real work and it changes the gate's core claim.

**Options, in the order I would rank them:**
1. **Cut the chute.** Use the coal hatch and the crawl space; both are two-way.
   Costs one nice idea, costs nothing else.
2. **Build directed edges properly**, with the validator upgraded to
   strong connectivity. Right if one-way traversal is a mechanic we want more of
   — a fire escape, a drop from a window ledge, a slide.
3. **Make it cargo-only**, like the dumbwaiter: cash goes down the chute, bodies
   do not. No graph change at all, because nothing walks it.

I lean to **3**, which keeps the fiction and needs no new engine concept.

> **Overruled, and rightly: option 2.** Drop-from-height is a planned verb, so
> the graph should model it rather than route around it. Built. The vault
> upstairs depends on it — climb up slow and careful, drop out of a window fast
> and committed — and the escapability check it forced is the more correct gate.
> The dumbwaiter in §4 is cut: throw delivers the same value uniformly, and a
> dumbwaiter is the hand-placed special case §9 forbids.

**The dog door / crawl space assumes bodies come in sizes.** Everything is
measured against one `actor_radius`. A gap only a small character fits through
is not currently expressible, and would mean per-character radii through the
fill, the validator and the collision predicate. If characters really do differ
in size later, that is the change that has to land first.

---

## 6. Questions I want answered before modelling

1. **Vault upstairs — agreed?** It is the change most likely to alter how the
   game plays, and everything else in this layout is arranged around it.
2. **The chute: cut it, build directed edges, or make it cargo-only?**
3. **Is the dumbwaiter interesting or fiddly?** Moving cash without moving a
   body is a genuinely new verb, and new verbs deserve their own decision.
4. **Two staircases per house, or one plus the trellis?** Two is a lot of floor
   area. One makes the landing decisive, possibly too decisive.
5. **Do both houses have to mirror?** Mirrored is fair and cheap; asymmetric is
   more interesting and doubles the modelling and the balance argument.

### Answered

1. **Vault upstairs: yes** — conditional on a fast one-way descent existing.
   Climb up slow and careful, drop out of a window fast and committed.
2. **Directed edges, properly.** Not cargo-only. Drop-from-height is a planned
   verb, and the gate becomes reachable *and* escapable, which is the more
   correct question. Built — see WORLD_AUTHORING §7 and §12.
3. **Dumbwaiter: cut.** Throw delivers the same value uniformly. A dumbwaiter is
   the hand-placed special case §9 forbids.
4. **One staircase** — the count was never the problem. The second approach must
   bypass the landing entirely: trellis → balcony → bedroom → straight into the
   study.
5. **Mirrored.**

Governing principle for the whole phase: **a large strategy space from uniform
rules, not many features.** Ambiguity is verbs × space. One consistent set of
heights, learnable and identical everywhere; anything at vault height is
vaultable, with no exceptions — one hand-placed exception teaches players not to
trust the rule, and the emergent play depends entirely on that trust.

---

## 7. And one thing the validator should learn — BUILT

The rule in §3 — *three ways into everything* — is currently a rule nobody
checks. It should be a gate row, the same way the doorway width already is:

> Find the articulation points of the walkable graph. Any zone with a role that
> matters, whose only access is through a single cut, has one route into it and
> fails.

Cheap to compute on a graph we already build, and it turns a design intention
into something that cannot quietly rot when somebody moves a wall. I would build
this **before** the house rather than after — same reasoning that put the
validator before the level, and the measurement before the doorway fix.

**Built, and it bit immediately.** Not as articulation points: a doorway is six
cells wide, so no single node is ever a cut and a node-level test would have
passed every house ever built. It asks at room granularity, from outdoors, and
it is paired with the escapability check that directed edges made necessary.
Exact semantics in WORLD_AUTHORING §7.

The first thing it refused was the shipped grey box, which had **one way into
every room** — true since the day it was built and invisible until something
checked. The interim fix was a second internal doorway per house, turning the
four rooms into a ring (hall → living → vault → basement → hall) instead of a
chain. The jail's second approach was already there: the back door onto the
perimeter.

---

## 8. Built — and what the gate cost

`tools/build_house.gd` generates it; `game/blockout/house.tscn` is the output and
`content/levels/house.tres` the bake. The old four-room blockout is retired.

Every one of the eighteen rooms has **exactly three ways in**, and every one is
escapable. That is not a coincidence — the connectivity was solved as a flow
problem before any box was placed, and the shape is what three costs:

| Piece | Why it exists |
|---|---|
| A stair bay, a whole slot wide | A flight is 704 long. A staircase IS a room (§11). |
| Two outside staircases, at the back | Both end rooms upstairs need a way in that is not through the other one. |
| Two light wells | The basement's own entrances. One-way in: 330 down is a fall, 330 up is not a verb. |
| **Two** doorways at each end of the vault | The cheapest third route into the vault and the bedroom. Two doors in one wall are two apertures, and one defender cannot stand in both. |
| Laundry chute, trapdoor, airing cupboard | One-way drops between stacked rooms — the third way into the boiler, the jail and the living room. |

The vault is upstairs and the one-way descent it was made conditional on is its
window: 330 to the garden, out and committed, with no way back up.

Three ways in is expensive, and knowing exactly *what* it is expensive in is the
useful part. Without the second doorway trick the house needed a second
staircase; without the light wells the basement needed a third internal
connection it had no room for.

**Not built, deliberately.** No dumbwaiter (cut in §6). No back stair — the pair
of vault doorways replaced it. Crouch, vault, slide, drop and throw are still
unbuilt verbs; the geometry is sized for them (§12) and nothing depends on them.
