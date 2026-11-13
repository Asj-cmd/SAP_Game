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
## How proud of the floor a team's floor tint sits. Enough to win the depth
## test against the floor it is laid on, little enough not to be a step.
const PATCH_THICKNESS: float = 0.6
## How far below the top of a room's zone its ceiling lamp hangs: the slab
## above (40) plus a fitting's drop.
const CEILING_LAMP_DROP: float = 60.0

const SNAP_DISTANCE: float = 400.0
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
var _identity: String = ""
var _backend: String = "enet"
## Bodies a side. From `--team-size=N` or the menu; a guest takes the host's
## (it is told with its seat and rejoins if it guessed wrong, see _rejoin_at).
var _team_size: int = GreyBoxLevel.DEFAULT_TEAM_SIZE
var _menu: MainMenu = null
## Started from the menu rather than from flags, so a failure goes back there
## with its reason instead of leaving a dead screen behind a banner.
var _from_menu: bool = false

func _ready() -> void:
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
	# Plays this window through a whole session by injected input (debug).
	if PlaytestPilot.requested(OS.get_cmdline_user_args()):
		add_child(PlaytestPilot.new(self))
	# Hashes this end of a two-process session for autobuild/net_smoke.mjs (debug).
	if NetSmoke.requested(OS.get_cmdline_user_args()):
		add_child(NetSmoke.new(self))
	if _wants_menu():
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
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--host" or arg == "--solo" or arg == "--split" \
				or arg.begins_with("--join") or arg.begins_with("--capture"):
			return false
	return true

func _read_command_line() -> void:
	_role = _role_from_command_line()
	_join_code = _argument("--join=", "")
	_advertise = _argument("--advertise=", "")
	_identity = _argument("--identity=", "")
	_backend = _argument("--backend=", "enet")
	_team_size = clampi(int(_argument("--team-size=", str(GreyBoxLevel.DEFAULT_TEAM_SIZE))),
		GreyBoxLevel.TEAM_SIZES.front(), GreyBoxLevel.TEAM_SIZES.back())

func _on_solo(team_size: int) -> void:
	_team_size = team_size
	_launch(MatchLink.Role.LOCAL, "", "")

func _on_host(address: String, team_size: int) -> void:
	_team_size = team_size
	_launch(MatchLink.Role.HOST, "", address)

func _on_join(code: String) -> void:
	_launch(MatchLink.Role.GUEST, code, "")

func _launch(role: MatchLink.Role, code: String, address: String) -> void:
	_role = role
	_join_code = code
	_advertise = address
	_from_menu = true
	_menu.close()
	_capture_mouse(not _split_screen)
	_start(GreyBoxLevel.SafeVariant.B)
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
	_capture_mouse(false)
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
	if link != null:
		link.close()
	link = null
	world = null
	players.clear()
	for view: MeshInstance3D in _actor_views.values():
		view.queue_free()
	_actor_views.clear()
	_view_heights.clear()
	_facings.clear()
	_body_opacity.clear()
	if _reach_marker != null:
		_reach_marker.visible = false
	_banner.text = ""
	# Nothing updates these without a match, so they would sit over the menu.
	_status.visible = false
	_headline.visible = false
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
		await get_tree().process_frame
	if request.paths:
		_show_paths = true
		_draw_paths()
		await get_tree().process_frame
	for i: int in request.figures.size():
		var spot: Vector4 = request.figures[i]
		var model: PackedScene = null
		if request.figure_models[i] != "" and ResourceLoader.exists(request.figure_models[i]):
			model = load(request.figure_models[i]) as PackedScene
		var posed: Node3D = _figure_instance(&"team_a", model)
		if posed == null:
			push_error("frame capture: no figure model to stand at %s" % spot)
			break
		posed.position = Vector3(spot.x, spot.y, spot.z)
		posed.rotation = Vector3(0.0, deg_to_rad(spot.w), 0.0)
		add_child(posed)
	if not request.figures.is_empty():
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
	if request.shot_count() == 0:
		await _capture_frame(request.path)
	else:
		if not request.eyes.is_empty():
			await _capture_from(request)
		if not request.chase_feet.is_empty():
			await _capture_chase(request)
	if request.quit_after:
		get_tree().quit()

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

