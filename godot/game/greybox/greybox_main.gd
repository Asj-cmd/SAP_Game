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
var _geometry: Node3D = null
var _seats: CanvasLayer = null
var _cameras: Array[ChaseCamera] = []
var _split_screen: bool = false
var _hud: Label = null
var _banner: Label = null
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

func _ready() -> void:
	_build_lighting()
	_build_hud()
	# The debug split can be asked for at startup as well as with F2, so an
	# unattended run can capture a frame of it. A mode nobody can screenshot is
	# a mode that quietly rots.
	_split_screen = OS.get_cmdline_user_args().has("--split")
	_capture_mouse(not _split_screen)
	_start(GreyBoxLevel.SafeVariant.B)
	_arm_capture()

# ---- looking at the screen ----

## Honours `--capture` on the command line: wait, save a PNG, exit.
##
## An unattended run that can produce a frame is the only way a claim about
## what the game LOOKS like gets checked. See FrameCapture.
func _arm_capture() -> void:
	var request: FrameCapture = FrameCapture.from_command_line(OS.get_cmdline_user_args())
	if not request.requested:
		return
	await get_tree().create_timer(request.delay).timeout
	if request.paths:
		_show_paths = true
		_draw_paths()
		await get_tree().process_frame
	if request.grab:
		# Through Input, not around it: the same key LocalPlayerInput polls, so
		# the frame shows the real path rather than a state posed for a photo.
		var press: InputEventKey = InputEventKey.new()
		press.keycode = KEY_Q
		press.pressed = true
		Input.parse_input_event(press)
		await get_tree().process_frame
		await get_tree().process_frame
	await _capture_frame(request.path)
	if request.quit_after:
		get_tree().quit()

func _capture_frame(to_path: String) -> void:
	# The texture only holds a finished frame after the draw, not after the
	# _process that queued it.
	await RenderingServer.frame_post_draw
	var written: String = FrameCapture.save(get_viewport(), to_path)
	if written == "":
		return
	print("frame capture: %s" % written)
	print("  %s" % FrameCapture.describe(_active_camera(), _actor_views.size()))

func _active_camera() -> Camera3D:
	return _cameras[0].camera if not _cameras.is_empty() else null

# ---- setup ----

func _start(variant: GreyBoxLevel.SafeVariant) -> void:
	level = GreyBoxLevel.new(variant)
	if not level.is_loaded():
		_banner.text = "NO BAKED LEVEL\nrun tools/build_house.gd then tools/bake_blockout.gd"
		return
	_build_geometry()

	var role: MatchLink.Role = _role_from_command_line()
	var backend: String = _argument("--backend=", "enet")

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
				level, worlds[0], _bots_enabled, backend,
				_argument("--advertise=", ""), _argument("--identity=", "")
			)
		MatchLink.Role.GUEST:
			link = MatchLink.guest(
				level, worlds, backend, _argument("--join=", ""), _argument("--identity=", "")
			)
		_:
			link = MatchLink.local(level, worlds[0], _bots_enabled)
	if link.failure != "":
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
	_render(_accumulator / SimWorld.SECONDS_PER_TICK)
	_track_cameras(delta)
	_update_hud()

func _advance_one_tick() -> void:
	_previous = _snapshot()
	var drawn: SimWorld = link.predicted_world()
	var commands: Array[SimCommand] = []
	for player: LocalPlayerInput in players:
		commands.append_array(player.drain(drawn, drawn.tick))
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
	for seat: int in mini(_cameras.size(), players.size()):
		var view: MeshInstance3D = _actor_views.get(players[seat].actor_id, null)
		if view == null:
			continue
		_cameras[seat].follow(view.position - Vector3(0.0, ACTOR_HEIGHT * 0.5, 0.0), delta)

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
func _render(alpha: float) -> void:
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

		view.position = target + _view_offset(entity)
		# Held, carrying and captured are read from the CONFIRMED world on every
		# role. A guest never guesses at an outcome.
		view.visible = not (entity.is_carriable() and entity.is_held())

	_show_reach(mine)

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

## Lifts an actor's mesh so it stands ON the floor. The simulation's position
## is the centre of a body one radius tall; the capsule is taller than that.
func _view_offset(entity: SimEntity) -> Vector3:
	if not entity.is_actor():
		return Vector3.ZERO
	return Vector3(0.0, ACTOR_HEIGHT * 0.5 - level.tuning.actor_radius, 0.0)

