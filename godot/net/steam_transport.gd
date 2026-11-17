class_name SteamTransport
extends SessionTransport
## Sessions over a Steam lobby, bytes over Steam Networking Messages.
##
## Talks to Steam ONLY through `steam`, an injected Object (the GodotSteam
## singleton in the game, a fake in tests). The `Steam` class name never appears
## in code, so the project parses and runs with no addon installed; without it
## every call here fails cleanly through the usual SESSION_FAILED path.
##
## Peer ids are the transport's: the host is HOST_PEER and gives each Steam id
## the next int from 2 in join order, over a tiny handshake (guest HELLO, host
## WELCOME <id>). Every packet carries one reserved first byte, so a handshake
## can never be mistaken for a payload and nothing here reaches MatchChannel
## unframed. Steam ids never leave this file.
##
## Untested against live Steam (BLOCKED.md): the GodotSteam call and signal
## names below follow its 4.x documentation and are exercised by a fake only.

const _BACKEND: StringName = &"steam"
const MAX_MEMBERS: int = 8
const LOBBY_FRIENDS_ONLY: int = 1
const _ENTER_SUCCESS: int = 1
const _CHANNEL: int = 0
const _SEND_UNRELIABLE: int = 0
const _SEND_RELIABLE: int = 8
const _JOIN_TIMEOUT_MS: int = 15000
const _TAG_PAYLOAD: int = 0
const _TAG_HELLO: int = 1
const _TAG_WELCOME: int = 2
const NO_STEAM: String = "Steam is not available (GodotSteam not installed or Steam not running)"

var steam: Object = null

var _state: State = State.IDLE
var _failure: String = ""
var _inbox: Array[NetEvent] = []
var _lobby: int = 0
var _me: int = 0
var _owner: int = 0
var _local: int = 0
var _becomes_ready: bool = false
var _joining_since: int = 0
var _next_peer: int = HOST_PEER + 1
## steam id -> peer id, and back (host only).
var _peer_of: Dictionary[int, int] = {}
var _steam_of: Dictionary[int, int] = {}

func _init(injected: Object = null) -> void:
	steam = injected if injected != null else _singleton()
	if steam != null:
		_connect_signal("lobby_created", _on_lobby_created)
		_connect_signal("lobby_joined", _on_lobby_joined)
		_connect_signal("lobby_chat_update", _on_chat_update)
		_connect_signal("network_messages_session_request", _on_session_request)

## True when a Steam singleton is present (the add-on is installed). It says
## nothing about whether the Steam client is running; a failed host/join does.
static func available() -> bool:
	return _singleton() != null

static func _singleton() -> Object:
	return Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null

func backend_name() -> StringName:
	return _BACKEND

func host_session() -> SessionHandle:
	if steam == null:
		_fail(NO_STEAM)
		return SessionHandle.new()
	_state = State.OPENING
	steam.call("createLobby", LOBBY_FRIENDS_ONLY, MAX_MEMBERS)
	# The handle must exist before the session does, and the lobby id is the
	# handle: wait (bounded) for Steam to answer rather than hand out nothing.
	var deadline: int = Time.get_ticks_msec() + 5000
	while _lobby == 0 and _state == State.OPENING and Time.get_ticks_msec() < deadline:
		steam.call("run_callbacks")
		if _lobby == 0:
			OS.delay_msec(5)
	if _lobby == 0:
		if _state == State.OPENING:
			_fail("Steam did not create a lobby")
		return SessionHandle.new()
	return SessionHandle.new(_BACKEND, str(_lobby))

func join_session(handle: SessionHandle) -> void:
	if not handle.is_for(_BACKEND):
		_fail("handle is not a %s session" % _BACKEND)
		return
	if steam == null:
		_fail(NO_STEAM)
		return
	if not handle.token.is_valid_int():
		_fail("malformed session token")
		return
	_state = State.OPENING
	_joining_since = Time.get_ticks_msec()
	_lobby = int(handle.token)
	_me = int(steam.call("getSteamID"))
	steam.call("joinLobby", _lobby)

func state() -> State:
	return _state

func failure() -> String:
	return _failure

func local_peer() -> int:
	return _local if _state == State.READY else 0

func peers() -> PackedInt32Array:
	var found: PackedInt32Array = PackedInt32Array()
	if _state != State.READY:
		return found
	if is_host():
		for peer_id: int in _steam_of:
			found.append(peer_id)
	else:
		found.append(HOST_PEER)
	found.sort()
	return found

func send(peer: int, payload: PackedByteArray, delivery: Delivery = Delivery.RELIABLE) -> void:
	if _state != State.READY:
		return
	var target: int = _owner if not is_host() else int(_steam_of.get(peer, 0))
	if target == 0:
		return # gone; not an error
	_send_to(target, _TAG_PAYLOAD, payload, delivery == Delivery.RELIABLE)

