class_name BotCrew
extends RefCounted
## Which actors are driven by bots, and why. See ARCHITECTURE.md §2.
##
## The two reasons are different in kind and are kept apart deliberately, from
## the first commit rather than after the second one turns up:
##
##   LOBBY_FILL is OPT-IN. Nobody has to play against bots, and a lobby that
##   wants a full house asks for one. Because it is optional it must also be
##   FAIR - see fill_lobby, which will decline to add any bot at all rather than
##   hand one team an extra body.
##
##   TAKEOVER is NOT optional, and cannot be. A player dropping out of a 3v3
##   leaves four other people in a match that is no longer worth finishing, and
##   "would you like a replacement" is not a question with a useful answer at
##   that moment.
##
## The takeover PATH is not built here: noticing that somebody has gone is the
## network layer's job, and there is no network layer yet. What is built is the
## capability it needs - attaching a director to an actor that is already alive,
## mid-match, at any tick. See take_over().
##
## Nothing in this file is a system, and nothing in it can be reached from
## inside step(). An empty crew emits no commands and is indistinguishable, from
## the simulation's side, from bots not existing.

enum Seat {
	LOBBY_FILL, ## Opt-in. Filled a slot nobody claimed, before the match began.
	TAKEOVER, ## Mandatory. Picked up a player who left mid-match.
}

var profile: BotProfileDef = null
var nav: NavGraph = null
var match_seed: int = 0

var _directors: Dictionary[int, BotDirector] = {}
var _seats: Dictionary[int, Seat] = {}
## Why the last fill_lobby() placed fewer bots than asked for. Empty when it
## did what was requested.
var declined_reason: String = ""

static func create(bot_profile: BotProfileDef, graph: NavGraph, seed_value: int) -> BotCrew:
	var crew: BotCrew = BotCrew.new()
	crew.profile = bot_profile
	crew.nav = graph
	crew.match_seed = seed_value
	return crew

func is_empty() -> bool:
	return _directors.is_empty()

func count() -> int:
	return _directors.size()

func drives(actor_id: int) -> bool:
	return _directors.has(actor_id)

func seat_of(actor_id: int) -> Seat:
	return _seats.get(actor_id, Seat.LOBBY_FILL)

func actor_ids() -> Array[int]:
	var ids: Array[int] = _directors.keys()
	ids.sort()
	return ids

func director_for(actor_id: int) -> BotDirector:
	return _directors.get(actor_id, null)

# ---- filling a lobby ----

## Fills unclaimed slots with bots, and keeps the sides even.
##
## The rule is that a bot must never be the reason one team is bigger. So this
## does not fill greedily: it finds the largest occupancy every team can be
## brought up to within the budget, and fills to exactly that. Given three
## humans in a 2v2 and one bot allowed, it makes 2v2. Given three humans and NO
## bots allowed, it places none and says why - an uneven match is the lobby's
## problem to solve, and quietly making it 2v1-plus-a-bot is not solving it.
##
## Returns the actor ids now driven by bots.
func fill_lobby(world: SimWorld, human_actor_ids: Array[int], max_bots: int) -> Array[int]:
	declined_reason = ""
	var added: Array[int] = []
	if profile == null or nav == null or max_bots <= 0:
		return added

	var team_ids: Array[StringName] = world.sorted_team_ids()
	var seats_per_team: int = world.mode.team_size if world.mode != null else 0
	if team_ids.is_empty() or seats_per_team <= 0:
		return added

	# Who is already sitting down, per team.
	var occupied: Dictionary[StringName, int] = {}
	for team_id: StringName in team_ids:
		occupied[team_id] = 0
	var taken: Dictionary[int, bool] = {}
	for actor_id: int in human_actor_ids:
		var actor: SimEntity = world.get_entity(actor_id)
		if actor == null or not actor.is_actor():
			continue
		taken[actor_id] = true
		if occupied.has(actor.team):
			occupied[actor.team] = occupied[actor.team] + 1

	var fullest: int = 0
	for team_id: StringName in team_ids:
		fullest = maxi(fullest, occupied[team_id])

	# Largest even occupancy the budget can reach. Counting down from a full
	# house means a generous budget fills every seat and a tight one still ends
	# level, just with smaller teams.
	var target: int = -1
	for candidate: int in range(seats_per_team, fullest - 1, -1):
		var needed: int = 0
		for team_id: StringName in team_ids:
			needed += maxi(0, candidate - occupied[team_id])
		if needed <= max_bots:
			target = candidate
			break

	if target < 0:
		declined_reason = (
			"no even line-up fits within %d bot(s) - one team already has %d player(s)"
			% [max_bots, fullest]
		)
		return added

	for team_id: StringName in team_ids:
		var wanted: int = target - occupied[team_id]
		if wanted <= 0:
			continue
		for actor_id: int in _free_slots_for(world, team_id, taken):
			if wanted <= 0:
				break
			_attach(world, actor_id, Seat.LOBBY_FILL)
			taken[actor_id] = true
			added.append(actor_id)
			wanted -= 1
	return added

