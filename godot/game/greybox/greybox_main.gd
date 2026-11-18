class_name GreyBoxMain
extends Node3D
## The grey-box playable slice: plain shapes, standard third-person controls.
##
## Purpose is a FEEL TEST, not a demo. It exists to settle safe-room variant A
## against variant B by playing them, and to tune movement before a house is
## modelled around numbers nobody has felt.
##
## SINGLE VIEW is the default, because the real game is online: one player, one
## camera, one mouse. Split-screen survives as a debug mode (F2) for watching
## two bodies at once while tuning, and it cannot be the default because a
## mouse cannot be shared - in that mode both seats need pads.
##
## The contract that matters here is one-directional (ARCHITECTURE.md §1). This
## layer READS simulation state and EMITS commands. It never writes into the
## world. The only physics in the scene belongs to the camera arm, and no rule
## ever consults it (§6).

## Presentation-only collision layer. The spring arm collides with these; the
## simulation has its own geometry and never asks the physics server anything.
const CAMERA_COLLISION_LAYER: int = 2

## Visual height of an actor capsule. The simulation models a body as a sphere
## of tuning.actor_radius, so the mesh is taller than the collider - a known
## simplification, called out because it is why the mesh needs a vertical
## offset to stand ON the floor rather than half-sunk into it.
const ACTOR_HEIGHT: float = 180.0
## Edge of the cube a carriable is drawn as.
##
## Named because _view_offset needs it: the simulation treats a carriable as a
## POINT, so a mesh centred on that point buries half of itself in whatever the
## point is resting on.
const CASH_SIZE: float = 50.0
## Where the modelled bundle lives. Absent until Blender has been run, which is
## a supported state - see _cash_model.
const CASH_MODEL: String = "res://art/models/cash.glb"
## A held bundle is drawn this far above the top of its carrier's head (see
## _hold_carried).
const CARRY_GAP: float = 12.0
## Per-team character models, absent until Blender has been run.
const ACTOR_MODEL: String = "res://art/models/character_%s.glb"
## How tall a crouched actor is drawn, as a fraction of standing.
##
## PRESENTATION ONLY. The simulation's crouch is a smaller collision sphere
## (MovementSystem._crouch_radius_scale); this is the mesh agreeing with it, so
## a crouched body LOOKS like it fits under the counter it actually fits under.
## Nothing here feeds back into the rules, and a Blender character with a real
## crouch pose replaces this by reading the same SimEntity.stance.
##
## 0.72, not the collider's 0.5. A person who ducks loses about a quarter of
## their height - they bend, they do not halve. Squashing a whole figure to the
## collider's ratio put the head at knee level and read as a body sunk into the
## floor rather than a crouch, which is the complaint this number answers. The
## two do not have to agree: the collider is a sphere and the drawing is a
## person, and only the collider decides what fits.
const CROUCH_VIEW_SCALE: float = 0.72
## How fast the capsule resizes toward its target height, per second.
##
## Smoothed rather than snapped because the stance flips in ONE tick and a mesh
## that halves instantly reads as a glitch rather than as ducking. Fast enough
## to stay honest about what the collider is doing - a body is only ever a few
## frames out of step with its own hitbox.
const CROUCH_VIEW_SPEED: float = 8.0
## How fast a drawn body turns to face its travel, per second. Fast enough that
## a change of direction does not look like drifting, slow enough that the
## turn is visible rather than instant.
const FACE_RATE: float = 12.0
## Drawn speed (units/s) under which a body keeps its facing (`_face`).
const FACE_MIN_SPEED: float = 40.0
## How proud of the floor a team's floor tint sits. Enough to win the depth
## test against the floor it is laid on, little enough not to be a step.
const PATCH_THICKNESS: float = 0.6
## How far below the top of a room's zone its ceiling lamp hangs: the slab
## above (40) plus a fitting's drop.
const CEILING_LAMP_DROP: float = 60.0

const SNAP_DISTANCE: float = 400.0
## How long a released bundle takes to go from the hands onto its sim arc (P4-2).
const RELEASE_BLEND: float = 0.25
## Confirmed states kept for interpolating remote bodies. A second or so: enough
## to ride out a late packet, short enough that nothing stale is ever drawn.
const CONFIRMED_HISTORY: int = 32
## Ceiling on catch-up steps in one frame. Without it a long stall makes the
## next frame simulate the whole gap, which stalls again.
const MAX_STEPS_PER_FRAME: int = 5

var world: SimWorld = null
var level: GreyBoxLevel = null
## Whichever end of the match this window is. Owns the transport, the lobby and
## the bots; presentation asks it where to draw and what is true.
var link: MatchLink = null
var players: Array[LocalPlayerInput] = []
## Bots filling the seats no local player took. On by default here because
## split-screen is a debug mode now, which makes this the only way to see the
## rules exercised by somebody other than yourself.
var _bots_enabled: bool = true

## The two most recent simulation states. Rendering interpolates between them,
## which lets a 30 Hz simulation drive any refresh rate without the simulation
## knowing a screen exists (§7).
var _previous: Dictionary[int, SimEntity] = {}
var _accumulator: float = 0.0

var _actor_views: Dictionary[int, MeshInstance3D] = {}
## Released-bundle blend (`_release_blend`): held last frame, gap, time left.
var _bundle_was_held: Dictionary[int, bool] = {}
var _release_gap: Dictionary[int, Vector3] = {}
var _release_left: Dictionary[int, float] = {}
## Loose-bundle tumble and bounce (P4-5): the spin/hop state, each bundle's drawn
## box in its own view space (the spin is about its middle), and where a
## tumbling bundle's resting point is drawn this frame (its contact shadow).
var _tumble: BundleTumble = BundleTumble.new()
var _bundle_boxes: Dictionary[int, AABB] = {}
var _bundle_base: Dictionary[int, Vector3] = {}
## Per drawn figure: its animation driver (P2-3), absent when the figure has no
## animation set (fallback models, capsules), and the confirmed state it was
## last driven from, to spot one-shots (_animate).
var _animators: Dictionary[int, FigureAnimator] = {}
var _anim_carrying: Dictionary[int, int] = {}
var _anim_captured: Dictionary[int, bool] = {}
var _anim_sentence: Dictionary[int, int] = {}
## Spotted startle (PT2-2), presentation only: per carrier, the bundle it held
## when last spotted and the tick that happened. Re-arms after SPOTTED_COOLDOWN,
## or at once when the carrier holds a different bundle (or none).
var _spotted_bundle: Dictionary[int, int] = {}
var _spotted_tick: Dictionary[int, int] = {}
## A defender of the cash's family this close (horizontal, units) and within
## SPOTTED_HEIGHT vertically spots the carrier. No line of sight test (REVIEW).
const SPOTTED_DISTANCE: float = 600.0
const SPOTTED_HEIGHT: float = 200.0
const SPOTTED_COOLDOWN: float = 8.0
var _anim_last_seen: Dictionary[int, Vector3] = {}
## `--anim-log`: print every one-shot as it fires (who, which, sim time), to find
## the moment a follow sheet should catch.
var _anim_log: bool = OS.get_cmdline_user_args().has("--anim-log")
## `--tumble-log`: print a tumbling bundle's sim point and drawn base every frame (P4-5).
var _tumble_log: bool = OS.get_cmdline_user_args().has("--tumble-log")
## The last figure each one-shot fired on (`throw`, `grab`, `seize`, `free`), for
## `--capture-follow=on:<one-shot>`.
var _anim_fired: Dictionary[StringName, int] = {}
## How far from a seized or freed body the actor who did it may be, to be
## animated reaching for it. Generous: the victim's last confirmed spot lags.
const INTERACT_REACH: float = 400.0
## Lift from the hands' midpoint (the wrist bones) to the carried bundle's base.
const CARRY_HAND_LIFT: float = 6.0
## Capsule height currently being drawn per actor, eased toward the stance's
## target. Presentation state, never read by a rule.
var _view_heights: Dictionary[int, float] = {}
## Which way each drawn body is pointing, eased toward its travel direction.
## Presentation state; no rule reads it.
var _facings: Dictionary[int, float] = {}
var _geometry: Node3D = null
var _seats: CanvasLayer = null
var _cameras: Array[ChaseCamera] = []
var _split_screen: bool = false
## Holds every on-screen text label, so a clean capture can hide them in one go.
var _text_layer: CanvasLayer = null
var _hud: Label = null
## One line shown while the debug HUD is hidden: how to get it back, plus the
## network status a host or guest cannot do without (the join code, connecting).
var _hud_hint: Label = null
## The debug HUD is a developer's view, not a player's: off by default, [F1]
## toggles it, `--debug-hud` starts with it on.
var _debug_hud_visible: bool = false
var _banner: Label = null
## Round, clock and score, always on (MatchStatus), and the big centred message
## between rounds and at the end of the match.
var _status: Label = null
var _headline: Label = null
var _match_hud: MatchHud = null
var _guide: FirstRunGuide = FirstRunGuide.new()
## The D3 team tell's marker and minimap (TeamTell, P2-4), on their own layer:
## they are the game's HUD, not debug text, so `--capture-hud` keeps them in a
## clean shot.
var _tell_layer: CanvasLayer = null
var _tell_overlay: TeamTellOverlay = null
## The team the overlay's map was turned for (re-set when this machine's seat
## changes team).
var _tell_team: StringName = &""
## Drawn-only capture stand-ins (`--capture-figure=...,team_b:2`), shown by the
## team tell like live bodies.
var _tell_extras: Array[TeamTellOverlay.Body] = []
## The disc under every body and loose bundle (ContactShadows, P3-5), and the
## drawn-only capture stand-ins and props that get one too (their feet are their
## origin; meta `shadow_radius`).
var _contact_shadows: ContactShadows = null
var _shadow_extras: Array[Node3D] = []
## Drawn height per actor's figure (its family member's), for the marker.
var _figure_heights: Dictionary[int, float] = {}
## Enter was pressed on the result screen; sent with the next tick.
var _rematch_asked: bool = false
## Marks that the local player has ASKED for something the host has not answered.
## The animation-on-input half of the split: the reach starts now, the outcome
## arrives when the host says so.
var _reach_marker: MeshInstance3D = null

## Confirmed states, kept so remote bodies can be drawn BETWEEN them.
##
## A guest is told where everyone else was, whenever packets happen to arrive.
## Drawing that straight is visible jitter. Drawing it a couple of ticks in the
## past means there is always a later state to interpolate towards - a few tens
## of milliseconds of staleness on other players, bought with smooth motion.
var _confirmed_frames: Array[Dictionary] = []
var _remote_clock: float = 0.0
var _seat_shown: int = SimEntity.NO_ENTITY

## Bot routes, drawn on request.
##
## Behaviour that cannot be seen gets diagnosed by staring at capsules and
## guessing - "the bot is stuck" becomes an argument about pathfinding when it
## is really about following. One marker per waypoint, and the one currently
## being steered towards is picked out, so the difference between a bad route
## and a bad follow is visible at a glance.
var _path_markers: Array[MeshInstance3D] = []
var _show_paths: bool = false

## How this window takes part in a match, and with what. Filled from the command
## line when one was given, otherwise from the menu - so the tools and the frame
## capture, which pass flags, never see the menu at all.
var _role: MatchLink.Role = MatchLink.Role.LOCAL
var _join_code: String = ""
var _advertise: String = ""
## Dedicated host (`--dedicated`, run with --headless): a host with no player of
## its own. It waits for a first guest, starts the match after a delay (bots
## fill the rest) and rematches by itself so the server keeps serving.
var _dedicated: bool = false
var _dedicated_wait: float = 15.0
var _dedicated_clock: float = -1.0 # counts down once the first guest is seated
var _dedicated_started: bool = false
var _dedicated_results: float = 0.0
var _identity: String = ""
var _backend: String = "enet"
## Bodies a side. From `--team-size=N` or the menu; a guest takes the host's
## (it is told with its seat and rejoins if it guessed wrong, see _rejoin_at).
var _team_size: int = GreyBoxLevel.DEFAULT_TEAM_SIZE
var _menu: MainMenu = null
var _pause: PauseMenu = null
var _results: ResultsPanel = null
## Started from the menu rather than from flags, so a failure goes back there
## with its reason instead of leaving a dead screen behind a banner.
var _from_menu: bool = false
## A menu-hosted match waits in the lobby panel until Start is pressed.
var _lobby_wait: bool = false
var _lobby: LobbyPanel = null

## Sound (P5-3): presentation only, fed from the confirmed state in `_animate` / `_render`.
var audio: GameAudio = GameAudio.new()

## Deadpan feedback (P5-4): event line, vanish puff, cut, camera nudge. Presentation only.
var feedback: GameFeedback = GameFeedback.new()
const NUDGE_LANDING: float = 6.0
const NUDGE_SEIZED: float = 12.0
var _fb_scores: Dictionary[StringName, int] = {}
var _fb_air: int = 0

func _ready() -> void:
	add_child(audio)
	_build_lighting()
	_build_hud()
	# The debug split can be asked for at startup as well as with F2, so an
	# unattended run can capture a frame of it. A mode nobody can screenshot is
	# a mode that quietly rots.
	_split_screen = OS.get_cmdline_user_args().has("--split")
	_read_command_line()
	_menu = MainMenu.new()
	add_child(_menu)
	_menu.solo_chosen.connect(_on_solo)
	_menu.host_chosen.connect(_on_host)
	_menu.join_chosen.connect(_on_join)
	_menu.host_steam_chosen.connect(_on_host_steam)
	SteamTransport.on_join_requested(_on_steam_invite)
	PlayerSettings.current().apply_audio()
	_lobby = LobbyPanel.new()
	add_child(_lobby)
	_lobby.start_pressed.connect(_lobby_start)
	_lobby.cancelled.connect(func() -> void: _return_to_menu(""))
	_pause = PauseMenu.new()
	add_child(_pause)
	_pause.resumed.connect(func() -> void: _set_paused(false))
	_pause.left.connect(func() -> void: _return_to_menu(""))
	_results = ResultsPanel.new()
	add_child(_results)
	_results.play_again.connect(_ask_rematch)
	_results.main_menu.connect(func() -> void: _return_to_menu(""))
	# Plays this window through a whole session by injected input (debug).
	if PlaytestPilot.requested(OS.get_cmdline_user_args()):
		add_child(PlaytestPilot.new(self))
	# Hashes this end of a two-process session for autobuild/net_smoke.mjs (debug).
	if NetSmoke.requested(OS.get_cmdline_user_args()):
		add_child(NetSmoke.new(self))
	if _wants_menu():
		_show_menu_backdrop(true)
		_menu.open()
		_capture_mouse(false)
		# So the menu itself can be photographed (`--menu --capture`).
		_arm_capture()
		return
	_menu.close()
	_capture_mouse(not _split_screen)
	_start(GreyBoxLevel.SafeVariant.B)
	_arm_capture()

