class_name BlockyFigure
extends Node3D
## 상자 몇 개로 만든 캐릭터(머리·몸통·팔 둘·다리 둘). 그림은 부품 면마다 작은 도트 질감(지금은 코드로 만든 임시)이고,
## 돌리면 어느 방향이든 알아서 맞고, 걸음은 몇 단계로 끊어서(보간 없음) 움직인다.
## 크기 단위: 세계 단위(칸). 키 약 0.95, 폭 약 0.4. 앞쪽 = +Z.

const PART_SHADER: Shader = preload("res://script/world/view3d/shader/blocky_part.gdshader")
const ID_SHADER: Shader = preload("res://script/world/view3d/shader/blocky_id.gdshader")

var parts: Array = []  # {node, pivot, material, id_node, id_material}
var head_ratio_value: float = 3.0
var walk_time: float = 0.0
var walking: bool = false
var facing_yaw_deg: float = 90.0  # 3/4 모습: 화면 오른쪽 아래를 본다(정면은 45, 화면 아래)
var _id_root: Node3D


static func _make_tex(w: int, h: int, painter: Callable) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)

	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, painter.call(x, y))

	return ImageTexture.create_from_image(img)


# 임시 도트 질감. 실제로는 Pixel Lab 으로 만든 작은 그림이 이 자리에 들어간다.
# 카메라가 위에서 30도로 내려다보므로 머리 윗면이 크게 보인다(앞면 높이의 약 40%) → 윗면에 가르마와 머리카락 결을 그리고,
# 얼굴은 앞면 아래쪽 3분의 2에 두며 앞머리가 이마를 덮는다. 색은 밝은 빛에서 하얗게 날아가지 않게 조금 어둡게 잡았다.
func _face_textures() -> Dictionary:
	var skin := Color(0.80, 0.56, 0.42)
	var skin_shade := Color(0.72, 0.49, 0.37)
	var hair := Color(0.30, 0.18, 0.13)
	var hair_hi := Color(0.40, 0.25, 0.18)
	var shirt := Color(0.78, 0.78, 0.74)
	var apron := Color(0.14, 0.34, 0.25)
	var pants := Color(0.30, 0.22, 0.20)
	var shoe := Color(0.20, 0.14, 0.12)
	var tex: Dictionary = {}
	tex["head_front"] = _make_tex(14, 13, func(x, y):
		var u: float = (float(x) + 0.5) / 14.0
		var v: float = (float(y) + 0.5) / 13.0
		if v < 0.30 or (v < 0.42 and (u < 0.18 or u > 0.82 or (int(u * 14.0) % 3 == 0))):
			return hair if int(u * 14.0 + v * 13.0) % 4 != 0 else hair_hi
		if v > 0.45 and v < 0.62 and (absf(u - 0.30) < 0.09 or absf(u - 0.70) < 0.09):
			return Color(0.10, 0.07, 0.07)
		if v > 0.78 and v < 0.88 and absf(u - 0.5) < 0.12:
			return Color(0.62, 0.28, 0.26)
		return skin)
	tex["head_side"] = _make_tex(13, 13, func(x, y):
		var u: float = (float(x) + 0.5) / 13.0
		var v: float = (float(y) + 0.5) / 13.0
		if v < 0.33 or u > 0.62:
			return hair if int(u * 13.0 + v * 13.0) % 4 != 0 else hair_hi
		if u < 0.10 and v > 0.5 and v < 0.6:
			return skin_shade
		return skin)
	tex["head_top"] = _make_tex(14, 13, func(x, y):
		var u: float = (float(x) + 0.5) / 14.0
		var v: float = (float(y) + 0.5) / 13.0
		if absf(u - 0.38) < 0.04 and v < 0.7:
			return hair_hi  # 가르마
		return hair if int(u * 14.0 * 1.0 + v * 13.0) % 3 != 0 else hair_hi)
	tex["torso_front"] = _make_tex(12, 10, func(x, y):
		var u: float = (float(x) + 0.5) / 12.0
		var v: float = (float(y) + 0.5) / 10.0
		if v > 0.30 and u > 0.22 and u < 0.78:
			return apron
		return shirt)
	tex["torso_side"] = _make_tex(8, 10, func(_x, y): return shirt if float(y) / 10.0 < 0.3 else apron)
	tex["torso_top"] = _make_tex(12, 8, func(_x, _y): return shirt)
	tex["arm"] = _make_tex(4, 10, func(_x, y): return shirt if float(y) / 10.0 < 0.65 else skin)
	tex["leg"] = _make_tex(4, 10, func(_x, y): return pants if float(y) / 10.0 < 0.75 else shoe)
	return tex


