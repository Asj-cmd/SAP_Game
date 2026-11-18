class_name GameAudio
extends Node
## Presentation-only sound (P5-3). Ordinary household sounds, nothing cartoon (D2).
##
## Never touched by `sim/`: GreyBoxMain spots events from the confirmed state and
## calls `play` / `footstep` here. Variants are chosen with this node's own RNG, never
## the simulation's. A missing file plays nothing (the art fallback rule), so a build
## without the audio folder, or the headless dummy driver, stays silent and error-free.
##
## World sounds are attenuated by hand against the listener (the chase camera) instead of
## AudioStreamPlayer3D: the seats live in SubViewports and the world is in centimetres.

const SFX_DIR: String = "res://art/audio/sfx/"
const MUSIC_PATH: String = "res://art/audio/music/loop.ogg"
const POOL_SIZE: int = 8
## Nothing farther than this (world units, 25 m) from the listener is heard.
const HEARING_RANGE: float = 2500.0
## One footstep per this much ground travelled.
const STEP_DISTANCE: float = 120.0
## Other bodies' sounds are never louder than the player's own steps.
const OTHER_BODY_DB: float = -5.0
const MUSIC_MENU_DB: float = 0.0
const MUSIC_MATCH_DB: float = -12.0

## The loop file has ~3.7 s of silence after its last note (measured, PT2-4): the music
## is sent back to the start here instead of waiting for it. 0 = play the whole file.
const MUSIC_LOOP_END: float = 128.3

## event -> {files: [names without .ogg], db: float, optional pitch: float, optional
## bus: StringName (default `DEFAULT_BUS`), optional path: a full res:// path that wins
## over SFX_DIR + file}. Each bus has its own volume slider (PT2-3).
const DEFAULT_BUS: StringName = &"SFX"
## The jail sound lives on its own in content/ so the user can swap in their own
## recording (HOW_TO_PLAY.md, "Changing the jail sound").
const JAILED_PATH: String = "res://content/sfx/jailed.ogg"
const EVENTS: Dictionary = {
	&"step": {"files": ["step_wood_1", "step_wood_2", "step_wood_3"], "db": -8.0, "bus": &"Footsteps"},
	&"grab": {"files": ["grab_1", "grab_2"], "db": -4.0},
	&"throw": {"files": ["throw"], "db": -3.0},
	&"seize": {"files": ["seize_thump", "seize_cloth"], "db": -2.0},
	&"free": {"files": ["free"], "db": -3.0},
	&"land": {"files": ["land"], "db": -6.0},
	&"cash": {"files": ["cash_1", "cash_2"], "db": -4.0},
	&"sting": {"files": ["sting"], "db": -6.0},
	# PT2-4: match end, heard by the local seat's family only (Kenney pizzicato jingles,
	# on the Music bus so the Music slider sets them), and the jail "boink" (REVIEW).
	&"win": {"files": ["jingle_win"], "db": -3.0, "bus": &"Music", "path": "res://art/audio/music/jingle_win.ogg"},
	&"lose": {"files": ["jingle_lose"], "db": -3.0, "bus": &"Music", "path": "res://art/audio/music/jingle_lose.ogg"},
	&"jailed": {"files": ["jailed"], "db": -3.0, "path": JAILED_PATH},
	# PT2-2: a carrier spotted by the family whose cash it holds. Placeholder: the
	# sting, pitched up; PT2-4 may give it its own file.
	&"spotted": {"files": ["sting"], "db": -5.0, "pitch": 1.25},
	&"tick": {"files": ["tick"], "db": -8.0},
	&"ui": {"files": ["ui_click"], "db": -8.0},
}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _streams: Dictionary[String, AudioStream] = {} # by res:// path
var _pool: Array[AudioStreamPlayer] = []
var _ui: AudioStreamPlayer = null
var _music: AudioStreamPlayer = null
var _listener: Vector3 = Vector3.ZERO
var _has_listener: bool = false

# Per-body footstep and landing state, and the match-level trackers.
var _step_last: Dictionary[int, Vector3] = {}
var _step_travel: Dictionary[int, float] = {}
var _air_frames: Dictionary[int, int] = {}
var _scores: Dictionary[StringName, int] = {}
var _phase: int = -1
var _last_count_second: int = -1

func _ready() -> void:
	_rng.randomize()
	for i: int in POOL_SIZE:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_pool.append(player)
	_ui = AudioStreamPlayer.new()
	_ui.bus = &"SFX"
	add_child(_ui)
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	add_child(_music)
	if ResourceLoader.exists(MUSIC_PATH):
		var loop: AudioStream = load(MUSIC_PATH) as AudioStream
		if loop is AudioStreamOggVorbis:
			(loop as AudioStreamOggVorbis).loop = true
		_music.stream = loop
		_music.volume_db = MUSIC_MENU_DB
		_music.play()
	# Every button in every panel clicks, whoever builds it.
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(func() -> void: play_ui())

func _process(_delta: float) -> void:
	if MUSIC_LOOP_END > 0.0 and _music != null and _music.playing \
			and _music.get_playback_position() >= MUSIC_LOOP_END:
		_music.seek(0.0)

func set_in_match(in_match: bool) -> void:
	if _music != null:
		_music.volume_db = MUSIC_MATCH_DB if in_match else MUSIC_MENU_DB

