# The house — layout specification

The buildable plan. Supersedes everything previously in this file (the
eighteen-room three-storey proposal, which was generated to satisfy a routing
gate rather than drawn for play, and was retired).

Three floors, four quadrants each, six rooms, two staircases. Compact and
heavily perforated: the possibility space comes from connection density, not
floor area.

## 0. What changes from what is built

The house at `b3a5f0f` is already two-by-two with doors on three faces, six
rooms over **two** floors, jail on the ground. This spec keeps that footprint and
its room shapes. The delta:

| Change | Why |
|---|---|
| **Add a basement**; move the jail down into it | Puts maximum vertical distance between the two objectives — a thief goes up then down, a rescuer down then up, and they cross by construction |
| **Add a second staircase** at the opposite corner | Two independent approaches to the vault; one defender cannot hold both |
| **Add a Living Room** (SW ground) and **Boiler** (SW basement) | Completes the ring corridor on each floor, so a chase can circulate instead of cornering |
| **Every exterior wall gets windows** | Upper ones are one-way drops, ground ones are two-way climbs. This is where most of the new movement comes from |
| **Add chute, coal chute, vent, exterior basement steps** | Five ways into the basement, three of them from outside on three different faces |
| **Reposition the two houses** point-symmetric and diagonally offset | Garden wraps fully around both; all four faces become live |

Nothing here requires a new engine concept. Directed edges, drops, and the
escapability check already exist.

---

## 1. The three principles this is built on

**Permeability beats size.** A small house with four exposed faces, windows
everywhere and three vertical routes has a larger movement space than a sprawl
of corridors. Every room touches an exterior wall, so every room has a way out.
Nobody can be cornered — only made to pay for leaving.

**Windows are openings, and gravity writes the rule.** You can always jump out;
you can rarely climb in. Upper windows are therefore one-way escapes and ground
windows are two-way but slow. No player needs this explained.

**Up is slow and contested; down is fast and free.** Stairs are the only way up.
Any window is a way down. Entering is a careful problem, leaving is an explosive
one — which is the rhythm a heist wants.

---

## 2. Dimensions

| Thing | Value | Why |
|---|---|---|
| Quadrant | 750 × 750 | Above the 755 camera minimum at the diagonal; below it a chase camera lives in a wall |
| House footprint | ~1590 square | Two quadrants plus walls |
| Wall | 30 | |
| Storey height | 300 | 260 clear over a 180 body |
| Doorway | 240 wide | Run through mid-chase, not sidle through |
| Step | 30 rise, 64 run | `TuningDef.step_up_height` and the fill's edge rule |
| Stair, per storey | 10 steps | **Switchback**: two flights of 5 (320 run each) plus a mid-landing |

**Switchback stairs are not cosmetic.** A straight flight needs 640 of floor to
land in; two straight staircases would eat most of a small house. Folded in half
they fit a quadrant, which is the only reason this plan can afford two.

---

## 3. Vertical stacking

Quadrants are named by compass corner and stack identically on every floor.
The basement omits the south-east quadrant.

| Column | Upper | Ground | Basement |
|---|---|---|---|
| **NW** | Landing A | Back Hall | Stair foot |
| **NE** | **VAULT** | Kitchen | **CELLAR (jail)** |
| **SW** | Bedroom | Living Room | Boiler |
| **SE** | Landing B | Front Hall | *solid earth* |

Two consequences worth stating:

**The vault sits directly above the jail**, two floors up in the same corner of
the house. The two objectives are vertically stacked, which makes the building
legible — the cash and the prison are the same corner, top and bottom.

**The NW column is the spine.** The main stair runs its full height, basement to
top. It is the only staircase reaching the basement; the second stair serves
ground-to-upper only, and the earth under it is solid.

### Heights

Garden sits at ground-floor level. The basement is genuinely below grade.

```
   y = 900   roof
   y = 600   upper floor
   y = 300   ground floor  ←  garden / terrain surface
   y =   0   basement floor
```

