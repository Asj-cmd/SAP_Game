class_name BotProfileDef
extends Resource
## Everything a bot's behaviour is made of. See ARCHITECTURE.md §4.
##
## A difficulty tier is a .tres, never a code path. BotDirector contains no
## tuned number at all: every value it weighs, waits for, or aims with is read
## from here, so "make the bots harder" is an inspector edit and "add a rookie
## tier" is a new file. The moment a constant appears in the director, the tier
## it belongs to stops being swappable and starts being a build.
##
## These fields used to live in TuningDef, which was the wrong home. TuningDef
## is what the WORLD is like - speeds, ranges, gravity - and every player shares
## it. A profile is what one OPPONENT is like, and two bots in the same match
## may reasonably differ. Keeping them apart is what lets a lobby mix tiers
## without touching the physics everyone plays by.

@export var id: StringName = &"standard"
@export var display_name: String = "Standard"

@export_group("Reaction")
## How often the bot re-scores every candidate action. This IS its reaction
## speed: nothing it has not yet noticed can affect what it does.
@export var decide_seconds: float = 0.4
## De-syncs teammates' decide ticks so a squad does not think in lockstep and
## turn in unison, which reads as scripted more than any single behaviour does.
@export var decide_jitter_seconds: float = 0.15
## Pause between choosing something and acting on it. Human hesitation: without
## it a bot's interactions land on the exact frame the conditions become true,
## which is the single most obviously inhuman thing a bot does.
@export var reaction_delay_seconds: float = 0.18

@export_group("What it wants")
## Score for each kind of task before distance, risk and coordination apply.
## Their RATIOS are the personality - a defender is one whose defend value
## outweighs its steal value, not one with a different code path.
@export var value_deposit: float = 100000.0
@export var value_rescue: float = 6000.0
@export var value_defend: float = 4000.0
@export var value_steal: float = 3000.0
@export var value_patrol: float = 150.0

@export_group("Judgement")
## Score lost per world-unit of navigation path. Higher means lazier: it takes
## the near thing over the valuable thing.
##
## Calibrated AFTER the world was rescaled to 1 unit = 1 cm, and it had to be:
## at the old value a journey across the map cost more than the raid at the end
## of it was worth, so a bot that had banked its cash scored standing still
## higher than robbing anybody and simply stopped. Distance should discriminate
## between errands, not veto the far ones.
@export var cost_per_unit: float = 0.15
## Score lost per enemy within vision of the target. Higher means more cautious.
@export var risk_weight: float = 1400.0
## How far away an enemy registers as a threat at all.
@export var vision_radius: float = 840.0
## Stickiness: the task already held wins ties and near-ties. Without it a bot
## standing between two equal options dithers between them forever.
@export var commit_bonus: float = 700.0
## A teammate is already on it - usually go elsewhere. This is the whole of the
## squad coordination; there is no assignment authority anywhere.
@export var coord_penalty: float = 2600.0
## Imperfection: +/- jitter per candidate per re-score. Zero makes a bot
## flawlessly consistent, which is both harder to beat and duller to play.
@export var choice_noise: float = 250.0

@export_group("Skill")
## Fraction of an interaction's true range the bot will act at. Below 1.0 it
## closes further than it strictly must, which loses it the marginal grabs a
## confident player takes.
@export var action_range_scale: float = 0.85
## How close a waypoint counts as reached. Larger cuts corners more loosely.
##
## Must stay WELL UNDER a cell (40), because a waypoint that counts as reached
## from a cell away can be counted as reached from the wrong side of a doorway.
## At 55 a bot standing beside a door ticked off the waypoint inside it, aimed
## at the next one - which was through the wall - and walked into that wall for
## the rest of the match. Harmless on a flat plane where the following waypoint
## was usually in open view; fatal in a house, where it is usually not.
@export var arrive_radius: float = 30.0
## Jitter applied to the travel direction, in radians. Steering imprecision -
## it does not walk perfect lines.
@export var steer_wobble: float = 0.05
## How far a bot walks before it recomputes its sense of what is near.
##
## Scoring errands needs distances from where the bot is standing, and getting
## them means flooding the whole stance graph - 14,000 of them in the house, and
## once per decision per bot. That flood was most of a stutter: the median tick
## was 1.6 ms and the 99th over 100.
##
## Reusing it while the bot is still roughly where it was costs almost nothing
## in quality, because moving a few cells adds roughly the same error to EVERY
## candidate and the choice between them is what the numbers are for. Larger is
## cheaper and staler.
@export var distance_refresh: float = 400.0
## How many waypoints ahead to look for a clear line when steering.
##
## The route is a sequence of standing places and the nearest one is often just
## inside a doorway, so walking straight at it means walking straight at the
## frame. Looking further ahead pulls the line taut through the gap. Larger is
## smoother and costs a clearance test per waypoint per tick; smaller hugs the
## route more literally.
@export var path_lookahead: int = 8

## How long a bot tolerates making no progress before backing off, in seconds.
##
## Two bodies meeting in a doorway cannot both go through, and neither can slide
## sideways because the frame is right there. Somebody has to give way, and
## nothing in a shortest-path route ever will - the route is right and the
## bodies are simply in each other's way.
@export var unstick_seconds: float = 0.7

## How often the route is recomputed while a task is held, in seconds. The world
## moves; a path to where the cash used to be is worse than no path.
@export var repath_seconds: float = 0.9

func decide_ticks() -> int:
	return maxi(1, SimWorld.seconds_to_ticks(decide_seconds))

func reaction_ticks() -> int:
	return maxi(0, SimWorld.seconds_to_ticks(reaction_delay_seconds))

func unstick_ticks() -> int:
	return maxi(1, SimWorld.seconds_to_ticks(unstick_seconds))

func repath_ticks() -> int:
	return maxi(1, SimWorld.seconds_to_ticks(repath_seconds))