func set_listener(position: Vector3) -> void:
	_listener = position
	_has_listener = true

func play_ui() -> void:
	var stream: AudioStream = _pick(&"ui")
	if stream != null:
		_ui.stream = stream
		_ui.volume_db = float(EVENTS[&"ui"]["db"])
		_ui.play()

## A world sound at `at`. `own` marks the local player's body, heard at full level.
func play(event: StringName, at: Vector3, own: bool = false) -> void:
	var distance: float = 0.0
	if _has_listener:
		distance = Vector2(at.x - _listener.x, at.z - _listener.z).length()
		if distance > HEARING_RANGE:
			return
	var stream: AudioStream = _pick(event)
	if stream == null:
		return
	var player: AudioStreamPlayer = _free_player()
	if player == null:
		return
	var db: float = float(EVENTS[event]["db"])
	if not own:
		db += OTHER_BODY_DB
	# Plain linear fall-off to silence at the edge of hearing.
	db += linear_to_db(maxf(1.0 - distance / HEARING_RANGE, 0.001))
	player.stream = stream
	player.bus = _bus_of(event)
	player.volume_db = db
	player.pitch_scale = _rng.randf_range(0.94, 1.06)
	player.play()

## A sound with no place: cash banked, the sting, the countdown.
func play_flat(event: StringName) -> void:
	var stream: AudioStream = _pick(event)
	var player: AudioStreamPlayer = _free_player()
	if stream == null or player == null:
		return
	player.stream = stream
	player.bus = _bus_of(event)
	player.volume_db = float(EVENTS[event]["db"])
	player.pitch_scale = float(EVENTS[event].get("pitch", 1.0))
	player.play()

## Called once per body per frame with where it is and whether it is walking on the floor.
## One step per STEP_DISTANCE travelled; landing after more than a few frames in the air.
func body(entity_id: int, position: Vector3, grounded: bool, walking: bool, own: bool) -> void:
	var last: Vector3 = _step_last.get(entity_id, position)
	_step_last[entity_id] = position
	var moved: float = Vector2(position.x - last.x, position.z - last.z).length()
	if moved > 300.0:
		moved = 0.0 # a respawn or a snap, not a walk
	if grounded and walking:
		var travelled: float = _step_travel.get(entity_id, 0.0) + moved
		if travelled >= STEP_DISTANCE:
			travelled = fmod(travelled, STEP_DISTANCE)
			play(&"step", position, own)
		_step_travel[entity_id] = travelled
	if grounded:
		if _air_frames.get(entity_id, 0) > 8 and walking:
			play(&"land", position, own)
		_air_frames[entity_id] = 0
	else:
		_air_frames[entity_id] = _air_frames.get(entity_id, 0) + 1

## Match-level sounds from the confirmed world: a deposit, the countdown, round/match end.
## `local_team` is the family of the seat this machine plays (&"" for none, e.g. a
## dedicated host): at MATCH_END it hears the win or lose jingle, nobody else anything.
func match_state(world: SimWorld, local_team: StringName = &"") -> void:
	for team_id: StringName in world.teams:
		var score: int = world.score_for(team_id)
		if _scores.has(team_id) and score > _scores[team_id]:
			play_flat(&"cash")
		_scores[team_id] = score
	var phase: int = int(world.match_phase)
	if phase != _phase:
		if phase == SimWorld.MatchPhase.ROUND_END:
			play_flat(&"sting")
		elif phase == SimWorld.MatchPhase.MATCH_END and _phase != -1:
			# The one call site for the match-end jingle (PT2-7 may move it into its
			# end sequence). `_phase != -1`: joining a match that already ended is silent.
			_match_end_jingle(world.match_winner, local_team)
		_last_count_second = -1
		_phase = phase
	if phase == SimWorld.MatchPhase.COUNTDOWN:
		var second: int = int(ceil(SimWorld.ticks_to_seconds(world.phase_ticks_remaining)))
		if second != _last_count_second:
			if _last_count_second != -1:
				play_flat(&"tick")
			_last_count_second = second

func _match_end_jingle(winner: StringName, local_team: StringName) -> void:
	if local_team == &"":
		return
	if winner == &"":
		play_flat(&"sting") # no winner: the plain round-end sting
	else:
		play_flat(&"win" if winner == local_team else &"lose")

## Forget per-body and match state (a new match starts).
func reset() -> void:
	_step_last.clear()
	_step_travel.clear()
	_air_frames.clear()
	_scores.clear()
	_phase = -1
	_last_count_second = -1

func _pick(event: StringName) -> AudioStream:
	var row: Dictionary = EVENTS.get(event, {})
	if row.is_empty():
		return null
	var files: Array = row["files"]
	var file: String = files[_rng.randi_range(0, files.size() - 1)]
	var path: String = String(row.get("path", SFX_DIR + file + ".ogg"))
	if _streams.has(path):
		return _streams[path]
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path) as AudioStream
	if stream != null:
		_streams[path] = stream
	return stream

func _bus_of(event: StringName) -> StringName:
	var row: Dictionary = EVENTS.get(event, {})
	return StringName(row.get("bus", DEFAULT_BUS))

func _free_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _pool:
		if not player.playing:
			return player
	return null
