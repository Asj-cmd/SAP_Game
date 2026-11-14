class_name TeamTell
extends Resource
## How a player tells their own family from the other one (DECISIONS D3, an
## EXPERIMENT; STYLE §2.4; PLAN P2-4). Four options, any combination:
##
##   marker     (a) a small mark over YOUR OWN teammates only, never over enemies
##   minimap    (b) a corner map that shows only your own teammates (and you)
##   wristband  (c) both families identical except a band on the left wrist in
##                  the family colour
##   kid_swap   (d) family A's elder child is a girl and the younger a boy,
##                  family B the reverse (the theme's `family_order_by_team`)
##
## The goal D3 sets: a STILL enemy should be hard to tell from your own family.
##
## Presentation only, and per machine: nothing here reaches the simulation or
## the network, so two players in one match may use different settings. Where a
## setting comes from, later winning: the shipped default
## (`art/theme/team_tell.tres`), the player's saved choice (`user://settings.cfg`,
## written by the menu and the F5-F8 keys), then `--team-tell=` on the command
## line (`none`, or a comma list of the option names), which is never saved.

const DEFAULT_PATH: String = "res://art/theme/team_tell.tres"
const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION: String = "team_tell"
## Option names, in the order the menu and the debug keys list them.
const OPTIONS: Array[StringName] = [&"marker", &"minimap", &"wristband", &"kid_swap"]

@export var marker: bool = false
@export var minimap: bool = true
@export var wristband: bool = true
@export var kid_swap: bool = false

static var _current: TeamTell = null

## The setting in force on this machine.
static func current() -> TeamTell:
	if _current == null:
		_current = _load()
	return _current

static func _load() -> TeamTell:
	var made: TeamTell = null
	if ResourceLoader.exists(DEFAULT_PATH):
		var shipped: TeamTell = load(DEFAULT_PATH) as TeamTell
		if shipped != null:
			made = shipped.duplicate() as TeamTell
	if made == null:
		made = TeamTell.new()
	var saved: ConfigFile = ConfigFile.new()
	if not _transient() and saved.load(SETTINGS_PATH) == OK:
		for option: StringName in OPTIONS:
			made.set(option, bool(saved.get_value(SECTION, String(option), made.get(option))))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--team-tell="):
			made.apply_list(arg.trim_prefix("--team-tell="))
	return made

## Sets every option from a comma list ("minimap,wristband"); "none" or "" = all off.
func apply_list(text: String) -> void:
	var wanted: PackedStringArray = text.split(",", false)
	for option: StringName in OPTIONS:
		set(option, wanted.has(String(option)))

func is_on(option: StringName) -> bool:
	return bool(get(option))

## Flips one option and saves the result for next time.
func toggle(option: StringName) -> void:
	set_option(option, not is_on(option))

func set_option(option: StringName, on: bool) -> void:
	if not OPTIONS.has(option):
		return
	set(option, on)
	save()

## An unattended run (any `--capture` flag, the pilot, the net smoke) neither
## reads nor writes the player's saved choice, so its frames depend only on its
## command line: a key a tool injects must not change the next run.
static func _transient() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture") or arg.begins_with("--pilot") or arg.begins_with("--net-smoke"):
			return true
	return false

func save() -> void:
	if _transient():
		return
	var saved: ConfigFile = ConfigFile.new()
	saved.load(SETTINGS_PATH)  # keep any other section; a missing file is fine
	for option: StringName in OPTIONS:
		saved.set_value(SECTION, String(option), is_on(option))
	saved.save(SETTINGS_PATH)

## "minimap + wristband", or "none".
func describe() -> String:
	var on: PackedStringArray = PackedStringArray()
	for option: StringName in OPTIONS:
		if is_on(option):
			on.append(label(option))
	return " + ".join(on) if not on.is_empty() else "none"

static func label(option: StringName) -> String:
	match option:
		&"marker":
			return "teammate marker"
		&"kid_swap":
			return "kid swap"
	return String(option)
