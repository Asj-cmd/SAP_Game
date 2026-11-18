class_name PlayerSettings
extends RefCounted
## What this player chose on this machine: mouse sensitivity, volumes, keyboard keys.
##
## Saved in `user://settings.cfg` in its own sections ([controls], [audio], [keys]);
## TeamTell keeps its section in the same file and this never touches it. Capture
## runs, the pilot and the net smoke neither read nor write it, so injected default
## keys keep working (the same rule as TeamTell).
##
## Presentation only. The simulation never sees any of it.

const PATH: String = "user://settings.cfg"

const SENSITIVITY_MIN: float = 0.25
const SENSITIVITY_MAX: float = 3.0

## Keyboard actions, in the order the settings screen lists them, and their labels.
const ACTIONS: Array[StringName] = [&"forward", &"back", &"left", &"right", &"jump", &"crouch", &"seize", &"free"]
const ACTION_LABELS: Dictionary[StringName, String] = {
	&"forward": "Forward", &"back": "Back", &"left": "Left", &"right": "Right",
	&"jump": "Jump", &"crouch": "Crouch (hold)", &"seize": "Seize / free", &"free": "Free",
}
const DEFAULT_KEYS: Dictionary[StringName, int] = {
	&"forward": KEY_W, &"back": KEY_S, &"left": KEY_A, &"right": KEY_D,
	&"jump": KEY_SPACE, &"crouch": KEY_SHIFT, &"seize": KEY_E, &"free": KEY_R,
}

## Multiplier on ChaseCamera.MOUSE_SENSITIVITY.
var sensitivity: float = 1.0
var master_volume: float = 1.0
var effects_volume: float = 1.0
var music_volume: float = 0.6
## Footsteps have their own bus and slider (PT2-3); 0 turns them off.
const FOOTSTEPS_DEFAULT: float = 0.4
var footsteps_volume: float = FOOTSTEPS_DEFAULT
var keys: Dictionary[StringName, int] = DEFAULT_KEYS.duplicate()
## The first-run guide has been finished (or skipped) on this machine.
var guide_done: bool = false

## Graphics presets (P7-2). `shadow_size` -1 = the theme's own size, 0 = sun shadow
## off; `scale` is the 3D render scale. MSAA stays off in every preset (D6).
const QUALITY_NAMES: Array[String] = ["low", "medium", "high"]
const QUALITY: Dictionary = {
	"high": {"shadow_size": -1, "scale": 1.0},
	"medium": {"shadow_size": 1024, "scale": 1.0},
	"low": {"shadow_size": 0, "scale": 0.75},
}
const MAX_FPS_CHOICES: Array[int] = [0, 30, 60, 120]

var quality: String = "high"
var fullscreen: bool = false
var vsync: bool = true
var max_fps: int = 0

static var _current: PlayerSettings = null

static func current() -> PlayerSettings:
	if _current == null:
		_current = PlayerSettings.new()
		_current._load()
	return _current

static func transient() -> bool:
	return _transient()

static func _transient() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture") or arg.begins_with("--pilot") or arg.begins_with("--net-smoke"):
			return true
	return false

func key_for(action: StringName) -> int:
	return keys.get(action, DEFAULT_KEYS[action])

func set_key(action: StringName, keycode: int) -> void:
	if ACTIONS.has(action):
		keys[action] = keycode
		save()

func reset_keys() -> void:
	keys = DEFAULT_KEYS.duplicate()
	save()

func set_sensitivity(value: float) -> void:
	sensitivity = clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)
	save()

## Which bus a slider drives.
func set_volume(bus: StringName, value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	match bus:
		&"Master":
			master_volume = value
		&"SFX":
			effects_volume = value
		&"Music":
			music_volume = value
		&"Footsteps":
			footsteps_volume = value
	apply_audio()
	save()

func volume_of(bus: StringName) -> float:
	match bus:
		&"Master":
			return master_volume
		&"SFX":
			return effects_volume
		&"Footsteps":
			return footsteps_volume
	return music_volume

## The buses a volume slider drives.
const AUDIO_BUSES: Array[StringName] = [&"Master", &"SFX", &"Music", &"Footsteps"]

## Pushes the volumes to the audio buses (a missing bus is skipped; 0 mutes it).
func apply_audio() -> void:
	for bus: StringName in AUDIO_BUSES:
		var index: int = AudioServer.get_bus_index(bus)
		if index >= 0:
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume_of(bus), 0.0001)))
			AudioServer.set_bus_mute(index, volume_of(bus) <= 0.0)

