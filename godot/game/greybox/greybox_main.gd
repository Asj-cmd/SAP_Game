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
## Ceiling on catch-up steps in one frame. Without it a long stall makes the
## next frame simulate the whole gap, which stalls again.
const MAX_STEPS_PER_FRAME: int = 5

var world: SimWorld = null
var level: GreyBoxLevel = null
var players: Array[LocalPlayerInput] = []

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

func _ready() -> void:
	_build_lighting()
	_build_hud()
	_capture_mouse(true)
	_start(GreyBoxLevel.SafeVariant.B)

# ---- setup ----

func _start(variant: GreyBoxLevel.SafeVariant) -> void:
	level = GreyBoxLevel.new(variant)
	if not level.is_loaded():
		_banner.text = "NO BAKED LEVEL\nrun tools/bake_blockout.gd on game/blockout/greybox_house.tscn"
		return
	_build_geometry()

	world = SimWorld.new(20260802)
	# Gated: broken content does not install and the world will not step
	# (WORLD_AUTHORING.md §7).
	if not world.configure(level.mode, level.tuning, level.zones, level.teams, level.collision):
		_banner.text = "CONTENT REJECTED\n%s" % "\n".join(world.content_failures)
		push_error("grey box: level content failed validation, refusing to run")
		return

	# Registration order is irrelevant - each system declares its phase.
	world.add_system(MovementSystem.new())
	world.add_system(CarrySystem.new())
	world.add_system(CaptureSystem.new())
	world.add_system(ScoringSystem.new())
	world.add_system(MatchFlowSystem.new())

	# The world builds its own bodies from content. Nothing here writes a
	# single field of simulation state.
	world.populate_roster()
	_build_seats()
	_rebuild_views()
	_previous = _snapshot()
	_accumulator = 0.0
	world.step([MatchCommand.start()])

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
		add_child(chase.rig)
		viewport.add_child(chase.camera)
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

	var seats: Array[int] = world.actor_ids()
	for seat: int in mini(players.size(), seats.size()):
		players[seat].actor_id = seats[seat]

# ---- the loop ----

## Explicitly accumulated, and explicitly NOT _physics_process.
##
## The simulation runs at its own fixed rate and must stay there. Jolt will
## want 60 Hz for ragdoll work later while the rules stay at 30, and tying the
## two together now would make that a migration instead of a setting.
func _process(delta: float) -> void:
	if world == null or not world.has_valid_content():
		return

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

	_render(_accumulator / SimWorld.SECONDS_PER_TICK)
	_track_cameras(delta)
	_update_hud()

func _advance_one_tick() -> void:
	_previous = _snapshot()
	var commands: Array[SimCommand] = []
	for player: LocalPlayerInput in players:
		commands.append_array(player.drain(world, world.tick))
	world.step(commands)

## A frozen copy of every entity, taken before the world moves on.
##
## duplicate_entity() rather than a reference: an aliased snapshot would track
## the live world and interpolate a value against itself, which looks exactly
## like no interpolation and is maddening to diagnose.
func _snapshot() -> Dictionary[int, SimEntity]:
	var frame: Dictionary[int, SimEntity] = {}
	for entity_id: int in world.sorted_entity_ids():
		frame[entity_id] = world.entities[entity_id].duplicate_entity()
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

# ---- rendering ----

func _render(alpha: float) -> void:
	for entity_id: int in world.sorted_entity_ids():
		var entity: SimEntity = world.entities[entity_id]
		var view: MeshInstance3D = _actor_views.get(entity_id, null)
		if view == null:
			continue
		var target: Vector3 = entity.position
		var earlier: SimEntity = _previous.get(entity_id, null)
		if earlier != null:
			# A teleport is not motion. Interpolating a jailing would slide the
			# body across the map instead of putting it in the cell.
			if earlier.position.distance_to(target) < SNAP_DISTANCE:
				target = earlier.position.lerp(target, clampf(alpha, 0.0, 1.0))
		view.position = target + _view_offset(entity)
		view.visible = not (entity.is_carriable() and entity.is_held())

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
	for zone: ZoneDef in level.zones:
		if zone.owner_team == &"":
			continue
		var patch: MeshInstance3D = MeshInstance3D.new()
		var slab: BoxMesh = BoxMesh.new()
		slab.size = Vector3(zone.bounds.size.x, 2.0, zone.bounds.size.z)
		patch.mesh = slab
		patch.position = Vector3(
			zone.bounds.get_center().x,
			zone.bounds.position.y + 41.0,
			zone.bounds.get_center().z
		)
		var tint: Color = _team_colour(zone.owner_team, false)
		patch.material_override = _flat(
			tint.darkened(0.25 if zone.role == ZoneDef.Role.CASH_ROOM else 0.6)
		)
		_geometry.add_child(patch)

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

	lines.append("")
	lines.append("move WASD / left stick    look mouse / right stick")
	lines.append("grab-drop Q/X    seize E/A    free ally R/B")
	lines.append("[F2] split-screen debug (needs two pads)    [Esc] release mouse")
	if _split_screen and Input.get_connected_joypads().size() < 2:
		lines.append("!! split-screen wants two pads - both seats are on one")
	_hud.text = "\n".join(lines)

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
