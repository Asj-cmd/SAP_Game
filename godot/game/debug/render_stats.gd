class_name RenderStats
extends RefCounted
## What the renderer did to draw a frame: draw calls, triangles, objects, and -
## when asked - how long frames take on this machine's GPU.
##
## The art phase needs budgets (STYLE.md) and the budgets need numbers from the
## real views, not a guess per asset. These are the renderer's own counters for
## the frame that was just drawn, read the same way for every view, so two runs
## of one view can be compared and a budget can be checked.
##
## The counters only exist with a real renderer: a `--headless` run reports
## zeros, so this runs inside the windowed capture path (`--capture-stats`,
## `--capture-timing=N`), never as a headless tool. Frame TIME is only worth
## reading windowed on the dev machine's GPU; a software renderer's numbers mean
## nothing (PLAN.md P1-1).
##
## Debug presentation. It reads counters and prints; it changes nothing the
## rules decide and nothing that is drawn.

## The line prefix `autobuild/render_stats.mjs` and `verify.mjs --frames` look for.
const TAG: String = "RENDER_STATS"

## Totals for the frame the renderer finished last, over every viewport (the
## seat's SubViewport draws the world; the root draws the HUD over it).
##
## Read right after `RenderingServer.frame_post_draw`, so the numbers are for
## the same frame a capture saved.
static func counters(seat: Viewport) -> Dictionary:
	var stats: Dictionary = {
		"draw_calls": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"triangles": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"video_mem_mb": _mb(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)),
		"texture_mem_mb": _mb(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)),
		"buffer_mem_mb": _mb(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)),
	}
	if seat != null:
		# The shadow passes, split out: once shadows are on (P3-5) they are the
		# first thing to grow, and the totals above would hide where.
		stats["shadow_draw_calls"] = seat.get_render_info(
			Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		stats["shadow_triangles"] = seat.get_render_info(
			Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	stats["adapter"] = RenderingServer.get_video_adapter_name()
	return stats

## Frame time over `frames` frames with vsync off, so the number is what this
## machine can do rather than the monitor's refresh rate.
##
## Measured while the match goes on (bots, sim ticks, HUD), because that is what
## a player's frame costs. Reports the wall-clock interval between frames
## (median, 95th percentile, worst) and the GPU's own time for the seat's
## viewport where the driver can time it.
static func time_frames(tree: SceneTree, seat: Viewport, frames: int) -> Dictionary:
	var previous_vsync: DisplayServer.VSyncMode = DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var seat_rid: RID = seat.get_viewport_rid() if seat != null else RID()
	if seat_rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(seat_rid, true)
	# Let the change take, and keep the first uncapped frames out of the sample.
	for warm: int in 10:
		await RenderingServer.frame_post_draw

	var intervals: PackedFloat64Array = PackedFloat64Array()
	var gpu: PackedFloat64Array = PackedFloat64Array()
	var cpu: PackedFloat64Array = PackedFloat64Array()
	var last: int = Time.get_ticks_usec()
	for i: int in frames:
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		intervals.append(float(now - last) / 1000.0)
		last = now
		if seat_rid.is_valid():
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(seat_rid))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(seat_rid))

	if seat_rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(seat_rid, false)
	DisplayServer.window_set_vsync_mode(previous_vsync)
	if tree != null:
		await tree.process_frame
	return {
		"frames": frames,
		"frame_ms_median": _round(_percentile(intervals, 0.5)),
		"frame_ms_p95": _round(_percentile(intervals, 0.95)),
		"frame_ms_worst": _round(_percentile(intervals, 1.0)),
		"seat_gpu_ms_median": _round(_percentile(gpu, 0.5)),
		"seat_cpu_ms_median": _round(_percentile(cpu, 0.5)),
	}

