class_name BlockyFigure
extends Node3D
## 상자로 만든 캐릭터. 머리·몸통(가슴)·골반, 팔(어깨 → 팔꿈치 → 손), 다리(엉덩이 → 무릎 → 발목 → 발)를 관절 마디로 이어 붙였다.
## 걸음은 스프라이트처럼 끊어서 바꾸지 않고 **걸은 거리로 정해지는 위상(phase)**에서 매 프레임 계산한다(보간 없이 부드럽게):
##   - 다리: 엉덩이가 앞뒤로 흔들리고, 앞으로 나아가는 구간에서만 무릎이 굽고, 발은 지면과 평평하게 유지
##   - 팔: 같은 쪽 다리와 반대로 흔들리고 팔꿈치가 앞으로 굽는다
##   - 몸: 걸음마다 위아래로 출렁(두 걸음에 두 번)하고, 가슴이 골반과 반대로 살짝 비틀리며, 약간 앞으로 숙이고, 머리는 수평을 지킨다
##   - 멈추면 한 번에 서지 않고 자세가 서서히 돌아오며(walk_blend), 서 있을 땐 숨쉬기·팔 흔들림이 있다
##   - 방향을 바꿀 때 몸이 즉시 돌지 않고 짧게 돌아간다
## move_speed(칸/초)가 걸음 속도를 정하므로 이동 속도와 발 구르는 속도가 맞는다(미끄러지듯 걷지 않는다).
## smooth = false 로 두면 예전의 4단계 끊어 걷기(비교용)로 움직인다.
## 크기 단위: 세계 단위(칸). 키 약 1.14, 폭 약 0.4. 앞쪽 = +Z.

const PART_SHADER: Shader = preload("res://script/world/view3d/shader/blocky_part.gdshader")
const ID_SHADER: Shader = preload("res://script/world/view3d/shader/blocky_id.gdshader")

static var _tex_cache: Dictionary = {}

var parts: Array = []  # {inst, material, id_inst, id_material}
var head_ratio_value: float = 3.0
var walk_time: float = 0.0
var walking: bool = false
var facing_yaw_deg: float = 90.0  # 목표 방향. 3/4 모습: 화면 오른쪽 아래를 본다(정면은 45, 화면 아래)
var move_speed: float = 1.5  # 칸/초. 걸음 속도(발 구르는 빠르기)를 정한다
var smooth: bool = true
var walk_blend: float = 0.0  # 0 = 서 있음, 1 = 걷는 자세
var phase: float = 0.0
var _yaw_cur: float = NAN
var _atk_t: float = -1.0  # 공격 진행 시간(초), -1 = 공격 중 아님
var _atk_dur: float = 0.4
var _atk_ranged: bool = false
var _atk_arc: float = 80.0  # 공격 부채꼴 각도(도). 팔을 이만큼 휩쓴다
var _weapon: Node3D = null
var _hurt_t: float = -1.0  # 피격 진행 시간(초), -1 = 아님
var _hurt_dur: float = 0.4
var weapon_always: bool = false  # true 면 무기를 늘 들고 있다(원정 방)
var _weapon_hold: float = 0.0  # 공격이 끝난 뒤에도 무기를 잠깐 더 보인다
var _idle_t: float = 0.0
var _id_root: Node3D
var _j: Dictionary = {}  # 관절 이름 → Node3D
var _leg_h: float = 0.45
var _step_len: float = 0.4


static func _make_tex(w: int, h: int, painter: Callable) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)

	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, painter.call(x, y))

	return ImageTexture.create_from_image(img)


