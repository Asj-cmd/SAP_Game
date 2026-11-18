class_name Lobby
extends RefCounted
## Who is in the match, which seat they hold, and what happens when they go.
##
## A pure model. It touches no transport, no world and no bots - it is given
## facts (someone arrived, someone vanished, a tick passed) and reports
## decisions as LobbyEvents for the caller to carry out. That is what lets the
## whole of it be tested headless, and it keeps the roster rules in one place
## instead of spread through the code that reacts to them.
##
## Three things are load-bearing here.
##
## AUTHORITY IS A ROLE, NEVER AN IDENTITY. Nothing asks "is this peer 1"; it
## asks who currently holds the role. Host migration is NOT built - a match ends
## when the host goes - but nothing here assumes the host is unique in what it
## KNOWS, because it is not: every guest already holds an identical confirmed
## world and could continue from it. Migration stays a matter of moving the role
## and picking a successor, rather than a rewrite.
##
## A SEAT OUTLIVES ITS OCCUPANT. Dropping out, a bot holding the place, and
## coming back are three changes to one seat, and the actor in the world never
## changes. Reconnecting is therefore the snapshot path that already exists,
## with nothing new underneath it.
##
## LEAVING IS NOT IMMEDIATE. A connection hiccup must not eject anybody. A seat
## goes quiet, waits out a grace window, and only then is handed to a bot - and
## the bot gives it straight back. Anything else punishes players for their
## router.

enum Phase {
	GATHERING, ## Assembling. Seats can still change hands freely.
	IN_MATCH, ## Playing. Seats change hands only through absence and return.
	ENDED, ## Over. See `ended_reason`.
}

## A player's member choice when they have not picked one (PT4-3). Any other
## value is a slot of their own family: slot n IS a member (dad, mom, ...), and
## only the slots that exist at the team size can be picked.
const RANDOM: int = -1

var phase: Phase = Phase.GATHERING
var seats: Array[LobbySeat] = []
## The peer currently holding the authority ROLE. Compared against, never
## assumed: see the note above about migration.
var authority: int = SessionTransport.HOST_PEER
## Opt-in, and the default is off. Nobody has to play against bots.
var bots_enabled: bool = false
## How long a seat stays a player's after they vanish, in ticks.
var grace_ticks: int = 0
var ended_reason: String = ""
## Why the last fill placed fewer bots than it could, from BotCrew.
var bots_declined: String = ""

static func create(grace: int, allow_bots: bool = false) -> Lobby:
	var lobby: Lobby = Lobby.new()
	lobby.grace_ticks = maxi(0, grace)
	lobby.bots_enabled = allow_bots
	return lobby

## Lays out one seat per roster slot, mirroring the world's actors.
func seat_roster(world: SimWorld) -> void:
	seats.clear()
	for actor_id: int in world.actor_ids():
		var actor: SimEntity = world.get_entity(actor_id)
		seats.append(LobbySeat.make(actor.team, actor.slot, actor_id))

func holds_authority(local_peer: int) -> bool:
	return local_peer != 0 and local_peer == authority

func is_ended() -> bool:
	return phase == Phase.ENDED

# ---- arriving ----

## Seats an arriving player, or gives them back the seat they left.
##
## Reclaiming comes FIRST and is matched on identity rather than on the peer id,
## because a peer id names a connection and a reconnecting player has a new one.
## Getting this the wrong way round would hand a returning player a fresh seat
## and leave a bot holding their old one for the rest of the match.
##
## `wanted` (PT4-3) is the member a NEW player asks for, as a slot of the family
## they are seated in, or RANDOM. A returning player keeps the seat, and so the
## member, they had; `wanted` is ignored for them. A wanted member that is not
## free leaves the player on Random rather than turning them away.
func admit(identity: String, peer: int, display_name: String, tick: int,
		wanted: int = RANDOM) -> LobbyEvent:
	if phase == Phase.ENDED:
		return LobbyEvent.ended(ended_reason)

	var existing: LobbySeat = seat_of(identity)
	if existing != null:
		var was_held: bool = existing.is_being_held()
		existing.peer = peer
		existing.occupancy = LobbySeat.Occupancy.HUMAN
		existing.presence = LobbySeat.Presence.PRESENT
		existing.absent_since = -1
		existing.held_for = ""
		if display_name != "":
			existing.display_name = display_name
		# Reclaimed rather than joined: the caller must release the bot and send
		# a snapshot. Both are paths that already exist.
		return LobbyEvent.about(
			LobbyEvent.Kind.RECLAIMED if was_held else LobbyEvent.Kind.SEAT_TAKEN,
			existing
		)

	var seat: LobbySeat = _next_open_seat()
	if seat == null:
		return LobbyEvent.about(LobbyEvent.Kind.SEAT_FREED, null, "the match is full")

	seat.clear_occupant()
	seat.identity = identity
	seat.peer = peer
	seat.display_name = display_name
	seat.occupancy = LobbySeat.Occupancy.HUMAN
	if wanted != RANDOM:
		choose(identity, wanted)
	return LobbyEvent.about(LobbyEvent.Kind.SEAT_TAKEN, seat_of(identity))

