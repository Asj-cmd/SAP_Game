extends SceneTree
## PT4-6: arm and hand proportions of the six family members, as drawn (after
## ArtTheme.shape_figure, i.e. with the theme's bone_scales), as fractions of
## the drawn height: shoulder, wrist and fingertip height with the arm hanging
## straight, forearm / upper arm / hand length, hand width (incl. the thumb),
## the hip-knee midpoint (where fingertips should end). Plus the carry check, in
## carry_idle: the wrist midpoint the bundle sits on (FigureAnimator.hands_point)
## against the crown; the bundle's bottom is that + CARRY_HAND_LIFT (6).
## A measuring tool, not a gate. Rows are printed after their hip line.
##   node autobuild/run_tool.mjs arm_probe

var _frame: int = 0
var _arts: Array[Node3D] = []

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_build()
		return false
	if _frame == 3:
		_report()
		return true
	return false

func _build() -> void:
	var theme: ArtTheme = ArtTheme.current()
	var x: float = 0.0
	for who: FamilyMember in theme.family:
		var art: Node3D = theme.member_scene(who).instantiate() as Node3D
		theme.shape_figure(art, who)
		var holder: Node3D = Node3D.new()
		holder.position = Vector3(x, 0.0, 0.0)
		x += 300.0
		holder.add_child(art)
		root.add_child(holder)
		art.set_meta(&"who", who)
		_arts.append(art)
		# A second copy held in carry_idle.
		var art2: Node3D = theme.member_scene(who).instantiate() as Node3D
		theme.shape_figure(art2, who)
		var holder2: Node3D = Node3D.new()
		holder2.position = Vector3(x, 0.0, 0.0)
		x += 300.0
		holder2.add_child(art2)
		root.add_child(holder2)
		art2.set_meta(&"who", who)
		art2.set_meta(&"carry", true)
		FigureAnimation.pose(art2, &"carry_idle", 0.5)
		_arts.append(art2)

func _bones(art: Node3D) -> Skeleton3D:
	return art.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D

func _world(bones: Skeleton3D, name: StringName) -> Vector3:
	return bones.global_transform * bones.get_bone_global_pose(bones.find_bone(name)).origin

## Hand extents (length along the bone, width) from the vertices weighted mostly
## to hand_l, in hand_l's bind space, times the hand's drawn scale.
func _hand_size(art: Node3D, bones: Skeleton3D) -> Vector2:
	var hand: int = bones.find_bone(&"hand_l")
	var tip: int = bones.find_bone(&"middle_04_leaf_l")
	var view: MeshInstance3D = art.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var skin: Skin = view.skin
	var bind_of: Dictionary = {}
	for i: int in skin.get_bind_count():
		var b: int = skin.get_bind_bone(i)
		if b < 0:
			b = bones.find_bone(skin.get_bind_name(i))
		bind_of[i] = b
	var hand_bind: Transform3D = Transform3D.IDENTITY
	for i: int in skin.get_bind_count():
		if bind_of[i] == hand:
			hand_bind = skin.get_bind_pose(i)
	var hand_set: Dictionary = {}
	for b: int in bones.get_bone_count():
		var walk: int = b
		while walk >= 0:
			if walk == hand:
				hand_set[b] = true
				break
			walk = bones.get_bone_parent(walk)
	var low: Vector3 = Vector3(INF, INF, INF)
	var high: Vector3 = -low
	for s: int in view.mesh.get_surface_count():
		var arrays: Array = view.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bone_ix: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per: int = bone_ix.size() / maxi(verts.size(), 1)
		for v: int in verts.size():
			var w_hand: float = 0.0
			for k: int in per:
				var bi: int = bone_ix[v * per + k]
				if hand_set.has(bind_of.get(bi, -1)):
					w_hand += weights[v * per + k]
			if w_hand >= 0.5:
				var local: Vector3 = hand_bind * verts[v]
				low = low.min(local)
				high = high.max(local)
	var size: Vector3 = high - low
	# Length is along the bone axis (local y in this rig); width the larger of x/z.
	var pose_scale: Vector3 = (bones.global_transform.basis * bones.get_bone_global_pose(hand).basis).get_scale()
	var s_len: float = size.y * pose_scale.y
	var s_wid: float = maxf(size.x * pose_scale.x, size.z * pose_scale.z)
	var _unused: int = tip
	print("    hand mesh in bind space low %s high %s scale %s" % [low, high, pose_scale])
	return Vector2(s_len, s_wid)