## Where a view's draws come from (`--capture-breakdown`, P3-6): every visible
## mesh under `root` whose bounds touch `camera`'s frustum, grouped by the name
## of its branch under `root` (two levels down, digits dropped), with surfaces
## (= main-pass draws before lamps), triangles and how many of those cast a sun
## shadow. An estimate from the scene, not the renderer's counters: the shadow
## pass culls against the sun's own frustum, which this does not model.
static func breakdown(root: Node, camera: Camera3D) -> String:
	var planes: Array[Plane] = camera.get_frustum() if camera != null else []
	var groups: Dictionary[String, PackedInt64Array] = {}
	_tally(root, root, planes, groups)
	var names: Array[String] = groups.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return groups[a][1] > groups[b][1])
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%-44s %6s %7s %9s %9s" % ["branch", "nodes", "surf", "tris", "cast_tris"])
	for name: String in names:
		var g: PackedInt64Array = groups[name]
		lines.append("%-44s %6d %7d %9d %9d" % [name, g[0], g[1], g[2], g[3]])
	return "\n".join(lines)

static func _tally(root: Node, node: Node, planes: Array[Plane],
		groups: Dictionary[String, PackedInt64Array]) -> void:
	var item: GeometryInstance3D = node as GeometryInstance3D
	if item != null and item.is_visible_in_tree() and item.layers != 0:
		var mesh: Mesh = null
		var copies: int = 1
		if item is MeshInstance3D:
			mesh = (item as MeshInstance3D).mesh
		elif item is MultiMeshInstance3D and (item as MultiMeshInstance3D).multimesh != null:
			mesh = (item as MultiMeshInstance3D).multimesh.mesh
			copies = (item as MultiMeshInstance3D).multimesh.visible_instance_count
			if copies < 0:
				copies = (item as MultiMeshInstance3D).multimesh.instance_count
		if mesh != null and _in_frustum(item.global_transform * item.get_aabb(), planes):
			var key: String = _branch(root, node)
			if not groups.has(key):
				groups[key] = PackedInt64Array([0, 0, 0, 0])
			var tris: int = 0
			for s: int in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(s)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				tris += (indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			tris *= copies
			var g: PackedInt64Array = groups[key]
			g[0] += 1
			g[1] += mesh.get_surface_count()
			g[2] += tris
			if item.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				g[3] += tris
			groups[key] = g
	for child: Node in node.get_children():
		_tally(root, child, planes, groups)

static func _branch(root: Node, node: Node) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var at: Node = node
	while at != null and at != root:
		var label: String = String(at.name)
		if label.begins_with("@"):
			label = at.get_class()
		parts.insert(0, label)
		at = at.get_parent()
	var digits: RegEx = RegEx.create_from_string("[0-9]+")
	var kept: String = "/".join(parts.slice(0, 2))
	var view: MeshInstance3D = node as MeshInstance3D
	if view != null and view.mesh != null and view.mesh.resource_name == "":
		kept += " [%s]" % view.mesh.get_class()
	return digits.sub(kept, "#", true)

static func _in_frustum(box: AABB, planes: Array[Plane]) -> bool:
	for plane: Plane in planes:
		# The box corner farthest along the plane's normal (planes face outward).
		var p: Vector3 = Vector3(
			box.position.x if plane.normal.x > 0.0 else box.end.x,
			box.position.y if plane.normal.y > 0.0 else box.end.y,
			box.position.z if plane.normal.z > 0.0 else box.end.z)
		if plane.is_point_over(p):
			return false
	return true

## One line a runner can parse: the tag, the view name, then JSON.
static func line(view: String, stats: Dictionary) -> String:
	return "%s %s %s" % [TAG, view, JSON.stringify(stats)]

static func _percentile(values: PackedFloat64Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	var index: int = clampi(int(ceil(fraction * float(sorted.size()))) - 1, 0, sorted.size() - 1)
	return sorted[index]

static func _round(value: float) -> float:
	return snappedf(value, 0.01)

static func _mb(bytes: int) -> float:
	return snappedf(float(bytes) / 1048576.0, 0.1)