## The menu is for a player starting the game plainly. Any flag that already
## says what to do - a role, a frame capture, the debug split - skips it, which
## is what keeps every tool and unattended capture working unchanged.
func _wants_menu() -> bool:
	if OS.get_cmdline_user_args().has("--menu"):
		return true
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--capture-screen=menu") or args.has("--capture-screen=settings"):
		return true
	if _invite_lobby() != "":
		return false
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--host" or arg == "--dedicated" or arg == "--solo" or arg == "--split" \
				or arg.begins_with("--join") or arg.begins_with("--capture"):
			return false
	return true

func _read_command_line() -> void:
	_role = _role_from_command_line()
	_join_code = _argument("--join=", "")
	_advertise = _argument("--advertise=", "")
	_dedicated = OS.get_cmdline_user_args().has("--dedicated")
	_dedicated_wait = float(_argument("--dedicated-wait=", "15"))
	_identity = _argument("--identity=", "")
	_backend = _argument("--backend=", "enet")
	var invited: String = _invite_lobby()
	if invited != "":
		_join_code = "steam:%s" % invited
		_backend = "steam"
	_team_size = clampi(int(_argument("--team-size=", str(GreyBoxLevel.DEFAULT_TEAM_SIZE))),
		GreyBoxLevel.TEAM_SIZES.front(), GreyBoxLevel.TEAM_SIZES.back())

func _on_solo(team_size: int) -> void:
	_team_size = team_size
	_launch(MatchLink.Role.LOCAL, "", "")

func _on_host(address: String, team_size: int) -> void:
	_team_size = team_size
	_backend = _argument("--backend=", "enet") # undo a cancelled Steam host
	_launch(MatchLink.Role.HOST, "", address)

func _on_host_steam(team_size: int) -> void:
	_team_size = team_size
	_backend = "steam"
	_launch(MatchLink.Role.HOST, "", "")

func _on_join(code: String) -> void:
	_launch(MatchLink.Role.GUEST, code, "")

## A friend's invite accepted while the game is running (Steam overlay).
func _on_steam_invite(lobby_id: int) -> void:
	if link != null:
		return # already in a session or match
	_on_join("steam:%d" % lobby_id)

func _launch(role: MatchLink.Role, code: String, address: String) -> void:
	_role = role
	_join_code = code
	_advertise = address
	_from_menu = true
	_menu.close()
	_lobby_wait = role == MatchLink.Role.HOST
	_capture_mouse(not _split_screen and not _lobby_wait)
	_start(GreyBoxLevel.SafeVariant.B)
	if _lobby_wait:
		if link != null and link.failure == "":
			var steam_token: String = ""
			if _backend == "steam":
				steam_token = LobbyCode.decode(link.session_code()).token
			_lobby.open(link.session_code(), _team_size, steam_token)
			DisplayServer.clipboard_set(link.session_code())
		else:
			_lobby_wait = false
		return
	# The code is what the host has to give somebody, and reading fourteen
	# characters off a screen to a friend is where they get mistyped.
	if link != null and link.failure == "" and link.role == MatchLink.Role.HOST:
		DisplayServer.clipboard_set(link.session_code())
		_banner.text = "Code copied - paste it to whoever is joining.\n%s" % link.session_code()
		get_tree().create_timer(6.0).timeout.connect(_clear_code_banner)

func _clear_code_banner() -> void:
	if _banner.text.begins_with("Code copied"):
		_banner.text = ""

## Back to the menu, closing the session cleanly - a host's port is released
## and a guest's peer goes quiet rather than timing out on the far end.
func _return_to_menu(problem: String) -> void:
	_tear_down()
	audio.reset()
	audio.set_in_match(false)
	_capture_mouse(false)
	_show_menu_backdrop(true)
	_menu.open(problem)

## A guest that built its world at a different team size from the host's
## cannot play: the rules (round length, jail time) come from the mode file for
## that size. It is told the host's size with its seat; this closes the session
## and joins again at that size, under the same identity, so the host gives it
## back the seat it was just handed.
func _rejoin_at(team_size: int) -> void:
	_tear_down()
	_team_size = team_size
	_start(GreyBoxLevel.SafeVariant.B)

## Closes the session and drops everything drawn for it.
func _tear_down() -> void:
	_lobby_wait = false
	if _lobby != null:
		_lobby.close()
	if link != null:
		link.close()
	link = null
	world = null
	players.clear()
	for view: MeshInstance3D in _actor_views.values():
		view.queue_free()
	_actor_views.clear()
	_clear_animators()
	_view_heights.clear()
	_facings.clear()
	_body_opacity.clear()
	if _reach_marker != null:
		_reach_marker.visible = false
	_banner.text = ""
	_set_paused(false)
	_results.hide_panel()
	# Nothing updates these without a match, so they would sit over the menu.
	_status.visible = false
	_match_hud.visible = false
	_headline.visible = false
	_tell_team = &""
	_tell_overlay.bodies = []
	_rematch_asked = false

# ---- looking at the screen ----

## For PlaytestPilot, which drives this window from outside.
func menu_screen() -> MainMenu:
	return _menu

func save_frame(to_path: String) -> void:
	await _capture_frame(to_path)

func headline_text() -> String:
	return _headline.text

func banner_text() -> String:
	return _banner.text

## Honours `--capture` on the command line: wait, save a PNG, exit.
##
## An unattended run that can produce a frame is the only way a claim about
## what the game LOOKS like gets checked. See FrameCapture.
func _arm_capture() -> void:
	var request: FrameCapture = FrameCapture.from_command_line(OS.get_cmdline_user_args())
	if not request.requested:
		return
	_capture_stats = request.stats
	_capture_timing = request.timing_frames
	await get_tree().create_timer(request.delay).timeout
	if request.clean:
		# The menu is its own layer and stays: a clean shot of the menu is still
		# a shot of the menu. Only the in-game text goes.
		_text_layer.visible = false
		# The team tell's marker and minimap are HUD, kept only when asked for.
		_tell_layer.visible = request.hud
		await get_tree().process_frame
	if request.paths:
		_show_paths = true
		_draw_paths()
		await get_tree().process_frame
	if request.screen != "":
		await _pose_screen(request.screen)
	for i: int in request.figures.size():
		var spot: Vector4 = request.figures[i]
		# The fifth field is a model path, or a family member's id (P2-1).
		var model: PackedScene = null
		var named: String = request.figure_models[i]
		var who: FamilyMember = null
		# Or "team_b:2": that team's roster slot, drawn as a live body of it would
		# be (family member, kid swap, wristband) and shown by the team tell.
		var team: StringName = &"team_a"
		var slot: int = 0
		var as_body: bool = named.begins_with("team_") and named.contains(":")
		if as_body:
			team = StringName(named.get_slice(":", 0))
			slot = int(named.get_slice(":", 1))
		elif named.begins_with("team_") and named.contains("/"):
			# "team_b/elder_boy": that member in that family's outfit colours.
			team = StringName(named.get_slice("/", 0))
			who = ArtTheme.current().member(StringName(named.get_slice("/", 1)))
			if who == null:
				push_error("frame capture: no family member %s" % named)
		elif named.begins_with("res://"):
			if ResourceLoader.exists(named):
				model = load(named) as PackedScene
		elif named != "":
			who = ArtTheme.current().member(StringName(named))
			if who == null:
				push_error("frame capture: no family member %s" % named)
		var posed: Node3D = _figure_instance(team, model, slot, who)
		if posed == null:
			push_error("frame capture: no figure model to stand at %s" % spot)
			break
		if as_body:
			var shown: TeamTellOverlay.Body = TeamTellOverlay.Body.new()
			shown.feet = Vector3(spot.x, spot.y, spot.z)
			shown.height = float(posed.get_meta(&"drawn_height", ACTOR_HEIGHT))
			shown.team = team
			_tell_extras.append(shown)
		posed.position = Vector3(spot.x, spot.y, spot.z)
		posed.rotation = Vector3(0.0, deg_to_rad(spot.w), 0.0)
		add_child(posed)
		posed.set_meta(&"shadow_radius", ArtTheme.current().contact_shadow_radius
			* float(posed.get_meta(&"drawn_height", ACTOR_HEIGHT)) / ACTOR_HEIGHT)
		_shadow_extras.append(posed)
		var clip: String = request.figure_clips[i]
		if clip != "":
			# The holder's one child is the shaped model (_figure_instance).
			var art: Node3D = posed.get_child(0) as Node3D
			var at: int = clip.find("@")
			var clip_name: String = clip if at < 0 else clip.substr(0, at)
			var seconds: float = 0.0 if at < 0 else float(clip.substr(at + 1))
			if not FigureAnimation.pose(art, StringName(clip_name), seconds):
				push_error("frame capture: no figure clip %s" % clip_name)
	for i: int in request.props.size():
		var spot: Vector4 = request.props[i]
		var prop: Node3D = ArtTheme.current().prop_instance(request.prop_models[i])
		if prop == null:
			push_error("frame capture: no prop model at %s" % request.prop_models[i])
			continue
		prop.position = Vector3(spot.x, spot.y, spot.z)
		prop.rotation = Vector3(0.0, deg_to_rad(spot.w), 0.0)
		add_child(prop)
		if request.prop_models[i] == CASH_MODEL:
			# A bundle stood for a shot (the cash-at-30-m views) is dressed and
			# shadowed like a loose one in play.
			ArtTheme.current().dress(prop, ArtTheme.current().cash)
			prop.set_meta(&"shadow_radius", ArtTheme.current().contact_shadow_bundle_radius)
			_shadow_extras.append(prop)
	if not request.figures.is_empty() or not request.props.is_empty():
		await get_tree().process_frame
	if request.crouch:
		# Through Input, like the grab below: the same key LocalPlayerInput
		# polls, so the frame shows a real crouch rather than a posed mesh.
		var duck: InputEventKey = InputEventKey.new()
		duck.keycode = KEY_SHIFT
		duck.pressed = true
		Input.parse_input_event(duck)
		# Long enough for the eased capsule to finish shrinking.
		await get_tree().create_timer(0.6).timeout
	if request.grab:
		# Through Input, not around it: the same key LocalPlayerInput polls, so
		# the frame shows the real path rather than a state posed for a photo.
		# Grab is the left mouse button (it was Q once; this pressed Q long after).
		var press: InputEventMouseButton = InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		Input.parse_input_event(press)
		await get_tree().process_frame
		await get_tree().process_frame
	if request.follow != "":
		await _capture_follow(request)
	elif request.shot_count() == 0:
		await _capture_frame(request.path)
	else:
		if not request.eyes.is_empty():
			await _capture_from(request)
		if not request.chase_feet.is_empty():
			await _capture_chase(request)
	if request.quit_after:
		get_tree().quit()

## `--capture-screen` (FrameCapture.screen, PT2-6): opens one UI screen the way
## its button or key would, then lets its opening fade finish. Debug only.
var _screen_hold: bool = false

func _pose_screen(screen: String) -> void:
	match screen:
		"settings":
			_menu.show_settings()
		"pause":
			_set_paused(true)
		"lobby":
			if level != null:
				_lobby.open("05ZG-0001-W5FG", _team_size)
		"results":
			if world != null and level != null:
				_screen_hold = true
				_results.show_for(world, level, true, level.teams[0].id)
	await get_tree().create_timer(0.5).timeout

## One shot per viewpoint, through the ordinary render path.
##
## The camera is added to the SAME SubViewport the chase camera lives in and
## made current, rather than rendering a private view: the whole point of a
## capture is what a player would see, and the failures worth catching live
## between a correct scene and the window (FrameCapture). A separate viewport
## would render past all of them.
func _capture_from(request: FrameCapture) -> void:
	var host: Viewport = _active_camera().get_viewport() if _active_camera() != null else null
	if host == null:
		push_error("frame capture: no viewport to place a camera in")
		return
	var eye: Camera3D = Camera3D.new()
	eye.near = ChaseCamera.NEAR_PLANE
	eye.far = ChaseCamera.FAR_PLANE
	host.add_child(eye)
	_capture_camera = eye
	eye.current = true

	for i: int in request.eyes.size():
		eye.global_position = request.eyes[i]
		var target: Vector3 = request.looks[i]
		var direction: Vector3 = target - eye.global_position
		if direction.length_squared() < 1.0:
			direction = Vector3(0.0, 0.0, -1.0)
		# look_at cannot resolve a straight-down gaze against a straight-up
		# reference, which is exactly what an overhead shot of a floor asks for.
		var up: Vector3 = Vector3.UP
		if absf(direction.normalized().dot(Vector3.UP)) > 0.999:
			up = Vector3.FORWARD
		eye.look_at(eye.global_position + direction, up)
		await get_tree().process_frame
		await _capture_frame(request.path_for(i))

	_capture_camera = null
	eye.queue_free()

## One shot per chase pose: a stand-in body at the feet position, the seat's own
## chase rig behind it, photographed through the ordinary seat camera.
##
## The stand-in is drawn, never simulated - the match goes on around it - and
## the rig stops following the seat's real body while the poses are taken.
func _capture_chase(request: FrameCapture) -> void:
	if _cameras.is_empty():
		push_error("frame capture: no chase camera to pose")
		return
	var chase: ChaseCamera = _cameras[0]
	var stand_in: Node3D = _stand_in()
	add_child(stand_in)
	_shadow_extras.append(stand_in)
	_posing_chase = true
	for i: int in request.chase_feet.size():
		var feet: Vector3 = request.chase_feet[i]
		var yaw: float = FrameCapture.yaw_toward(feet, request.chase_facing[i])
		stand_in.position = feet
		# The body faces where the camera looks, as it does in play.
		stand_in.rotation = Vector3(0.0, yaw + PI, 0.0)
		chase.reset()
		chase.follow(feet, 0.0)
		chase.pose(yaw, request.chase_pitch[i])
		# The spring arm settles in the physics step, and anything that reacts
		# to where the camera ended up reacts in the frame after that.
		for settle: int in 3:
			await get_tree().physics_frame
		# The same fade play applies to the seat's own body.
		_set_opacity(stand_in, chase.body_opacity())
		await get_tree().process_frame
		await get_tree().process_frame
		await _capture_frame(request.path_for(request.eyes.size() + i))
		print("  chase arm %.0f, body opacity %.2f" % [
			chase.world_position().distance_to(feet + Vector3(0.0, ChaseCamera.PIVOT_HEIGHT, 0.0)),
			chase.body_opacity()])
	_posing_chase = false
	stand_in.queue_free()