# head_ratio: 몇 등신인가(키 ÷ 머리 높이). 2 = 머리가 키의 절반(아주 아기자기), 3 = 키의 3분의 1.
# 전체 키는 항상 같고(0.95칸 ≈ 2배 화면에서 32픽셀) 머리 비율에 따라 몸통·다리 길이가 달라진다.
# total: 전체 키(칸). torso_fixed > 0 이면 몸통 길이를 그 값으로 고정하고 남는 길이를 다리에 준다(키가 커질 때 팔다리만 늘리는 방식).
func build(parent: Node, id_parent: Node, head_ratio: float = 3.0, total: float = 0.95, torso_fixed: float = -1.0) -> void:
	head_ratio_value = head_ratio
	var t: Dictionary = _face_textures()
	var head_h: float = total / head_ratio
	var head_w: float = head_h * 1.1
	var rest: float = total - head_h
	var leg_h: float = rest * 0.46
	var torso_h: float = rest - leg_h

	if torso_fixed > 0.0:
		torso_h = torso_fixed
		leg_h = rest - torso_h

	var arm_h: float = torso_h * 0.92 + maxf(total - 0.95, 0.0) * 0.45
	var torso_w: float = clampf(head_w * 0.82, 0.22, 0.4)
	var torso_d: float = torso_w * 0.55
	var arm_w: float = clampf(torso_w * 0.28, 0.07, 0.11)
	var leg_w: float = clampf(torso_w * 0.38, 0.09, 0.15)
	var neck_y: float = leg_h + torso_h

	var specs: Array = [
		{"name": "leg_l", "size": Vector3(leg_w, leg_h, leg_w), "pivot": Vector3(-torso_w * 0.24, leg_h, 0.0), "tex": ["leg", "leg", "leg"]},
		{"name": "leg_r", "size": Vector3(leg_w, leg_h, leg_w), "pivot": Vector3(torso_w * 0.24, leg_h, 0.0), "tex": ["leg", "leg", "leg"]},
		{"name": "torso", "size": Vector3(torso_w, torso_h, torso_d), "pivot": Vector3(0.0, neck_y, 0.0), "tex": ["torso_front", "torso_side", "torso_top"], "no_swing": true},
		{"name": "arm_l", "size": Vector3(arm_w, arm_h, arm_w), "pivot": Vector3(-(torso_w * 0.5 + arm_w * 0.5), neck_y - torso_h * 0.04, 0.0), "tex": ["arm", "arm", "arm"]},
		{"name": "arm_r", "size": Vector3(arm_w, arm_h, arm_w), "pivot": Vector3(torso_w * 0.5 + arm_w * 0.5, neck_y - torso_h * 0.04, 0.0), "tex": ["arm", "arm", "arm"]},
		{"name": "head", "size": Vector3(head_w, head_h, head_h * 0.95), "pivot": Vector3(0.0, neck_y, 0.0), "tex": ["head_front", "head_side", "head_top"], "no_swing": true, "head": true},
	]
	_id_root = Node3D.new()
	id_parent.add_child(_id_root)

	for sp in specs:
		var pivot := Node3D.new()
		pivot.name = sp["name"]
		pivot.position = sp["pivot"]
		add_child(pivot)
		var size: Vector3 = sp["size"]
		var mesh := BoxMesh.new()
		mesh.size = size
		var inst := MeshInstance3D.new()
		inst.mesh = mesh

		# 상자 중심: 다리·팔·몸통은 관절 아래로 늘어지고, 머리는 위로 솟는다.
		inst.position = Vector3(0.0, size.y * 0.5, 0.0) if sp.get("head", false) else Vector3(0.0, -size.y * 0.5, 0.0)

		var m := ShaderMaterial.new()
		m.shader = PART_SHADER
		m.set_shader_parameter("tex_front", t[sp["tex"][0]])
		m.set_shader_parameter("tex_side", t[sp["tex"][1]])
		m.set_shader_parameter("tex_top", t[sp["tex"][2]])
		m.set_shader_parameter("part_size", size)
		inst.material_override = m
		pivot.add_child(inst)

		var id_inst := MeshInstance3D.new()
		id_inst.mesh = mesh
		id_inst.layers = 2
		id_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var idm := ShaderMaterial.new()
		idm.shader = ID_SHADER
		id_inst.material_override = idm
		_id_root.add_child(id_inst)
		parts.append({"pivot": pivot, "inst": inst, "material": m, "id_inst": id_inst, "id_material": idm, "swing": not sp.get("no_swing", false), "left": str(sp["name"]).ends_with("_l"), "arm": str(sp["name"]).begins_with("arm"), "base_y": sp["pivot"].y})

	parent.add_child(self)


