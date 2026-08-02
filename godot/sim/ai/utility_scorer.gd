class_name UtilityScorer
extends RefCounted
## Ranks candidate tasks. See ARCHITECTURE.md §2.
##
## The whole of the bot's judgement, and deliberately the whole of it in one
## short function: what a task is worth, less what it costs to reach, less what
## it risks, plus what it is worth to finish the thing already started, less
## what it is worth to duplicate a team-mate.
##
## Every term is a field of BotProfileDef. There is no number in this file, and
## that is the point - a difficulty tier changes what a bot values, and if any
## of these weights were written here instead, it would change what a bot IS.

## Score for `kind` before anything is deducted, straight from content.
##
## An unrecognised kind scores nothing rather than defaulting to something
## plausible: a task nobody gave a value to should be invisible, not cheap.
static func base_value(profile: BotProfileDef, kind: BotTask.Kind) -> float:
	match kind:
		BotTask.Kind.DEPOSIT:
			return profile.value_deposit
		BotTask.Kind.RESCUE:
			return profile.value_rescue
		BotTask.Kind.DEFEND:
			return profile.value_defend
		BotTask.Kind.STEAL:
			return profile.value_steal
		BotTask.Kind.PATROL:
			return profile.value_patrol
		_:
			return 0.0

## What this task is worth to this bot, right now. Higher wins.
##
## `distance` is walking distance along the nav graph, never straight-line: the
## room through the wall is not close, and a bot that thinks it is will spend
## the round walking into that wall.
static func score(
	profile: BotProfileDef,
	kind: BotTask.Kind,
	distance: float,
	threats: int,
	committed: bool,
	claimed_by_ally: bool,
	noise: float
) -> float:
	var value: float = base_value(profile, kind)
	if value <= 0.0:
		return -INF
	# Unreachable is not expensive, it is impossible. Scoring it as merely
	# distant lets a bot pick a target it can never arrive at and stand there
	# pushing into the geometry for the rest of the round.
	if distance < 0.0:
		return -INF

	var total: float = value
	total -= distance * profile.cost_per_unit
	total -= float(threats) * profile.risk_weight
	if committed:
		total += profile.commit_bonus
	if claimed_by_ally:
		total -= profile.coord_penalty
	return total + noise
