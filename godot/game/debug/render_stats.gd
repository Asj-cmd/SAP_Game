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
