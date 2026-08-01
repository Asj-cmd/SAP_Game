# Cash Grab — Technical Architecture (Godot)

The build specification. Every structural decision below exists to serve one
goal: **the gameplay will change repeatedly and substantially over the life of
this project, and each change must be cheap and safe.**

That single requirement is what separates this document from the MVP that
preceded it. The Three.js build and its 1:1 GDScript port both encoded one
specific ruleset directly into control flow — team names, room names and
mechanics threaded together through the same 850-line file. It worked, and
verifying it against the original was straightforward, but every new feature
meant surgery inside working code. This architecture makes new features
*additive* instead.

---

## 0. Principles

1. **The simulation is pure and headless.** The game's rules run with no scene
   tree, no rendering, no input devices, and no wall clock. Presentation is a
   consumer of simulation state, never a participant in it.
2. **All state changes enter through commands.** Nothing mutates the world
   directly — not a player, not a bot, not the server. This is what makes
   netcode, replays, and testing possible at all.
3. **Content is data, not code.** Zones, teams, modes and tuning are Resources
   edited in the inspector. Adding a room or a game mode must not require
   touching a `.gd` file.
4. **Rules read roles, never names.** No rule may ask "is this `bedroomA`". It
   asks "is this a cash room belonging to a team that is not mine".
5. **Systems are independent and composable.** A feature is a new system plus
   new content, plugged into an event bus — not an edit inside an existing one.
6. **Static typing everywhere.** GDScript is markedly faster and far safer to
   refactor when fully typed. Untyped declarations are a defect.

---

## 1. Layers

```
┌───────────────────────────────────────────────────────┐
│  PRESENTATION   scenes, meshes, animation, VFX, audio │  reads state
│                 camera, HUD, input capture            │  emits commands
├───────────────────────────────────────────────────────┤
│  NETWORK        replication, prediction, lobby        │  transports both
├───────────────────────────────────────────────────────┤
│  SIMULATION     rules, scoring, match flow, bot AI    │  THE GAME
├───────────────────────────────────────────────────────┤
│  CONTENT        zones, teams, modes, tuning (.tres)   │  pure data
└───────────────────────────────────────────────────────┘
```

Dependencies point **downward only**. Simulation must never reference anything
in Presentation or Network. This is not a style preference — it is the property
that lets the same simulation run on a headless server, inside a client
predicting ahead of that server, and in a test harness, without modification.

---

## 2. Directory layout

```
godot/
├── content/              Data. Edited in the inspector, not in code.
│   ├── zones/            ZoneDef      — one per room
│   ├── teams/            TeamDef      — one per family
│   ├── modes/            GameModeDef  — 2v2, 3v3, custom rulesets
│   └── tuning/           TuningDef    — speeds, ranges, timers, AI weights
│
├── sim/                  Pure. No Node, no scene tree, no rendering.
│   ├── core/
│   │   ├── sim_world.gd     all mutable state + step()
│   │   ├── sim_command.gd   an intent to change the world
│   │   ├── sim_event.gd     a record that something happened
│   │   ├── sim_random.gd    seeded RNG — the ONLY randomness allowed
│   │   └── sim_entity.gd    actors, carriables
│   ├── systems/
│   │   ├── movement_system.gd
│   │   ├── carry_system.gd      pick up / drop / deposit
│   │   ├── capture_system.gd    capture, hold, release, timeout
│   │   ├── scoring_system.gd    derived score, win detection
│   │   └── match_flow_system.gd rounds, countdowns, match end
│   └── ai/
│       ├── bot_director.gd      produces SimCommands, like a player
│       ├── utility_scorer.gd
│       └── nav_graph.gd
│
├── net/                  Replication + prediction. Knows sim, not scenes.
├── game/                 Presentation. Knows sim state, never mutates it.
│   ├── world/  actors/  camera/  fx/
├── ui/
├── tools/                headless_sim.gd, replay.gd, debug overlays
└── addons/
```

---

## 3. The simulation contract

This is the load-bearing part of the whole design.

```gdscript
class_name SimWorld extends RefCounted

## Advance the world exactly one fixed step. Returns everything that
## happened, for presentation and networking to react to.
func step(commands: Array[SimCommand]) -> Array[SimEvent]
```

**Hard rules inside `sim/` — violations are defects, not preferences:**

| Forbidden | Why | Use instead |
|---|---|---|
| `get_node()`, `$Path`, scene access | Breaks headless execution | Pass data in |
| `randf()`, `randi()` | Destroys determinism and replays | `SimRandom` |
| `Time.get_ticks_msec()`, `delta` from `_process` | Wall clock is not reproducible | `world.tick` |
| Colors, meshes, sounds, node names | Presentation leaking into rules | Emit a `SimEvent` |
| Mutating state outside a system | Untraceable, unreplicable | Issue a `SimCommand` |

**What this buys, concretely:**

- **Netcode becomes tractable.** Clients predict by running the same `step()`
  locally; the server's authoritative result reconciles cleanly because both
  ran identical logic.