## Watches one live body (FrameCapture.follow, P2-3): a free camera beside it,
## re-placed every shot, `follow_count` shots `follow_every` seconds apart,
## shrunk into one contact sheet, four across. Prints what each cell shows (the
## clip its FigureAnimator was playing, and the state it was drawn from), so the
## sheet can be checked against the driver. The match plays on untouched.
func _capture_follow(request: FrameCapture) -> void:
	var parts: PackedStringArray = request.follow.split(":")
	var team: StringName = StringName(parts[0])
	var slot: int = int(parts[1]) if parts.size() > 1 else 0
	var target: int = SimEntity.NO_ENTITY
	if team == &"on":
		# on:<one-shot>: wait for the next throw / grab / seize / free and follow
		# whoever does it (bot matches drift between windowed runs, so a fixed
		# time catches a different moment each run).
		var what: StringName = StringName(parts[1]) if parts.size() > 1 else &"throw"
		# on:<one-shot>:me waits for YOUR body to fire it (with --pilot=carry).
		var only_mine: bool = parts.size() > 2 and parts[2] == "me"
		_anim_fired.clear()
		var waited: float = 0.0
		while waited < 300.0:
			if _anim_fired.has(what) and (not only_mine or _anim_fired[what] == _local_actor()):
				break
			await get_tree().process_frame
			waited += get_process_delta_time()
		target = _anim_fired.get(what, SimEntity.NO_ENTITY)
		if only_mine and target != _local_actor():
			target = SimEntity.NO_ENTITY
	for entity_id: int in world.sorted_entity_ids():
		var entity: SimEntity = world.entities[entity_id]
		if entity.is_actor() and entity.team == team and entity.slot == slot:
			target = entity_id
	var host: Viewport = _active_camera().get_viewport() if _active_camera() != null else null
	if target == SimEntity.NO_ENTITY or host == null:
		push_error("frame capture: nobody at %s to follow" % request.follow)
		return
	var eye: Camera3D = Camera3D.new()
	eye.near = ChaseCamera.NEAR_PLANE
	eye.far = ChaseCamera.FAR_PLANE
	eye.fov = 50.0
	host.add_child(eye)
	_capture_camera = eye
	eye.current = true
	var cells: Array[Image] = []
	const CELL: Vector2i = Vector2i(480, 270)
	# View "bundle" (P4-5): the camera watches the bundle the body carries, and
	# keeps watching it once let go, from a side fixed at the first shot.
	var bundle_id: int = SimEntity.NO_ENTITY
	var bundle_side: Vector3 = Vector3.ZERO
	for i: int in request.presses.size():
		if request.presses[i] == "LMB" or request.presses[i] == "RMB":
			_click_later(MOUSE_BUTTON_LEFT if request.presses[i] == "LMB" else MOUSE_BUTTON_RIGHT,
				request.press_at[i])
			continue
		_press_later(OS.find_keycode_from_string(request.presses[i]),
			request.press_at[i], request.press_hold[i])
	for shot: int in request.follow_count:
		if shot > 0:
			await get_tree().create_timer(request.follow_every).timeout
		var view: MeshInstance3D = _actor_views.get(target, null)
		if view == null:
			break
		var facing: float = _facings.get(target, 0.0)
		var ahead: Vector3 = Vector3(sin(facing), 0.0, cos(facing))
		var left: Vector3 = Vector3(ahead.z, 0.0, -ahead.x)
		var away: Vector3 = left
		var rise: float = 40.0
		match request.follow_view:
			"front":
				away = ahead
			"back":
				away = -ahead
				rise = 160.0
			"above":
				# Down into an open-topped space (the jail pen): 60 degrees up,
				# from the body's left, `distance` from its middle.
				away = left * 0.5
				rise = request.follow_distance * 0.87
		var middle: Vector3 = view.position
		if request.follow_view.begins_with("bundle"):
			var carrier: SimEntity = link.outcome_world().get_entity(target)
			if carrier != null and carrier.is_carrying():
				bundle_id = carrier.carrying_id
			elif bundle_id == SimEntity.NO_ENTITY and carrier != null:
				# Followed from a throw (on:throw): the bundle already flying
				# nearest the thrower.
				var nearest: float = INF
				for cash_id: int in link.outcome_world().sorted_entity_ids():
					var cash: SimEntity = link.outcome_world().entities[cash_id]
					if cash.is_carriable() and cash.in_flight \
							and cash.position.distance_to(carrier.position) < nearest:
						nearest = cash.position.distance_to(carrier.position)
						bundle_id = cash_id
			if bundle_side == Vector3.ZERO:
				# "bundle_r": from the body's right instead.
				bundle_side = -left if request.follow_view == "bundle_r" else left
			away = bundle_side
			rise = 60.0
			if _actor_views.has(bundle_id):
				middle = _actor_views[bundle_id].position
		eye.global_position = middle + away * request.follow_distance + Vector3(0.0, rise, 0.0)
		eye.look_at(middle, Vector3.UP)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		image.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
		cells.append(image)
		var truth: SimEntity = link.outcome_world().get_entity(target)
		var animator: FigureAnimator = _animators.get(target, null)
		print("  cell %d  t=%.1f  clip=%s%s%s%s  motion=%d grounded=%s stance=%d speed=%.0f vy=%.0f carrying=%s captured=%s" % [
			shot + 1, world.tick * SimWorld.SECONDS_PER_TICK,
			animator.clip if animator != null else &"(none)",
			" +arms" if animator != null and bool(animator.tree.get(&"parameters/action/active")) else "",
			" dip=%.1f" % animator.settle_dip() if animator != null and animator.settle_dip() > 0.0 else "",
			" hop=%.0f" % animator.hop_lift() if animator != null and animator.hop_lift() > 0.0 else "",
			truth.motion_state, truth.is_grounded, truth.stance,
			Vector2(truth.velocity.x, truth.velocity.z).length(), truth.velocity.y,
			truth.is_carrying(), truth.is_captured])
		if bundle_id != SimEntity.NO_ENTITY:
			var cash: SimEntity = link.outcome_world().get_entity(bundle_id)
			var drawn_base: Vector3 = _bundle_base.get(bundle_id, Vector3.INF)
			if cash != null:
				print("        bundle %d sim=(%.1f,%.1f,%.1f) in_flight=%s held=%s drawn_base=%s" % [
					bundle_id, cash.position.x, cash.position.y, cash.position.z, cash.in_flight,
					cash.is_held(), "-" if drawn_base == Vector3.INF else "(%.1f,%.1f,%.1f)" % [
						drawn_base.x, drawn_base.y, drawn_base.z]])
	_capture_camera = null
	eye.queue_free()
	if target == _local_actor():
		# Your own body: one more frame, through the seat's own chase camera
		# (what the player sees at the end of the sheet), as <path>_chase.png.
		await get_tree().process_frame
		await _capture_frame("%s_chase.png" % request.path.get_basename())
	if cells.is_empty():
		return
	var across: int = 4
	var down: int = ceili(float(cells.size()) / across)
	var sheet: Image = Image.create(CELL.x * across, CELL.y * down, false, cells[0].get_format())
	for i: int in cells.size():
		sheet.blit_rect(cells[i], Rect2i(Vector2i.ZERO, CELL),
			Vector2i((i % across) * CELL.x, (i / across) * CELL.y))
	var to_path: String = "%s_sheet.png" % request.path.get_basename()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to_path.get_base_dir()))
	if sheet.save_png(to_path) == OK:
		print("frame capture: %s" % ProjectSettings.globalize_path(to_path))

## Presses `key` after `at` seconds and lets go `hold` seconds later (at least a
## frame), through Input like the other injected captures. Not awaited: a follow
## keeps shooting while it runs.
func _press_later(key: Key, at: float, hold: float) -> void:
	if key == KEY_NONE:
		push_error("frame capture: unknown key for --capture-press")
		return
	if at > 0.0:
		await get_tree().create_timer(at).timeout
	var down: InputEventKey = InputEventKey.new()
	down.keycode = key
	down.physical_keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	if hold > 0.0:
		await get_tree().create_timer(hold).timeout
	else:
		await get_tree().process_frame
		await get_tree().process_frame
	var up: InputEventKey = down.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)

## Clicks `button` after `at` seconds (`--capture-press=RMB@1.5`: throw, LMB:
## grab / drop), held three frames like the pilot's click.
func _click_later(button: MouseButton, at: float) -> void:
	if at > 0.0:
		await get_tree().create_timer(at).timeout
	for down: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)
		for frame: int in 3:
			await get_tree().process_frame

## A team_a body for chase shots: the model when it has been built, else the
## capsule the game falls back to. Origin at the feet either way.
func _stand_in() -> Node3D:
	var root: Node3D = Node3D.new()
	var art: Node3D = _figure_instance(&"team_a")
	if art != null:
		root.add_child(art)
		return root
	var look: StandardMaterial3D = ArtTheme.current().figure_material(&"team_a")
	var body: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = level.tuning.actor_radius
	capsule.height = ACTOR_HEIGHT
	body.mesh = capsule
	body.position = Vector3(0.0, ACTOR_HEIGHT * 0.5, 0.0)
	body.material_override = look
	root.add_child(body)
	return root

## True while chase shots are being posed: the rig is parked on the stand-in.
var _posing_chase: bool = false

func _capture_frame(to_path: String) -> void:
	# The texture only holds a finished frame after the draw, not after the
	# _process that queued it.
	await RenderingServer.frame_post_draw
	var written: String = FrameCapture.save(get_viewport(), to_path)
	if written == "":
		return
	print("frame capture: %s" % written)
	print("  %s" % FrameCapture.describe(_active_camera(), _actor_views.size()))
	if _capture_stats:
		# Read now: the counters describe the frame just saved, and the timing
		# below draws more frames over them.
		var seat: Viewport = _active_camera().get_viewport() if _active_camera() != null else null
		var stats: Dictionary = RenderStats.counters(seat)
		if _capture_timing > 0:
			stats.merge(await RenderStats.time_frames(get_tree(), seat, _capture_timing))
		print(RenderStats.line(to_path.get_file().get_basename(), stats))
		if OS.get_cmdline_user_args().has("--capture-breakdown"):
			print(RenderStats.breakdown(self, _active_camera()))

## `--capture-stats` / `--capture-timing=N` (FrameCapture): print what the
## renderer did for each command-line shot. Off for F12 and the pilot.
var _capture_stats: bool = false
var _capture_timing: int = 0
## The camera a capture is actually looking through - the placed one while a
## viewpoint shot is being taken, otherwise the first seat's chase camera.
var _capture_camera: Camera3D = null

func _active_camera() -> Camera3D:
	if _capture_camera != null:
		return _capture_camera
	return _cameras[0].camera if not _cameras.is_empty() else null

# ---- setup ----

## Behind the main menu (PT2-6): the two houses, drawn only (no world, no bots),
## seen from a camera circling the lot once every MENU_ORBIT_SECONDS. Built the
## first time the menu opens; after a match the match's own geometry is reused.
const MENU_ORBIT_SECONDS: float = 90.0
const MENU_ORBIT_RADIUS: float = 4300.0
const MENU_ORBIT_HEIGHT: float = 1700.0
const MENU_ORBIT_LOOK_HEIGHT: float = 200.0
var _menu_camera: Camera3D = null
var _menu_orbit: float = 0.35