---

## 4. UPPER FLOOR

```
                    NORTH
        ┌───────────────┬───────────────┐
        │   LANDING A   │     VAULT     │
        │               │               │
   WEST │  stair down   │   the cash    │ EAST
        │  chute ▼ ─────┤               │
        ├───────────────┼───────────────┤
        │    BEDROOM    │   LANDING B   │
        │               │  stair down   │
        └───────────────┴───────────────┘
                    SOUTH
```

**Landing A** (NW) — head of the main stair. The **laundry chute** opens in its
east wall and drops down the NW/NE boundary into the cellar, two floors below.
Windows: north, west.

**Vault** (NE) — the cash. Doors from *both* landings, so neither stair is the
only approach. Windows: north, east.

**Bedroom** (SW) — no objective. It exists as circulation and as somewhere to
lose a pursuer. Windows: west, south.

**Landing B** (SE) — head of the second stair. Windows: south, east.

Ring corridor: Landing A → Vault → Landing B → Bedroom → Landing A.

**Six windows, every one a one-way drop to the garden**, covering all four faces.

---

## 5. GROUND FLOOR

```
                    NORTH
        ┌───────────────┬───────────────┐
        │   BACK HALL   │    KITCHEN    │
        │  ▲ back door  │               │
   WEST │  stair up     │  side door ►  │ EAST
        │  stair down   │               │
        ├───────────────┼───────────────┤
        │    LIVING     │  FRONT HALL   │
        │               │  stair up     │
        │               │  ▼ front door │
        └───────────────┴───────────────┘
                    SOUTH
```

**Back Hall** (NW) — **back door** north. Main stair runs both up to the landing
and down to the cellar.

**Kitchen** (NE) — **side door** east. Windows: north, east.

**Living Room** (SW) — no exterior door, but two climbable windows: west, south.

**Front Hall** (SE) — **front door** south. Second stair up only.

Ring corridor: Back Hall → Kitchen → Front Hall → Living → Back Hall.

**Three doors on three faces, four climbable windows on the remaining face and
beyond.** Seven ways onto this floor.

---

## 6. BASEMENT

L-shaped, under NW/NE/SW. One open space rather than partitioned rooms — a
prisoner must have more than one way out, and open space is the cheapest way to
guarantee it.

```
                    NORTH
        ┌───────────────┬───────────────┐
        │  STAIR FOOT   │    CELLAR     │
        │               │   = JAIL      │
   WEST │  exterior ────┤   ▲ chute in  │ EAST
        │  steps ▲      │               │
        ├───────────────┼───────────────┘
        │    BOILER     │
        │  ◄ coal chute │      solid earth
        │  ◄ vent       │
        └───────────────┘
                    SOUTH
```

**Cellar** (NE) — the jail. The laundry chute lands here.

**Boiler** (SW) — **coal chute** in the west face (one-way down from the garden)
and a **vent** in the south face at crawl height (two-way, slow).

**Stair foot** (NW) — main stair, and **exterior basement steps** rising to the
north garden.

All three areas are open to each other. A released prisoner has the stair, the
exterior steps, and the vent — three ways out, on three faces.

---

## 7. Connections

| Route | Faces | Direction | Character |
|---|---|---|---|
| Front door | S | two-way | Obvious, watchable |
| Back door | N | two-way | Obvious, watchable |
| Side door | E | two-way | Obvious, watchable |
| Ground windows ×4 | W, S, N, E | two-way | Slow to climb in, quick to leave |
| Upper windows ×6 | all four | **one-way down** | Escape from anywhere upstairs |
| Main stair | — | two-way, all three floors | The spine |
| Second stair | — | two-way, ground↔upper | Bypasses the main stair entirely |
| Laundry chute | — | **one-way down** | Upper landing → jail, two floors instantly |
| Exterior basement steps | N | two-way | Reach the jail without entering the house |
| Coal chute | W | **one-way down** | Fast way into the basement, no way back |
| Vent | S | two-way, crawl | Slow, low, arrives unseen |

