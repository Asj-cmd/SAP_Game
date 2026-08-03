class_name LobbySeat
extends RefCounted
## One place in the match, and who is currently in it.
##
## A seat outlives whoever is sitting in it. That is the whole reason it exists
## as its own thing: a player dropping out, a bot holding the place, and the
## player coming back are three changes to ONE seat, not three different seats.
## The actor in the world never changes, so nothing downstream has to care.

enum Occupancy {
	EMPTY, ## Nobody, and no bot either.
	HUMAN, ## A player is driving it.
	BOT, ## A bot is driving it - lobby fill, or holding it for someone.
}

enum Presence {
	PRESENT, ## Connected and playing.
	HICCUP, ## Gone, but inside the grace window. Nothing has happened yet.
	VACATED, ## Gone past the grace window. A bot has the seat.
}

var team: StringName = &""
var slot: int = 0
## The body in the world. Fixed for the life of the match.
var actor_id: int = SimEntity.NO_ENTITY

var occupancy: Occupancy = Occupancy.EMPTY
var presence: Presence = Presence.PRESENT

## Transport id of whoever is in it. CHANGES on reconnect - a peer id names a
## connection, not a person.
var peer: int = 0
## Stable across reconnects: the thing a returning player is recognised by.
## Steam supplies it; ENet has nothing like it, so the client presents one.
var identity: String = ""
var display_name: String = ""
## Whose seat this really is while a bot is keeping it warm. Empty once the seat
## belongs to the bot outright (a lobby fill rather than a takeover).
var held_for: String = ""
## Tick the current hiccup began, for the grace countdown. -1 when present.
var absent_since: int = -1

static func make(seat_team: StringName, seat_slot: int, actor: int) -> LobbySeat:
	var seat: LobbySeat = LobbySeat.new()
	seat.team = seat_team
	seat.slot = seat_slot
	seat.actor_id = actor
	return seat

func is_open() -> bool:
	return occupancy == Occupancy.EMPTY

## Is a human actually playing it right now?
func is_played() -> bool:
	return occupancy == Occupancy.HUMAN and presence == Presence.PRESENT

## Is a bot standing in for someone who is expected back?
func is_being_held() -> bool:
	return occupancy == Occupancy.BOT and held_for != ""

func describe() -> String:
	var who: String = display_name if display_name != "" else "-"
	return "%s[%d] %s %s %s" % [
		team, slot, Occupancy.keys()[occupancy], Presence.keys()[presence], who,
	]