func _rebuild_views() -> void:
	for view: MeshInstance3D in _actor_views.values():
		view.queue_free()
	_actor_views.clear()

	if _reach_marker == null:
		_reach_marker = MeshInstance3D.new()
		var pip: SphereMesh = SphereMesh.new()
		pip.radius = 22.0
		pip.height = 44.0
		_reach_marker.mesh = pip
		_reach_marker.material_override = _flat(Color(1.0, 0.85, 0.2))
		_reach_marker.visible = false
		add_child(_reach_marker)

	for entity_id: int in world.sorted_entity_ids():
		var entity: SimEntity = world.entities[entity_id]
		var view: MeshInstance3D = MeshInstance3D.new()
		if entity.is_actor():
			var body: CapsuleMesh = CapsuleMesh.new()
			body.radius = level.tuning.actor_radius
			body.height = ACTOR_HEIGHT
			view.mesh = body
		else:
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(50, 50, 50)
			view.mesh = box
		view.material_override = _flat(_team_colour(entity.team, entity.is_carriable()))
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

func _team_colour(team: StringName, is_cash: bool) -> Color:
	var base: Color = Color(0.85, 0.25, 0.25) if team == &"team_a" else Color(0.25, 0.45, 0.9)
	return base.lightened(0.4) if is_cash else base

func _flat(colour: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	return material

func _build_lighting() -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -40, 0)
	sun.light_energy = 1.1
	add_child(sun)

	var environment: WorldEnvironment = WorldEnvironment.new()
	var settings: Environment = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.07, 0.07, 0.09)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.45, 0.45, 0.5)
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	add_child(environment)

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

	for blocker: AABB in level.collision.blockers:
		var solid: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = blocker.size
		solid.mesh = box
		solid.position = blocker.get_center()
		solid.material_override = _flat(Color(0.26, 0.26, 0.29))
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

	# A floor patch per owned room, so which house you are in is readable
	# without labels or art.
	#
	# Laid on the floor the SIMULATION found, not on the bottom of the zone box.
	# A zone is a volume that means something and may be generous (§2); where
	# the floor is, is a fact about the geometry, and the walkable surface is
	# the thing that already knows it. This used to be `bounds.position.y + 41`
	# - the 41 being the grey box's floor slab plus one - and the house puts its
	# room zones flush with each storey instead, so every patch floated 41 units
	# in the air and every body looked sunk to the shins in it. One offset, both
	# complaints.
	for zone: ZoneDef in level.zones:
		if zone.owner_team == &"":
			continue
		var floor_y: float = _floor_of(zone)
		if floor_y == INF:
			continue # nowhere to stand in it; nothing to tint
		var patch: MeshInstance3D = MeshInstance3D.new()
		var slab: BoxMesh = BoxMesh.new()
		slab.size = Vector3(zone.bounds.size.x, 2.0, zone.bounds.size.z)
		patch.mesh = slab
		patch.position = Vector3(
			zone.bounds.get_center().x,
			floor_y + 1.0,
			zone.bounds.get_center().z
		)
		var tint: Color = _team_colour(zone.owner_team, false)
		patch.material_override = _flat(
			tint.darkened(0.25 if zone.role == ZoneDef.Role.CASH_ROOM else 0.6)
		)
		_geometry.add_child(patch)

## The height an actor's FEET rest at inside this zone, or INF if none do.
##
## Taken from the lowest stance the walkable surface found there, minus the body
## radius, because a stance is where a body's CENTRE sits rather than where the
## floor is. Lowest rather than nearest, so a room with a step in it tints from
## its main floor.
##
## Read off the LEVEL rather than the world, because geometry is built before a
## world exists. Taking it from `world.surface` skipped every patch instead of
## misplacing it - a quieter bug than the one being fixed and no better.
func _floor_of(zone: ZoneDef) -> float:
	if level.surface == null or level.surface.nodes.is_empty():
		return INF
	var lowest: float = INF
	for stance: Vector3 in level.surface.nodes:
		if zone.contains_point(stance):
			lowest = minf(lowest, stance.y)
	if lowest == INF:
		return INF
	return lowest - level.tuning.actor_radius

func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	layer.add_child(_hud)
	_banner = Label.new()
	_banner.position = Vector2(16, 300)
	layer.add_child(_banner)

# ---- HUD ----

## Every tuned number here is READ from content (WORLD_AUTHORING.md §9).
## Nothing states how long shelter lasts, or that a grab ends it.
func _update_hud() -> void:
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
	lines.append("grab-drop Q/X    seize E/A    free ally R/B")
	lines.append("[F4] bot paths %s" % ("on" if _show_paths else "off"))
	lines.append("[F2] split-screen debug    [F3] bots %s    [F12] save a frame    [Esc] release mouse"
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
		if not players.is_empty():
			players[0].add_mouse_motion(motion.relative)
		return

	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	match key.keycode:
		KEY_1:
			_reset(GreyBoxLevel.SafeVariant.A)
		KEY_2:
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
	_banner.text = ""
	_start(variant)
