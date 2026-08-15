# The house — layout specification

Two phases. **Phase 1 is the whole build order right now**; Phase 2 is written
down so it can be verified in advance, and built only once Phase 1 has been
played and is fun.

This replaces every previous version of this file. The eighteen-room generated
house, the three-room terrace, and the three-storey 1590 plan are all retired.
Their reasoning is in git history and in `PROJECT_MEMORY.md` §5.

---

## 0. Why two phases

This house has been rebuilt three times, and every rebuild had the same cause:
**too much was built before anything was played.** Eighteen rooms before ten
seconds of fun. Then a terrace with all its doors on one face. Then a plan whose
thirteen person-sized window openings made a suburban house read as a car park.

Phase 1 is a two-storey house that can be judged. Phase 2 adds a basement, and
carries the least-proven idea in the design — that rescue should mean going
*down*. Nobody has played that. It may be excellent or it may be a long walk, and
there is no way to know from a diagram.

**Nothing in Phase 1 reserves space for Phase 2.** Shaping a building around an
unplayed feature is the same mistake in miniature. When the basement arrives it
gets its own coordinates, written by someone who has played the floors above it.

---

# PHASE 1 — the two-storey house

## 1. What changed, and why

| Change | Reason |
|---|---|
| Rooms **750 → 1000** | A staircase is 640 long. In a 750 room it spans the whole depth; at 1000 it is a strip along one wall with two-thirds of the room still clear |
| **Straight flight hugging one wall** — no switchback | A switchback puts a landing in the middle of the room and occupies it as a solid block. A straight flight against a wall keeps the whole thing on the perimeter, where it obstructs nothing |
| Stair base sits **beside the doorway**, not facing it, with a **120 flat landing** before the first riser | You walk in, and have a moment of level floor, before turning to climb — rather than meeting a wall of steps head-on |
| Step run **64 → 48** | 64 run put the flight at 25°, closer to a ramp than a stair once it was actually played. 48 gives 32° while staying clear of the fill's 40-unit sampling cell |
| Stairwell void is the **whole footprint**, not a tuned partial cut | A partial cut (open only the top part of the run) looked right on paper and was visibly wrong in play — the ceiling didn't line up with where a climbing body's head actually was, and a player watched the character clip through solid floor. The stair owns its whole corner already; cutting all of it is simpler and cannot drift out of alignment with the geometry it is supposed to match |
| Passable openings **13 → 7** | Making every window person-sized is what produced the car park. Most windows are now small, high, and solid |
| **Two floors, not three** | See §0 |
| Jail is the **only ground room with no exterior opening** | Rescue must cost something. With the jail off the basement it would otherwise be the easiest thing in the game |

**Retracted:** the earlier principle that "nobody can ever be cornered". That is
what drove the porosity. Some rooms *should* be risky to enter — being cornered
occasionally is drama, not a design failure.

## 2. Dimensions

| Thing | Value | Why |
|---|---|---|
| Room | 1000 × 1000 | A 480 stair strip plus a 120 landing along one wall still leaves most of the room clear |
| Wall | 30 | |
| House footprint | **2090 square** | Two rooms plus three walls |
| Storey height | 300 | 260 clear over a 180 body |
| Doorway | 240 wide × 240 tall | Run through mid-chase, not sidle through |
| Step | 30 rise, 48 run | `TuningDef.step_up_height`; 48 keeps 8 units of slack over the fill's 40-unit sampling cell — enough that a column centre cannot miss a tread, the failure a shorter run risks |
| Stair per storey | 10 steps, **one straight flight** | No switchback, no mid-landing |
| Flat landing before the first step | **120** | So the flight does not start flush against the doorway you just walked through |
| Stair footprint | **480 × 280** flight + 120 landing = **600 × 280** total, against an exterior wall | All of it on the perimeter |
| Stairwell void above | **The whole footprint, base to top** | See below — deliberately not tuned tighter than the flight |

**Why straight beats switchback.** Both climb 300 in ten steps. The difference
is where the floor goes:

| | Footprint | Shape |
|---|---|---|
| Straight, against a wall | 600 × 280 | Strip on the perimeter |
| U switchback | 580 × 560 | Solid block, landing mid-room |
| L quarter-turn | 600 × 600 | Two walls, awkward inner pocket |

A switchback saves *length* and spends *area* — and it parks a landing in the
middle of the room, floating, which is exactly the defect visible in the first
build. At 750 rooms the length mattered enough to be worth it. At 1000 it does
not: a stair strip along one wall leaves most of the room completely clear.