func _report() -> void:
	var cash: Node3D = (load("res://art/models/cash.glb") as PackedScene).instantiate() as Node3D
	root.add_child(cash)
	for m: Node in cash.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		print("cash mesh %s aabb %s in world %s" % [mi.name, mi.get_aabb(), mi.global_transform * mi.get_aabb()])
	print("member        H   shoulder  wrist(hang)  tip(hang)  forearm  upper  hand_len  palm_w")
	for art: Node3D in _arts:
		var who: FamilyMember = art.get_meta(&"who")
		var bones: Skeleton3D = _bones(art)
		var h: float = minf(who.height, ArtTheme.current().figure_height)
		var shoulder: Vector3 = _world(bones, &"upperarm_l")
		var elbow: Vector3 = _world(bones, &"lowerarm_l")
		var wrist: Vector3 = _world(bones, &"hand_l")
		var tip: Vector3 = _world(bones, &"middle_04_leaf_l")
		var foot: float = art.get_parent().global_position.y
		if art.has_meta(&"carry"):
			var crown: float = _world(bones, &"Head").y
			var mid: Vector3 = (wrist + _world(bones, &"hand_r")) * 0.5
			var apart: float = wrist.distance_to(_world(bones, &"hand_r"))
			print("    hands mid relative to feet %s" % (mid - (art.get_parent() as Node3D).global_position))
			print("  carry %-13s hands_y %.1f  head_joint %.1f  crown %.1f  hands-crown %.1f  hands apart %.1f  tips %.1f/%.1f" % [
				who.id, mid.y, crown, h, mid.y - h, apart, tip.y, _world(bones, &"middle_04_leaf_r").y])
			# PT4-7 REDO: the highest fingertip (any *_leaf bone of either hand)
			# against the bundle's bottom (hands_point + CARRY_HAND_LIFT).
			var bottom: float = mid.y + 6.0
			var top_tip: float = -INF
			for b: int in bones.get_bone_count():
				var bn: String = bones.get_bone_name(b)
				if bn.contains("_leaf_"):
					top_tip = maxf(top_tip, _world(bones, StringName(bn)).y)
			print("  carry %-13s bundle bottom %.1f  highest fingertip %.1f  tip above bottom %.1f" % [
				who.id, bottom, top_tip, top_tip - bottom])
			continue
		var upper: float = shoulder.distance_to(elbow)
		var fore: float = elbow.distance_to(wrist)
		var hand_len: float = wrist.distance_to(tip)
		var size: Vector2 = _hand_size(art, bones)
		var sh_y: float = shoulder.y - foot
		print("    hip %.3f knee %.3f mid-thigh %.3f" % [(_world(bones, &"thigh_l").y - foot) / h, (_world(bones, &"calf_l").y - foot) / h,
			((_world(bones, &"thigh_l").y + _world(bones, &"calf_l").y) * 0.5 - foot) / h])
		var wrist_hang: float = sh_y - upper - fore
		var tip_hang: float = wrist_hang - hand_len
		print("%-13s %5.1f  %.3f  %.3f  %.3f  %.3f  %.3f  %.3f(mesh %.3f)  %.3f" % [
			who.id, h, sh_y / h, wrist_hang / h, tip_hang / h, fore / h, upper / h, hand_len / h, size.x / h, size.y / h])