func _show_menu_backdrop(on: bool) -> void:
	if not on:
		if _menu_camera != null:
			_menu_camera.queue_free()
			_menu_camera = null
		return
	if level == null:
		level = GreyBoxLevel.new(GreyBoxLevel.SafeVariant.B, GreyBoxLevel.LEVEL_PATH, _team_size)
		if not level.is_loaded():
			level = null
			return
		_build_geometry()
	# The last match's seat views would cover the root viewport, and keep rendering.
	if _seats != null:
		_seats.visible = false
		for view: Node in _seats.find_children("*", "SubViewport", true, false):
			(view as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _menu_camera == null:
		_menu_camera = Camera3D.new()
		_menu_camera.near = ChaseCamera.NEAR_PLANE
		_menu_camera.far = ChaseCamera.FAR_PLANE
		_menu_camera.fov = 50.0
		add_child(_menu_camera)
	_menu_camera.current = true
	_orbit_menu_camera(0.0)

func _orbit_menu_camera(delta: float) -> void:
	if _menu_camera == null or level == null:
		return
	_menu_orbit = fmod(_menu_orbit + delta * TAU / MENU_ORBIT_SECONDS, TAU)
	var middle: Vector3 = level.collision.bounds.get_center()
	middle.y = MENU_ORBIT_LOOK_HEIGHT
	_menu_camera.global_position = middle + Vector3(
		sin(_menu_orbit) * MENU_ORBIT_RADIUS, MENU_ORBIT_HEIGHT, -cos(_menu_orbit) * MENU_ORBIT_RADIUS)
	_menu_camera.look_at(middle, Vector3.UP)

func _start(variant: GreyBoxLevel.SafeVariant) -> void:
	_show_menu_backdrop(false)
	_guide.begin()
	level = GreyBoxLevel.new(variant, GreyBoxLevel.LEVEL_PATH, _team_size)
	if not level.is_loaded():
		_banner.text = "NO BAKED LEVEL\nrun tools/build_house.gd then tools/bake_blockout.gd"
		return
	_build_geometry()

	var role: MatchLink.Role = _role
	var backend: String = _backend

	# A guest needs three worlds: what the host confirmed, what it is guessing,
	# and somewhere to decode snapshots into before trusting them.
	var worlds: Array[SimWorld] = []
	for i: int in (3 if role == MatchLink.Role.GUEST else 1):
		var made: SimWorld = _build_world()
		if made == null:
			return
		worlds.append(made)

	match role:
		MatchLink.Role.HOST:
			link = MatchLink.host(
				level, worlds[0], _bots_enabled, backend, _advertise, _identity
			)
		MatchLink.Role.GUEST:
			link = MatchLink.guest(level, worlds, backend, _join_code, _identity)
		_:
			link = MatchLink.local(level, worlds[0], _bots_enabled)
	if link.failure != "":
		if _from_menu:
			_return_to_menu("Could not start: %s" % link.failure)
			return
		_banner.text = "NETWORK\n%s" % link.failure
		return

	world = link.outcome_world()
	# Sit down before opening the door, or the first guest is given this body.
	if not _dedicated:
		link.seat_local("You")
	_confirmed_frames.clear()
	_seat_shown = SimEntity.NO_ENTITY
	_build_seats()
	_rebuild_views()
	_previous = _snapshot()
	_accumulator = 0.0

	# Only the authority starts a match, and only the authority fills it with
	# bots. A guest is told that both happened, like everything else.
	if link.role != MatchLink.Role.GUEST:
		if _dedicated:
			print("DEDICATED HOST code=%s" % link.session_code())
		elif not _lobby_wait:
			_begin_match()

## Fills empty seats (when bots are on) and starts the match.
func _begin_match() -> void:
	if link.lobby.bots_enabled:
		link.lobby.note_fill(
			link.crew.fill_lobby(world, _seated_actors(), world.actor_ids().size()),
			link.crew.declined_reason
		)
	world.step([MatchCommand.start()])

func _lobby_start(bots: bool) -> void:
	if link == null or not _lobby_wait:
		return
	_lobby_wait = false
	_lobby.close()
	_bots_enabled = bots
	link.lobby.bots_enabled = bots
	_capture_mouse(not _split_screen)
	_begin_match()

## One configured, gated world. Null when the content was refused.
func _build_world() -> SimWorld:
	var made: SimWorld = SimWorld.new(20260802)
	# Gated: broken content does not install and the world will not step
	# (WORLD_AUTHORING.md 7).
	if not made.configure(
		level.mode, level.tuning, level.zones, level.teams, level.collision, level.surface
	):
		_banner.text = "CONTENT REJECTED\n%s" % "\n".join(made.content_failures)
		push_error("grey box: level content failed validation, refusing to run")
		return null
	# Registration order is irrelevant - each system declares its phase.
	made.add_system(MovementSystem.new())
	made.add_system(CarrySystem.new())
	made.add_system(CaptureSystem.new())
	made.add_system(ScoringSystem.new())
	made.add_system(MatchFlowSystem.new())
	made.populate_roster()
	return made

func _role_from_command_line() -> MatchLink.Role:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--host") or args.has("--dedicated"):
		return MatchLink.Role.HOST
	for arg: String in args:
		if arg == "--join" or arg.begins_with("--join="):
			return MatchLink.Role.GUEST
	if _invite_lobby() != "":
		return MatchLink.Role.GUEST
	return MatchLink.Role.LOCAL

## Steam starts the game with `+connect_lobby <id>` from an invite (not after `--`).
func _invite_lobby() -> String:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	return SteamTransport.lobby_from_args(args)

func _argument(prefix: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback

func _seated_actors() -> Array[int]:
	var seated: Array[int] = []
	for player: LocalPlayerInput in players:
		if player.actor_id != SimEntity.NO_ENTITY:
			seated.append(player.actor_id)
	return seated

## One seat normally, two in the debug split. Each seat owns a viewport, a
## chase camera and a device.
func _build_seats() -> void:
	if _seats != null:
		_seats.queue_free()
	for chase: ChaseCamera in _cameras:
		if chase.rig != null:
			chase.rig.queue_free()
	_cameras = []
	players = []

	_seats = CanvasLayer.new()
	_seats.layer = -1 # behind the HUD
	add_child(_seats)

	var split: HBoxContainer = HBoxContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 4)
	_seats.add_child(split)

	var pads: Array[int] = Input.get_connected_joypads()
	var seat_count: int = 2 if _split_screen else 1

	for seat: int in seat_count:
		var container: SubViewportContainer = SubViewportContainer.new()
		container.stretch = true
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		split.add_child(container)

		var viewport: SubViewport = SubViewport.new()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.handle_input_locally = false
		container.add_child(viewport)
		# Every seat renders THIS node's world, so geometry and bodies exist
		# once and are seen from as many places as there are seats.
		viewport.world_3d = get_world_3d()
		viewport.add_to_group(&"seat_viewport")

		var chase: ChaseCamera = ChaseCamera.new(CAMERA_COLLISION_LAYER)
		# The WHOLE RIG goes inside the seat's viewport, not just the camera.
		#
		# A Camera3D renders the viewport it sits under, and it cannot be lifted
		# out of the spring arm to get there - it already has a parent, so the
		# add is refused and the arm ends up driving a camera that belongs to
		# somewhere else. The seat then has no camera, draws its clear colour,
		# and covers the view with a flat rectangle. That reads as "nothing
		# renders" while every rule underneath is working perfectly.
		#
		# Safe because world_3d above is shared: the rig is in this viewport's
		# tree but in the SAME 3D world as the geometry and the bodies, which is
		# also what lets the spring arm probe collide with anything.
		viewport.add_child(chase.rig)
		chase.camera.current = true
		_cameras.append(chase)

		# Seat 0 gets mouse and keys in single view. In the split both seats
		# need pads: there is one mouse and it cannot be halved.
		var input: LocalPlayerInput
		if _split_screen:
			input = LocalPlayerInput.new(
				LocalPlayerInput.Device.GAMEPAD,
				pads[seat] if seat < pads.size() else 0
			)
		else:
			input = LocalPlayerInput.new(LocalPlayerInput.Device.KEYBOARD_MOUSE)
		input.camera = chase
		players.append(input)

	# A guest is TOLD which body is its own and has nothing to drive until it
	# has been; taking the first actor would put two machines on one body.
	if link != null and link.role == MatchLink.Role.GUEST:
		for player: LocalPlayerInput in players:
			player.actor_id = link.actor_id
		return
	var seats: Array[int] = world.actor_ids()
	for seat: int in mini(players.size(), seats.size()):
		players[seat].actor_id = seats[seat]
	# The lobby decides which body is this machine's, so that a host and its
	# guests cannot be handed the same one.
	if link != null and link.actor_id != SimEntity.NO_ENTITY:
		players[0].actor_id = link.actor_id

# ---- the loop ----

## Explicitly accumulated, and explicitly NOT _physics_process.
##
## The simulation runs at its own fixed rate and must stay there. Jolt will
## want 60 Hz for ragdoll work later while the rules stay at 30, and tying the
## two together now would make that a migration instead of a setting.
func _process(delta: float) -> void:
	_orbit_menu_camera(delta)
	if link == null or world == null or not world.has_valid_content():
		return

	# Drained every FRAME, not every tick. Packets arrive when they arrive, and
	# holding one until the next simulation step adds latency nobody asked for.
	link.poll_network()
	if link.rejoin_team_size > 0:
		_rejoin_at(link.rejoin_team_size)
		return
	# A session can die mid-match - the host quits, the connection drops for
	# good - and that used to be silent: the world simply stopped. Say so, and
	# say how to get out.
	if link.failure != "":
		# A join that never got in has nothing on screen worth staying for, so
		# it goes straight back to the menu with the reason and the code still
		# typed. A match that WAS running keeps its last frame, so the player
		# can see where it ended.
		if _from_menu and link.role == MatchLink.Role.GUEST and link.actor_id == SimEntity.NO_ENTITY:
			_return_to_menu(link.failure)
			return
		_banner.text = "NETWORK   %s\n[F10] back to the menu" % link.failure
		return
	_follow_seat()
	_record_confirmed()
	if _dedicated:
		_dedicated_tick(delta)

	for player: LocalPlayerInput in players:
		player.poll(delta)

	_accumulator += delta
	var steps: int = 0
	while _accumulator >= SimWorld.SECONDS_PER_TICK and steps < MAX_STEPS_PER_FRAME:
		_accumulator -= SimWorld.SECONDS_PER_TICK
		steps += 1
		_advance_one_tick()
	if steps == MAX_STEPS_PER_FRAME:
		# Dropped time rather than chased it. A visible skip beats a frame that
		# takes longer to simulate than it took to arrive.
		_accumulator = 0.0

	_advance_remote_clock(delta)
	_draw_paths()
	_render(_accumulator / SimWorld.SECONDS_PER_TICK, delta)
	_track_cameras(delta)
	_update_hud()

## The dedicated host's whole job: start `--dedicated-wait=` seconds (15) after
## the first guest sits down, and rematch 12 s after each match result.
func _dedicated_tick(delta: float) -> void:
	if not _dedicated_started:
		if _dedicated_clock < 0.0 and link.transport.peers().size() > 0:
			_dedicated_clock = _dedicated_wait
			print("DEDICATED first guest seated; starting in %.0f s" % _dedicated_wait)
		elif _dedicated_clock >= 0.0:
			_dedicated_clock -= delta
			if _dedicated_clock <= 0.0:
				_dedicated_started = true
				_begin_match()
		return
	if link.outcome_world().match_phase == SimWorld.MatchPhase.MATCH_END:
		_dedicated_results += delta
		if _dedicated_results >= 12.0:
			_dedicated_results = 0.0
			_rematch_asked = true
	else:
		_dedicated_results = 0.0

func _advance_one_tick() -> void:
	_previous = _snapshot()
	var drawn: SimWorld = link.predicted_world()
	var commands: Array[SimCommand] = []
	for player: LocalPlayerInput in players:
		commands.append_array(player.drain(drawn, drawn.tick))
	if _rematch_asked:
		_rematch_asked = false
		commands.append(MatchCommand.rematch(drawn.tick))
	# Handed over whole. Bots, remote players and this one all end up in one
	# list with no marker and no precedence - which is exactly the guarantee
	# that none of them can be given a privilege by accident.
	link.advance(commands)

## A frozen copy of every entity, taken before the world moves on.
##
## duplicate_entity() rather than a reference: an aliased snapshot would track
## the live world and interpolate a value against itself, which looks exactly
## like no interpolation and is maddening to diagnose.
func _snapshot() -> Dictionary[int, SimEntity]:
	var drawn: SimWorld = link.predicted_world()
	var frame: Dictionary[int, SimEntity] = {}
	for entity_id: int in drawn.sorted_entity_ids():
		frame[entity_id] = drawn.entities[entity_id].duplicate_entity()
	return frame

## Cameras track the RENDERED position, not the simulation's - otherwise they
## would step 30 times a second while the world they are watching moves
## smoothly, and the judder would be blamed on the movement code.
func _track_cameras(delta: float) -> void:
	if _posing_chase:
		return
	for seat: int in mini(_cameras.size(), players.size()):
		var view: MeshInstance3D = _actor_views.get(players[seat].actor_id, null)
		if view == null:
			continue
		_cameras[seat].follow(view.position - Vector3(0.0, ACTOR_HEIGHT * 0.5, 0.0), delta)
		# The fade is for the chase camera's view; a free capture camera (a
		# follow sheet) shoots the body as everyone else sees it.
		var own: SimEntity = link.predicted_world().entities.get(players[seat].actor_id, null)
		var jailed: bool = own != null and own.is_captured
		_fade_body(players[seat].actor_id, view,
			1.0 if _capture_camera != null else _cameras[seat].body_opacity(jailed))

## Last opacity drawn per actor, so a body is only re-walked when it changes.
var _body_opacity: Dictionary[int, float] = {}

## Draws a seat's own body see-through when the camera is pressed up against
## it (ChaseCamera.FADE_FROM). Presentation only.
func _fade_body(actor_id: int, view: Node3D, opacity: float) -> void:
	if absf(_body_opacity.get(actor_id, 1.0) - opacity) < 0.01:
		return
	_body_opacity[actor_id] = opacity
	_set_opacity(view, opacity)

## Through MATERIALS, not GeometryInstance3D.transparency: the Compatibility
## renderer ignores that property (P0-6: a body set to 0.25 drew fully solid).
## Each surface gets an alpha copy of its own material while faded and its
## original back at full opacity, so colours and the model's look are kept.
## Blended with a depth pre-pass. ALPHA_HASH (a dither) was tried and drew the
## body solid on the Compatibility renderer. The pre-pass works per mesh, so the
## current box-built placeholder shows its inner box faces when faded; a
## character that is one closed mesh will not.
static func _set_opacity(node: Node, opacity: float) -> void:
	var mesh_view: MeshInstance3D = node as MeshInstance3D
	if mesh_view != null and mesh_view.mesh != null:
		var flat: StandardMaterial3D = mesh_view.material_override as StandardMaterial3D
		if flat != null:
			# A primitive's own flat colour. A dressed body's scaffold capsule is
			# already fully see-through and stays that way.
			if flat.albedo_color.a > 0.0:
				_fade_material(flat, opacity)
		else:
			_fade_surfaces(mesh_view, opacity)
	for child: Node in node.get_children():
		_set_opacity(child, opacity)

static func _fade_surfaces(mesh_view: MeshInstance3D, opacity: float) -> void:
	var copies: Array = mesh_view.get_meta(&"fade_copies", [])
	if copies.is_empty():
		for surface: int in mesh_view.mesh.get_surface_count():
			var own: StandardMaterial3D = mesh_view.mesh.surface_get_material(surface) as StandardMaterial3D
			copies.append(own.duplicate() if own != null else null)
		mesh_view.set_meta(&"fade_copies", copies)
	for surface: int in copies.size():
		var copy: StandardMaterial3D = copies[surface] as StandardMaterial3D
		if copy == null:
			continue
		_fade_material(copy, opacity)
		mesh_view.set_surface_override_material(surface, copy if opacity < 1.0 else null)

static func _fade_material(material: StandardMaterial3D, opacity: float) -> void:
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS \
		if opacity < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.albedo_color.a = opacity

# ---- what the network changes about drawing ----

## Picks up the seat the host assigned, once it arrives.
##
## A guest cannot work out which body is its own: the roster is identical on
## both machines and nothing in it says "you". It is told, and until it has been
## told there is nobody to follow and nothing to drive.
func _follow_seat() -> void:
	if link.role != MatchLink.Role.GUEST or link.actor_id == _seat_shown:
		return
	_seat_shown = link.actor_id
	for player: LocalPlayerInput in players:
		player.actor_id = link.actor_id
	_rebuild_views()
	_previous = _snapshot()

## Keeps the last few confirmed states, so remote bodies have something to be
## interpolated BETWEEN.
func _record_confirmed() -> void:
	if link.role != MatchLink.Role.GUEST:
		return
	var truth: SimWorld = link.outcome_world()
	if not _confirmed_frames.is_empty() and _confirmed_frames[-1]["tick"] >= truth.tick:
		return
	var frame: Dictionary[int, SimEntity] = {}
	for entity_id: int in truth.sorted_entity_ids():
		frame[entity_id] = truth.entities[entity_id].duplicate_entity()
	_confirmed_frames.append({"tick": truth.tick, "entities": frame})
	while _confirmed_frames.size() > CONFIRMED_HISTORY:
		_confirmed_frames.pop_front()

## Advances the clock that remote bodies are drawn on.
##
## Deliberately BEHIND the newest confirmed state. Packets do not arrive on a
## metronome, so drawing the newest state the moment it lands means every
## remote body stutters at the rate the network happens to deliver. Sitting a
## couple of ticks in the past means there is always a later state to move
## towards, and motion becomes continuous.
##
## Eased toward the target rather than snapped to it, because a burst of late
## packets would otherwise jerk everyone sideways at once.
func _advance_remote_clock(delta: float) -> void:
	if _confirmed_frames.is_empty():
		return
	var newest: float = float(_confirmed_frames[-1]["tick"])
	var oldest: float = float(_confirmed_frames[0]["tick"])
	var target: float = newest - float(level.tuning.interpolation_delay_ticks)

	_remote_clock += delta / SimWorld.SECONDS_PER_TICK
	_remote_clock += (target - _remote_clock) * clampf(delta * 4.0, 0.0, 1.0)
	_remote_clock = clampf(_remote_clock, oldest, newest)

## Where a remote body should be drawn right now: between the two confirmed
## states straddling the remote clock.
func _remote_position(entity_id: int, fallback: Vector3) -> Vector3:
	if _confirmed_frames.size() < 2:
		return fallback
	for i: int in range(_confirmed_frames.size() - 1, 0, -1):
		var later: Dictionary = _confirmed_frames[i]
		var earlier: Dictionary = _confirmed_frames[i - 1]
		if float(earlier["tick"]) > _remote_clock:
			continue
		var from: SimEntity = earlier["entities"].get(entity_id, null)
		var to: SimEntity = later["entities"].get(entity_id, null)
		if from == null or to == null:
			return fallback
		# A teleport is not motion. Interpolating a jailing would slide the body
		# across the map instead of putting it in the cell.
		if from.position.distance_to(to.position) >= SNAP_DISTANCE:
			return to.position
		var span: float = float(later["tick"]) - float(earlier["tick"])
		var blend: float = 0.0 if span <= 0.0 else (_remote_clock - float(earlier["tick"])) / span
		return from.position.lerp(to.position, clampf(blend, 0.0, 1.0))
	return fallback

func _local_actor() -> int:
	return players[0].actor_id if not players.is_empty() else SimEntity.NO_ENTITY

# ---- rendering ----

## Two sources, deliberately kept apart (MatchLink, PredictionPolicy).
##
##   WHERE a body is drawn comes from the predicted world for your own body,
##   and from interpolated confirmed states for everyone else.
##   WHAT IS TRUE about it - carrying, held, visible at all - always comes from
##   the confirmed world.
##
## Collapsing those into one lookup is one line shorter and puts a capture on
## screen that the host may not have agreed to.
func _render(alpha: float, delta: float) -> void:
	var drawn: SimWorld = link.predicted_world()
	var truth: SimWorld = link.outcome_world()
	var mine: int = _local_actor()
	var remote: bool = link.role == MatchLink.Role.GUEST

	for entity_id: int in truth.sorted_entity_ids():
		var entity: SimEntity = truth.entities[entity_id]
		var view: MeshInstance3D = _actor_views.get(entity_id, null)
		if view == null:
			continue

		var target: Vector3
		if remote and entity_id != mine:
			target = _remote_position(entity_id, entity.position)
		else:
			var local: SimEntity = drawn.get_entity(entity_id)
			target = local.position if local != null else entity.position
			var earlier: SimEntity = _previous.get(entity_id, null)
			if earlier != null and earlier.position.distance_to(target) < SNAP_DISTANCE:
				target = earlier.position.lerp(target, clampf(alpha, 0.0, 1.0))

		var placed: Vector3 = target + _view_offset(
			entity, _drawn_height(entity_id, entity, view, delta))
		if entity.is_carriable():
			placed += _release_blend(entity_id, entity, view.position, placed, delta)
		var travelled: Vector3 = placed - view.position
		view.position = placed
		if entity.is_carriable():
			_tumble_bundle(entity_id, entity, view, placed, delta)
		if entity.is_actor() and entity.is_captured:
			# Jailed (P4-3): it runs in place, so it turns to the way its keys
			# point, from the world its motion is drawn from; no keys, it holds.
			var keys: SimEntity = entity
			if not remote or entity_id == mine:
				var own: SimEntity = drawn.get_entity(entity_id)
				if own != null:
					keys = own
			travelled = _held_heading(keys, delta)
		_face(entity_id, entity, view, travelled, delta)
		# Held, carrying and captured are read from the CONFIRMED world on every
		# role. A guest never guesses at an outcome.
		view.visible = true

	if not _cameras.is_empty():
		audio.set_listener(_cameras[0].world_position())
	audio.set_in_match(true)
	var own_body: SimEntity = truth.get_entity(mine) if mine != SimEntity.NO_ENTITY else null
	audio.match_state(truth, own_body.team if own_body != null else &"")
	_feedback_scores(truth)
	_animate(drawn, truth, mine, remote, delta)
	_hold_carried(truth)
	_show_reach(mine)
	_update_tell(truth, mine)
	_place_contact_shadows(truth)

## A bundle let go (thrown, dropped, or shaken loose by a seizure) starts where the
## sim puts it: the carrier's CENTRE, about a body's half-height below the hands
## it was drawn on. Drawn straight there, it dropped that far in one frame. So
## the gap between where it was last drawn (the hands) and where it is now is
## carried and eased out over RELEASE_BLEND (P4-2), smoothstep, so it leaves the
## hands moving with its arc and arrives on it without a kink. Drawn only; the
## sim's bundle is untouched. Returns the offset to add this frame.
func _release_blend(entity_id: int, entity: SimEntity, drawn_before: Vector3,
		placed: Vector3, delta: float) -> Vector3:
	var held: bool = entity.is_held()
	var was_held: bool = _bundle_was_held.get(entity_id, held)
	_bundle_was_held[entity_id] = held
	if held:
		_release_left.erase(entity_id)
		return Vector3.ZERO
	if was_held:
		var gap: Vector3 = drawn_before - placed
		if gap.length() < SNAP_DISTANCE:
			_release_gap[entity_id] = gap
			_release_left[entity_id] = RELEASE_BLEND
	if not _release_left.has(entity_id):
		return Vector3.ZERO
	var left: float = _release_left[entity_id] - delta
	if left <= 0.0:
		_release_left.erase(entity_id)
		return Vector3.ZERO
	_release_left[entity_id] = left
	var k: float = left / RELEASE_BLEND
	return _release_gap[entity_id] * (k * k * (3.0 - 2.0 * k))

## A loose bundle in flight spins end over end, and on landing hops twice while
## the spin eases to the nearest flat pose (P4-5, `BundleTumble`). The spin is
## about the bundle's middle, so its drawn origin moves by the difference; it is
## lifted (never sunk) so no corner goes under the floor beneath the sim's point.
## x and z are the sim's (plus the P4-2 release blend); at rest it lies exactly
## on the sim's point. A bundle with no tumble state is left as it was drawn.
func _tumble_bundle(entity_id: int, entity: SimEntity, view: MeshInstance3D,
		placed: Vector3, delta: float) -> void:
	var tumble: Dictionary = _tumble.update(entity_id, entity, view.rotation.y, delta,
		_release_left.has(entity_id))
	if not tumble[&"active"]:
		_bundle_base.erase(entity_id)
		return
	var spun: Basis = tumble[&"basis"]
	var rest: Basis = Basis(Vector3.UP, _tumble.yaw_of(entity_id))
	var box: AABB = _bundle_boxes.get(entity_id, AABB(Vector3(-CASH_SIZE, 0.0, -CASH_SIZE) * 0.5,
		Vector3(CASH_SIZE, CASH_SIZE * 0.5, CASH_SIZE)))
	var centre: Vector3 = box.get_center()
	var base: Vector3 = placed + Vector3(0.0, tumble[&"lift"], 0.0)
	var origin: Vector3 = base + rest * centre - spun * centre
	if not tumble[&"resting"] and _contact_shadows != null:
		var ground: float = _contact_shadows.floor_below(placed - _view_offset(entity, 0.0))
		if ground > -INF:
			var lowest: float = INF
			for corner: int in 8:
				lowest = minf(lowest, (origin + spun * box.get_endpoint(corner)).y)
			if lowest < ground:
				origin.y += ground - lowest
				base.y += ground - lowest
	view.position = origin
	view.basis = spun
	_bundle_base[entity_id] = base - _view_offset(entity, 0.0)
	if _tumble_log:
		print("tumble id=%d sim=(%.1f,%.1f,%.1f) drawn_base=(%.1f,%.1f,%.1f) lift=%.2f flight=%s resting=%s" % [
			entity_id, placed.x, placed.y, placed.z, base.x, base.y, base.z,
			base.y - placed.y, entity.in_flight, tumble[&"resting"]])

## A disc on the floor under every drawn body and every loose bundle, and under
## the capture's stand-ins. Read from where things are DRAWN this frame; a held
## bundle has none (its carrier's covers it).
func _place_contact_shadows(truth: SimWorld) -> void:
	if _contact_shadows == null:
		return
	var theme: ArtTheme = ArtTheme.current()
	_contact_shadows.begin()
	for entity_id: int in _actor_views:
		var entity: SimEntity = truth.get_entity(entity_id)
		var view: MeshInstance3D = _actor_views[entity_id]
		if entity == null or not view.visible:
			continue
		if entity.is_actor():
			var tall: float = _figure_heights.get(entity_id, ACTOR_HEIGHT)
			var feet: Vector3 = view.position - Vector3(0.0, _view_heights.get(entity_id, ACTOR_HEIGHT) * 0.5, 0.0)
			_contact_shadows.add(feet, theme.contact_shadow_radius * tall / ACTOR_HEIGHT)
		elif entity.is_carriable() and not entity.is_held():
			_contact_shadows.add(_bundle_base.get(entity_id, view.position - _view_offset(entity, 0.0)),
				theme.contact_shadow_bundle_radius)
	for extra: Node3D in _shadow_extras:
		if is_instance_valid(extra) and extra.is_inside_tree() and extra.visible:
			_contact_shadows.add(extra.global_position, float(extra.get_meta(&"shadow_radius",
				theme.contact_shadow_radius)))
	_contact_shadows.finish()

## Hands the team tell's overlay (marker, minimap) the bodies as drawn this
## frame, and turns its map for this machine's team. Your team is read from the
## confirmed world, like every other outcome.
func _update_tell(truth: SimWorld, mine: int) -> void:
	if _tell_overlay == null:
		return
	var me: SimEntity = truth.get_entity(mine)
	var team: StringName = me.team if me != null else &""
	if team != _tell_team and team != &"":
		_tell_team = team
		var own_spawn: Vector3 = Vector3.ZERO
		var enemy_spawn: Vector3 = Vector3.ZERO
		for each: TeamDef in level.teams:
			var centre: Vector3 = Vector3.ZERO
			for point: Vector3 in each.spawn_points:
				centre += point / float(maxi(1, each.spawn_points.size()))
			if each.id == team:
				own_spawn = centre
			else:
				enemy_spawn = centre
		var lot: AABB = WorldBackdrop.widest_blocker(level.collision.blockers) \
			if not level.collision.blockers.is_empty() else AABB()
		_tell_overlay.set_level(lot, level.zones, own_spawn, enemy_spawn)
	_tell_overlay.own_team = team
	_tell_overlay.camera = _active_camera()
	var bodies: Array[TeamTellOverlay.Body] = []
	for entity_id: int in _actor_views:
		var entity: SimEntity = truth.get_entity(entity_id)
		if entity == null or not entity.is_actor():
			continue
		var view: MeshInstance3D = _actor_views[entity_id]
		var body: TeamTellOverlay.Body = TeamTellOverlay.Body.new()
		body.feet = view.position - Vector3(0.0, _view_heights.get(entity_id, ACTOR_HEIGHT) * 0.5, 0.0)
		body.height = _figure_heights.get(entity_id, ACTOR_HEIGHT)
		body.team = entity.team
		body.mine = entity_id == mine
		bodies.append(body)
	bodies.append_array(_tell_extras)
	_tell_overlay.bodies = bodies

## Flips one team-tell option (F5-F8, the menu) and redraws whatever it changes:
## the wristband and the kid swap are on the figures, so those rebuild them.
func _toggle_tell(option: StringName) -> void:
	var tell: TeamTell = TeamTell.current()
	tell.toggle(option)
	if option == &"wristband" or option == &"kid_swap":
		_rebuild_views()
		_previous = _snapshot()
	_banner.text = "Team tell: %s" % tell.describe()
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if _banner.text.begins_with("Team tell:"):
			_banner.text = "")