This is how PUBG houses do it, and how most real houses do it. The switchback
was solving a problem the larger rooms had already solved.

**48 run, not 64.** The first straight-stair build kept the switchback's 64 run,
which put the flight at 25° — visibly too shallow, closer to a ramp than a
stair. 48 run gives 32°, a real staircase angle, while staying 8 units clear of
the 40-unit fill-sampling cell so a walkable stance is never at risk of landing
on a tread boundary. Below roughly 44 that margin gets uncomfortably thin; 48
was chosen with slack to spare rather than cut to the minimum.

**The stairwell void is the WHOLE footprint, not a tight cut.** An earlier
version cut only the top part of the run, on the theory that a climbing body's
head only needs the ceiling gone once it is tall enough to hit it. That
derivation was correct in principle and wrong in practice: the cut it produced
did not line up with where the body's head actually was, and a player watching
from outside saw the character clip through solid floor mid-climb. The stair
already owns its whole corner of the room — nothing else needs that ceiling —
so the fix is to stop being clever and cut the entire footprint, landing
included, base to top. A void larger than strictly necessary is invisible; one
that is wrong by even a small margin is not.

## 3. Quadrants and coordinates

House-local: origin at the south-west corner, **X east, Z north**.

```
   Z=2090  ┌────────────────┬────────────────┐
           │       NW       │       NE       │
           │   30 – 1030    │  1060 – 2060   │
   Z=1060  ├────────────────┼────────────────┤
   Z=1030  │       SW       │       SE       │
           │   30 – 1030    │  1060 – 2060   │
   Z=30    └────────────────┴────────────────┘
         X=30            1030  1060        2060
```

Internal walls run along **X 1030–1060** and **Z 1030–1060**. Diagonal quadrants
(NW/SE and NE/SW) touch only at a point and can never share a door.

### Vertical stack

| Quadrant | Ground | Upper |
|---|---|---|
| **SE** | Front Hall — front door (S), **main stair** | Landing A — head of main stair |
| **NE** | Kitchen — side door (E) | **MASTER BEDROOM — cash** |
| **NW** | Back Hall — back door (N), **second stair** | Landing B — head of second stair |
| **SW** | **JAIL** — no exterior opening | **STUDY — cash** |

Two things fall out of this and both are deliberate:

**The two staircases are diagonally opposite** (SE and NW), so going up one and
down the other means crossing the whole floor. That is the loop a chase needs.

**Neither staircase lands in a cash room.** They arrive in SE and NW; the cash is
in NE and SW. So you never step off a stair straight onto the money, and each
cash room opens onto *both* landings — two independent approaches, neither
holdable by one defender.

## 4. GROUND FLOOR — y 0 to 300

```
                      NORTH
        ┌────────────────┬────────────────┐
        │  ▲ back door   │                │
        │ ║ BACK HALL    │    KITCHEN     │
   WEST │ ║ stair up     │   side door ►  │ EAST
        │ ║ (west wall)  │                │
        ├────────────────┼────────────────┤
        │                │  FRONT HALL  ║ │
        │      JAIL      │  stair up    ║ │
        │  no way out    │  (east wall) ║ │
        │                │  ▼ front door  │
        └────────────────┴────────────────┘
                      SOUTH
```

**Front Hall** (SE) — the **front door** on the south face. **Main stair** runs
north up the **east wall**, base at the south end so it sits *beside* the front
door rather than facing it: you enter and turn right to climb. One passable
window on the east face, north of the stair top.

**Kitchen** (NE) — the **side door** on the east face, looking at the contested
middle of the lot.

**Back Hall** (NW) — the **back door** on the north face. **Second stair** runs
south down the **west wall**, base at the north end beside the back door: enter
and turn left to climb. One passable window on the west face, south of the stair
top.

**Jail** (SW) — **the only room in the house with no exterior opening.** Reached
from the Front Hall or the Back Hall, and from nowhere else. A rescuer must get
inside and cross the ground floor, then get back out with their teammate.

Ring corridor: Front Hall → Kitchen → Back Hall → Jail → Front Hall.

**Five ways onto this floor**, one per face plus one: front door (S), back door
(N), side door (E), Back Hall window (W), Front Hall window (E).

## 5. UPPER FLOOR — y 300 to 600

