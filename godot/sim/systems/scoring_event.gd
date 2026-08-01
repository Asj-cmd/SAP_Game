class_name ScoringEvent
extends SimEvent
## A team's holdings changed. See ARCHITECTURE.md §5.
##
## Carries the numbers and nothing about how they are shown - no counter
## animation, no sting, no colour. Presentation owns all of that.

const KIND_SCORE_CHANGED: StringName = &"ScoreChanged"

var team: StringName = &""
var previous_score: int = 0
var current_score: int = 0

static func score_changed(tick: int, team_id: StringName, previous: int, current: int) -> ScoringEvent:
	var event: ScoringEvent = ScoringEvent.new(KIND_SCORE_CHANGED, tick)
	event.team = team_id
	event.previous_score = previous
	event.current_score = current
	return event

## Positive when the team gained, negative when it was robbed.
func delta() -> int:
	return current_score - previous_score

func to_digest_string() -> String:
	return "%s|T%s|%d>%d" % [super(), team, previous_score, current_score]
