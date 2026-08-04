class_name TuningDef
extends Resource
## Speeds, ranges, timers and AI weights. See ARCHITECTURE.md §4.
##
## Durations are authored in SECONDS because that is what a designer reasons
## in. The simulation converts them to whole ticks against its fixed timestep
## (SimWorld.seconds_to_ticks) and counts ticks thereafter - no wall clock ever
## reaches a rule (§3).
##
## The AI weights are a table, not logic. A future difficulty tier is a
## different .tres swapped in here - never an edit to the scoring code.

@export_group("Movement")
@export var move_speed: float = 440.0
## Multiplier applied to move_speed while carrying.
##
## 1.0 for now: carrying does not slow you down. The field and the
## carry_speed() path stay live precisely so that this is a number a designer
## dials rather than a code change - set it below 1.0 and laden actors are
## slower with nothing recompiled.
@export var carry_speed_scale: float = 1.0
## Actor body radius, for collision against level geometry. Also acts as the
## body's half-height, so a resting actor's centre sits this far above the
## floor it stands on.
@export var actor_radius: float = 20.0

@export_group("Gravity")
## Downward acceleration in units per second squared. Zero or less means no
## gravity is authored and actors do not fall - only ever right for a fixture
## that is testing horizontal rules. See WORLD_AUTHORING.md §5.
@export var gravity: float = 2000.0
## Fall speed is capped so a long drop cannot outrun the swept test.
@export var terminal_fall_speed: float = 3000.0
## How high a threshold an actor walks over without a jump. Stairs and door
## sills should not require a verb the game may never have.
@export var step_up_height: float = 30.0

## ---- the threshold set ----
##
## These four numbers, plus step_up_height above, are the whole vocabulary of
## height in this game. Every ledge, gap and drop in every level is built to one
## of them, with NO exceptions - not one hand-placed ledge at an in-between
## height, ever.
##
## That is not tidiness. The strategy space comes from players trusting that a
## thing which LOOKS vaultable IS vaultable, everywhere, and improvising on that
## trust. A single exception teaches them the rule is unreliable, and once they
## stop trusting it they stop improvising and the emergent play goes with it
## (ARCHITECTURE.md §9 - uniform rules, never curated lists).
##
## The verbs that read these do not exist yet. The GEOMETRY is sized for them
## now because retrofitting heights into a finished house is the expensive
## version. See WORLD_AUTHORING.md §12.

## Waist height on a 180-unit body: hop over without slowing down.
@export var vault_height: float = 120.0
## Clear opening a crouching body passes through. Under a counter, through a
## serving hatch, along a crawl space.
@export var crouch_gap: float = 130.0
## The furthest an actor may drop and keep going. Also the fall a one-way route
## is allowed to be: past this, the surface refuses the edge in both directions
## rather than offering a trip nobody survives.
@export var max_drop_height: float = 480.0

@export_group("Ways into a room")
## How many independent approaches a room that matters must have, and how many
## it should have. Below `routes_required` the level does not load; below
## `routes_wanted` the bake says so and carries on.
##
## Two is the floor because one door is one defender. Three is the aspiration,
## and it is only an aspiration: failing everything below three would refuse
## every level anyone has yet drawn, including the one being played.
@export var routes_required: int = 2
@export var routes_wanted: int = 3

@export_group("Interaction ranges")
@export var pickup_range: float = 144.0
@export var capture_range: float = 164.0
@export var rescue_range: float = 164.0

@export_group("Timers (seconds)")
@export var respawn_seconds: float = 0.0
## How long a captured actor stays held when nobody frees them.
@export var capture_hold_seconds: float = 60.0

@export_group("Netcode")
## Ticks between a local input and the tick it is applied on, locally AND on the
## host. Tuning rather than a constant because it is the cheapest knob available
## once real latency is in play, and the right value is a feel judgement.
##
## Holding your own input back by a tick or two gives it time to reach the host
## before the host reaches that tick, so the host applies it on the tick the
## client predicted it on and the client's own actions stop mispredicting at all.
## What remains are other players' actions, which is a much smaller share.
##
## The cost is input latency, paid always, against misprediction paid sometimes.
## Zero is honest for a local match and wrong for an online one.
@export var input_delay_ticks: int = 2

## How often the host sends an unrequested full snapshot, in ticks.
##
## A keyframe. Nothing needs it while the command stream is arriving intact, and
## that is exactly why it exists: the failures it covers are the ones where
## something has already gone wrong quietly. Cheap at this scale - a few hundred
## bytes against a stream costing ~32 bytes a tick.
@export var snapshot_interval_ticks: int = 150

## How far behind the newest confirmed state remote bodies are drawn, in ticks.
##
## Packets do not arrive on a metronome. Drawing the newest state the moment it
## lands makes every remote body stutter at whatever rate the network happened
## to deliver; sitting slightly in the past means there is always a later state
## to move towards and motion is continuous.
##
## The cost is that other players are seen this many ticks late - which is a
## real disadvantage in a chase, and the reason this is a dial rather than a
## constant. Too low and they jitter, too high and you are shooting at ghosts.
@export var interpolation_delay_ticks: int = 3

## How long a seat stays a player's after they drop, in seconds.
##
## A connection hiccup must not eject anybody: most disconnections are a few
## seconds of nothing, and taking somebody's seat for their router is the worst
## available reading of it. Past this window a bot holds the seat and hands it
## straight back when they return.
##
## The trade is between a squad briefly playing a body short and a player
## briefly losing their place. Both are bad; this decides which.
@export var reconnect_grace_seconds: float = 8.0

## The AI weights that used to sit here now live in BotProfileDef.
##
## They were in the wrong place. This resource is what the WORLD is like, and
## every player in a match shares one; a bot profile is what one OPPONENT is
## like, and a lobby may reasonably mix tiers. Merging them made difficulty a
## property of the level.

func carry_speed() -> float:
	return move_speed * carry_speed_scale