```
                      NORTH
        ┌────────────────┬────────────────┐
        │ ║ LANDING B    │ MASTER BEDROOM │
        │ ║ stair down   │     CASH       │
   WEST │ ║ void 600x280 │  window ▼ E    │ EAST
        │                │                │
        ├────────────────┼────────────────┤
        │     STUDY      │  LANDING A   ║ │
        │      CASH      │  stair down  ║ │
        │  window ▼ S    │  void 600x280║ │
        └────────────────┴────────────────┘
                      SOUTH
```

**Landing A** (SE) — head of the main stair. Circulation only.

**Master Bedroom** (NE) — a cash room. Doors to **both** landings. One passable
window on the east face — a **one-way drop** to the garden.

**Landing B** (NW) — head of the second stair. Circulation only.

**Study** (SW) — the second cash room. Doors to **both** landings. One passable
window on the south face — a **one-way drop**.

Ring corridor: Landing A → Master Bedroom → Landing B → Study → Landing A.

**Cash is split randomly between the two cash rooms at the start of every
round.** A raider does not know where the money is until they are upstairs, so
scouting is worth something and a defender cannot pre-position perfectly. Two
`CASH_ROOM` zones; the split is a spawn rule, not new machinery.

The two cash rooms are diagonally opposite, so covering both means crossing the
floor.

## 6. Windows — the important change

**Most windows are not openings.** This is what stops the building reading as a
car park, and it is also better play: one window you know you can jump out of is
a landmark, thirteen identical ones are wallpaper.

### Decorative windows — solid, not passable

Every room gets **one or two** on each exterior face it owns. Roughly **900 wide
× 600 tall, sill at +900**. They are wall as far as the simulation is concerned —
they exist to make the elevation read as a house and to let light in.

Draw them. Do not put them in the collision openings list.

### Passable openings — seven in the whole house

| # | Opening | Room | Face | Direction |
|---|---|---|---|---|
| 1 | **Front door** | Front Hall (SE) | South | Two-way |
| 2 | **Back door** | Back Hall (NW) | North | Two-way |
| 3 | **Side door** | Kitchen (NE) | East | Two-way |
| 4 | Ground window | Back Hall (NW) | West | Two-way, slow climb |
| 5 | Ground window | Front Hall (SE) | East | Two-way, slow climb |
| 6 | **Escape window** | Master Bedroom (NE) | East | **One-way drop** |
| 7 | **Escape window** | Study (SW) | South | **One-way drop** |

The two escape windows must be **visually distinct** from the decorative ones —
full height, or standing open, or a balcony rail. A player has to be able to tell
at a glance which one they can leave through.

**Gravity writes the rule.** Any passable window can be jumped out of. Only the
ground-floor pair can be climbed into, and slowly. Nothing in this house is an
invisible trapdoor.

## 7. Opening schedule — Phase 1

Openings are centred on their room's face unless noted. Doorway heads at +240;
ground window sill +90, head +240; escape window sill +80, head +240.

### Ground floor (y 0–300)

| Tag | Element | Room | Face / wall | Local coords (X, Z) | Direction |
|---|---|---|---|---|---|
| G1 | Front door | Front Hall | South outer | X 1440–1680 · Z 0–30 | Two-way |
| G2 | Window | Front Hall | East outer, **north of the stair top** | X 2060–2090 · Z 745–985 | Two-way climb |
| G3 | Main stair | Front Hall | Against east wall, running north | X 1780–2060 · Z 60–660 (120 flat landing, then 480 flight) | Up to Landing A. Base at Z 60, beside the front door |
| G4 | Side door | Kitchen | East outer | X 2060–2090 · Z 1440–1680 | Two-way |
| G5 | Back door | Back Hall | North outer | X 410–650 · Z 2060–2090 | Two-way |
| G6 | Window | Back Hall | West outer, **south of the stair top** | X 0–30 · Z 1105–1345 | Two-way climb |
| G7 | Second stair | Back Hall | Against west wall, running south | X 30–310 · Z 1430–2030 (120 flat landing at the top, then 480 flight down) | Up to Landing B. Base at Z 2030, beside the back door |
| D1 | Doorway | Front Hall ↔ Kitchen | Internal Z 1030–1060 | X 1440–1680 · Z 1030–1060 | Two-way |
| D2 | Doorway | Kitchen ↔ Back Hall | Internal X 1030–1060 | X 1030–1060 · Z 1440–1680 | Two-way |
| D3 | Doorway | Back Hall ↔ Jail | Internal Z 1030–1060 | X 410–650 · Z 1030–1060 | Two-way |
| D4 | Doorway | Jail ↔ Front Hall | Internal X 1030–1060 | X 1030–1060 · Z 410–650 | Two-way |