func set_quality(value: String) -> void:
	if QUALITY.has(value):
		quality = value
		apply_video()
		save()

func set_fullscreen(value: bool) -> void:
	fullscreen = value
	apply_video()
	save()

func set_vsync(value: bool) -> void:
	vsync = value
	apply_video()
	save()

func set_max_fps(value: int) -> void:
	max_fps = value
	apply_video()
	save()

## `--quality=low|medium|high` wins over the saved value, also in capture runs.
func _quality_override() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--quality=") and QUALITY.has(arg.substr(10)):
			quality = arg.substr(10)

## Sun shadow atlas size for the current preset (0 = off).
func shadow_size(theme_size: int) -> int:
	var size: int = int(QUALITY[quality]["shadow_size"])
	return theme_size if size < 0 else mini(size, theme_size)

## Pushes quality, window mode, vsync and the frame cap to the engine. Window
## settings are left alone in capture / pilot / net-smoke runs.
func apply_video() -> void:
	WorldBackdrop.apply_quality(shadow_size(ArtTheme.current().sun_shadow_size))
	var scale: float = float(QUALITY[quality]["scale"])
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		for node: Node in tree.get_nodes_in_group(&"seat_viewport"):
			var viewport: Viewport = node as Viewport
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			viewport.scaling_3d_scale = scale
	if _transient():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen \
		else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync \
		else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps

func _load() -> void:
	if _transient():
		_quality_override()
		return
	load_from(PATH)
	_quality_override()

## Reads every saved value from `path`; a missing file leaves the defaults. Returns
## whether the file was read. Separate from `_load` so a test can use its own file.
func load_from(path: String) -> bool:
	var file: ConfigFile = ConfigFile.new()
	if file.load(path) != OK:
		return false
	sensitivity = clampf(float(file.get_value("controls", "sensitivity", sensitivity)),
		SENSITIVITY_MIN, SENSITIVITY_MAX)
	master_volume = clampf(float(file.get_value("audio", "master", master_volume)), 0.0, 1.0)
	effects_volume = clampf(float(file.get_value("audio", "effects", effects_volume)), 0.0, 1.0)
	music_volume = clampf(float(file.get_value("audio", "music", music_volume)), 0.0, 1.0)
	footsteps_volume = clampf(float(file.get_value("audio", "footsteps", footsteps_volume)), 0.0, 1.0)
	guide_done = bool(file.get_value("firstrun", "guide_done", guide_done))
	var q: String = str(file.get_value("video", "quality", quality))
	quality = q if QUALITY.has(q) else "high"
	fullscreen = bool(file.get_value("video", "fullscreen", fullscreen))
	vsync = bool(file.get_value("video", "vsync", vsync))
	max_fps = int(file.get_value("video", "max_fps", max_fps))
	for action: StringName in ACTIONS:
		keys[action] = int(file.get_value("keys", String(action), keys[action]))
	return true

func save() -> void:
	if _transient():
		return
	save_to(PATH)

## Writes every value to `path`, keeping the file's other sections (TeamTell's).
func save_to(path: String) -> void:
	var file: ConfigFile = ConfigFile.new()
	file.load(path)  # keep other sections; a missing file is fine
	file.set_value("controls", "sensitivity", sensitivity)
	file.set_value("audio", "master", master_volume)
	file.set_value("audio", "effects", effects_volume)
	file.set_value("audio", "music", music_volume)
	file.set_value("audio", "footsteps", footsteps_volume)
	file.set_value("firstrun", "guide_done", guide_done)
	file.set_value("video", "quality", quality)
	file.set_value("video", "fullscreen", fullscreen)
	file.set_value("video", "vsync", vsync)
	file.set_value("video", "max_fps", max_fps)
	for action: StringName in ACTIONS:
		file.set_value("keys", String(action), keys[action])
	file.save(path)
