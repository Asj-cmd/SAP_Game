class_name MatchEvent
extends SimEvent
## Match and round transitions. See ARCHITECTURE.md §5.
##
## States what the match did, never how it is presented: no banner, no camera
## move, no music sting. Presentation subscribes and owns all of that.

const KIND_PHASE_CHANGED: StringName = &"MatchPhaseChanged"
const KIND_ROUND_STARTED: StringName = &"RoundStarted"
const KIND_ROUND_ENDED: StringName = &"RoundEnded"
const KIND_MATCH_ENDED: StringName = &"MatchEnded"

## Why a round ended.
const REASON_TARGET_REACHED: StringName = &"target_reached"
const REASON_TIME_EXPIRED: StringName = &"time_expired"

var from_phase: SimWorld.MatchPhase = SimWorld.MatchPhase.WAITING
var to_phase: SimWorld.MatchPhase = SimWorld.MatchPhase.WAITING
var round_number: int = 0
## Winning team, or empty for a drawn round.
var winner: StringName = &""
var reason: StringName = &""

static func phase_changed(
	tick: int,
	previous: SimWorld.MatchPhase,
	current: SimWorld.MatchPhase
) -> MatchEvent:
	var event: MatchEvent = MatchEvent.new(KIND_PHASE_CHANGED, tick)
	event.from_phase = previous
	event.to_phase = current
	return event

static func round_started(tick: int, number: int) -> MatchEvent:
	var event: MatchEvent = MatchEvent.new(KIND_ROUND_STARTED, tick)
	event.round_number = number
	return event

static func round_ended(tick: int, number: int, winning_team: StringName, why: StringName) -> MatchEvent:
	var event: MatchEvent = MatchEvent.new(KIND_ROUND_ENDED, tick)
	event.round_number = number
	event.winner = winning_team
	event.reason = why
	return event

static func match_ended(tick: int, winning_team: StringName) -> MatchEvent:
	var event: MatchEvent = MatchEvent.new(KIND_MATCH_ENDED, tick)
	event.winner = winning_team
	return event

func to_digest_string() -> String:
	return "%s|p%d>%d|n%d|w%s|r%s" % [super(), from_phase, to_phase, round_number, winner, reason]
