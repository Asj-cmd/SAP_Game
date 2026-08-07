class_name CaptureSystem
extends SimSystem
## An actor may be captured, held for a duration, and released early by an
## ally. See ARCHITECTURE.md §5.
##
## Named for the MECHANIC, not the fiction. "Jail" and "rescue" are one
## configuration of this: the holding pen is whichever zone content marks
## Role.JAIL, and its content name happens to be 'basement'. Nothing here
## knows that word, so a mode that locks you in a van, a cage or the boot of a
## car is content, not code.
##
## Ported from the rules in autoload/match_state.gd (handle_lock,
## handle_rescue, and the per-tick jail countdown), re-expressed against
## roles and ownership instead of hardcoded room names.

func phase() -> SimSystem.Phase:
	return SimSystem.Phase.INTERACTION

func system_name() -> StringName:
	return &"CaptureSystem"

func handles(kind: StringName) -> bool:
	return kind == CaptureCommand.KIND_CAPTURE or kind == CaptureCommand.KIND_RELEASE

func handle(world: SimWorld, command: SimCommand) -> void:
	var capture_command: CaptureCommand = command as CaptureCommand
	if capture_command == null:
		return
	if capture_command.kind == CaptureCommand.KIND_CAPTURE:
		_try_capture(world, capture_command)
	else:
		_try_release(world, capture_command)

## Per-tick: run the lockup clock down, then refresh safe-room protection.
##
## Captivity is resolved before protection so that an actor released this tick
## re-evaluates its safety from where it now stands, rather than spending a
## tick holding a grant it earned before being seized.
func step(world: SimWorld) -> void:
	for entity_id: int in world.sorted_entity_ids():
		var entity: SimEntity = world.entities[entity_id]
		if entity.is_actor():
			_tick_captivity(world, entity)
	for entity_id: int in world.sorted_entity_ids():
		var entity: SimEntity = world.entities[entity_id]
		if entity.is_actor():
			_tick_safety(world, entity)

# ---- capture ----

## Every condition below is a rule from the original handle_lock, in order.
## Each returns silently: a rejected attempt is not an error, it is simply an
## action that did not meet its conditions.
func _try_capture(world: SimWorld, command: CaptureCommand) -> void:
	var captor: SimEntity = world.get_entity(command.actor_id)
	var target: SimEntity = world.get_entity(command.target_id)
	if captor == null or target == null:
		return
	if not captor.is_actor() or not target.is_actor():
		return
	if captor.team == target.team:
		return
	# A held actor can neither seize nor be seized again.
	if captor.is_captured or target.is_captured:
		return

	var captor_zone: ZoneDef = world.zone_at(captor.position)
	var target_zone: ZoneDef = world.zone_at(target.position)
	if captor_zone == null or target_zone == null:
		return
	# Both must be in the same room - reaching through a wall is not a capture.
	if captor_zone.id != target_zone.id:
		return
	if not _may_capture_on(captor_zone, captor.team):
		return
	if captor.position.distance_squared_to(target.position) > _capture_range_squared(world):
		return
	# The safe room's whole purpose. The grant is refreshed first: commands are
	# resolved before per-tick updates, so an actor that reached the room this
	# tick would otherwise stand unprotected for one tick after arriving.
	_refresh_safety_grant(world, target)
	if target.is_protected():
		return

	_seize(world, captor, target)

## Where a team is entitled to seize intruders: ground its own team owns.
##
## Role.JAIL is excluded even when owned. Guards camping the holding pen would
## make rescue impossible by design, and the original drew exactly this line -
## its isOwnHome covered living room, bedroom and yard, never the basement.
func _may_capture_on(zone: ZoneDef, team: StringName) -> bool:
	if not zone.is_owned_by(team):
		return false
	return zone.role != ZoneDef.Role.JAIL