- **Replays are nearly free.** Record the seed and the command stream; replay
  is a re-simulation. This is also the single best debugging tool a multiplayer
  game can have — "it happened once and I can't reproduce it" stops being a
  category of bug.
- **Bots are not special-cased.** `BotDirector` emits the same `SimCommand`s a
  human's input produces. A bot cannot cheat, because there is no path into the
  world that bypasses the rules. (The MVP achieved this too, and it was the
  right call — it carries forward.)
- **Rules can be verified without a window open.**

---

## 4. Content model

### ZoneDef

The change that unlocks everything else: rooms carry **roles**, not identities.

```gdscript
class_name ZoneDef extends Resource

enum Role { NEUTRAL, HOME, CASH_ROOM, JAIL }

@export var id: StringName
@export var role: Role
@export var owner_team: StringName     # empty for neutral ground
@export var bounds: AABB               # 3D from the start — see §6
@export var no_capture: bool = false   # a safe room: cannot be jailed here
@export var links: Array[StringName]   # connected zones, for navigation
```

Rules then read intent rather than trivia:

```gdscript
# Instead of:  if zone == "bedroomA" or zone == "bedroomB"
if zone.role == ZoneDef.Role.CASH_ROOM and zone.owner_team != actor.team:
```

A third house, a shared central vault, a mode where the jail is upstairs — all
become new `.tres` files. No rule changes.

Note this also directly expresses the design you described: cash sitting in a
room where you *cannot* be sent to lockup is simply
`role = CASH_ROOM, no_capture = true`.

### TeamDef, GameModeDef, TuningDef

```gdscript
class_name GameModeDef extends Resource
@export var team_size: int
@export var rounds_to_win: int
@export var round_seconds: float
@export var cash_per_team: int
@export var capture_seconds: float     # lockup timeout
```

A new mode is a new resource. Not a new code path, and not a constant edited at
the top of a file.

---

## 5. Systems and events

Each system is independent, ordered explicitly by `SimWorld`, and communicates
only through world state and events:

```gdscript
class_name SimSystem extends RefCounted
func handle(world: SimWorld, cmd: SimCommand) -> void
func step(world: SimWorld) -> void
```

`CaptureSystem` is deliberately named for the *mechanic*, not the *fiction*. It
implements "an actor may be captured, held for a duration, and released early
by an ally" — jail and rescue are one configuration of it. Any future
capture-like mechanic reuses it rather than growing a parallel system.

**Presentation subscribes to events and owns all feel:**

| Event | Presentation responds with |
|---|---|
| `CashPickedUp` | prop attaches, sound, brief flash |
| `ActorCaptured` | ragdoll, VFX at that location, audio |
| `RoundEnded` | banner, camera move, music sting |

Because the rules emit *what happened* and never *how it looks*, juice and
polish can be iterated freely without any risk to correctness.

---

## 6. Three decisions that must be made now, not later

**Physics is not part of the deterministic simulation.** Jolt is not
bit-identical across platforms and compilers, so a physics-driven world cannot
be lockstepped. The professional split, and the one used by comparable games:

- **Rules** (who holds cash, who is captured, score, round flow) — deterministic,
  command-driven, replicated as authoritative state.
- **Physics bodies** (thrown objects, ragdolls, knocked furniture) —
  server-simulated, snapshot-replicated, client-interpolated. Visually shared,
  never load-bearing for a rule.

The boundary must be explicit: a physics object may *trigger* a command
("this object entered the deposit volume"), but the rule outcome is always
decided by the simulation.

**Positions are 3D from the first commit.** The MVP was a flat plane with a
bolted-on `floor` axis, and every subsequent vertical feature fought that
decision. `Vector3` and `AABB` cost nothing now and prevent a painful retrofit
once the house is genuinely multi-storey.

**Positions stay 32-bit float. The game does not need cross-platform
bit-determinism.** `Vector3` components are `real_t`, which is 32-bit outside a
double-precision build — measured resolution is ~5.12e-7 at magnitude 10 and
~0.0002 at a world extent of 3200 units.

That is ample for gameplay, and the alternative is not worth its price.
Cross-platform bit-determinism is required by exactly two things: lockstep
netcode, and replays that re-simulate on a different architecture than the one
that recorded them. This game uses neither. It is server-authoritative with
client prediction and reconciliation, so the server is the single source of
truth and correcting client drift is not a failure mode — it is the mechanism
working as designed. Fixed-point positions would tax every line of movement
code, permanently, to buy a property the netcode never reads.

Two weaker forms of determinism *are* required, and both survive this decision:

- **Same-build determinism**, so a client can re-simulate its own recent past
  during reconciliation or rollback. float32 provides this.
- **Logic determinism** — no insertion-order dependence, no engine RNG, no wall
  clock. This is what `state_digest()` actually protects, and what the §3 bans
  exist for. The digest's real quarry is a system that iterates unsorted or
  reads state it shouldn't, not float drift.