## Keeps the sides even as players arrive: the emptier team gets the next one.
##
## Same principle as the bot fill - nobody should be handed an advantage by
## whoever happened to click first - and it means a lobby that fills up
## naturally needs no rebalancing at the end.
##
## An empty seat first, and failing that a seat a bot was merely FILLING. A bot
## exists so that a short-handed lobby still plays; it must never be the reason
## a real player cannot get in. This was found the hard way: a two-seat match
## with one host and one filler bot had no room for anybody, and a guest that
## asked to join was turned away without being told.
##
## A seat a bot is HOLDING for an absent player is not available. That seat is
## already somebody's, and they are expected back.
func _next_open_seat() -> LobbySeat:
	var empty: LobbySeat = _emptiest_where(true)
	return empty if empty != null else _emptiest_where(false)

func _emptiest_where(want_empty: bool) -> LobbySeat:
	var occupied: Dictionary[StringName, int] = {}
	for seat: LobbySeat in seats:
		occupied[seat.team] = occupied.get(seat.team, 0) + (0 if seat.is_open() else 1)

	var best: LobbySeat = null
	for seat: LobbySeat in seats:
		var eligible: bool = seat.is_open() if want_empty else (
			seat.occupancy == LobbySeat.Occupancy.BOT and seat.held_for == ""
		)
		if not eligible:
			continue
		if best == null or occupied[seat.team] < occupied[best.team]:
			best = seat
	return best

# ---- choosing a member (PT4-3) ----

## A player asks to play member `slot` of their own family, or RANDOM. Returns
## "" when done, else why not (shown to that player). Only while GATHERING, and
## never another family: players do not change sides here.
##
## A member somebody PICKED is theirs: asking for it is refused, naming them. A
## member a Random player only sits on provisionally is not: the two swap, so
## the Random player lands on the asker's old seat. An empty member or one a
## filler bot holds is simply taken (the caller releases the bot and refills).
func choose(identity: String, slot: int) -> String:
	if phase != Phase.GATHERING:
		return "the match has started"
	var mine: LobbySeat = seat_of(identity)
	if mine == null:
		return "you are not seated"
	if slot == RANDOM:
		mine.chosen = false
		return ""
	var target: LobbySeat = seat_at(mine.team, slot)
	if target == null:
		return "there is no such member at this team size"
	if target != mine:
		if target.is_persons():
			if target.chosen:
				var who: String = target.display_name if target.display_name != "" else "another player"
				return "taken by %s" % who
			var mover: LobbySeat = LobbySeat.new()
			mover.copy_occupant_from(mine)
			mine.copy_occupant_from(target)
			target.copy_occupant_from(mover)
		else:
			target.copy_occupant_from(mine)
			mine.clear_occupant()
	target.chosen = true
	return ""

## At Start: every Random player of each family draws one of the places left
## for them (their own provisional seat, an empty one, or one a filler bot
## holds), from `rng` - the host's own generator, never the sim's. Picked
## members are never drawn. Places nobody draws keep their bot or stay empty
## for the bot fill that follows.
func resolve_random(rng: RandomNumberGenerator) -> void:
	if phase != Phase.GATHERING:
		return
	var teams: Array[StringName] = []
	for seat: LobbySeat in seats:
		if not teams.has(seat.team):
			teams.append(seat.team)
	for team_id: StringName in teams:
		var drawers: Array[LobbySeat] = []
		var places: Array[LobbySeat] = []
		for slot: int in offered_slots(team_id):
			var seat: LobbySeat = seat_at(team_id, slot)
			if seat.is_persons() and seat.chosen:
				continue
			places.append(seat)
			if seat.is_persons():
				var copy: LobbySeat = LobbySeat.new()
				copy.copy_occupant_from(seat)
				drawers.append(copy)
				seat.clear_occupant()
		for drawer: LobbySeat in drawers:
			var at: int = rng.randi_range(0, places.size() - 1)
			places[at].copy_occupant_from(drawer)
			places.remove_at(at)

## The match has started: choices are fixed from here on.
func begin() -> void:
	if phase == Phase.GATHERING:
		phase = Phase.IN_MATCH

## The seat of member `slot` in `team_id`, or null at this team size.
func seat_at(team_id: StringName, slot: int) -> LobbySeat:
	for seat: LobbySeat in seats:
		if seat.team == team_id and seat.slot == slot:
			return seat
	return null

