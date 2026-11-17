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
var keys: Dictionary[StringName, int] = DEFAULT_KEYS.duplicate()
## The first-run guide has been finished (or skipped) on this machine.
var guide_done: bool = false

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
	apply_audio()
	save()

func volume_of(bus: StringName) -> float:
	match bus:
		&"Master":
			return master_volume
		&"SFX":
			return effects_volume
	return music_volume

## Pushes the three volumes to the audio buses (a missing bus is skipped).
func apply_audio() -> void:
	for bus: StringName in [&"Master", &"SFX", &"Music"]:
		var index: int = AudioServer.get_bus_index(bus)
		if index >= 0:
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume_of(bus), 0.0001)))
			AudioServer.set_bus_mute(index, volume_of(bus) <= 0.0)

func _load() -> void:
	if _transient():
		return
	var file: ConfigFile = ConfigFile.new()
	if file.load(PATH) != OK:
		return
	sensitivity = clampf(float(file.get_value("controls", "sensitivity", sensitivity)),
		SENSITIVITY_MIN, SENSITIVITY_MAX)
	master_volume = clampf(float(file.get_value("audio", "master", master_volume)), 0.0, 1.0)
	effects_volume = clampf(float(file.get_value("audio", "effects", effects_volume)), 0.0, 1.0)
	music_volume = clampf(float(file.get_value("audio", "music", music_volume)), 0.0, 1.0)
	guide_done = bool(file.get_value("firstrun", "guide_done", guide_done))
	for action: StringName in ACTIONS:
		keys[action] = int(file.get_value("keys", String(action), keys[action]))

func save() -> void:
	if _transient():
		return
	var file: ConfigFile = ConfigFile.new()
	file.load(PATH)  # keep other sections; a missing file is fine
	file.set_value("controls", "sensitivity", sensitivity)
	file.set_value("audio", "master", master_volume)
	file.set_value("audio", "effects", effects_volume)
	file.set_value("audio", "music", music_volume)
	file.set_value("firstrun", "guide_done", guide_done)
	for action: StringName in ACTIONS:
		file.set_value("keys", String(action), keys[action])
	file.save(PATH)