# 임시 도트 질감. 실제로는 Pixel Lab 으로 만든 작은 그림이 이 자리에 들어간다.
# 카메라가 위에서 30도로 내려다보므로 머리 윗면이 크게 보인다 → 윗면에 가르마와 머리카락 결을 그리고,
# 얼굴은 앞면 아래쪽 3분의 2에 두며 앞머리가 이마를 덮는다. 색은 밝은 빛에서 하얗게 날아가지 않게 조금 어둡게 잡았다.
static func _face_textures() -> Dictionary:
	if not _tex_cache.is_empty():
		return _tex_cache

	var skin := Color(0.80, 0.56, 0.42)
	var skin_shade := Color(0.72, 0.49, 0.37)
	var hair := Color(0.30, 0.18, 0.13)
	var hair_hi := Color(0.40, 0.25, 0.18)
	var shirt := Color(0.78, 0.78, 0.74)
	var apron := Color(0.14, 0.34, 0.25)
	var pants := Color(0.30, 0.22, 0.20)
	var pants_dk := Color(0.25, 0.18, 0.16)
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
	tex["upper_arm"] = _make_tex(4, 6, func(_x, _y): return shirt)
	tex["forearm"] = _make_tex(4, 6, func(_x, y): return shirt if float(y) / 6.0 < 0.34 else skin)
	tex["hand"] = _make_tex(4, 3, func(_x, _y): return skin)
	tex["thigh"] = _make_tex(4, 6, func(_x, y): return pants if y % 3 != 2 else pants_dk)
	tex["shin"] = _make_tex(4, 6, func(_x, y): return pants if float(y) / 6.0 < 0.78 else shoe)
	tex["foot"] = _make_tex(4, 3, func(_x, _y): return shoe)
	_tex_cache = tex
	return tex


# head_ratio: 몇 등신인가(키 ÷ 머리 높이). 2 = 머리가 키의 절반(아주 아기자기), 3 = 키의 3분의 1.
# total: 전체 키(칸). torso_fixed > 0 이면 몸통 길이를 그 값으로 고정하고 남는 길이를 다리에 준다.
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
	_leg_h = leg_h
	_step_len = leg_h * 0.9
	var foot_h: float = minf(leg_h * 0.14, 0.07)
	var thigh_h: float = (leg_h - foot_h) * 0.5
	var shin_h: float = (leg_h - foot_h) * 0.5
	var hand_h: float = arm_h * 0.14
	var upper_h: float = (arm_h - hand_h) * 0.52
	var fore_h: float = (arm_h - hand_h) * 0.48
	_id_root = Node3D.new()
	id_parent.add_child(_id_root)

	# 관절 뼈대: hips(골반, 높이 leg_h) → chest(가슴 윗면 = 목 높이, 몸통은 아래로 늘어짐) → head / 어깨 → 팔꿈치
	var hips := _joint("hips", self, Vector3(0.0, leg_h, 0.0))
	var chest := _joint("chest", hips, Vector3(0.0, torso_h, 0.0))
	var head := _joint("head", chest, Vector3.ZERO)
	_box(chest, Vector3(torso_w, torso_h, torso_d), t["torso_front"], t["torso_side"], t["torso_top"], false)
	_box(head, Vector3(head_w, head_h, head_h * 0.95), t["head_front"], t["head_side"], t["head_top"], true)

	for side in [-1, 1]:
		var key: String = "l" if side < 0 else "r"
		# 팔: 어깨 → 위팔, 팔꿈치 → 아래팔, 손목 → 손
		var shoulder := _joint("sh_" + key, chest, Vector3(float(side) * (torso_w * 0.5 + arm_w * 0.5), -torso_h * 0.04, 0.0))
		_box(shoulder, Vector3(arm_w, upper_h, arm_w), t["upper_arm"], t["upper_arm"], t["upper_arm"], false)
		var elbow := _joint("el_" + key, shoulder, Vector3(0.0, -upper_h, 0.0))
		_box(elbow, Vector3(arm_w * 0.94, fore_h, arm_w * 0.94), t["forearm"], t["forearm"], t["forearm"], false)
		var wrist := _joint("wr_" + key, elbow, Vector3(0.0, -fore_h, 0.0))
		_box(wrist, Vector3(arm_w * 0.9, hand_h, arm_w * 0.9), t["hand"], t["hand"], t["hand"], false)
		# 다리: 엉덩이 → 허벅지, 무릎 → 정강이, 발목 → 발(앞쪽으로 길쭉)
		var hip := _joint("hip_" + key, hips, Vector3(float(side) * torso_w * 0.24, 0.0, 0.0))
		_box(hip, Vector3(leg_w, thigh_h, leg_w), t["thigh"], t["thigh"], t["thigh"], false)
		var knee := _joint("kn_" + key, hip, Vector3(0.0, -thigh_h, 0.0))
		_box(knee, Vector3(leg_w * 0.94, shin_h, leg_w * 0.94), t["shin"], t["shin"], t["shin"], false)
		var ankle := _joint("an_" + key, knee, Vector3(0.0, -shin_h, 0.0))
		var foot_node := _box(ankle, Vector3(leg_w * 0.96, foot_h, leg_w * 1.55), t["foot"], t["foot"], t["foot"], false)
		foot_node.position = Vector3(0.0, -foot_h * 0.5, leg_w * 0.28)

	parent.add_child(self)


