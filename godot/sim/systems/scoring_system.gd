class_name ScoringSystem
extends SimSystem
## Counts what each team currently holds. See ARCHITECTURE.md §5.
##
## Score is DERIVED from where the carriables are, recomputed from scratch
## every tick, and never incremented. That is the single most important
## property in this file, and it is carried over from the 1:1 port where it
## was already load-bearing: an incrementing score can drift, and every way it
## drifts is a bug that survives the round it started in. A derived score
## cannot disagree with the board, because it IS the board.
##
## The consequence worth understanding: "stealing" needs no special case. A
## carriable's count follows it the instant it leaves a room, so a raider
## lifting cash drops the victim's score on the same tick, with no bookkeeping
## anywhere and nothing to reconcile if the raider is caught on the way home.

func phase() -> SimSystem.Phase:
	return SimSystem.Phase.SCORING

## A derived view, not an actor action. Freezing it would let the displayed
## score disagree with the board it summarises - after a round reset returns
## the cash home, a dormant scorer would still be showing last round's total
## right through the countdown.
func runs_when_paused() -> bool:
	return true

func system_name() -> StringName:
	return &"ScoringSystem"

func step(world: SimWorld) -> void:
	var counted: Dictionary[StringName, int] = {}
	for team_id: StringName in world.sorted_team_ids():
		counted[team_id] = 0

	for entity_id: int in world.sorted_entity_ids():
		var entity: SimEntity = world.entities[entity_id]
		if not entity.is_carriable():
			continue
		var owner_team: StringName = _scoring_team_for(world, entity)
		entity.scored_for_team = owner_team
		if owner_team != &"" and counted.has(owner_team):
			counted[owner_team] = counted[owner_team] + 1

	for team_id: StringName in counted:
		var previous: int = world.score_for(team_id)
		var current: int = counted[team_id]
		if previous != current:
			world.emit(ScoringEvent.score_changed(world.tick, team_id, previous, current))
	world.scores = counted

## Which team a carriable currently counts for, or empty for none.
##
## Role-based, so it covers both cases without distinguishing them: cash still
## sitting in its home vault, and cash hauled back and dumped in your own.
## Both are "at rest in a cash room", and that is deliberately the whole rule -
## a deposit is not an event that needs recording, it is a position.
func _scoring_team_for(world: SimWorld, carriable: SimEntity) -> StringName:
	# In transit counts for nobody. This is what makes a steal instant.
	if carriable.is_held():
		return &""
	var zone: ZoneDef = world.zone_at(carriable.position)
	if zone == null or zone.role != ZoneDef.Role.CASH_ROOM:
		return &""
	return zone.owner_team