# 보이기/숨기기(윤곽선 번호 판 쪽도 함께).
func set_shown(shown: bool) -> void:
	visible = shown

	if _id_root != null:
		_id_root.visible = shown


# 장면에서 치운다(비율을 바꿔 다시 만들 때).
func destroy() -> void:
	if _id_root != null:
		_id_root.queue_free()

	queue_free()


# 걸음 단계(0~3)를 끊어서 팔다리를 흔든다. 보간 없이 몇 단계만(제한 애니메이션).
func animate(delta: float) -> void:
	if walking:
		walk_time += delta

	var step: int = int(floor(walk_time * 8.0)) % 4 if walking else 0
	var swing_deg: float = [0.0, 32.0, 0.0, -32.0][step]
	var bob: float = 0.015 if (walking and step % 2 == 1) else 0.0

	for p in parts:
		var pivot: Node3D = p["pivot"]

		if not p["swing"]:
			pivot.position.y = float(p["base_y"]) + bob
			continue

		var dir: float = -1.0 if p["left"] else 1.0
		var arm_flip: float = -1.0 if p["arm"] else 1.0
		pivot.rotation_degrees.x = swing_deg * dir * arm_flip


# 정렬 순번과 부품 깊이 순서를 셰이더에 넣고, 윤곽선 판의 위치를 맞춘다. camera 는 부품 앞뒤를 가릴 때 쓴다.
func sync_sort(rank: float, count: float, camera: Camera3D, id_value: float) -> void:
	rotation_degrees.y = facing_yaw_deg
	_id_root.global_transform = global_transform
	var order: Array = []

	for p in parts:
		var node: Node3D = p["inst"]
		order.append({"depth": node.global_position.dot(camera.basis.z), "p": p})

	order.sort_custom(func(a, b): return a["depth"] < b["depth"])  # 뒤 → 앞

	for i in range(order.size()):
		var p: Dictionary = order[i]["p"]
		var sub: float = float(i) / float(maxi(order.size() - 1, 1))
		p["material"].set_shader_parameter("rank", rank)
		p["material"].set_shader_parameter("rank_count", count)
		p["material"].set_shader_parameter("sub", sub)
		var idm: ShaderMaterial = p["id_material"]
		idm.set_shader_parameter("rank", rank)
		idm.set_shader_parameter("rank_count", count)
		idm.set_shader_parameter("sub", sub)
		idm.set_shader_parameter("id", id_value)
		(p["id_inst"] as Node3D).global_transform = (p["inst"] as Node3D).global_transform