## Drives every figure's animation (FigureAnimator, P2-3) after the bodies have
## been placed. Motion (stance, airborne, speed) comes from the world the body is
## DRAWN from: the predicted one for your own body, the confirmed one for every
## other (a guest's remote bodies have no prediction). Carrying and captured are
## outcomes and always come from the confirmed world.
##
## One-shots are spotted from changes in that confirmed state between frames,
## never from drawn positions: a bundle let go and flying sideways is a throw; an
## actor that becomes captured was seized by the nearest enemy, one released
## before its sentence ran out was freed by the nearest teammate.
func _animate(drawn: SimWorld, truth: SimWorld, mine: int, remote: bool, delta: float) -> void:
	if _animators.is_empty():
		return
	var move_speed: float = level.tuning.move_speed
	var seized: Array[int] = []
	var freed: Array[int] = []
	for entity_id: int in _animators:
		var entity: SimEntity = truth.get_entity(entity_id)
		if entity == null:
			continue
		var motion: SimEntity = entity
		if not remote or entity_id == mine:
			var local: SimEntity = drawn.get_entity(entity_id)
			if local != null:
				motion = local
		var animator: FigureAnimator = _animators[entity_id]
		var was_carrying: int = _anim_carrying.get(entity_id, SimEntity.NO_ENTITY)
		if was_carrying != SimEntity.NO_ENTITY and entity.carrying_id != was_carrying:
			var bundle: SimEntity = truth.get_entity(was_carrying)
			# A drop (or a seized carrier's bundle) also goes in_flight, but falls
			# straight down: only a throw leaves the hand moving sideways.
			if bundle != null and bundle.in_flight \
					and Vector2(bundle.velocity.x, bundle.velocity.z).length() > 1.0:
				_act(truth, entity_id, &"throw")
		if was_carrying == SimEntity.NO_ENTITY and entity.is_carrying():
			_anim_fired[&"grab"] = entity_id
			audio.play(&"grab", entity.position, entity_id == mine)
			var ground: ZoneDef = truth.zone_at(entity.position)
			if ground != null and ground.owner_team != &"" and ground.owner_team != entity.team:
				feedback.add_line("%s took cash" % _who_text(entity, mine))
			if _anim_log:
				print("anim grab  %s:%d  t=%.1f" % [entity.team, entity.slot,
					truth.tick * SimWorld.SECONDS_PER_TICK])
		_anim_carrying[entity_id] = entity.carrying_id
		var was_captured: bool = _anim_captured.get(entity_id, entity.is_captured)
		if entity.is_captured and not was_captured:
			seized.append(entity_id)
			# `--capture-follow=on:jailed` follows the one seized, not the seizer.
			_anim_fired[&"jailed"] = entity_id
		elif was_captured and not entity.is_captured and _anim_sentence.get(entity_id, 0) > 1:
			freed.append(entity_id)
		_anim_captured[entity_id] = entity.is_captured
		_anim_sentence[entity_id] = entity.capture_ticks_remaining
		if entity_id == mine:
			if motion.is_grounded:
				if _fb_air > 8 and not entity.is_captured and not _cameras.is_empty():
					_cameras[0].nudge(NUDGE_LANDING)
				_fb_air = 0
			else:
				_fb_air += 1
		audio.body(entity_id, motion.position, motion.is_grounded,
			not entity.is_captured and motion.velocity.length() > 1.0, entity_id == mine)
		animator.update(motion, entity.is_carrying(), entity.is_captured, move_speed, delta,
			level.tuning.crouch_speed_scale)
	for victim: int in seized:
		# PT2-4: the jail "boink", where the victim was caught (it is already in jail
		# in `truth`), so the captor hears it too; full level for the local victim.
		var caught_at: Vector3 = _anim_last_seen.get(victim, truth.get_entity(victim).position)
		audio.play(&"jailed", caught_at, victim == mine)
		_act_nearest(truth, victim, false)
		_feedback_body(truth, victim, mine, true)
	for victim: int in freed:
		_act_nearest(truth, victim, true)
		_feedback_body(truth, victim, mine, false)
	_spot_carriers(truth, mine)
	for entity_id: int in _animators:
		var seen: SimEntity = truth.get_entity(entity_id)
		if seen != null:
			_anim_last_seen[entity_id] = seen.position