func _seize(world: SimWorld, captor: SimEntity, target: SimEntity) -> void:
	# A held actor cannot keep hold of anything. Capture states only that the
	# grip was broken; where the carriable then goes belongs to the carry
	# system, which reads this event.
	if target.is_carrying():
		var carriable: SimEntity = world.get_entity(target.carrying_id)
		if carriable != null:
			carriable.carried_by = SimEntity.NO_ENTITY
			carriable.position = target.position
		world.emit(CaptureEvent.carriable_released(world.tick, target.id, target.carrying_id))
		target.carrying_id = SimEntity.NO_ENTITY

	target.is_captured = true
	# Computed BEFORE the tally is bumped, so a first capture serves the base
	# sentence and only a repeat costs more.
	target.capture_ticks_remaining = _capture_hold_ticks(world, target)
	target.captures_this_round += 1
	target.captured_on_tick = world.tick
	target.velocity = Vector3.ZERO
	# Protection does not survive being seized, so a released actor cannot walk
	# out still shielded by a grant it earned before capture.
	target.clear_safety()

	var jail: ZoneDef = _jail_for(world, target.team)
	if jail != null:
		target.position = _holding_spot(world, jail)
		target.zone_id = jail.id

	world.emit(CaptureEvent.captured(
		world.tick, target.id, captor.id, jail.id if jail != null else &""
	))

# ---- release ----

## Conditions from the original handle_rescue.
func _try_release(world: SimWorld, command: CaptureCommand) -> void:
	var rescuer: SimEntity = world.get_entity(command.actor_id)
	var target: SimEntity = world.get_entity(command.target_id)
	if rescuer == null or target == null:
		return
	if not rescuer.is_actor() or not target.is_actor():
		return
	# A held actor cannot free anyone, including itself.
	if rescuer.is_captured:
		return
	if rescuer.team != target.team:
		return
	if not target.is_captured:
		return

	# The rescuer must physically be in the pen holding their own team.
	var jail: ZoneDef = _jail_for(world, rescuer.team)
	if jail == null:
		return
	var rescuer_zone: ZoneDef = world.zone_at(rescuer.position)
	if rescuer_zone == null or rescuer_zone.id != jail.id:
		return
	if rescuer.position.distance_squared_to(target.position) > _release_range_squared(world):
		return

	_free(world, target, rescuer.id, CaptureEvent.REASON_RESCUE)

func _tick_captivity(world: SimWorld, entity: SimEntity) -> void:
	if not entity.is_captured:
		return
	# Seized this very tick. Commands resolve before per-tick updates, so
	# serving time now would shorten every sentence by one tick - a mode
	# authored for 2.0s would actually run 1.967s.
	if entity.captured_on_tick == world.tick:
		return
	if entity.capture_ticks_remaining <= 0:
		# Held with no clock left: an unlimited hold, released only by an ally.
		return
	entity.capture_ticks_remaining -= 1
	if entity.capture_ticks_remaining <= 0:
		entity.capture_ticks_remaining = 0
		_free(world, entity, SimEntity.NO_ENTITY, CaptureEvent.REASON_TIMEOUT)

func _free(world: SimWorld, target: SimEntity, agent_id: int, reason: StringName) -> void:
	target.is_captured = false
	target.capture_ticks_remaining = 0
	target.captured_on_tick = -1
	world.emit(CaptureEvent.released(world.tick, target.id, agent_id, reason))

# ---- safe rooms ----

## Maintains the two content-driven protection conditions.
##
## Protection is keyed to the zone the actor is standing in, so leaving and
## returning starts a fresh grant - a timed safe room is a repeatable tactic,
## not a once-per-round consumable.
func _tick_safety(world: SimWorld, entity: SimEntity) -> void:
	var zone: ZoneDef = _refresh_safety_grant(world, entity)
	if zone == null:
		return

	# Condition two: the clock. Untouched when the grant is unlimited.
	if entity.safe_ticks_remaining > 0:
		entity.safe_ticks_remaining -= 1
		if entity.safe_ticks_remaining == 0:
			world.emit(CaptureEvent.safety_lapsed(
				world.tick, entity.id, CaptureEvent.REASON_EXPIRED, zone.id
			))

## Brings an actor's grant in line with the room it is standing in, and
## applies the pickup condition. Advances no clock, so it is safe to call both
## from the per-tick update and from a capture attempt mid-tick.
##
## Returns the protecting zone, or null when this actor has none.
func _refresh_safety_grant(world: SimWorld, entity: SimEntity) -> ZoneDef:
	if entity.is_captured:
		entity.clear_safety()
		return null

	var zone: ZoneDef = world.zone_at(entity.position)
	if zone == null or not zone.grants_safety():
		entity.clear_safety()
		return null

	# A different room (or a re-entry) starts a fresh grant.
	if entity.safe_zone_id != zone.id:
		entity.safe_zone_id = zone.id
		entity.safe_forfeited = false
		entity.safe_ticks_remaining = (
			SimWorld.seconds_to_ticks(zone.safe_duration_seconds)
			if zone.safety_is_timed()
			else SimEntity.SAFE_UNLIMITED
		)

	# Condition one: the grab. Sticky for this visit - "ends on pickup" means
	# ended, not suspended, so dropping the loot does not restore the shield.
	if zone.safe_ends_on_pickup and entity.is_carrying() and not entity.safe_forfeited:
		entity.safe_forfeited = true
		world.emit(CaptureEvent.safety_lapsed(
			world.tick, entity.id, CaptureEvent.REASON_PICKUP, zone.id
		))

	return zone