### Upper floor (y 300–600)

| Tag | Element | Room | Face / wall | Local coords (X, Z) | Direction |
|---|---|---|---|---|---|
| U1 | Main stair head + **floor void** | Landing A | Against east wall | Void X 1780–2060 · Z 60–660 — the WHOLE stair footprint, base to top | Down to Front Hall |
| U2 | Escape window | Master Bedroom | East outer | X 2060–2090 · Z 1440–1680 | **One-way down** |
| U3 | Second stair head + **floor void** | Landing B | Against west wall | Void X 30–310 · Z 1430–2030 — the WHOLE stair footprint, base to top | Down to Back Hall |
| U4 | Escape window | Study | South outer | X 410–650 · Z 0–30 | **One-way down** |
| D5 | Doorway | Landing A ↔ Master Bedroom | Internal Z 1030–1060 | X 1440–1680 · Z 1030–1060 | Two-way |
| D6 | Doorway | Master Bedroom ↔ Landing B | Internal X 1030–1060 | X 1030–1060 · Z 1440–1680 | Two-way |
| D7 | Doorway | Landing B ↔ Study | Internal Z 1030–1060 | X 410–650 · Z 1030–1060 | Two-way |
| D8 | Doorway | Study ↔ Landing A | Internal X 1030–1060 | X 1030–1060 · Z 410–650 | Two-way |

Anything not in these two tables is solid wall.

## 8. Routes — what the gate should see

| Zone | Independent routes from outdoors | Notes |
|---|---|---|
| Master Bedroom (cash) | 2 | Main stair → Landing A → D5; second stair → Landing B → D6 |
| Study (cash) | 2 | Second stair → Landing B → D7; main stair → Landing A → D8 |
| Jail | 2 | Front Hall → D4; Back Hall → D3 |

All three role-bearing zones sit at **min cut 2** — passing `routes_required`,
below `routes_wanted` (3), so the bake will print advisories. **That is expected.
Do not add routes to silence them.** Three-everywhere is what commissioned the
eighteen-room maze; the floor is 2 and the playtest decides the rest.

## 9. The lot

Two identical houses, **rotated 180° and point-symmetric about the lot centre**
(2690, 1845). Not mirrored — mirroring in X once produced two houses facing the
same way.

```
   ┌────────────────────────────────────────────────┐
   │                              ┌────────────┐    │
   │                              │  HOUSE B   │    │
   │        ┌────────────┐        │  rot 180°  │    │
   │        │  HOUSE A   │        │  front ▲ N │    │
   │        │   rot 0°   │        └────────────┘    │
   │        │  front ▼ S │                          │
   │        └────────────┘                          │
   └────────────────────────────────────────────────┘
```

| Element | X (east) | Z (north) |
|---|---|---|
| Lot / boundary wall | 0 – 5380 | 0 – 3690 |
| House A | 350 – 2440 | 350 – 2440 |
| House B | 2940 – 5030 | 1250 – 3340 |
| Corridor between | 2440 – 2940 | full depth |
| Lot centre | 2690 | 1845 |

House-local → world, House A: `world = local + (350, 350)`.
House B: `world.x = 5030 − local.x`, `world.z = 3340 − local.z`.

**The houses got bigger; the garden got smaller.** Margins are 350 (was 550) and
the corridor is 500 (was 620). This is deliberate and it is the trade worth
knowing: a bigger house means fewer accidental encounters, and thin encounter
rates have bitten this project twice. Growing the house *and* the lot would make
it worse. Keep the buildings close.

Each front door faces **away** from the other house, so the nearest entrances to
an attacker are the back and side doors and the front door is a flank.

### Territory

Ground within **400** of a house's outer wall belongs to that house — capture is
legal there. The corridor and outer margin are neutral and capture is illegal.

Never let the only safe place also be the only crossing. An earlier build put
every encounter on neutral ground, so no capture was ever legal and the game had
no interactions at all.

### Spawns, cash, jail

| Thing | Where |
|---|---|
| Team spawns ×4 | Own yard, spread along the back and side faces |
| Cash bundles | **Split randomly each round** between Master Bedroom (NE upper) and Study (SW upper) |
| Jail | Ground floor, SW quadrant |

## 10. Drawing guide

**Three sheets**: ground plan, upper plan, lot map. Optionally a section through
the SE column showing the main stair in elevation.

