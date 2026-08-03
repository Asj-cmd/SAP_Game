class_name PlayerIdentity
extends RefCounted
## Who a player is, across connections.
##
## A peer id names a CONNECTION. Reconnecting gets you a new one, so keying a
## seat on it means a returning player is a stranger: they are handed a fresh
## seat while a bot sits in their old one for the rest of the match, and from
## the inside it looks like the game forgot them. The lobby has always matched
## on a stable identity; until now nothing was supplying one.
##
## So: a random token, minted once and kept. It is not a login and proves
## nothing - it only has to be the same value next time, which is exactly the
## job. On a dropped Tailscale session that is the difference between walking
## back into your own match and watching a bot play it.
##
## THIS IS THE SLOT A STEAM ID OCCUPIES LATER. When the Steam backend lands, its
## identity comes with the connection, already authenticated, and local() stops
## being called. Nothing above changes, because nothing above ever cared where
## the token came from.
##
## Deliberately NOT authenticated. Anyone who knows a token could claim that
## seat, which is fine for a private playtest over a mesh VPN between people who
## know each other, and is not fine for shipping. Steam is what fixes it, and
## the fix is a backend rather than a redesign.

const PATH: String = "user://player.cfg"
const SECTION: String = "player"
const KEY: String = "token"
## 128 bits. Long enough that two playtesters never collide.
const BYTES: int = 16
## A ceiling for anything arriving off the wire. A Steam id is far shorter than
## this; a token this long is somebody probing.
const MAX_LENGTH: int = 64

## This machine's token, minting and storing one the first time it is asked.
static func local() -> String:
	var config: ConfigFile = ConfigFile.new()
	if config.load(PATH) == OK:
		var stored: String = str(config.get_value(SECTION, KEY, ""))
		if is_acceptable(stored):
			return stored

	var minted: String = mint()
	config.set_value(SECTION, KEY, minted)
	# A save that fails is not fatal: the match still works, the player simply
	# becomes a stranger if they drop. Worth a warning, not a refusal to play.
	if config.save(PATH) != OK:
		push_warning("identity: could not store a token - a reconnect will not reclaim its seat")
	return minted

static func mint() -> String:
	var crypto: Crypto = Crypto.new()
	return crypto.generate_random_bytes(BYTES).hex_encode()

## Is this something we are willing to treat as an identity?
##
## Everything off the wire is untrusted, including this. The check is a shape
## check rather than a validity check - there is nothing to validate against -
## so it only refuses the obviously malformed: nothing at all, or something long
## enough to be an attempt at the seat table.
static func is_acceptable(token: String) -> bool:
	return token.length() > 0 and token.length() <= MAX_LENGTH