func _start(variant: GreyBoxLevel.SafeVariant) -> void:
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
		if link.lobby.bots_enabled:
			link.lobby.note_fill(
				link.crew.fill_lobby(world, _seated_actors(), world.actor_ids().size()),
				link.crew.declined_reason
			)
		world.step([MatchCommand.start()])

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
	if args.has("--host"):
		return MatchLink.Role.HOST
	for arg: String in args:
		if arg == "--join" or arg.begins_with("--join="):
			return MatchLink.Role.GUEST
	return MatchLink.Role.LOCAL

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
		_fade_body(players[seat].actor_id, view, _cameras[seat].body_opacity())

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

		view.position = target + _view_offset(
			entity, _drawn_height(entity_id, entity, view, delta))
		_face(entity_id, entity, view, delta)
		# Held, carrying and captured are read from the CONFIRMED world on every
		# role. A guest never guesses at an outcome.
		view.visible = true

	_hold_carried(truth)
	_show_reach(mine)

## A held bundle is drawn over its carrier's head.
##
## It used to be hidden while held (the simulation puts it at the carrier's
## centre, inside the mesh), so from the chair nobody could see who had the cash
## - including the player carrying it (P0-8 walkthrough). In front of the chest
## was tried first: the chase camera sits behind, so the body hid it. Overhead
## reads from every side. Placed after every body has been, so it follows the
## carrier drawn THIS frame. A carry pose replaces this with animation (P2-3).
func _hold_carried(truth: SimWorld) -> void:
	for entity_id: int in truth.sorted_entity_ids():
		var entity: SimEntity = truth.entities[entity_id]
		if not entity.is_carriable() or not entity.is_held():
			continue
		var view: MeshInstance3D = _actor_views.get(entity_id, null)
		var carrier: MeshInstance3D = _actor_views.get(entity.carried_by, null)
		if view == null or carrier == null:
			continue
		# The carrier's view sits at the middle of the height drawn for it, so
		# half that height up is the top of its head, crouched or not.
		var drawn: float = _view_heights.get(entity.carried_by, ACTOR_HEIGHT)
		view.position = carrier.position + Vector3(0.0, drawn * 0.5 + CARRY_GAP, 0.0)
		view.rotation = Vector3(0.0, _facings.get(entity.carried_by, 0.0), 0.0)

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
func _face(entity_id: int, entity: SimEntity, view: Node3D, delta: float) -> void:
	if not entity.is_actor():
		return
	var travel: Vector3 = Vector3(entity.velocity.x, 0.0, entity.velocity.z)
	if travel.length_squared() < 1.0:
		return
	var wanted: float = atan2(travel.x, travel.z)
	var now: float = _facings.get(entity_id, wanted)
	# Shortest way round, so crossing the -PI seam does not spin the long way.
	var gap: float = wrapf(wanted - now, -PI, PI)
	var turned: float = wrapf(now + gap * minf(1.0, FACE_RATE * delta), -PI, PI)
	_facings[entity_id] = turned
	view.rotation = Vector3(0.0, turned, 0.0)

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
func _figure_instance(team: StringName, model: PackedScene = null) -> Node3D:
	var figure: PackedScene = model if model != null else _actor_model(team)
	if figure == null:
		return null
	var theme: ArtTheme = ArtTheme.current()
	var art: Node3D = figure.instantiate() as Node3D
	ArtTheme.dress_whole(art, theme.figure_material(team))
	if model != null or theme.figure_scene() != null:
		theme.shape_figure(art)
	var holder: Node3D = Node3D.new()
	holder.add_child(art)
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