## The spotted startle (PT2-2). From the CONFIRMED world, each frame: a body
## carrying another family's cash, with a free member of that family within
## SPOTTED_DISTANCE (and SPOTTED_HEIGHT), is spotted - once per carry, then not
## again for SPOTTED_COOLDOWN while it holds the same bundle. The carrier's figure
## jolts and both of them hear the sting. Presentation only: nothing here reaches
## the sim, the bots or the network; every machine works it out for itself.
func _spot_carriers(truth: SimWorld, mine: int) -> void:
	var cooldown: int = SimWorld.seconds_to_ticks(SPOTTED_COOLDOWN)
	var actors: Array[int] = truth.actor_ids()
	for carrier_id: int in actors:
		var carrier: SimEntity = truth.get_entity(carrier_id)
		if carrier == null or not carrier.is_carrying() or carrier.is_captured:
			_spotted_bundle.erase(carrier_id)
			continue
		var bundle: SimEntity = truth.get_entity(carrier.carrying_id)
		if bundle == null or bundle.team == &"" or bundle.team == carrier.team:
			continue
		if _spotted_bundle.get(carrier_id, SimEntity.NO_ENTITY) == bundle.id:
			var since: int = truth.tick - _spotted_tick.get(carrier_id, truth.tick)
			if since >= 0 and since < cooldown:
				continue
		var spotter: int = SimEntity.NO_ENTITY
		for other_id: int in actors:
			var other: SimEntity = truth.get_entity(other_id)
			if other == null or other.team != bundle.team or other.is_captured:
				continue
			var gap: Vector3 = other.position - carrier.position
			if absf(gap.y) < SPOTTED_HEIGHT and Vector2(gap.x, gap.z).length() <= SPOTTED_DISTANCE:
				spotter = other_id
				break
		if spotter == SimEntity.NO_ENTITY:
			continue
		_spotted_bundle[carrier_id] = bundle.id
		_spotted_tick[carrier_id] = truth.tick
		if _animators.has(carrier_id):
			_animators[carrier_id].startle()
		if carrier_id == mine and not _cameras.is_empty():
			_cameras[0].nudge(NUDGE_LANDING)
		if carrier_id == mine or spotter == mine:
			audio.play_flat(&"spotted")
		if _anim_log:
			print("anim spotted  %s:%d by %d  t=%.1f" % [carrier.team, carrier.slot, spotter,
				truth.tick * SimWorld.SECONDS_PER_TICK])

## "You", or "<family> <member>" (for example "<family> dad").
func _who_text(entity: SimEntity, mine: int) -> String:
	if entity.id == mine:
		return "You"
	var member: FamilyMember = ArtTheme.current().member_for(entity.team, entity.slot,
		TeamTell.current().kid_swap)
	var word: String = GameFeedback.member_words(member.id) if member != null else "player"
	return "%s %s" % [FamilyNames.name_of(entity.team), word]

## Event line, puff, and for your own body the cut and the camera nudge (P5-4).
func _feedback_body(truth: SimWorld, victim: int, mine: int, caught: bool) -> void:
	var entity: SimEntity = truth.get_entity(victim)
	if entity == null:
		return
	var own: bool = victim == mine
	var who: String = _who_text(entity, mine)
	var verb: String = "caught" if caught else "freed"
	var was: String = "were" if own else "was"
	feedback.add_line("%s %s %s" % [who, was, verb])
	var at: Vector3 = _anim_last_seen.get(victim, entity.position) if caught else entity.position
	feedback.puff(self, at, GameFeedback.PUFF_COUNT if caught else GameFeedback.PUFF_COUNT_SMALL)
	if own:
		feedback.cut(GameFeedback.CUT_SECONDS_SEIZED if caught else GameFeedback.CUT_SECONDS_FREED)
		if caught and not _cameras.is_empty():
			_cameras[0].nudge(NUDGE_SEIZED)

## "<family> banked cash" when a team's score rises.
func _feedback_scores(truth: SimWorld) -> void:
	for team_id: StringName in truth.teams:
		var score: int = truth.score_for(team_id)
		if _fb_scores.has(team_id) and score > _fb_scores[team_id]:
			feedback.add_line("%s banked cash" % FamilyNames.name_of(team_id))
		_fb_scores[team_id] = score

## Plays `interact` on the actor nearest `victim` (where it was last drawn) on
## its own team (`ally`, a free) or the other (a seize), within reach.
func _act_nearest(truth: SimWorld, victim: int, ally: bool) -> void:
	var who: SimEntity = truth.get_entity(victim)
	var at: Vector3 = _anim_last_seen.get(victim, who.position if who != null else Vector3.ZERO)
	var best: int = SimEntity.NO_ENTITY
	var best_distance: float = INTERACT_REACH
	for entity_id: int in _animators:
		var other: SimEntity = truth.get_entity(entity_id)
		if other == null or entity_id == victim or other.is_captured or who == null:
			continue
		if (other.team == who.team) != ally:
			continue
		var gap: float = other.position.distance_to(at)
		if gap < best_distance:
			best_distance = gap
			best = entity_id
	if best != SimEntity.NO_ENTITY:
		_act(truth, best, &"free" if ally else &"seize")

## Fires a one-shot on `entity_id`'s figure: `throw`, or `seize` / `free` (both
## play `interact`). Logged under --anim-log.
func _act(truth: SimWorld, entity_id: int, what: StringName) -> void:
	_animators[entity_id].act(&"throw" if what == &"throw" else &"interact")
	_anim_fired[what] = entity_id
	var actor: SimEntity = truth.get_entity(entity_id)
	if actor != null:
		audio.play(what, actor.position, entity_id == _local_actor())
	if _anim_log:
		var who: SimEntity = truth.get_entity(entity_id)
		print("anim %s  %s:%d  t=%.1f" % [what, who.team, who.slot,
			truth.tick * SimWorld.SECONDS_PER_TICK])

## A held bundle is drawn over its carrier's head.
##
## It used to be hidden while held (the simulation puts it at the carrier's
## centre, inside the mesh), so from the chair nobody could see who had the cash
## - including the player carrying it (P0-8 walkthrough). In front of the chest
## was tried first: the chase camera sits behind, so the body hid it. Overhead
## reads from every side. Placed after every body has been, so it follows the
## carrier drawn THIS frame. An animated figure (P2-3) holds it on its hands in
## the carry pose; the fixed gap over the head is for the fallback bodies.
func _hold_carried(truth: SimWorld) -> void:
	for entity_id: int in truth.sorted_entity_ids():
		var entity: SimEntity = truth.entities[entity_id]
		if not entity.is_carriable() or not entity.is_held():
			continue
		var view: MeshInstance3D = _actor_views.get(entity_id, null)
		var carrier: MeshInstance3D = _actor_views.get(entity.carried_by, null)
		if view == null or carrier == null:
			continue
		view.rotation = Vector3(0.0, _facings.get(entity.carried_by, 0.0), 0.0)
		# An animated figure holds it up in its hands (the carry_* clips, P2-2):
		# the bundle sits on the hands as posed this frame.
		var animator: FigureAnimator = _animators.get(entity.carried_by, null)
		if animator != null:
			var hands: Vector3 = animator.hands_point()
			if hands != Vector3.INF:
				view.position = hands + Vector3(0.0, CARRY_HAND_LIFT, 0.0)
				continue
		# The carrier's view sits at the middle of the height drawn for it, so
		# half that height up is the top of its head, crouched or not.
		var drawn: float = _view_heights.get(entity.carried_by, ACTOR_HEIGHT)
		view.position = carrier.position + Vector3(0.0, drawn * 0.5 + CARRY_GAP, 0.0)

## The animation-on-input half of the split.
##
## The reach starts the instant the button is pressed and stops when the host
## answers - which is what covers the latency on an outcome without ever
## predicting one. The player sees an immediate response to their input, and
## never sees a consequence undone.
func _show_reach(mine: int) -> void:
	if _reach_marker == null:
		return
	var view: MeshInstance3D = _actor_views.get(mine, null)
	var waiting: bool = not link.awaiting().is_empty()
	_reach_marker.visible = waiting and view != null
	if _reach_marker.visible:
		_reach_marker.position = view.position + Vector3(0.0, ACTOR_HEIGHT * 0.75, 0.0)

## Turns a drawn body to face the way it is travelling.
##
## PRESENTATION ONLY, and it has to be: the simulation has no notion of facing
## at all - an actor is a sphere with a velocity, and every rule that could care
## about direction (capture range, pickup range) is a distance instead. So this
## is the mesh being polite about which way it points, and nothing reads it.
##
## Needed once the camera sits behind the body. A character that runs forward
## while pointing north looks like it is sliding, and that reads as a bug rather
## than as a simplification.
##
## Falls back to holding the last facing when stopped, rather than snapping to
## a default: a body that has come to rest is still facing wherever it arrived.
##
## Faces the way the body was DRAWN moving this frame (`travelled`), not its
## velocity (P4-2). The sim's velocity is the intent times the speed, kept while
## a wall turns the move into a slide along it, so a body run diagonally into a
## wall faced into it and was drawn with its face and arm inside the brick.
## Tiny drawn moves (under FACE_MIN_SPEED) and jumps of a teleport (a round reset,
## a snap) keep the facing.
func _face(entity_id: int, entity: SimEntity, view: Node3D, travelled: Vector3,
		delta: float) -> void:
	if not entity.is_actor() or delta <= 0.0:
		return
	var travel: Vector3 = Vector3(travelled.x, 0.0, travelled.z)
	if travel.length() < FACE_MIN_SPEED * delta or travel.length() > SNAP_DISTANCE:
		return
	var wanted: float = atan2(travel.x, travel.z)
	var now: float = _facings.get(entity_id, wanted)
	# Shortest way round, so crossing the -PI seam does not spin the long way.
	var gap: float = wrapf(wanted - now, -PI, PI)
	var turned: float = wrapf(now + gap * minf(1.0, FACE_RATE * delta), -PI, PI)
	_facings[entity_id] = turned
	view.rotation = Vector3(0.0, turned, 0.0)

## The "travel" a jailed body faces: its intent's direction, as a drawn step
## just over `_face`'s minimum, or zero (facing held) below the deadzone.
func _held_heading(entity: SimEntity, delta: float) -> Vector3:
	var intent: Vector3 = Vector3(entity.move_intent.x, 0.0, entity.move_intent.z)
	if intent.length() < MovementSystem.INTENT_DEADZONE:
		return Vector3.ZERO
	return intent.normalized() * FACE_MIN_SPEED * 2.0 * delta

## Lifts an actor's mesh so it stands ON the floor. The simulation's position
## is the centre of a body one radius tall; the capsule is taller than that.
##
## Takes the height being DRAWN rather than ACTOR_HEIGHT, so a crouched capsule
## keeps its feet on the ground while its head comes down. Offsetting a
## shortened mesh by the standing half-height would sink it into the floor,
## which is the same bug this function exists to prevent for the standing case.
func _view_offset(entity: SimEntity, drawn_height: float) -> Vector3:
	if entity.is_carriable():
		# A carriable is a POINT to the simulation, and CarrySystem rests it
		# exactly ON the surface it lands on - so a cube centred there has half
		# its depth below the floor. Reported from a playtest as the cash
		# sinking into the ground; it was never sinking, it was being drawn
		# through its own resting point.
		#
		# Only while it is loose. A held bundle takes the carrier's position,
		# which is a body centre rather than a point on the ground, and lifting
		# it there would float it above the hand.
		if entity.is_held():
			return Vector3.ZERO
		# THE MODEL NEEDS NO LIFT. It is authored with its origin at its bottom
		# face, so it already rests on the point the simulation put it at. Only
		# the fallback CUBE is centred on its own middle and needs raising -
		# lifting both by half a cube floated the bundle 8 units off the floor,
		# because the model is 17 tall and the cube is 50.
		if _cash_model() != null:
			return Vector3.ZERO
		return Vector3(0.0, CASH_SIZE * 0.5, 0.0)
	if not entity.is_actor():
		return Vector3.ZERO
	var radius: float = level.tuning.actor_radius
	if entity.stance == SimEntity.Stance.CROUCHED:
		# The simulation drops the body's centre when it crouches, so the feet
		# are already where they should be - the mesh only has to stop being
		# offset for a body it is no longer the size of.
		radius *= MovementSystem.CROUCH_RADIUS_SCALE
	return Vector3(0.0, drawn_height * 0.5 - radius, 0.0)