| Symbol | Means |
|---|---|
| Heavy solid line | Wall |
| Gap in a wall | Doorway, 240 wide |
| Thin double line, **hatched** | Decorative window — **solid**, not a route |
| Thin double line, **open** | Passable window — annotate direction |
| Arrow pointing down | One-way drop |
| Hatched rectangle, arrow up | Stair flight |
| Dashed rectangle | Stairwell void in the floor above |

Draw both floors on the same grid, north up, so the columns stack. **Annotate
direction on every passable opening** — one-way versus two-way is the most
important fact here and is invisible in plan. And distinguish decorative from
passable windows clearly; conflating them is exactly the error this revision
fixes.

---

# PHASE 2 — the basement

**Do not build this until Phase 1 has been played and is fun.** Written now so it
can be reviewed in advance, not so it can be started early.

## 11. What Phase 2 changes

The jail moves from the ground floor down into a basement, and the SW ground
quadrant becomes a **Living Room** — an ordinary room with two passable windows
on the west and south faces.

That single move is the point of the phase: it puts maximum vertical distance
between the two objectives. Cash upstairs, prison underground. **A thief goes up
then down; a rescuer goes down then up. They cross by construction rather than by
luck.**

## 12. The basement

**L-shaped**, under NW, SW and SE. The **NE quadrant is not excavated** — solid
earth, because the Kitchen's side door and the ground beneath it stay undisturbed.

| Quadrant | Basement |
|---|---|
| SE | Stair foot — main stair continues down from the Front Hall |
| SW | **CELLAR — the jail** |
| NW | Boiler — coal chute (W), vent (S… see below) |
| NE | *solid earth* |

Heights shift down by one storey: basement floor `y = −300`, ground `y = 0`,
upper `y = 300`. Garden stays at ground level, so the basement is below grade.

Only the **main stair** reaches the basement. The second stair still stops at the
ground floor, and the earth under the NW quadrant is excavated but not connected
to it. Rescue therefore has one interior route and must otherwise come from
outside.

## 13. Basement openings

The cellar and the boiler are **open to each other** through a 480 arch — they
are adjacent (SW touches NW along Z 1030–1060), so this is possible. The stair
foot connects to the cellar along X 1030–1060.

| Element | Area | Face | Direction | Note |
|---|---|---|---|---|
| Main stair foot | Stair foot (SE) | interior | Two-way | The only interior route down |
| Arch | Stair foot ↔ Cellar | internal, X 1030–1060 | Open, 480 wide | |
| Arch | Cellar ↔ Boiler | internal, Z 1030–1060 | Open, 480 wide | |
| **Exterior basement steps** | **Cellar (SW)** | South | Two-way | Walled pit in the lawn, 250 × 640 run, descending 300. **Lands in the cellar itself** |
| **Coal chute** | Boiler (NW) | West | **One-way down** | Sloped mouth in the west garden, 200 × 200 |
| **Vent** | Boiler (NW) | North | Two-way, crawl | 240 wide × 90 tall. Slow, low, arrives unseen |
| **Laundry chute** | intake Landing B (NW upper) → exit Cellar | interior shaft | **One-way down** | Two storeys. Shaft 200 × 200, sealed at the ground floor and a blocker there and in Landing B's floor |

**The exterior steps land in the Cellar, not the stair foot.** This is a
correction already paid for once: with the steps in the stair foot, every route
to the jail funnelled through one arch — min cut 1, gate refuses to load, one
defender holds the whole basement. Landing them in the cellar gives the jail its
own outside door and makes "a rescue can skip the house" literal.

**Routes to the Cellar:** exterior steps, the arch from the stair foot, the arch
from the boiler, and the chute one-way in. Min cut ≥ 2. ✔

## 14. The chute is the interesting one

From the upper landing it drops two storeys straight into the enemy jail. Two
readings, both good:

- A rescuer dives in for an instant rescue — and is then stuck in the basement
  with the person they came for, both needing a way out.
- A thief cornered upstairs escapes the chase, and lands in the worst room in the
  house.

That is a real decision with a real consequence, from one hole in a wall.

## 15. Phase 2 acceptance

Before building it, Phase 1 must have been **played by two humans** and judged
worth extending. If the two-storey house is not fun, a basement will not rescue
it — and the specific question Phase 2 answers, *"is a rescue that means
descending two floors better than one across a landing?"*, is only answerable by
someone who has felt the shorter version first.
