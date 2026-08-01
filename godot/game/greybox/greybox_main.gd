extends Node3D
## The grey-box playable slice: two people on one couch, plain shapes.
##
## Purpose is a FEEL TEST, not a demo. It exists to settle safe-room variant A
## against variant B by playing them, and to tune movement before a house is
## authored around numbers nobody has felt. Anything that makes it look
## finished works against that, so: boxes, capsules, team colours, nothing else.
##
## The contract that matters here is one-directional (ARCHITECTURE.md §1).
## This layer READS simulation state and EMITS commands. It never writes into
## the world. Every visual below is derived from SimEntity values, and the only
## path from a controller to the simulation is a SimCommand.

const SNAP_DISTANCE: float = 120.0
## Ceiling on catch-up steps in one frame. Without it a long stall makes the
## next frame simulate the whole gap, which stalls again - the spiral that
## turns one hitch into a freeze.
const MAX_STEPS_PER_FRAME: int = 5

var world: SimWorld = null
var level: GreyBoxLevel = null
var players: Array[LocalPlayerInput] = []

## The two most recent simulation states. Rendering interpolates between them,
## which is what lets a 30 Hz simulation drive a 144 Hz screen without the
## simulation knowing the screen exists (§7).
var _previous: Dictionary[int, SimEntity] = {}
var _accumulator: float = 0.0

var _actor_views: Dictionary[int, MeshInstance3D] = {}
var _geometry: Node3D = null
var _cameras: Array[ChaseCamera] = []
var _hud: Label = null
var _banner: Label = null

func _ready() -> void:
	_build_viewports()
	_build_lighting()
	_build_hud()
	_start(GreyBoxLevel.SafeVariant.B)

# ---- setup ----

func _start(variant: GreyBoxLevel.SafeVariant) -> void:
	level = GreyBoxLevel.new(variant)
	if not level.is_loaded():
		_banner.text = "NO BAKED LEVEL
run tools/bake_blockout.gd on game/blockout/greybox_house.tscn"
		return
	_build_geometry()

	world = SimWorld.new(20260801)
	# Gated: broken content does not install and the world will not step
	# (WORLD_AUTHORING.md §7). Failing loudly here beats discovering it by
	# walking through a wall.
	var accepted: bool = world.configure(
		level.mode, level.tuning, level.zones, level.teams, level.collision
	)
	if not accepted:
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
	# single field of simulation state - this layer reads and commands, and
	# that is the whole of its contract (§1).
	world.populate_roster()
	_assign_devices()
	_rebuild_views()
	for chase: ChaseCamera in _cameras:
		chase.reset()
	_previous = _snapshot()
	_accumulator = 0.0
	world.step([MatchCommand.start()])

## Keyboard plus a pad, or two pads. Two players is the whole point: every open
## question in this slice is about what two people do to each other, and a
## third seat or a bot would answer none of them.
func _assign_devices() -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	players = []
	if pads.size() >= 2:
		players.append(LocalPlayerInput.new(LocalPlayerInput.Device.GAMEPAD, pads[0]))
		players.append(LocalPlayerInput.new(LocalPlayerInput.Device.GAMEPAD, pads[1]))
	else:
		players.append(LocalPlayerInput.new(LocalPlayerInput.Device.KEYBOARD))
		var pad: int = pads[0] if pads.size() > 0 else 0
		players.append(LocalPlayerInput.new(LocalPlayerInput.Device.GAMEPAD, pad))

	var seats: Array[int] = world.actor_ids()
	for seat: int in mini(players.size(), seats.size()):
		players[seat].actor_id = seats[seat]

# ---- the loop ----

## Explicitly accumulated, and explicitly NOT _physics_process.
##
## The simulation runs at its own fixed rate and must stay there. Jolt will
## want 60 Hz for ragdoll work later; the rules will still want 30. Tying the
## two together now would make that a migration instead of a setting.
func _process(delta: float) -> void:
	if world == null or not world.has_valid_content():
		return

	for player: LocalPlayerInput in players:
		player.poll()

	_accumulator += delta
	var steps: int = 0
	while _accumulator >= SimWorld.SECONDS_PER_TICK and steps < MAX_STEPS_PER_FRAME:
		_accumulator -= SimWorld.SECONDS_PER_TICK
		steps += 1
		_advance_one_tick()
	if steps == MAX_STEPS_PER_FRAME:
		# Dropped time rather than chased it. Better a visible skip than a
		# frame that takes longer to simulate than it took to arrive.
		_accumulator = 0.0

	_render(_accumulator / SimWorld.SECONDS_PER_TICK)
	_track_cameras(delta)
	_update_hud()

## Each seat gets its own chase camera, following the body that seat drives.
##
## The camera reads the RENDERED position, not the simulation's - otherwise it
## would step 30 times a second while the world it is looking at moves
## smoothly, and the judder would be blamed on the movement code.
func _track_cameras(delta: float) -> void:
	for seat: int in mini(_cameras.size(), players.size()):
		var actor: SimEntity = world.get_entity(players[seat].actor_id)
		if actor == null:
			continue
		var view: MeshInstance3D = _actor_views.get(players[seat].actor_id, null)
		var here: Vector3 = view.position if view != null else actor.position
		_cameras[seat].follow(here, actor.velocity, delta)

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
## like no interpolation at all and is maddening to diagnose.
func _snapshot() -> Dictionary[int, SimEntity]:
	var frame: Dictionary[int, SimEntity] = {}
	for entity_id: int in world.sorted_entity_ids():
		frame[entity_id] = world.entities[entity_id].duplicate_entity()
	return frame

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
		view.position = target
		view.visible = not (entity.is_carriable() and entity.is_held())

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
			body.height = level.tuning.actor_radius * 4.0
			view.mesh = body
		else:
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(24, 24, 24)
			view.mesh = box
		view.material_override = _flat(_team_colour(entity.team, entity.is_carriable()))
		add_child(view)
		_actor_views[entity_id] = view