func _rebuild_views() -> void:
	for view: MeshInstance3D in _actor_views.values():
		view.queue_free()
	_actor_views.clear()
	_view_heights.clear()
	_facings.clear()
	_body_opacity.clear()

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
			var art: Node3D = _figure_instance(entity.team)
			if art != null:
				# The model's origin is its FEET and the capsule's is its
				# middle, so the figure drops half a body to stand in it.
				art.position = Vector3(0.0, -ACTOR_HEIGHT * 0.5, 0.0)
				view.add_child(art)
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
				view.add_child(bundle)
				dressed = true
			else:
				var box: BoxMesh = BoxMesh.new()
				box.size = Vector3(CASH_SIZE, CASH_SIZE, CASH_SIZE)
				view.mesh = box
		# A dressed view keeps its model's own materials and hides the primitive
		# it was built around; an undressed one is the flat team-coloured shape
		# the game has always drawn. Hidden by a transparent material rather
		# than by `visible`, because _drawn_height still resizes the capsule to
		# carry the crouch and a hidden node would stop being measured.
		if dressed:
			view.material_override = _invisible()
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

	for blocker: AABB in blockers:
		var solid: MeshInstance3D = MeshInstance3D.new()
		# Walls, floor and ceiling colours by face direction, in one material
		# and one draw call per box (ArtTheme.blockout_box); the lot's ground
		# box has a lawn on top, the highest boxes (the roofs) roof tile.
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
	# room is not painted on the floor any more (STYLE.md §3.4).
	for patch: FloorTint.Patch in FloorTint.patches(level):
		var finish: StandardMaterial3D = theme.floors.get(ArtTheme.room_kind(patch.zone.id), null)
		if finish == null:
			continue
		var tint: MeshInstance3D = MeshInstance3D.new()
		var slab: BoxMesh = BoxMesh.new()
		# Thin, and only just clear of the floor. A tint, not a rug: at two
		# units thick and a unit up it read as a raised platform with a lip.
		slab.size = Vector3(patch.footprint.size.x, PATCH_THICKNESS, patch.footprint.size.y)
		tint.mesh = slab
		var middle: Vector2 = patch.footprint.get_center()
		tint.position = Vector3(middle.x, patch.floor_y + PATCH_THICKNESS * 0.5, middle.y)
		tint.material_override = finish
		if patch.zone.outdoor:
			tint.layers = WorldBackdrop.OUTDOOR_LAYER
		_geometry.add_child(tint)

	for lamp: Node in WorldBackdrop.interior_lights(level.zones, theme, CEILING_LAMP_DROP):
		_geometry.add_child(lamp)

func _build_hud() -> void:
	_text_layer = CanvasLayer.new()
	add_child(_text_layer)
	_debug_hud_visible = OS.get_cmdline_user_args().has("--debug-hud")
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_text_layer.add_child(_hud)
	_hud_hint = Label.new()
	_hud_hint.position = Vector2(16, 12)
	_hud_hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	_text_layer.add_child(_hud_hint)
	_banner = Label.new()
	_banner.position = Vector2(16, 300)
	_text_layer.add_child(_banner)
	_status = Label.new()
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_status.offset_top = 36.0
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_constant_override("outline_size", 6)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_text_layer.add_child(_status)
	_headline = Label.new()
	_headline.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_headline.offset_top = 180.0
	_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_headline.add_theme_font_size_override("font_size", 44)
	_headline.add_theme_constant_override("outline_size", 10)
	_headline.add_theme_color_override("font_outline_color", Color.BLACK)
	_text_layer.add_child(_headline)

# ---- HUD ----

## Every tuned number here is READ from content (WORLD_AUTHORING.md §9).
## Nothing states how long shelter lasts, or that a grab ends it.
func _update_hud() -> void:
	var truth: SimWorld = link.outcome_world()
	# The debug HUD carries the same numbers, on the same rows of screen.
	_status.visible = link.is_ready() and not _debug_hud_visible
	_headline.visible = link.is_ready()
	if link.is_ready():
		_status.text = MatchStatus.line(truth, level, truth.get_entity(_local_actor()))
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
			team.display_name, world.score_for(team.id), world.round_wins_for(team.id),
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
				bot.team,
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
		KEY_F10:
			_return_to_menu("")
		KEY_ENTER, KEY_KP_ENTER:
			# Only the authority restarts a match; a guest is told it happened.
			if link.role != MatchLink.Role.GUEST \
					and link.outcome_world().match_phase == SimWorld.MatchPhase.MATCH_END:
				_rematch_asked = true
		KEY_F1:
			_debug_hud_visible = not _debug_hud_visible
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
			_capture_mouse(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
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

func _capture_mouse(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE

## Switching variant rebuilds rather than editing content in place: a runtime
## edit would be presentation writing into the layer the rules read.
func _reset(variant: GreyBoxLevel.SafeVariant) -> void:
	for view: MeshInstance3D in _actor_views.values():
		view.queue_free()
	_actor_views.clear()
	_view_heights.clear()
	_facings.clear()
	_body_opacity.clear()
	_banner.text = ""
	_start(variant)
