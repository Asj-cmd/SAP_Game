class_name LobbyEvent
extends RefCounted
## Something the lobby decided. Reported, never performed.
##
## The lobby is a pure model: it holds seats and works out what should happen to
## them, and something else does it. That keeps it testable with no world, no
## transport and no bots, and it keeps the decisions in one readable place
## rather than spread across the code that acts on them.
##
## The caller turns these into actions - a takeover into BotCrew.take_over, a
## reclaim into BotCrew.release plus a snapshot.

enum Kind {
	SEAT_TAKEN, ## A player sat down (joined, or reclaimed their old seat).
	SEAT_FREED, ## A player left for good, or the lobby gave their seat up.
	TAKEOVER_DUE, ## Grace expired: a bot should take this seat now.
	RECLAIMED, ## The player came back. Release the bot and send a snapshot.
	BOTS_FILLED, ## Lobby fill placed bots on these seats.
	BOTS_DECLINED, ## Lobby fill placed none, because it could not stay even.
	ENDED, ## The match is over. See `reason`.
}

var kind: Kind = Kind.SEAT_TAKEN
var seat: LobbySeat = null
var reason: String = ""

static func about(event_kind: Kind, about_seat: LobbySeat, why: String = "") -> LobbyEvent:
	var event: LobbyEvent = LobbyEvent.new()
	event.kind = event_kind
	event.seat = about_seat
	event.reason = why
	return event

static func ended(why: String) -> LobbyEvent:
	var event: LobbyEvent = LobbyEvent.new()
	event.kind = Kind.ENDED
	event.reason = why
	return event

func _to_string() -> String:
	return "LobbyEvent(%s %s %s)" % [
		Kind.keys()[kind], seat.describe() if seat != null else "-", reason,
	]
