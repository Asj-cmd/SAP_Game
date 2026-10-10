class_name NetworkAddress
extends RefCounted
## Which of this machine's addresses another player can actually reach.
##
## The join code CONTAINS the host's address (LobbyCode), so the address it is
## built from decides whether anybody can use it. Getting it wrong is the most
## common way a first networked session fails, and it fails silently - the
## guest just waits. PLAYTEST.md used to ask the host to look their Tailscale
## address up and type it on a command line; this does the looking.
##
## Preference, best first:
##
##   Tailscale (100.64.0.0/10)  reachable by anyone on the same tailnet, which
##                              is how two homes reach each other today
##   home network (10/8, 172.16/12, 192.168/16)
##                              reachable from the same house only
##   127.0.0.1                  this computer only - a second window
##
## Presentation-side and advisory. The menu pre-fills the result and the player
## can overwrite it.

static func best() -> Dictionary:
	var lan: String = ""
	for address: String in IP.get_local_addresses():
		if not _is_ipv4(address):
			continue
		if _is_tailscale(address):
			return {
				"address": address,
				"note": "Tailscale address - friends on your tailnet can join from home.",
			}
		if lan == "" and _is_private(address):
			lan = address
	if lan != "":
		return {
			"address": lan,
			"note": "Home-network address - only players in the same house can join. "
				+ "For friends elsewhere, run Tailscale on both computers.",
		}
	return {
		"address": "127.0.0.1",
		"note": "No network found - only a second window on this computer can join.",
	}

static func _is_ipv4(address: String) -> bool:
	return address.count(".") == 3 and not address.contains(":")

static func _octets(address: String) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for part: String in address.split("."):
		out.append(part.to_int())
	return out

static func _is_tailscale(address: String) -> bool:
	var o: PackedInt32Array = _octets(address)
	return o[0] == 100 and o[1] >= 64 and o[1] <= 127

static func _is_private(address: String) -> bool:
	var o: PackedInt32Array = _octets(address)
	return o[0] == 10 \
		or (o[0] == 172 and o[1] >= 16 and o[1] <= 31) \
		or (o[0] == 192 and o[1] == 168)