**Five ways into the basement**, three of them from outside, on three faces.

---

## 8. Why it is shaped like this

**Two diagonal staircases make a genuine loop.** Up the north-west, across the
top, down the south-east, back across the ground floor. A chase can circulate
indefinitely rather than ending in a corner.

**The two stairs do not meet.** Main stair lands on Landing A, second stair on
Landing B, and the vault opens onto both. So there are two independent
approaches to the cash, and one defender cannot hold them.

**The objectives pull vertically apart.** Vault at the top, jail at the bottom.
A thief goes up then down; a rescuer goes down then up. They cross by
construction rather than by luck.

**Every one-way route goes downward and is visible.** No invisible trapdoors —
that mistake was made once with light wells and confirmed unpleasant on first
contact. Gravity makes the rule self-explaining.

**The laundry chute is the most interesting hole in the building.** From the top
landing it drops into the enemy jail. Two readings, both good: a rescuer dives in
for an instant rescue and is then stuck in the basement with the person they came
for; or a thief cornered upstairs escapes the chase and lands in the worst room
in the house.

**The exterior basement steps let a rescue skip the house entirely.** So the
defender must choose between guarding the vault at the top and the jail outside
the bottom. Neither can be abandoned.

**The vent is the patience route.** Crawl height, slow, but it arrives unseen.
Once a noise model exists it becomes the stealth option, and it costs one hole.

**The basement is harder to reach than the top floor** — one staircase down
versus two up. Stealing should be easier than rescuing; a rescue should feel like
a favour someone did you.

---

## 9. The lot

Two identical houses, **rotated 180° and point-symmetric about the centre of the
lot** — automatically fair, with no mirroring (mirroring in x once produced two
houses facing the same way).

```
   ┌──────────────────────────────────────────────────┐
   │                                    ┌──────────┐  │
   │                                    │          │  │
   │              ┌──────────┐          │ HOUSE B  │  │
   │              │          │          │  front ▲ │  │
   │              │ HOUSE A  │          └──────────┘  │
   │              │ ▼ front  │                        │
   │              └──────────┘                        │
   └──────────────────────────────────────────────────┘
```

| | X (east) | Z (north) |
|---|---|---|
| Lot | 0 – 4900 | 0 – 3450 |
| House A | 550 – 2140 | 550 – 2140 |
| House B | 2760 – 4350 | 1310 – 2900 |

House A unrotated: its front door faces **south**. House B rotated 180°: its
front door faces **north**. The houses are offset diagonally, so House B sits
north-east of House A.

**Garden wraps completely around both.** You can walk a full circle around either
house — 550 of clearance on the outer faces, a 620-wide corridor between them.
That is what makes all four faces live, and it means a chase leaving the house
continues outside rather than ending.

### The consequence worth noticing

Because they are point-symmetric and offset, **each house's front door faces
away from the other.** The nearest entrances to an attacker are the *back and
side* doors — and the front door becomes the long way round, a flanking option
rather than the default.

That was not the original intent but it is better than it: the contested middle
of the lot is served by side doors and windows, and the obvious entrance is the
far one.

### Territory

Ground within roughly 400 of a house's walls belongs to that house — capture is
legal there. The diagonal band through the middle of the lot is neutral, and
crossing it is safe. This matters: an earlier build put every encounter on
neutral ground and no capture was ever legal, so the game had no interactions at
all. Never let the only safe place also be the only crossing.

---

## 10. If it needs to be smaller

Cut in this order: **the Bedroom** first (fold into Landing A, leaving three
spaces upstairs), then **the Living Room** (the ground ring becomes an L). That
reaches four rooms and loses no route — only the loop tightens and chases
shorten.

Do not go below four. Under that there is nowhere to lose a pursuer, and the
whole design rests on being able to.