## A team's unoccupied actor ids, in slot order, so which seat a bot takes is a
## property of the roster rather than of dictionary iteration.
func _free_slots_for(
	world: SimWorld,
	team_id: StringName,
	taken: Dictionary[int, bool]
) -> Array[int]:
	var free: Array[int] = []
	for actor_id: int in world.actor_ids():
		var actor: SimEntity = world.get_entity(actor_id)
		if actor.team != team_id or taken.has(actor_id) or _directors.has(actor_id):
			continue
		free.append(actor_id)
	return free

# ---- taking over from a player ----

## Puts a bot behind an actor that is already in play.
##
## Nothing calls this yet, because noticing a dropout belongs to the network
## layer. It exists now so that layer finds the capability waiting rather than
## an architecture that has to be re-cut to allow it, and the property that
## makes it safe is worth stating while it is still cheap to preserve:
##
## attaching mid-match perturbs NOTHING. The director's randomness is derived by
## hashing rather than drawn from the world, so no other stream shifts; it emits
## ordinary commands, so no rule behaves differently; and is_bot is absent from
## the state digest, so a client that swapped a player for a bot and one that
## has not yet heard still agree on the state of the match. A takeover is a
## change of who is holding the controller, and the simulation is not entitled
## to an opinion about that.
func take_over(world: SimWorld, actor_id: int) -> BotDirector:
	return _attach(world, actor_id, Seat.TAKEOVER)

## Hands an actor back, for a player reconnecting or a lobby removing bots.
func release(world: SimWorld, actor_id: int) -> void:
	if not _directors.has(actor_id):
		return
	_directors.erase(actor_id)
	_seats.erase(actor_id)
	var actor: SimEntity = world.get_entity(actor_id)
	if actor != null:
		actor.is_bot = false

func _attach(world: SimWorld, actor_id: int, seat: Seat) -> BotDirector:
	var actor: SimEntity = world.get_entity(actor_id)
	if actor == null or not actor.is_actor():
		return null
	var director: BotDirector = BotDirector.for_actor(actor_id, profile, nav, match_seed)
	_directors[actor_id] = director
	_seats[actor_id] = seat
	# A LABEL, not simulation state. No rule reads it and the digest omits it,
	# which is what lets a takeover happen mid-match without a desync. It is set
	# for presentation and for the lobby, both of which have a legitimate reason
	# to know, and neither of which the rules consult.
	actor.is_bot = true
	return director

# ---- the tick ----

## Every bot's commands for this tick, in ascending actor order.
##
## Order is fixed rather than incidental because the claim table is built up as
## the crew is drained: a bot deciding later in the same tick sees what an
## earlier one just took. Iterating a dictionary's insertion order instead would
## make two machines coordinate differently from identical state.
func drain(world: SimWorld, tick: int) -> Array[SimCommand]:
	var commands: Array[SimCommand] = []
	var claims: Dictionary[String, int] = _claims()
	for actor_id: int in actor_ids():
		commands.append_array(_directors[actor_id].drain(world, tick, claims))
	return commands

## What each bot is currently on, rebuilt every tick from the directors
## themselves. Self-cleaning: a task that was abandoned or completed simply
## stops appearing, with nothing to expire and no stale claim to clear.
func _claims() -> Dictionary[String, int]:
	var claims: Dictionary[String, int] = {}
	for actor_id: int in actor_ids():
		var task: BotTask = _directors[actor_id].current_task()
		if task != null and not task.is_none():
			claims[task.key()] = actor_id
	return claims