func _joint(joint_name: String, parent_node: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = joint_name
	n.position = pos
	parent_node.add_child(n)
	_j[joint_name] = n
	return n


# 관절 아래로 늘어지는(또는 head 처럼 위로 솟는) 상자 하나를 만든다. 반환: 상자 노드(위치 조절용)
func _box(pivot: Node3D, size: Vector3, tex_front: Texture2D, tex_side: Texture2D, tex_top: Texture2D, up: bool) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.position = Vector3(0.0, size.y * 0.5, 0.0) if up else Vector3(0.0, -size.y * 0.5, 0.0)
	var m := ShaderMaterial.new()
	m.shader = PART_SHADER
	m.set_shader_parameter("tex_front", tex_front)
	m.set_shader_parameter("tex_side", tex_side)
	m.set_shader_parameter("tex_top", tex_top)
	m.set_shader_parameter("part_size", size)
	inst.material_override = m
	# 보이는 부품은 DEPTH 를 직접 쓰는 셰이더라 그림자 패스에서 그림자 깊이가 순번에 따라 뒤죽박죽이 된다.
	# → 보이는 쪽은 그림자를 끄고, 같은 모양의 그림자 전용 상자(보통 재질)를 자식으로 달아 그림자를 드리운다.
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(inst)
	var shadow_inst := MeshInstance3D.new()
	shadow_inst.mesh = mesh
	shadow_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	inst.add_child(shadow_inst)
	var id_inst := MeshInstance3D.new()
	id_inst.mesh = mesh
	id_inst.layers = 2
	id_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var idm := ShaderMaterial.new()
	idm.shader = ID_SHADER
	id_inst.material_override = idm
	_id_root.add_child(id_inst)
	parts.append({"inst": inst, "material": m, "id_inst": id_inst, "id_material": idm})
	return inst


# 모든 부품에 곱하는 색(1,1,1 = 원래 색). 피격 번쩍임 등.
func set_tint(c: Color) -> void:
	for part in parts:
		(part["material"] as ShaderMaterial).set_shader_parameter("tint", c)


# 순번 깊이를 쓸지(기본) / 진짜 깊이를 쓸지. 순번 정렬이 없는 장면(원정 방)에서는 false.
func set_sorted(sorted: bool) -> void:
	for part in parts:
		(part["material"] as ShaderMaterial).set_shader_parameter("use_sort", sorted)


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


func animate(delta: float) -> void:
	if walking:
		walk_time += delta

	if is_nan(_yaw_cur):
		_yaw_cur = facing_yaw_deg

	# 방향은 가장 가까운 쪽으로 짧게 돌아간다(즉시 휙 돌지 않게)
	if smooth:
		_yaw_cur = rad_to_deg(lerp_angle(deg_to_rad(_yaw_cur), deg_to_rad(facing_yaw_deg), clampf(delta * 16.0, 0.0, 1.0)))
	else:
		_yaw_cur = facing_yaw_deg

	if not smooth:
		_animate_stepped(delta)
		return

	_idle_t += delta

	if _hurt_t >= 0.0:
		_hurt_t += delta

		if _hurt_t >= _hurt_dur:
			_hurt_t = -1.0

	if _atk_t >= 0.0:
		_atk_t += delta
		_weapon_hold = 0.3

		if _atk_t >= _atk_dur:
			_atk_t = -1.0
	elif _weapon_hold > 0.0:
		_weapon_hold -= delta
	# 걷는 자세 비중: 걷기 시작하면 빠르게 1로, 멈추면 조금 천천히 0으로
	var target: float = 1.0 if walking else 0.0
	walk_blend = move_toward(walk_blend, target, delta * (7.0 if walking else 5.0))

	if walk_blend > 0.01:
		# 한 주기(두 걸음) 동안 가는 거리 = 걸음 길이 × 2. 속도가 빠를수록 위상이 빨리 간다.
		phase = fmod(phase + TAU * move_speed / (_step_len * 2.0) * delta, TAU)

	_apply_pose()
	rotation_degrees.y = _yaw_cur  # 정렬 판(sync_sort)이 없는 장면(원정 방)에서도 바라보는 방향으로 돈다


func _apply_pose() -> void:
	var w: float = walk_blend
	var s: float = sin(phase)
	var c: float = cos(phase)
	var idle: float = 1.0 - w
	var br: float = sin(_idle_t * 2.1)
	var d2r: float = PI / 180.0
	var hips: Node3D = _j["hips"]
	var chest: Node3D = _j["chest"]
	var head: Node3D = _j["head"]
	# 몸통: 두 걸음에 두 번 출렁(다리가 수직일 때 가장 높고 벌렸을 때 가장 낮다), 골반 좌우 기울기·비틀기
	hips.position.y = _leg_h + w * 0.022 * (0.5 * cos(2.0 * phase) - 0.25)
	hips.position.x = w * 0.012 * s
	hips.rotation = Vector3(0.0, w * 3.0 * d2r * s, w * 2.0 * d2r * s)
	chest.rotation = Vector3(w * 3.0 * d2r, -w * 6.0 * d2r * s, -w * 1.2 * d2r * s)
	chest.scale = Vector3(1.0, 1.0 + idle * 0.012 * br, 1.0)
	head.rotation = Vector3(-w * 3.0 * d2r + idle * 0.8 * d2r * br, w * 3.5 * d2r * s, 0.0)

	for side in [-1, 1]:
		var k: String = "l" if side < 0 else "r"
		var sg: float = 1.0 if side < 0 else -1.0  # 왼쪽 +, 오른쪽 - (왼발이 앞으로 나갈 때 sin > 0)
		var hip: Node3D = _j["hip_" + k]
		var knee: Node3D = _j["kn_" + k]
		var ankle: Node3D = _j["an_" + k]
		var sh: Node3D = _j["sh_" + k]
		var el: Node3D = _j["el_" + k]
		var ang: float = sg * s  # 이 다리의 앞뒤 위치(+ = 앞)
		var vel: float = sg * c  # 이 다리의 앞뒤 속도(+ = 앞으로 나아가는 중)
		var hip_x: float = -w * 30.0 * ang  # -x 회전 = 다리가 앞(+Z)으로
		var knee_x: float = w * (6.0 + 42.0 * maxf(vel, 0.0) * (1.0 - 0.25 * absf(ang))) + idle * 2.0
		hip.rotation = Vector3(hip_x * d2r, 0.0, 0.0)
		knee.rotation = Vector3(knee_x * d2r, 0.0, 0.0)
		ankle.rotation = Vector3(-(hip_x + knee_x) * 0.7 * d2r + w * (-6.0 * d2r * clampf(vel, 0.0, 1.0)), 0.0, 0.0)
		# 팔은 같은 쪽 다리와 반대로
		var arm_x: float = w * 26.0 * ang + idle * 2.2 * br * sg  # + = 뒤로
		var forward: float = maxf(-ang, 0.0)  # 팔이 앞에 있을수록 팔꿈치가 더 굽는다
		sh.rotation = Vector3(arm_x * d2r, 0.0, sg * (idle * 1.5 + w * 2.0) * d2r)
		el.rotation = Vector3(-(w * (12.0 + 22.0 * forward) + idle * 7.0) * d2r, 0.0, 0.0)

	_apply_attack_pose(d2r)
	_apply_hurt_pose(d2r)


# ---------------------------------------------------------------- 피격

# 맞았을 때: 몸이 뒤로 젖혀지며 팔을 휘젓고 무릎이 꺾였다가 돌아온다. 번쩍임(색)과 밀려남(위치)은 호출한 쪽이 한다.
func play_hurt(duration: float = 0.4) -> void:
	_hurt_t = 0.0
	_hurt_dur = maxf(0.15, duration)


func hurt_amount() -> float:
	if _hurt_t < 0.0:
		return 0.0

	var p: float = clampf(_hurt_t / _hurt_dur, 0.0, 1.0)
	return pow(1.0 - p, 2.0)


func _apply_hurt_pose(d2r: float) -> void:
	if _hurt_t < 0.0:
		return

	var k: float = hurt_amount()
	var shake: float = sin(_hurt_t * 70.0) * k
	(_j["chest"] as Node3D).rotation = Vector3(-22.0 * d2r * k, shake * 5.0 * d2r, shake * 3.0 * d2r)
	(_j["head"] as Node3D).rotation = Vector3(-18.0 * d2r * k, -shake * 6.0 * d2r, 0.0)
	(_j["hips"] as Node3D).rotation = Vector3(-4.0 * d2r * k, 0.0, 0.0)
	(_j["sh_l"] as Node3D).rotation = Vector3(-30.0 * d2r * k, 0.0, 38.0 * d2r * k)
	(_j["sh_r"] as Node3D).rotation = Vector3(-30.0 * d2r * k, 0.0, -38.0 * d2r * k)
	(_j["el_l"] as Node3D).rotation = Vector3(-35.0 * d2r * k, 0.0, 0.0)
	(_j["el_r"] as Node3D).rotation = Vector3(-35.0 * d2r * k, 0.0, 0.0)

	for k2 in ["l", "r"]:
		(_j["kn_" + k2] as Node3D).rotation.x = 26.0 * d2r * k
		(_j["hip_" + k2] as Node3D).rotation.x = -12.0 * d2r * k



# ---------------------------------------------------------------- 공격

# 무기를 오른손에 쥐게 한다(kind: "sword" 칼 / "staff" 지팡이). 공격 중과 직후에만 보인다.
func set_weapon(kind: String) -> void:
	if _weapon != null:
		_weapon.queue_free()
		_weapon = null

	var wrist: Node3D = _j["wr_r"]
	_weapon = Node3D.new()
	wrist.add_child(_weapon)
	var steel := _make_tex(2, 2, func(_x, _y): return Color(0.86, 0.9, 0.97))
	var grip := _make_tex(2, 2, func(_x, _y): return Color(0.4, 0.26, 0.15))
	var gold := _make_tex(2, 2, func(_x, _y): return Color(0.95, 0.78, 0.25))
	var glow := _make_tex(2, 2, func(_x, _y): return Color(0.55, 0.9, 1.0))

	if kind == "staff":
		var rod := _box(_weapon, Vector3(0.035, 0.5, 0.035), grip, grip, grip, false)
		rod.position = Vector3(0.0, 0.05, 0.0)
		var orb := _box(_weapon, Vector3(0.09, 0.09, 0.09), glow, glow, glow, false)
		orb.position = Vector3(0.0, 0.5, 0.0)
	else:
		# 칼: 손에서 아래(-Y)로 뻗는 날. 팔을 앞으로 휘두르면 날이 앞을 향한다.
		var handle := _box(_weapon, Vector3(0.035, 0.1, 0.035), grip, grip, grip, false)
		handle.position = Vector3(0.0, 0.03, 0.0)
		var guard := _box(_weapon, Vector3(0.13, 0.03, 0.05), gold, gold, gold, false)
		guard.position = Vector3(0.0, -0.1, 0.0)
		var blade := _box(_weapon, Vector3(0.07, 0.5, 0.025), steel, steel, steel, false)
		blade.position = Vector3(0.0, -0.1, 0.0)
		_weapon.rotation.x = deg_to_rad(-50.0)  # 칼끝이 손에서 앞쪽 아래로 비스듬히(팔을 들면 앞쪽 위)

	_weapon.visible = weapon_always


# 공격 동작을 시작한다. duration 은 휘두르는 전체 시간. ranged 면 두 팔을 앞으로 뻗어 쏘는 동작.
func play_attack(duration: float, ranged: bool = false, arc_degrees: float = 80.0) -> void:
	_atk_t = 0.0
	_atk_arc = arc_degrees
	_atk_dur = maxf(0.15, duration)
	_atk_ranged = ranged


func is_attacking() -> bool:
	return _atk_t >= 0.0


func _apply_attack_pose(d2r: float) -> void:
	if _atk_t < 0.0:
		if _weapon != null:
			_weapon_hold = maxf(0.0, _weapon_hold)
			_weapon.visible = weapon_always or _weapon_hold > 0.0
			_weapon.rotation.x = lerpf(_weapon.rotation.x, deg_to_rad(-50.0), 0.5)

			if weapon_always and _hurt_t < 0.0:
				# 무기를 쥔 오른팔: 걸을 때도 크게 흔들지 않고 칼끝을 앞으로 내민 자세(마인크래프트처럼)
				var sr: Node3D = _j["sh_r"]
				var er: Node3D = _j["el_r"]
				sr.rotation.x = lerpf(sr.rotation.x, deg_to_rad(-24.0), 0.75)
				er.rotation.x = lerpf(er.rotation.x, deg_to_rad(-22.0), 0.75)

		return

	var p: float = clampf(_atk_t / _atk_dur, 0.0, 1.0)
	var sh_r: Node3D = _j["sh_r"]
	var el_r: Node3D = _j["el_r"]
	var sh_l: Node3D = _j["sh_l"]
	var el_l: Node3D = _j["el_l"]
	var chest: Node3D = _j["chest"]
	var hips: Node3D = _j["hips"]
	var head: Node3D = _j["head"]

	if _weapon != null:
		_weapon.visible = true

	if _atk_ranged:
		# 두 팔을 앞으로 뻗었다가(0~0.3) 잠깐 버티고(~0.65) 내린다
		var raise: float = smoothstep(0.0, 0.3, p) * (1.0 - smoothstep(0.65, 1.0, p))
		sh_r.rotation = Vector3(deg_to_rad(-85.0) * raise, 0.0, 0.0)
		sh_l.rotation = Vector3(deg_to_rad(-80.0) * raise, 0.0, deg_to_rad(-8.0) * raise)
		el_r.rotation = Vector3(deg_to_rad(-8.0) * raise, 0.0, 0.0)
		el_l.rotation = Vector3(deg_to_rad(-8.0) * raise, 0.0, 0.0)
		chest.rotation = Vector3(deg_to_rad(-4.0) * raise, 0.0, 0.0)
		hips.rotation.x = deg_to_rad(-5.0) * raise
		head.rotation.x = deg_to_rad(-3.0) * raise
		return

	# 칼 휘두르기: 궤적(수평 부채꼴)과 같이 팔을 옆으로 휩쓴다. 팔을 앞으로 들어 올린 채(arm_up) 한쪽 끝(-1)에서 반대쪽 끝(+1)으로
	# 어깨를 좌우(yaw)로 돌려 지나가고, 몸통·머리가 따라 돈다. 0~0.2 준비(옆으로 벌림) → 0.2~0.5 휩쓸기 → 0.5~1 되돌림.
	var s_sweep: float
	if p < 0.2:
		s_sweep = lerpf(0.0, -1.0, smoothstep(0.0, 0.2, p))
	elif p < 0.5:
		s_sweep = lerpf(-1.0, 1.0, smoothstep(0.2, 0.5, p))
	else:
		s_sweep = lerpf(1.0, 0.0, smoothstep(0.5, 1.0, p))

	var arm_up: float = smoothstep(0.0, 0.2, p) * (1.0 - smoothstep(0.55, 1.0, p))
	var half_deg: float = _atk_arc * 0.5 + 8.0
	# 회전 순서가 yaw(Y) → pitch(X) 라서, 팔을 앞으로 든 뒤 전체를 수직축으로 돌리는 것이 된다.
	sh_r.rotation = Vector3(deg_to_rad(-24.0 - 62.0 * arm_up), deg_to_rad(half_deg) * s_sweep, 0.0)
	el_r.rotation = Vector3(deg_to_rad(-22.0 - 10.0 * arm_up), 0.0, 0.0)
	sh_l.rotation = Vector3(deg_to_rad(8.0) * arm_up, deg_to_rad(-10.0) * s_sweep, deg_to_rad(4.0))
	el_l.rotation = Vector3.ZERO
	chest.rotation = Vector3(deg_to_rad(3.0) * arm_up, deg_to_rad(16.0) * s_sweep, 0.0)
	hips.rotation = Vector3(0.0, deg_to_rad(6.0) * s_sweep, 0.0)
	head.rotation.y = deg_to_rad(7.0) * s_sweep

	if _weapon != null:
		_weapon.rotation.x = deg_to_rad(-50.0 + 42.0 * arm_up)  # 휩쓸 땐 칼날이 거의 수평(팔과 나란히)


# 예전 방식(비교용): 걸음 단계 0~3 을 끊어서 팔다리를 흔든다. 보간 없음.
func _animate_stepped(_delta: float) -> void:
	var step: int = int(floor(walk_time * 8.0)) % 4 if walking else 0
	var swing_deg: float = [0.0, 32.0, 0.0, -32.0][step]
	var bob: float = 0.015 if (walking and step % 2 == 1) else 0.0
	var hips: Node3D = _j["hips"]
	hips.position.y = _leg_h + bob
	hips.position.x = 0.0
	hips.rotation = Vector3.ZERO
	(_j["chest"] as Node3D).rotation = Vector3.ZERO
	(_j["head"] as Node3D).rotation = Vector3.ZERO

	for side in [-1, 1]:
		var k: String = "l" if side < 0 else "r"
		var dir: float = -1.0 if side < 0 else 1.0
		(_j["hip_" + k] as Node3D).rotation = Vector3(deg_to_rad(swing_deg * dir), 0.0, 0.0)
		(_j["kn_" + k] as Node3D).rotation = Vector3.ZERO
		(_j["an_" + k] as Node3D).rotation = Vector3.ZERO
		(_j["sh_" + k] as Node3D).rotation = Vector3(deg_to_rad(-swing_deg * dir), 0.0, 0.0)
		(_j["el_" + k] as Node3D).rotation = Vector3.ZERO


# 정렬 순번과 부품 깊이 순서를 셰이더에 넣고, 윤곽선 판의 위치를 맞춘다. camera 는 부품 앞뒤를 가릴 때 쓴다.
func sync_sort(rank: float, count: float, camera: Camera3D, id_value: float) -> void:
	rotation_degrees.y = facing_yaw_deg if is_nan(_yaw_cur) else _yaw_cur
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