## Eases an actor's capsule toward the height its stance calls for, and returns
## the height actually drawn this frame.
func _drawn_height(entity_id: int, entity: SimEntity, view: MeshInstance3D,
		delta: float) -> float:
	var body: CapsuleMesh = view.mesh as CapsuleMesh
	if body == null:
		return ACTOR_HEIGHT
	var wanted: float = ACTOR_HEIGHT
	if entity.is_actor() and entity.stance == SimEntity.Stance.CROUCHED:
		wanted = ACTOR_HEIGHT * CROUCH_VIEW_SCALE
	var current: float = _view_heights.get(entity_id, wanted)
	# Exponential ease, framerate-independent: the same motion at 30 fps and
	# 144, rather than a per-frame fraction that is faster on a better machine.
	var eased: float = current + (wanted - current) * minf(
		1.0, CROUCH_VIEW_SPEED * delta)
	if absf(wanted - eased) < 0.5:
		eased = wanted
	_view_heights[entity_id] = eased
	body.height = eased
	# A capsule's height includes its two hemispherical caps, so the radius has
	# to come down with it or Godot clamps the height and the crouch stops
	# short of what was asked for.
	body.radius = minf(level.tuning.actor_radius, eased * 0.5)

	# A MODEL PARENTED TO THIS VIEW DOES NOT FOLLOW THE MESH. Resizing a
	# CapsuleMesh changes the shape this node draws and nothing about its
	# children, so a character model kept its full height while the offset
	# below dropped it - which read as the body sinking knee-deep into the
	# floor rather than ducking. Scaling the NODE squashes the model with it.
	#
	# Vertical only. A crouching body gets shorter, not narrower; scaling all
	# three axes would pinch it inward and make it read as shrinking.
	var squash: float = eased / ACTOR_HEIGHT
	if _animators.has(entity_id):
		# An animated figure crouches by its own pose (crouch_* clips), so it is
		# not squashed; it stands with its feet on the sim's feet, which are half
		# the drawn height below the view (_view_offset), crouched or not. The
		# landing settle (P4-2) dips it a few units for a moment after a landing;
		# the view itself, its contact shadow and the camera do not move.
		# A jail hop (P4-3) lifts it the same way: drawn only, the sim's body
		# stays on the holding spot, and so do its shadow and the camera.
		# The spotted startle (PT2-2) lifts it and leans it back about the feet
		# (forward is local +z, so back is a negative x turn); drawn only too.
		var figure_anim: FigureAnimator = _animators[entity_id]
		var dip: float = figure_anim.settle_dip() - figure_anim.hop_lift() - figure_anim.startle_lift()
		var lean: float = -figure_anim.startle_lean()
		for child: Node in view.get_children():
			var held: Node3D = child as Node3D
			if held != null:
				held.scale = Vector3.ONE
				held.position = Vector3(0.0, -eased * 0.5 - dip, 0.0)
				held.rotation.x = lean
		return eased
	for child: Node in view.get_children():
		var figure: Node3D = child as Node3D
		if figure != null:
			figure.scale = Vector3(1.0, squash, 1.0)
	return eased

## The cash bundle model, or null when it has not been built.
##
## Cached rather than loaded per entity: eight bundles in a match, one model.
static var _cash_scene: PackedScene = null
static var _cash_looked: bool = false

## Per-team character models, cached. Null until Blender has been run, which is
## a supported state - the capsule shows through and the game still plays.
static var _actor_scenes: Dictionary[StringName, PackedScene] = {}
static var _actor_looked: Dictionary[StringName, bool] = {}

## A drawn figure for one body of `team`, origin at its feet, in the theme's
## figure material (a copy per body, for the fade) and sized/nudged by the
## theme; null when no model exists (the capsule shows instead). Wrapped in a
## holder so the crouch squash (_drawn_height) does not undo the theme's scale.
## `slot` picks the family member (ArtTheme.member_for, P2-1); `who` names one
## outright (the capture tool's stand-ins).
func _figure_instance(team: StringName, model: PackedScene = null, slot: int = 0,
		who: FamilyMember = null) -> Node3D:
	var theme: ArtTheme = ArtTheme.current()
	var tell: TeamTell = TeamTell.current()
	# A model given outright is drawn as itself unless a member is named too.
	var member: FamilyMember = who
	if member == null and model == null:
		member = theme.member_for(team, slot, tell.kid_swap)
	var figure: PackedScene = model
	if figure == null and member != null:
		figure = theme.member_scene(member)
	if figure == null:
		figure = _actor_model(team)
	if figure == null:
		return null
	var art: Node3D = figure.instantiate() as Node3D
	ArtTheme.dress_whole(art, theme.figure_material(team))
	# D3 default: the member's outfit in its family's colours (P2-1b). Option
	# (c) puts everyone back in the same plain clothes, told apart by the band.
	# The member's hair colour goes on with or without a team (P2-6).
	theme.outfit_figure(art, team, member, tell.wristband)
	if model != null or member != null or theme.figure_scene() != null:
		theme.shape_figure(art, member)
	# D3 (c): the one coloured thing on a figure (TeamTell, P2-4).
	if tell.wristband and team != &"":
		theme.add_wristband(art, team)
	var holder: Node3D = Node3D.new()
	holder.add_child(art)
	holder.set_meta(&"drawn_height", minf(member.height, theme.figure_height)
		if member != null else ACTOR_HEIGHT)
	return holder

func _actor_model(team: StringName) -> PackedScene:
	if team == &"":
		return null
	var themed: PackedScene = ArtTheme.current().figure_scene()
	if themed != null:
		return themed
	if not _actor_looked.get(team, false):
		_actor_looked[team] = true
		# team_a -> "a", so one model serves whatever the team is called.
		var suffix: String = String(team).replace("team_", "")
		var path: String = ACTOR_MODEL % suffix
		if ResourceLoader.exists(path):
			_actor_scenes[team] = load(path) as PackedScene
	return _actor_scenes.get(team, null)

## A material that draws nothing, for the crouch scaffold under a real model.
func _invisible() -> StandardMaterial3D:
	var hide: StandardMaterial3D = StandardMaterial3D.new()
	hide.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hide.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	hide.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return hide

func _cash_model() -> PackedScene:
	if not _cash_looked:
		_cash_looked = true
		if ResourceLoader.exists(CASH_MODEL):
			_cash_scene = load(CASH_MODEL) as PackedScene
	return _cash_scene

func _clear_animators() -> void:
	_animators.clear()
	_anim_carrying.clear()
	_anim_captured.clear()
	_anim_sentence.clear()
	_anim_last_seen.clear()
	_spotted_bundle.clear()
	_spotted_tick.clear()
	_fb_scores.clear()
	_fb_air = 0
	feedback.clear_lines()
	# The loose-bundle tumble state goes with the views it drew (P4-5).
	_tumble = BundleTumble.new()
	_bundle_boxes.clear()
	_bundle_base.clear()

func _rebuild_views() -> void:
	for view: MeshInstance3D in _actor_views.values():
		view.queue_free()
	_actor_views.clear()
	_clear_animators()
	_view_heights.clear()
	_facings.clear()
	_body_opacity.clear()
	_figure_heights.clear()

	if _reach_marker == null:
		_reach_marker = MeshInstance3D.new()
		var pip: SphereMesh = SphereMesh.new()
		pip.radius = 22.0
		pip.height = 44.0
		_reach_marker.mesh = pip
		_reach_marker.material_override = _flat(Color(1.0, 0.85, 0.2))
		_reach_marker.visible = false
		add_child(_reach_marker)

	var theme: ArtTheme = ArtTheme.current()
	for entity_id: int in world.sorted_entity_ids():
		var entity: SimEntity = world.entities[entity_id]
		var view: MeshInstance3D = MeshInstance3D.new()
		## Whether a model was parented onto this view, in which case the
		## primitive under it must not be painted over the top of it.
		var dressed: bool = false
		if entity.is_actor():
			# A capsule always, model on top of it when one exists. The capsule
			# stays because _drawn_height resizes it for the crouch and the rest
			# of presentation measures against it; the model is parented so it
			# inherits that squash rather than needing its own crouch pose.
			var body: CapsuleMesh = CapsuleMesh.new()
			body.radius = level.tuning.actor_radius
			body.height = ACTOR_HEIGHT
			view.mesh = body
			# Whatever the model came with, it is drawn in the theme's one
			# figure material (STYLE.md §2.3), a copy per body for the fade.
			var art: Node3D = _figure_instance(entity.team, null, entity.slot)
			if art != null:
				_figure_heights[entity_id] = float(art.get_meta(&"drawn_height", ACTOR_HEIGHT))
				# The model's origin is its FEET and the capsule's is its
				# middle, so the figure drops half a body to stand in it.
				art.position = Vector3(0.0, -ACTOR_HEIGHT * 0.5, 0.0)
				view.add_child(art)
				# The holder's one child is the shaped model (_figure_instance).
				var animator: FigureAnimator = FigureAnimator.attach(art.get_child(0) as Node3D)
				if animator != null:
					_animators[entity_id] = animator
				# The capsule becomes the crouch scaffold rather than the thing
				# seen - see the material choice below.
				dressed = true
		else:
			# The modelled bundle if it has been built, the placeholder cube if
			# not. Art is optional by design: the game has to stay playable and
			# screenshot-able from a clean checkout before anything is modelled,
			# and a missing .glb is a cosmetic gap rather than a broken build.
			var art: PackedScene = _cash_model()
			if art != null:
				var bundle: Node = art.instantiate()
				theme.dress(bundle, theme.cash)
				# The bundle model is several boxes: one mesh, a surface per
				# material, so it is two draws and not seven (P3-6).
				var merged: ArrayMesh = MeshMerge.of_tree(bundle as Node3D) if bundle is Node3D else null
				if merged != null:
					var one: MeshInstance3D = MeshInstance3D.new()
					one.name = "cash"
					one.mesh = merged
					one.transform = (bundle as Node3D).transform
					bundle.free()
					bundle = one
					_bundle_boxes[entity_id] = one.transform * merged.get_aabb()
				view.add_child(bundle)
				dressed = true
			else:
				var box: BoxMesh = BoxMesh.new()
				box.size = Vector3(CASH_SIZE, CASH_SIZE, CASH_SIZE)
				view.mesh = box
				_bundle_boxes[entity_id] = box.get_aabb()
		# A dressed view keeps its model's own materials and hides the primitive
		# it was built around; an undressed one is the flat team-coloured shape
		# the game has always drawn. Hidden by a transparent material rather
		# than by `visible`, because _drawn_height still resizes the capsule to
		# carry the crouch and a hidden node would stop being measured.
		if dressed:
			view.material_override = _invisible()
			# Still a transparent draw per body and per bundle if it stays on a
			# render layer; on none, it is measured but never drawn (P3-6).
			view.layers = 0
			view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif entity.is_actor():
			view.material_override = theme.figure_material(entity.team)
		else:
			view.material_override = theme.cash
		add_child(view)
		_actor_views[entity_id] = view

## Draws every bot's current route as a line of pips.
##
## Only the authority has directors to ask - a guest sees bots as ordinary
## remote players and has no idea what they intend, which is the point.
func _draw_paths() -> void:
	var wanted: int = 0
	if _show_paths and link != null and link.crew != null:
		for actor_id: int in link.crew.actor_ids():
			var director: BotDirector = link.crew.director_for(actor_id)
			if director == null:
				continue
			var route: PackedVector3Array = director.route()
			for i: int in route.size():
				var pip: MeshInstance3D = _path_pip(wanted)
				pip.position = route[i] + Vector3(0.0, 40.0, 0.0)
				# The waypoint being steered towards, picked out: a route that
				# threads the doorway while the aim point sits on the frame is a
				# following problem, and looks nothing like a routing problem.
				var aiming: bool = i == director.leg()
				pip.scale = Vector3.ONE * (2.0 if aiming else 1.0)
				pip.material_override = _flat(
					Color(1.0, 0.4, 0.1) if aiming else Color(0.2, 1.0, 0.4)
				)
				pip.visible = true
				wanted += 1
	for i: int in range(wanted, _path_markers.size()):
		_path_markers[i].visible = false

func _path_pip(index: int) -> MeshInstance3D:
	while _path_markers.size() <= index:
		var pip: MeshInstance3D = MeshInstance3D.new()
		var ball: SphereMesh = SphereMesh.new()
		ball.radius = 10.0
		ball.height = 20.0
		pip.mesh = ball
		add_child(pip)
		_path_markers.append(pip)
	return _path_markers[index]