## The members a family has at this team size, as slots in order.
func offered_slots(team_id: StringName) -> Array[int]:
	var slots: Array[int] = []
	for seat: LobbySeat in seats:
		if seat.team == team_id:
			slots.append(seat.slot)
	slots.sort()
	return slots

# ---- leaving ----

## Notes that a peer has gone. NOT the same as them leaving.
##
## The seat goes quiet and the grace window starts. Nothing is taken away yet,
## because most disconnections are a few seconds of nothing and ejecting
## somebody for their router is the worst possible reading of it.
func note_absence(peer: int, tick: int) -> Array[LobbyEvent]:
	var events: Array[LobbyEvent] = []
	if peer == authority:
		# No migration yet, deliberately. Every guest holds an identical
		# confirmed world, so this is a decision not to continue rather than an
		# inability to - which is what keeps migration available later.
		phase = Phase.ENDED
		ended_reason = "the host left"
		events.append(LobbyEvent.ended(ended_reason))
		return events

	for seat: LobbySeat in seats:
		if seat.peer != peer or seat.occupancy != LobbySeat.Occupancy.HUMAN:
			continue
		seat.presence = LobbySeat.Presence.HICCUP
		seat.absent_since = tick
		events.append(LobbyEvent.about(LobbyEvent.Kind.SEAT_FREED, seat, "connection lost"))
	return events

## Runs the grace clocks. Called once per simulation tick, never on a wall clock.
func advance(tick: int) -> Array[LobbyEvent]:
	var events: Array[LobbyEvent] = []
	if phase == Phase.ENDED:
		return events
	for seat: LobbySeat in seats:
		if seat.presence != LobbySeat.Presence.HICCUP:
			continue
		if tick - seat.absent_since < grace_ticks:
			continue
		# Grace is up. A bot takes the seat, and remembers whose it is.
		seat.presence = LobbySeat.Presence.VACATED
		seat.occupancy = LobbySeat.Occupancy.BOT
		seat.held_for = seat.identity
		events.append(LobbyEvent.about(LobbyEvent.Kind.TAKEOVER_DUE, seat))
	return events

# ---- bots ----

## Records the outcome of a lobby fill. The fill itself is BotCrew's - it
## already knows how to keep the teams even and to decline rather than tilt
## them - and this only reports what it did.
func note_fill(filled: Array[int], declined: String) -> Array[LobbyEvent]:
	var events: Array[LobbyEvent] = []
	bots_declined = declined
	if not filled.is_empty():
		for actor_id: int in filled:
			var seat: LobbySeat = seat_for_actor(actor_id)
			if seat == null:
				continue
			seat.occupancy = LobbySeat.Occupancy.BOT
			seat.display_name = "Bot"
			events.append(LobbyEvent.about(LobbyEvent.Kind.BOTS_FILLED, seat))
	if declined != "":
		events.append(LobbyEvent.about(LobbyEvent.Kind.BOTS_DECLINED, null, declined))
	return events

## Seats a human should be counted as holding, for BotCrew.fill_lobby.
##
## A seat being held FOR someone counts as theirs. Otherwise a player who
## dropped out would be filled over as though they had never been there, and
## would find their seat gone when they came back.
func human_actor_ids() -> Array[int]:
	var ids: Array[int] = []
	for seat: LobbySeat in seats:
		if seat.occupancy == LobbySeat.Occupancy.HUMAN or seat.is_being_held():
			ids.append(seat.actor_id)
	return ids

# ---- queries ----

func seat_of(identity: String) -> LobbySeat:
	if identity == "":
		return null
	for seat: LobbySeat in seats:
		if seat.identity == identity:
			return seat
	return null

func seat_for_actor(actor_id: int) -> LobbySeat:
	for seat: LobbySeat in seats:
		if seat.actor_id == actor_id:
			return seat
	return null

func occupied_count() -> int:
	var total: int = 0
	for seat: LobbySeat in seats:
		if not seat.is_open():
			total += 1
	return total

func humans_present() -> int:
	var total: int = 0
	for seat: LobbySeat in seats:
		if seat.is_played():
			total += 1
	return total

## Are the sides level? Reported rather than enforced, so a caller can show it.
func is_balanced() -> bool:
	var per_team: Dictionary[StringName, int] = {}
	for seat: LobbySeat in seats:
		if not seat.is_open():
			per_team[seat.team] = per_team.get(seat.team, 0) + 1
	var seen: int = -1
	for team_id: StringName in per_team:
		if seen >= 0 and per_team[team_id] != seen:
			return false
		seen = per_team[team_id]
	return true