func poll() -> Array[NetEvent]:
	if steam != null:
		steam.call("run_callbacks")
		if _becomes_ready:
			_becomes_ready = false
			_state = State.READY
			_inbox.append(NetEvent.session_ready(_local))
		if _state == State.OPENING and not is_host() and _joining_since > 0 \
			and Time.get_ticks_msec() - _joining_since > _JOIN_TIMEOUT_MS:
			_fail("could not reach the Steam lobby in time")
		if _state == State.READY or _state == State.OPENING:
			_drain_messages()
	var drained: Array[NetEvent] = _inbox.duplicate()
	_inbox.clear()
	return drained

func close() -> void:
	if steam != null and _lobby != 0:
		steam.call("leaveLobby", _lobby)
	_peer_of.clear()
	_steam_of.clear()
	_local = 0
	_lobby = 0
	_state = State.CLOSED

# ---- steam callbacks ----

func _on_lobby_created(result: int, lobby_id: int) -> void:
	if result != 1: # k_EResultOK
		_fail("Steam could not create a lobby (result %d)" % result)
		return
	_lobby = lobby_id
	_me = int(steam.call("getSteamID"))
	_owner = _me
	_local = HOST_PEER
	_becomes_ready = true

func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if lobby_id != _lobby or is_host():
		return
	if response != _ENTER_SUCCESS:
		_fail("Steam refused the lobby (response %d)" % response)
		return
	_owner = int(steam.call("getLobbyOwner", _lobby))
	_send_to(_owner, _TAG_HELLO, PackedByteArray(), true)

## state bits: 1 entered; anything else (left, disconnected, kicked, banned) is a departure.
func _on_chat_update(lobby_id: int, changed_id: int, _making_change_id: int, chat_state: int) -> void:
	if lobby_id != _lobby or chat_state == 1:
		return
	if is_host():
		if _peer_of.has(changed_id):
			var peer_id: int = _peer_of[changed_id]
			_peer_of.erase(changed_id)
			_steam_of.erase(peer_id)
			_inbox.append(NetEvent.peer_left(peer_id))
	elif changed_id == _owner and _state == State.READY:
		_state = State.CLOSED
		_inbox.append(NetEvent.peer_left(HOST_PEER, "host went away"))

func _on_session_request(remote: Variant) -> void:
	steam.call("acceptSessionWithUser", remote)

# ---- bytes ----

func _send_to(steam_id: int, tag: int, body: PackedByteArray, reliable: bool) -> void:
	var framed: PackedByteArray = PackedByteArray([tag])
	framed.append_array(body)
	steam.call("sendMessageToUser", steam_id, framed,
		_SEND_RELIABLE if reliable else _SEND_UNRELIABLE, _CHANNEL)

func _drain_messages() -> void:
	var messages: Array = steam.call("receiveMessagesOnChannel", _CHANNEL, 64)
	for message: Variant in messages:
		if not message is Dictionary:
			continue
		var packet: PackedByteArray = (message as Dictionary).get("payload", PackedByteArray())
		var from_id: int = int((message as Dictionary).get("identity", 0))
		if packet.is_empty() or from_id == 0:
			continue
		var body: PackedByteArray = packet.slice(1)
		match packet[0]:
			_TAG_HELLO:
				if is_host() and _state == State.READY:
					_admit(from_id)
			_TAG_WELCOME:
				if not is_host() and _state == State.OPENING and from_id == _owner \
					and body.size() >= 2:
					_local = body[0] | (body[1] << 8)
					_state = State.READY
					_inbox.append(NetEvent.session_ready(_local))
					_inbox.append(NetEvent.peer_joined(HOST_PEER))
			_TAG_PAYLOAD:
				if is_host():
					if _peer_of.has(from_id):
						_inbox.append(NetEvent.payload_from(_peer_of[from_id], body))
				elif from_id == _owner:
					_inbox.append(NetEvent.payload_from(HOST_PEER, body))
			_:
				pass # unknown framing: dropped, never guessed at

func _admit(steam_id: int) -> void:
	var assigned: int = int(_peer_of.get(steam_id, 0))
	if assigned == 0:
		assigned = _next_peer
		_next_peer += 1
		_peer_of[steam_id] = assigned
		_steam_of[assigned] = steam_id
		_inbox.append(NetEvent.peer_joined(assigned))
	_send_to(steam_id, _TAG_WELCOME,
		PackedByteArray([assigned & 0xFF, (assigned >> 8) & 0xFF]), true)

func _connect_signal(signal_name: String, handler: Callable) -> void:
	if steam.has_signal(signal_name):
		steam.connect(signal_name, handler)

func _fail(why: String) -> void:
	_failure = why
	_state = State.FAILED
	_inbox.append(NetEvent.session_failed(why))