# ---- content lookups ----

## The pen holding `team`'s captured members.
##
## Prefers the team's authored jail_zone, and otherwise finds the zone by ROLE:
## a holding pen that some other team owns. Neither path names a room, so the
## content is free to call it a basement, a van or a broom cupboard.
func _jail_for(world: SimWorld, team: StringName) -> ZoneDef:
	var team_def: TeamDef = world.get_team(team)
	if team_def != null and team_def.jail_zone != &"":
		var authored: ZoneDef = world.get_zone(team_def.jail_zone)
		if authored != null:
			return authored
	for zone_id: StringName in world.zone_ids_in_resolution_order():
		var zone: ZoneDef = world.zones[zone_id]
		if zone.role == ZoneDef.Role.JAIL and zone.owner_team != team:
			return zone
	return null

## Ranges are compared SQUARED, against squared distances.
##
## Identical results, and it keeps the comparison inside the exactly
## representable subset (§6) - multiplication and comparison only, no sqrt.
## A range check has no reason to reach for a square root: the only thing it
## ever does with the distance is compare it.
func _capture_range_squared(world: SimWorld) -> float:
	if world.tuning == null:
		return 0.0
	return world.tuning.capture_range * world.tuning.capture_range

func _release_range_squared(world: SimWorld) -> float:
	if world.tuning == null:
		return 0.0
	return world.tuning.rescue_range * world.tuning.rescue_range

## Lockup length is a MODE property (a 3v3 may hold longer than a 2v2), with
## tuning as the fallback when no mode is installed.
##
## Grows with the number of times this actor has already been caught this round.
## Without that, the pen is a slow respawn and the cheapest strategy is to throw
## yourself at the vault until something sticks.
func _capture_hold_ticks(world: SimWorld, target: SimEntity) -> int:
	if world.mode != null:
		var repeat: float = (
			world.mode.capture_escalation_seconds * float(target.captures_this_round)
		)
		return SimWorld.seconds_to_ticks(world.mode.capture_seconds + repeat)
	if world.tuning != null:
		return SimWorld.seconds_to_ticks(world.tuning.capture_hold_seconds)
	return 0

## Where in the pen a prisoner is put: on the FLOOR of it.
##
## It used to be `jail.bounds.get_center()`, and a zone is a VOLUME - a room's
## centre is halfway up the room. A held actor does not fall, because being held
## is not a state you move in, so the prisoner simply hung in mid-air for the
## whole sentence. It looked exactly like a bug and it was one.
##
## Taken from the walkable surface, which is the thing that knows where the
## floor is - the same question spawn points already ask (§9: derive, never
## restate). The volume centre remains the fallback for a fixture with no
## surface built.
func _holding_spot(world: SimWorld, jail: ZoneDef) -> Vector3:
	var centre: Vector3 = jail.bounds.get_center()
	if world.surface == null or world.surface.is_empty():
		return centre

	# The LOWEST standing place in the pen, nearest its middle. Not the nearest
	# standing place to the middle: the pen has a staircase across one end, and
	# asking for "somewhere to stand near the centre" put the prisoner half way
	# up it. Being held is a floor, not a place.
	#
	# Ties break on the lower node index so two machines agree, the same reason
	# every other search in the simulation does.
	var best: int = -1
	var best_height: float = INF
	var best_reach: float = INF
	for node: int in world.surface.size():
		var stance: Vector3 = world.surface.nodes[node]
		if not jail.contains_point(stance):
			continue
		var reach: float = Vector2(stance.x - centre.x, stance.z - centre.z).length_squared()
		if stance.y > best_height + 0.01:
			continue
		if absf(stance.y - best_height) <= 0.01 and reach >= best_reach:
			continue
		best = node
		best_height = stance.y
		best_reach = reach
	return world.surface.nodes[best] if best >= 0 else centre