func _team_colour(team: StringName, is_cash: bool) -> Color:
	var base: Color = Color(0.85, 0.25, 0.25) if team == &"team_a" else Color(0.25, 0.45, 0.9)
	return base.lightened(0.35) if is_cash else base

func _flat(colour: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	return material

## Split-screen: one viewport per seat, both rendering the same 3D world.
##
## Two chase cameras rather than one shared framing camera. A shared camera has
## to pull back far enough to hold both players, which is the distant view that
## made movement unjudgeable in the first place - and this slice exists to
## judge movement.
func _build_viewports() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = -1 # behind the HUD
	add_child(layer)

	var split: HBoxContainer = HBoxContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 4)
	layer.add_child(split)

	for seat: int in 2:
		var container: SubViewportContainer = SubViewportContainer.new()
		container.stretch = true
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		split.add_child(container)

		var viewport: SubViewport = SubViewport.new()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.handle_input_locally = false
		container.add_child(viewport)
		# Both viewports render THIS node's world, so the geometry and actor
		# meshes exist once and are seen twice.
		viewport.world_3d = get_world_3d()

		var chase: ChaseCamera = ChaseCamera.new()
		viewport.add_child(chase.camera)
		chase.camera.current = true
		_cameras.append(chase)

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

## The level's blockers, drawn as the plain boxes they are. Rebuilt whenever a
## level loads; the shell is not drawn, since a box around the camera is only
## ever in the way.
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
		solid.material_override = _flat(Color(0.24, 0.24, 0.27))
		_geometry.add_child(solid)

	# Rooms get a flat floor patch in their owner's colour, so which house you
	# are standing in is readable without labels or art.
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
		tint.a = 1.0
		patch.material_override = _flat(tint.darkened(0.55 if zone.role != ZoneDef.Role.CASH_ROOM else 0.25))
		_geometry.add_child(patch)

func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	layer.add_child(_hud)
	_banner = Label.new()
	_banner.position = Vector2(16, 260)
	layer.add_child(_banner)

# ---- HUD ----

## Every tuned number here is READ from content (WORLD_AUTHORING.md §9).
##
## Nothing states how long shelter lasts, or that it ends on a pickup - both
## come off the ZoneDef. That is what keeps the A/B question one content edit
## away from being answered rather than a code change, which is the entire
## reason this slice exists.
func _update_hud() -> void:
	var zone: ZoneDef = level.sheltered_zone()
	var lines: PackedStringArray = PackedStringArray()

	lines.append("SAFE ROOM: %s" % _describe_shelter(zone))
	lines.append("[1] / [2] restart with the other configuration")
	lines.append("")
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
			_device_name(players[seat]),
			"HELD %.1fs" % SimWorld.ticks_to_seconds(actor.capture_ticks_remaining) if actor.is_captured else "free",
			"  carrying" if actor.is_carrying() else "",
			"  sheltered%s" % _shelter_remaining(actor) if actor.is_protected() else "",
		])

	lines.append("")
	lines.append("move: WASD / left stick    grab-drop: Q / X    seize: E / A    free ally: R / B")
	_hud.text = "\n".join(lines)

## Reads the shelter rule off the zone rather than naming it.
func _describe_shelter(zone: ZoneDef) -> String:
	if zone == null or not zone.grants_safety():
		return "none"
	var parts: PackedStringArray = PackedStringArray()
	if zone.safety_is_timed():
		parts.append("%.1fs" % zone.safe_duration_seconds)
	else:
		parts.append("no timer")
	if zone.safe_ends_on_pickup:
		parts.append("ends on pickup")
	return " + ".join(parts)

func _shelter_remaining(actor: SimEntity) -> String:
	if actor.safe_ticks_remaining == SimEntity.SAFE_UNLIMITED:
		return ""
	return " %.1fs" % SimWorld.ticks_to_seconds(actor.safe_ticks_remaining)

func _device_name(player: LocalPlayerInput) -> String:
	return "keyboard" if player.device == LocalPlayerInput.Device.KEYBOARD else "pad %d" % player.pad_id

func _phase_name(phase: SimWorld.MatchPhase) -> String:
	return SimWorld.MatchPhase.keys()[phase]

# ---- restart ----

## Switching variant rebuilds the level rather than editing it in place.
##
## Live-editing the ZoneDef would have presentation writing into content the
## rules read, which is the one direction this architecture does not allow. A
## restart is also the honest comparison: the same question, played twice.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	var key: InputEventKey = event
	if key.keycode == KEY_1:
		_reset(GreyBoxLevel.SafeVariant.A)
	elif key.keycode == KEY_2:
		_reset(GreyBoxLevel.SafeVariant.B)

func _reset(variant: GreyBoxLevel.SafeVariant) -> void:
	for view: MeshInstance3D in _actor_views.values():
		view.queue_free()
	_actor_views.clear()
	_banner.text = ""
	_start(variant)