For replay: seed plus input log reproduces a match exactly on the same build and
architecture. Cross-platform sharing exports rendered video or a snapshot
stream, never a re-simulation. A distribution feature must not levy a permanent
tax on the simulation.

Consequence for `sim/`: prefer the exactly-representable subset (`+`, `-`, `*`,
comparison) and treat `sqrt`, `normalized()` and trigonometry as deliberate
choices rather than reflexes — but no outright ban is warranted.

---

## 7. Working practice

- **Fixed simulation timestep**, decoupled from render framerate. Rendering
  interpolates between the two most recent simulation states.
- **One system per pull of work.** Build `sim/core` first and prove it with the
  headless runner before any system is written; build each system to green
  before starting the next.
- **The headless runner stays first-class.** `tools/headless_sim.gd` must be
  able to play a full match with no window at any point in the project's life.
  It is the fastest correctness signal available and it must never rot.
- **Content before code.** When a change *can* be expressed as data, it must be.

---

## 8. What this costs

This is slower to start than continuing to extend the ported monolith, and that
is the deliberate trade. The first playable will take longer to arrive, because
`sim/core` and the content model have to exist before any feature does. The
return is that feature number twenty costs roughly what feature number two did,
rather than an order of magnitude more — which is the actual difference between
a prototype and something shippable.

---

## 9. Designed-for extension

None of the features below are committed. What follows is not a set of hooks for
them — it is the small number of *shapes* that keep them cheap if they happen and
cost nothing if they never do.

One test governs everything in this section: **if the feature is cut, does this
become dead code?** If yes, it was a feature hook and does not belong in an
architecture. If it merely becomes a smaller version of something the game needs
regardless, it is a capability and it is safe. A "vent system" fails that test.
"How two spaces connect, and under what rules" passes it, because a doorway
needs the same thing.

### Space connectivity is a graph, not a partition

`ZoneDef.links` is already an adjacency list. It should carry *typed edges*
rather than bare ids: each connection gets a traversal rule (who may pass, after
what delay), a cost, and a noise profile.

That single shape expresses a locked door, a one-way drop, a gap that only fits
an unencumbered actor, and "you may follow an intruder into your own room after
N seconds" — as content, not code. Cut every exotic traversal idea and it
degrades to a plain doorway. Nothing is stranded.

The simulation knows edge *rules*; content supplies the names. A crawlspace and
a laundry chute are one mechanism with different labels and numbers — and the
label is precisely where this game's identity lives. Keeping fiction in content
lets the architecture stay generic while the game stays specific, which is the
same reason zones carry roles instead of identities (§4).

### Movement is a state machine inside the simulation

Crouch, slide, jump, vault and carry are simulation state, not animation state.
The presentation node reads that state and plays something; it never decides it.
Let movement logic accumulate inside a `CharacterBody3D` and prediction breaks —
after which every new movement verb is a netcode rewrite instead of a case in a
state machine.

### Loadout is a small fixed stat vector

A handful of numbers per actor — move, carry, capture, escape — read by the
systems that already exist. Not a plugin system, not scripted abilities. If the
idea is dropped, what remains is per-character tuning values, which the game
needs anyway.

Two design constraints follow from the shape. The budget is spent per *team*
rather than per player, so a roster is forced to diversify and the allocation
becomes a conversation between friends. And every meaningful allocation needs a
readable silhouette, because a stat the opponent cannot see has no counterplay.

### Appearance never reaches the simulation

The simulation knows a team, a slot, and a loadout. It must never know a mesh, a
colour, a texture, or a display name. Everything visual resolves on the
presentation side from those keys.

This is what makes player-supplied appearance nearly free later: a texture swap
in a layer the rules cannot observe, with no netcode consequence beyond an asset
handshake. It also allows such assets to stay peer-shared inside a lobby rather
than uploaded to a service — which keeps a shipping title clear of a
content-moderation obligation it would not otherwise incur.

### Uniform rules, never curated lists

Where a behaviour could be either a general predicate or a hand-placed list, it
must be the predicate. "Any container above a volume threshold can be hidden in"
yields hiding places nobody designed and a strategy space that survives contact
with players. Twelve hand-placed hiding spots yield twelve hand-placed hiding
spots, and the game is solved in a week.

The same applies to what can be climbed, carried, or thrown. The general rule is
usually *less* code than the curated list, and it is the only version that
produces emergent play. This has to be written down rather than left to habit,
because each individual special case always looks reasonable on its own.

### Replay is a product feature, not only a debugging aid

Match state must remain reconstructable from seed plus input log. It already is,
and it costs kilobytes.

Protect that deliberately: it makes highlight export a rendering problem rather
than a simulation one, and short shareable clips are the main distribution
mechanism for a game of this kind. Anything that makes the simulation depend on
un-recorded input destroys the property silently — which is the underlying
reason for the §3 bans on wall clock, engine RNG, and scene state.