func _flat(colour: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	return material

func _build_lighting() -> void:
	for node: Node in WorldBackdrop.environment(ChaseCamera.FAR_PLANE, ArtTheme.current()):
		add_child(node)
	PlayerSettings.current().apply_video()

## The level's blockers as plain boxes, plus a static body per box for the
## camera arm to slide along.
##
## Those bodies are the ONLY physics in the project, they live on their own
## layer, and no rule reads them. Movement collides against the same AABBs
## deterministically inside sim/ (§6).
func _build_geometry() -> void:
	if _geometry != null:
		_geometry.queue_free()
	_geometry = Node3D.new()
	add_child(_geometry)
	var theme: ArtTheme = ArtTheme.current()
	var blockers: Array[AABB] = level.collision.blockers
	var outside: MeshInstance3D = WorldBackdrop.ground(blockers, ChaseCamera.FAR_PLANE, theme)
	if outside != null:
		outside.layers = WorldBackdrop.OUTDOOR_LAYER
		_geometry.add_child(outside)
	var lot_ground: AABB = WorldBackdrop.widest_blocker(blockers) if not blockers.is_empty() else AABB()
	var roof_top: float = -INF
	for blocker: AABB in blockers:
		roof_top = maxf(roof_top, blocker.end.y)

	# The textured shell (P3-2): every blocker but the lot's ground, merged per
	# house and material. The ground keeps its lawn box below.
	if theme.shell:
		var started: int = Time.get_ticks_usec()
		var shells: Array[MeshInstance3D] = ShellBuilder.build(level, theme, blockers.find(lot_ground))
		for shell: MeshInstance3D in shells:
			_geometry.add_child(shell)
		print("shell: %d meshes in %.0f ms" % [shells.size(),
			float(Time.get_ticks_usec() - started) / 1000.0])

	# What surrounds the houses (P3-4): fences, streets, neighbours, trees, and
	# the lot's flat finishes. Drawn only; the bounds are still the wall.
	if theme.exterior and not blockers.is_empty() and level.collision.bounds.size.x > 0.0:
		for part: Node3D in ExteriorBuilder.build(level, theme, lot_ground.end.y):
			_geometry.add_child(part)

	# Furniture (P3-3): drawn by FurnitureDresser from the level's props, never
	# as a blockout box or shell. Its blockers still get camera bodies below.
	var furniture: Dictionary[AABB, bool] = {}
	if level.level != null:
		for box: AABB in level.level.furniture:
			furniture[box] = true
		if not level.level.props.is_empty():
			_geometry.add_child(FurnitureDresser.build(level.level.props, theme))

	for blocker: AABB in blockers:
		if (not theme.shell or blocker == lot_ground) and not furniture.has(blocker):
			_blockout_solid(blocker, theme, lot_ground, roof_top)
		var body: StaticBody3D = StaticBody3D.new()
		body.position = blocker.get_center()
		body.collision_layer = CAMERA_COLLISION_LAYER
		body.collision_mask = 0
		var collider: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = blocker.size
		collider.shape = shape
		body.add_child(collider)
		_geometry.add_child(body)

	# A floor finish per room (oak, tile, carpet, concrete, lawn: the theme's
	# `floors`, by room kind). Laid on the floor the SIMULATION found (the
	# walkable surface), never the zone box's bottom - that once floated every
	# patch 41 units up. Where else it goes, and why, is FloorTint. Who owns a
	# room is not painted on the floor any more (STYLE.md §3.4). One mesh
	# indoors and one out (the outdoor render layer), a surface per finish, with
	# world UVs so a textured finish is true size.
	var indoor_patches: Array[FloorTint.Patch] = []
	var outdoor_patches: Array[FloorTint.Patch] = []
	for patch: FloorTint.Patch in FloorTint.patches(level):
		if patch.zone.outdoor:
			outdoor_patches.append(patch)
		elif not theme.shell:
			# With the shell on, the shell lays every indoor floor itself, from
			# the geometry (`ShellBuilder`: out to the walls, through the sills).
			indoor_patches.append(patch)
	for outdoor: bool in [false, true]:
		var mesh: ArrayMesh = ShellBuilder.floor_mesh(
			outdoor_patches if outdoor else indoor_patches, theme, PATCH_THICKNESS)
		if mesh == null:
			continue
		var floors: MeshInstance3D = MeshInstance3D.new()
		floors.mesh = mesh
		if outdoor:
			floors.layers = WorldBackdrop.OUTDOOR_LAYER
		_geometry.add_child(floors)

	for lamp: Node in WorldBackdrop.interior_lights(level.zones, theme, CEILING_LAMP_DROP):
		_geometry.add_child(lamp)

	_contact_shadows = ContactShadows.make(blockers, theme)
	_geometry.add_child(_contact_shadows)

## One blocker as a P1-4 blockout box: walls, floor and ceiling colours by face
## direction, in one material and one draw call (ArtTheme.blockout_box).
func _blockout_solid(blocker: AABB, theme: ArtTheme, lot_ground: AABB, roof_top: float) -> void:
	var solid: MeshInstance3D = MeshInstance3D.new()
	# The lot's ground box has a lawn on top, the highest boxes (the roofs) roof tile.
	var top: Color = theme.floor_colour
	if blocker == lot_ground:
		top = theme.lawn_colour
	elif is_equal_approx(blocker.end.y, roof_top):
		top = theme.roof_colour
	solid.mesh = theme.blockout_box(blocker.size, top)
	solid.position = blocker.get_center()
	if blocker == lot_ground:
		# Out of the room lamps' reach: it fills the screen outdoors, and on
		# Compatibility every lamp touching it draws it all again.
		solid.layers = WorldBackdrop.OUTDOOR_LAYER
	_geometry.add_child(solid)

func _build_hud() -> void:
	_text_layer = CanvasLayer.new()
	add_child(_text_layer)
	_debug_hud_visible = OS.get_cmdline_user_args().has("--debug-hud")
	# Every text here is in the shared UI theme (PT2-6): cream on a charcoal outline.
	var ui: Theme = UiTheme.current()
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.theme = ui
	_hud.theme_type_variation = UiTheme.HUD
	_hud.add_theme_font_size_override("font_size", 15)
	_text_layer.add_child(_hud)
	_hud_hint = Label.new()
	_hud_hint.position = Vector2(16, 12)
	_hud_hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	_hud_hint.theme = ui
	_hud_hint.theme_type_variation = UiTheme.HUD
	_hud_hint.add_theme_font_size_override("font_size", 13)
	_text_layer.add_child(_hud_hint)
	_banner = Label.new()
	_banner.position = Vector2(16, 300)
	_banner.theme = ui
	_banner.theme_type_variation = UiTheme.HUD
	_text_layer.add_child(_banner)
	_status = Label.new()
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_status.offset_top = 36.0
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.theme = ui
	_status.theme_type_variation = UiTheme.HUD
	_text_layer.add_child(_status)
	_status.visible = false  # the line stays for the debug HUD only
	_match_hud = MatchHud.new()
	_text_layer.add_child(_match_hud)
	_text_layer.add_child(_guide)
	_text_layer.add_child(feedback)
	_headline = Label.new()
	_headline.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_headline.offset_top = 180.0
	_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_headline.theme = ui
	_headline.theme_type_variation = UiTheme.HUD_BIG
	_text_layer.add_child(_headline)
	_tell_layer = CanvasLayer.new()
	add_child(_tell_layer)
	_tell_overlay = TeamTellOverlay.new()
	_tell_overlay.tell = TeamTell.current()
	_tell_overlay.colours = ArtTheme.current().family_colours
	_tell_layer.add_child(_tell_overlay)

# ---- HUD ----

## Every tuned number here is READ from content (WORLD_AUTHORING.md §9).
## Nothing states how long shelter lasts, or that a grab ends it.
func _update_hud() -> void:
	var truth: SimWorld = link.outcome_world()
	# The debug HUD carries the same numbers, on the same rows of screen.
	_status.visible = link.is_ready() and _debug_hud_visible
	_match_hud.visible = link.is_ready() and not _debug_hud_visible
	_headline.visible = link.is_ready()
	var ended: bool = link.is_ready() and truth.match_phase == SimWorld.MatchPhase.MATCH_END and not _split_screen
	if ended:
		_results.show_for(truth, level, link.role != MatchLink.Role.GUEST)
		if _pause.is_open():
			_set_paused(false)
		_headline.visible = false  # the panel says it; the text stays for the pilot
		_capture_mouse(false)
	elif _results.visible and not _screen_hold:
		_results.hide_panel()
		if not _pause.is_open():
			_capture_mouse(not _split_screen)
	if link.is_ready():
		var mine: SimEntity = truth.get_entity(_local_actor())
		_status.text = MatchStatus.line(truth, level, mine)
		if _match_hud.visible:
			_match_hud.refresh(truth, level, mine, players[0] if not players.is_empty() else null)
		_guide.visible = not _debug_hud_visible and not _lobby_wait
		if _guide.visible:
			_guide.refresh(truth, mine, get_process_delta_time())
		_headline.text = MatchStatus.headline(truth, level, link.role != MatchLink.Role.GUEST)
	_hud.visible = _debug_hud_visible
	_hud_hint.visible = not _debug_hud_visible
	if not _debug_hud_visible:
		var hint: String = "[F1] debug HUD"
		if link.role != MatchLink.Role.LOCAL:
			hint = "%s     %s" % [_network_line(), hint]
		_hud_hint.text = hint
		return
	var zone: ZoneDef = level.sheltered_zone()
	var lines: PackedStringArray = PackedStringArray()

	lines.append(_network_line())
	lines.append("SAFE ROOM: %s     [1]/[2] restart with the other configuration" % _describe_shelter(zone))
	lines.append("%s   round %d   %s" % [
		_phase_name(world.match_phase),
		world.round_number,
		"%.1fs" % SimWorld.ticks_to_seconds(world.phase_ticks_remaining),
	])
	for team: TeamDef in level.teams:
		lines.append("%s  cash %d  rounds %d" % [
			FamilyNames.name_of(team.id), world.score_for(team.id), world.round_wins_for(team.id),
		])

	lines.append("")
	for seat: int in players.size():
		var actor: SimEntity = world.get_entity(players[seat].actor_id)
		if actor == null:
			continue
		lines.append("P%d %s  %s%s%s" % [
			seat + 1,
			players[seat].device_name(),
			"HELD %.1fs" % SimWorld.ticks_to_seconds(actor.capture_ticks_remaining) if actor.is_captured else "free",
			"  carrying" if actor.is_carrying() else "",
			"  sheltered%s" % _shelter_remaining(actor) if actor.is_protected() else "",
		])

	# What each bot thinks it is doing. Behaviour that cannot be read off the
	# screen gets debugged by staring at capsules and guessing.
	if link.crew != null:
		for actor_id: int in link.crew.actor_ids():
			var bot: SimEntity = world.get_entity(actor_id)
			var task: BotTask = link.crew.director_for(actor_id).current_task()
			if bot == null:
				continue
			lines.append("BOT %s  %s  %s%s" % [
				FamilyNames.name_of(bot.team),
				BotCrew.Seat.keys()[link.crew.seat_of(actor_id)],
				BotTask.Kind.keys()[task.kind],
				"  carrying" if bot.is_carrying() else "",
			])

	# Where the camera IS, not where it should be. A blank window has several
	# causes that look identical from the outside - no camera in the viewport, a
	# rig stranded at the origin, a near plane swallowing the level - and this
	# line separates the ones about position from the ones that are not.
	lines.append("")
	for seat: int in _cameras.size():
		lines.append("cam%d %s  near %.0f far %.0f" % [
			seat + 1,
			_cameras[seat].world_position().round(),
			_cameras[seat].camera.near,
			_cameras[seat].camera.far,
		])

	lines.append("")
	lines.append("move WASD / left stick    look mouse / right stick")
	lines.append("jump SPACE or A    crouch SHIFT or LS (hold)")
	lines.append("seize / free ally E or B    grab-drop LMB / X    throw RMB / RB")
	lines.append("[F1] hide this    [F4] bot paths %s" % ("on" if _show_paths else "off"))
	lines.append("team tell: %s    [F5] marker  [F6] minimap  [F7] wristband  [F8] kid swap"
		% TeamTell.current().describe())
	lines.append("[F10] leave to menu    [F2] split-screen debug    [F3] bots %s    [F12] save a frame    [Esc] release mouse"
		% ("on" if _bots_enabled else "off"))
	if _split_screen and Input.get_connected_joypads().size() < 2:
		lines.append("!! split-screen wants two pads - both seats are on one")
	_hud.text = "\n".join(lines)

## Which end of the match this window is, and what a second machine needs.
##
## The code is on screen because that is where somebody reads it from. Anything
## that makes a player go and find it is friction the invite path exists to
## remove, and the fallback should not be worse than it has to be.
func _network_line() -> String:
	match link.role:
		MatchLink.Role.HOST:
			return "HOSTING   code %s   %d connected   tick %d" % [
				link.session_code(), link.transport.peers().size(), world.tick,
			]
		MatchLink.Role.GUEST:
			if not link.is_ready():
				return "CONNECTING to the host...   [F10] cancel"
			var waiting: String = "  REACHING..." if not link.awaiting().is_empty() else ""
			return "JOINED   confirmed %d   predicting %+d   remote -%d ticks%s" % [
				link.outcome_world().tick,
				link.predicted_world().tick - link.outcome_world().tick,
				level.tuning.interpolation_delay_ticks,
				waiting,
			]
	return "LOCAL   one machine, no network"

func _describe_shelter(zone: ZoneDef) -> String:
	if zone == null or not zone.grants_safety():
		return "none"
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%.1fs" % zone.safe_duration_seconds if zone.safety_is_timed() else "no timer")
	if zone.safe_ends_on_pickup:
		parts.append("ends on pickup")
	return " + ".join(parts)

func _shelter_remaining(actor: SimEntity) -> String:
	if actor.safe_ticks_remaining == SimEntity.SAFE_UNLIMITED:
		return ""
	return " %.1fs" % SimWorld.ticks_to_seconds(actor.safe_ticks_remaining)

func _phase_name(phase: SimWorld.MatchPhase) -> String:
	return SimWorld.MatchPhase.keys()[phase]

# ---- input that is not a player's ----

func _unhandled_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		if not players.is_empty() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			players[0].add_mouse_motion(motion.relative)
		return

	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	# The menu owns the keyboard while it is up, and with no match there is
	# nothing for the in-game keys to act on.
	if _menu != null and _menu.visible:
		return
	if link == null:
		return
	match key.keycode:
		KEY_F9:
			_guide.skip()
		KEY_F10:
			_return_to_menu("")
		KEY_ENTER, KEY_KP_ENTER:
			# Only the authority restarts a match; a guest is told it happened.
			if link.role != MatchLink.Role.GUEST \
					and link.outcome_world().match_phase == SimWorld.MatchPhase.MATCH_END:
				_rematch_asked = true
		KEY_F1:
			_debug_hud_visible = not _debug_hud_visible
		KEY_F5, KEY_F6, KEY_F7, KEY_F8:
			# The D3 team tell, one option a key, combinable (TeamTell.OPTIONS order:
			# marker, minimap, wristband, kid swap). Saved for next time.
			_toggle_tell(TeamTell.OPTIONS[key.keycode - KEY_F5])
		KEY_1:
			# Switching variant rebuilds the session. Only a local match can do
			# that - a host would be re-opening a port it already holds, and a
			# guest has no say over the rules.
			if link.role == MatchLink.Role.LOCAL:
				_reset(GreyBoxLevel.SafeVariant.A)
		KEY_2:
			if link.role == MatchLink.Role.LOCAL:
				_reset(GreyBoxLevel.SafeVariant.B)
		KEY_F2:
			# Debug only. The real game is online - one player, one camera, one
			# mouse - so a second seat here is for watching two bodies while
			# tuning, never for how the game is played.
			_split_screen = not _split_screen
			_capture_mouse(not _split_screen)
			_build_seats()
		KEY_ESCAPE:
			if _split_screen:
				_capture_mouse(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
			elif not _results.visible and link.is_ready() and not _pause.is_rebinding():
				_set_paused(not _pause.is_open())
		KEY_F12:
			_capture_frame(FrameCapture.DEFAULT_PATH)
		KEY_F4:
			_show_paths = not _show_paths
			_draw_paths()
		KEY_F3:
			# Proving the claim as much as offering the option: with bots off,
			# every seat they held goes back to being an actor nobody is
			# driving, and the match runs exactly as it did before they existed.
			# Only the authority has bots to toggle. A guest asking would be
			# asking about somebody else's machine.
			if link.role == MatchLink.Role.GUEST:
				return
			_bots_enabled = not _bots_enabled
			link.lobby.bots_enabled = _bots_enabled
			if _bots_enabled:
				link.lobby.note_fill(
					link.crew.fill_lobby(world, _seated_actors(), world.actor_ids().size()),
					link.crew.declined_reason
				)
			else:
				for actor_id: int in link.crew.actor_ids():
					link.crew.release(world, actor_id)

## Only the authority restarts a match; a guest is told it happened.
func _ask_rematch() -> void:
	if link != null and link.role != MatchLink.Role.GUEST and link.outcome_world().match_phase == SimWorld.MatchPhase.MATCH_END:
		_rematch_asked = true

## The pause panel. The sim keeps running; the local seats stand still.
func _set_paused(paused: bool) -> void:
	if _pause == null or paused == _pause.is_open():
		return
	if paused:
		_pause.open()
	else:
		_pause.close()
	for player: LocalPlayerInput in players:
		player.suspended = paused
	_capture_mouse(not paused and not _split_screen)

func _capture_mouse(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE

## Switching variant rebuilds rather than editing content in place: a runtime
## edit would be presentation writing into the layer the rules read.
func _reset(variant: GreyBoxLevel.SafeVariant) -> void:
	for view: MeshInstance3D in _actor_views.values():
		view.queue_free()
	_actor_views.clear()
	_clear_animators()
	_view_heights.clear()
	_facings.clear()
	_body_opacity.clear()
	_banner.text = ""
	_start(variant)
