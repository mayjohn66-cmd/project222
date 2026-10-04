class_name HouseShapes
extends RefCounted
## 박공 건물에 덧붙이는 모양 부품: 지붕창, 포치(기둥 현관), 돌출 창, 낮은 별채, 코너 탑, 2층 허리 보.
## VillageAssets.build_gable 이 규칙의 shape 문자열(예: "porch;dormer:2;tower")을 읽어 부품(PartBuilder)에 덧붙인다.
## 문과 앞벽은 항상 +z 쪽이고, 지붕창은 용마루 기준 앞쪽 경사(+v: 용마루가 x 방향이면 +z, 아니면 +x)에 놓는다.
## 부품은 건물 면보다 나중에 그려지므로(extras) 지붕·벽 위에 올라가 보인다.

const COMBOS: Array = [
	"porch",
	"porch;dormer:2",
	"bay;dormer:1",
	"annex;porch",
	"tower;porch",
	"jetty;dormer:2",
	"bay;annex",
	"porch;bay;dormer:1",
	"jetty;porch",
	"annex;dormer:1",
]


static func has(tokens: PackedStringArray, name: String) -> bool:
	for t in tokens:
		if t.split(":")[0] == name:
			return true

	return false


static func count_of(tokens: PackedStringArray, name: String, default_count: int = 1) -> int:
	for t in tokens:
		var parts: PackedStringArray = t.split(":")

		if parts[0] == name:
			return int(parts[1]) if parts.size() > 1 else default_count

	return 0


# 창이 있는 작은 벽 질감(지붕창·돌출 창 앞면용)
static func window_tex(w_px: int, h_px: int, plaster: Color, timber: Color) -> ImageTexture:
	var w: int = maxi(w_px, 6)
	var h: int = maxi(h_px, 6)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(plaster)
	img.fill_rect(Rect2i(0, 0, w, 1), timber)
	img.fill_rect(Rect2i(0, 0, 1, h), timber)
	img.fill_rect(Rect2i(w - 1, 0, 1, h), timber)
	var ww: int = maxi(int(float(w) * 0.5), 3)
	var wh: int = maxi(int(float(h) * 0.55), 3)
	var wx: int = (w - ww) / 2
	var wy: int = maxi(int(float(h) * 0.2), 1)
	img.fill_rect(Rect2i(wx - 1, wy - 1, ww + 2, wh + 2), Color(0.92, 0.88, 0.8))
	img.fill_rect(Rect2i(wx, wy, ww, wh), Color(0.5, 0.74, 0.92))
	img.fill_rect(Rect2i(wx + ww / 2, wy, 1, wh), Color(0.92, 0.88, 0.8))
	return ImageTexture.create_from_image(img)


# ctx: b(PartBuilder), p, lo, hi, wall_h(1층 벽 높이), wall_h_total, roof_h, ridge_x, hs, vc, levels, plaster, timber, roof_tint,
#      roof_spec, wall_spec, door_cx, door_w, cells, door_cell
static func apply(tokens: PackedStringArray, ctx: Dictionary) -> void:
	if has(tokens, "jetty"):
		_jetty(ctx)

	if has(tokens, "porch"):
		_porch(ctx)

	if has(tokens, "bay"):
		_bay(ctx)

	if has(tokens, "annex"):
		_annex(ctx)

	if has(tokens, "tower"):
		_tower(ctx)

	var dormers: int = count_of(tokens, "dormer", 1)

	if dormers > 0:
		_dormers(ctx, dormers)


static func _jetty(c: Dictionary) -> void:
	var b = c["b"]
	var lo: Vector2 = c["lo"]
	var hi: Vector2 = c["hi"]
	var wall_h: float = c["wall_h_total"]
	var y_m: float = wall_h * float(c.get("story_frac", 0.58))
	var beam: Dictionary = VillageAssets.wood(c["p"], Color(0.4, 0.27, 0.17), "jetty_beam")
	VillageAssets.box(b, "jetty_z", beam, Vector3(lo.x - 0.1, y_m - 0.08, hi.y), Vector3(hi.x + 0.12, y_m + 0.08, hi.y + 0.11))
	VillageAssets.box(b, "jetty_x", beam, Vector3(hi.x, y_m - 0.08, lo.y - 0.1), Vector3(hi.x + 0.11, y_m + 0.08, hi.y + 0.12))
	var x: float = lo.x + 0.4

	while x < hi.x - 0.2:
		VillageAssets.box(b, "bracket", beam, Vector3(x - 0.04, y_m - 0.22, hi.y), Vector3(x + 0.04, y_m - 0.08, hi.y + 0.09))
		x += 1.2

	var z: float = hi.y - 0.4

	while z > lo.y + 0.2:
		VillageAssets.box(b, "bracket", beam, Vector3(hi.x, y_m - 0.22, z - 0.04), Vector3(hi.x + 0.09, y_m - 0.08, z + 0.04))
		z -= 1.2


static func _porch(c: Dictionary) -> void:
	var b = c["b"]
	var hi: Vector2 = c["hi"]
	var p: Dictionary = c["p"]
	var cx: float = c["door_cx"]
	var dw: float = float(c["door_w"]) * 0.5 + 0.3
	var wall_h: float = c["wall_h"]
	var ytop: float = minf(wall_h * 0.82, wall_h - 0.2)
	var out: float = 0.66
	var post: Dictionary = VillageAssets.wood(p, Color(0.62, 0.44, 0.3), "porch_post")
	VillageAssets.box(b, "porch_floor", VillageAssets.stone_spec(p, Color(1.1, 1.06, 1.0), "porch_floor"), Vector3(cx - dw, 0.0, hi.y), Vector3(cx + dw, 0.12, hi.y + out))

	for sx in [-1.0, 1.0]:
		VillageAssets.box(b, "porch_post", post, Vector3(cx + sx * dw - 0.045, 0.12, hi.y + out - 0.1), Vector3(cx + sx * dw + 0.045, ytop, hi.y + out - 0.01))

	# 앞으로 처지는 작은 지붕
	var rt: Dictionary = c["roof_spec"]
	var y_hi: float = ytop + 0.26
	VillageAssets.slope(b, "porch_roof", rt, Vector3(cx - dw - 0.1, y_hi, hi.y), Vector3(cx + dw + 0.1, y_hi, hi.y), Vector3(cx + dw + 0.1, ytop, hi.y + out + 0.1), Vector3(cx - dw - 0.1, ytop, hi.y + out + 0.1), Vector3(0.0, out + 0.1, y_hi - ytop).normalized(), 2.0 * dw + 0.2, out + 0.2)
	VillageAssets.box(b, "porch_fascia", c["trim_spec"], Vector3(cx - dw - 0.1, ytop - 0.05, hi.y + out + 0.06), Vector3(cx + dw + 0.1, ytop + 0.02, hi.y + out + 0.12))


static func _bay(c: Dictionary) -> void:
	var b = c["b"]
	var lo: Vector2 = c["lo"]
	var hi: Vector2 = c["hi"]
	var p: Dictionary = c["p"]
	var cells: int = c["cells"]
	var cell_w: float = (hi.x - lo.x) / float(cells)
	var k: int = int(c["door_cell"]) + 1

	if k >= cells:
		k = int(c["door_cell"]) - 1

	if k < 0:
		return

	var cx: float = lo.x + (float(k) + 0.5) * cell_w
	var half: float = clampf(cell_w * 0.4, 0.4, 0.58)
	var y0: float = 0.14
	var y1: float = c["wall_h"] * 0.66
	var depth: float = 0.38
	var ts: int = p["ts"]
	var wall: Dictionary = VillageAssets.spec(PlaceholderTextures.flat_color(ts, c["plaster"]), Color.WHITE, "bay_wall", "돌출 창 벽 회반죽 단색 %d×%d" % [ts, ts])
	VillageAssets.box(b, "bay", wall, Vector3(cx - half, y0, hi.y), Vector3(cx + half, y1, hi.y + depth))
	# 창: 앞면 하나 + 오른쪽(보이는) 옆면 하나
	var parts: Dictionary = win_parts(b, p, Vector3(cx - half, y0, hi.y), Vector3(cx + half + 0.12, y1, hi.y + depth + 0.12))
	var wy0: float = y0 + (y1 - y0) * 0.22
	var wy1: float = y0 + (y1 - y0) * 0.8
	win_on_z(parts, cx, wy0, wy1, half * 0.62, hi.y + depth, false)
	win_on_x(parts, hi.y + depth * 0.5, wy0, wy1, depth * 0.3, cx + half, false)
	var rt: Dictionary = c["roof_spec"]
	VillageAssets.slope(b, "bay_roof", rt, Vector3(cx - half - 0.05, y1 + 0.16, hi.y), Vector3(cx + half + 0.05, y1 + 0.16, hi.y), Vector3(cx + half + 0.05, y1, hi.y + depth + 0.08), Vector3(cx - half - 0.05, y1, hi.y + depth + 0.08), Vector3(0.0, depth + 0.08, 0.16).normalized(), 2.0 * half + 0.1, depth + 0.1)
	_cheek(b, wall, Vector3(cx + half + 0.03, y1, hi.y), Vector3(cx + half + 0.03, y1 + 0.16, hi.y), Vector3(cx + half + 0.03, y1, hi.y + depth + 0.06))
	VillageAssets.box(b, "bay_plinth", VillageAssets.stone_spec(p, Color(0.8, 0.78, 0.74), "bay_plinth"), Vector3(cx - half - 0.03, y0 - 0.1, hi.y), Vector3(cx + half + 0.03, y0 + 0.02, hi.y + depth + 0.03))


static func _annex(c: Dictionary) -> void:
	var b = c["b"]
	var lo: Vector2 = c["lo"]
	var hi: Vector2 = c["hi"]
	var p: Dictionary = c["p"]
	var wall_h: float = c["wall_h"]
	var ah: float = wall_h * 0.6
	var run: float = 1.05
	var z1: float = hi.y - 0.7
	var z0: float = maxf(lo.y + 0.5, z1 - 2.2)
	var ts: int = p["ts"]
	var wall: Dictionary = VillageAssets.spec(PlaceholderTextures.flat_color(ts, c["plaster"]), Color.WHITE, "annex_wall", "별채 벽 회반죽 단색 %d×%d" % [ts, ts])
	var xe: float = hi.x + run - 0.1
	VillageAssets.box(b, "annex", wall, Vector3(hi.x - 0.05, 0.0, z0), Vector3(xe, ah, z1))
	# 창: 앞면(+z)과 바깥 옆면(+x) 각 하나
	var parts: Dictionary = win_parts(b, p, Vector3(hi.x, 0.0, z0), Vector3(xe + 0.12, ah, z1 + 0.12))
	var wy0: float = ah * 0.34
	var wy1: float = ah * 0.8
	win_on_z(parts, (hi.x + xe) * 0.5, wy0, wy1, 0.2, z1)
	win_on_x(parts, (z0 + z1) * 0.5, wy0, wy1, 0.22, xe)
	var rt: Dictionary = c["roof_spec"]
	var drop: float = 0.3
	VillageAssets.slope(b, "annex_roof", rt, Vector3(hi.x - 0.02, ah + drop, z0 - 0.1), Vector3(hi.x - 0.02, ah + drop, z1 + 0.1), Vector3(hi.x + run + 0.12, ah, z1 + 0.1), Vector3(hi.x + run + 0.12, ah, z0 - 0.1), Vector3(drop, run + 0.14, 0.0).normalized(), z1 - z0 + 0.2, run + 0.16)
	VillageAssets.box(b, "annex_fascia", c["trim_spec"], Vector3(hi.x + run + 0.08, ah - 0.06, z0 - 0.1), Vector3(hi.x + run + 0.14, ah + 0.02, z1 + 0.1))
	# 지붕 옆 틈 메우기(삼각 볼) + 돌 밑단 + 모서리 기둥: 본채 벽과 같은 차림으로 맞춰 "덧붙인 상자"처럼 보이지 않게 한다.
	_cheek(b, wall, Vector3(hi.x - 0.02, ah, z1 + 0.06), Vector3(hi.x - 0.02, ah + drop, z1 + 0.06), Vector3(hi.x + run + 0.1, ah, z1 + 0.06))
	VillageAssets.box(b, "annex_plinth", VillageAssets.stone_spec(p, Color(0.8, 0.78, 0.74), "annex_plinth"), Vector3(hi.x - 0.05, 0.0, z0 - 0.03), Vector3(xe + 0.03, 0.14, z1 + 0.03))
	var post_spec: Dictionary = VillageAssets.spec(PlaceholderTextures.flat_color(ts, c["timber"]), Color.WHITE, "annex_post", "별채 모서리 기둥·윗보 목재 단색 %d×%d" % [ts, ts])
	VillageAssets.box(b, "annex_post", post_spec, Vector3(xe - 0.04, 0.12, z1 - 0.02), Vector3(xe + 0.05, ah, z1 + 0.05))
	VillageAssets.box(b, "annex_post", post_spec, Vector3(xe - 0.04, 0.12, z0 - 0.03), Vector3(xe + 0.05, ah, z0 + 0.04))
	VillageAssets.box(b, "annex_beam", post_spec, Vector3(hi.x - 0.05, ah - 0.09, z1 - 0.02), Vector3(xe + 0.05, ah, z1 + 0.05))
	VillageAssets.box(b, "annex_beam", post_spec, Vector3(xe - 0.04, ah - 0.09, z0 - 0.03), Vector3(xe + 0.05, ah, z1 + 0.05))


# 세 점(a,b,c)으로 이루어진 삼각 판 하나(지붕 아래 옆 틈을 벽 재질로 막는다). 바깥을 향한 면은 자동으로 맞춘다.
static func _cheek(b, spec: Dictionary, pa: Vector3, pb: Vector3, pc: Vector3) -> void:
	var st: SurfaceTool = b.new_part(spec, pa, pc)
	var n: Vector3 = (pb - pa).cross(pc - pa).normalized()

	if n.x + n.z < 0.0:
		n = -n

	BuildingMesh._tri(st, pa, pb, pc, n, Vector2(0, 1), Vector2(0, 0), Vector2(1, 1))


static func _tower(c: Dictionary) -> void:
	var b = c["b"]
	var lo: Vector2 = c["lo"]
	var hi: Vector2 = c["hi"]
	var p: Dictionary = c["p"]
	var r: float = 0.66
	var cx: float = lo.x + 0.1
	var cz: float = hi.y - 0.1
	var th: float = c["wall_h_total"] + c["roof_h"] * 0.9 + 0.35
	var ts: int = p["ts"]
	var spec: Dictionary = VillageAssets.spec(PlaceholderTextures.flat_color(ts, c["plaster"]), Color.WHITE, "tower_wall", "코너 탑 벽 회반죽 단색 %d×%d" % [ts, ts])
	VillageAssets.oct(b, "tower_body", spec, cx, cz, r, 0.0, th)
	VillageAssets.oct(b, "tower_cap_ring", c["trim_spec"], cx, cz, r + 0.08, th, th + 0.1)
	VillageAssets.oct(b, "tower_roof", c["roof_spec"], cx, cz, r + 0.16, th + 0.1, th + 0.1 + 1.15, 0.03)
	# 창: 카메라를 정면으로 보는 대각선 면에 틀(크림) + 유리 카드 두 줄(벽이 평평하니 창만 따로)
	var frame_c: Dictionary = VillageAssets.spec(PlaceholderTextures.flat_color(ts, Color(0.95, 0.92, 0.84)), Color.WHITE, "tower_win_frame", "탑 창틀 크림 단색 %d×%d" % [ts, ts])
	var glass_c: Dictionary = VillageAssets.spec(PlaceholderTextures.flat_color(ts, Color(0.5, 0.74, 0.92)), Color.WHITE, "tower_win_glass", "탑 창 유리 단색 %d×%d" % [ts, ts])
	var ap: float = r * 0.9239
	var dk: float = 0.7071

	for wy in [th * 0.3, th * 0.62]:
		VillageAssets._card(b, frame_c, cx + dk * (ap + 0.02), wy, cz + dk * (ap + 0.02), 0.3, 0.46)
		VillageAssets._card(b, glass_c, cx + dk * (ap + 0.04), wy + 0.04, cz + dk * (ap + 0.04), 0.2, 0.38)


# 박공 끝벽(삼각형) 아랫단에 어두운 목재 띠(벨트)를 두른다. 위에서 내려다보면 삼각형은 아랫부분만 가느다랗게 보여서,
# 띠가 없으면 지붕 사이에 밋밋한 흰(그늘에선 갈색) 쐐기만 남아 미완성처럼 보인다. 보이는 끝벽(ridge_x 면 +x 쪽, 아니면 +z 쪽)에만 단다.
static func gable_truss(b, spec: Dictionary, lo: Vector2, hi: Vector2, wall_h: float, _roof_h: float, ridge_x: bool) -> void:
	var v0: float = (lo.y if ridge_x else lo.x)
	var v1: float = (hi.y if ridge_x else hi.x)
	var u_end: float = (hi.x if ridge_x else hi.y)
	_truss_box(b, spec, ridge_x, u_end, v0 - 0.04, v1 + 0.04, wall_h - 0.02, wall_h + 0.11, 0.06)


static func _truss_box(b, spec: Dictionary, ridge_x: bool, u_end: float, va: float, vb: float, y0: float, y1: float, t: float) -> void:
	if ridge_x:
		VillageAssets.box(b, "gable_truss", spec, Vector3(u_end, y0, va), Vector3(u_end + t, y1, vb))
	else:
		VillageAssets.box(b, "gable_truss", spec, Vector3(va, y0, u_end), Vector3(vb, y1, u_end + t))


static func _dormers(c: Dictionary, count: int) -> void:
	var b = c["b"]
	var lo: Vector2 = c["lo"]
	var hi: Vector2 = c["hi"]
	var p: Dictionary = c["p"]
	var ridge_x: bool = c["ridge_x"]
	var levels: Array = c["levels"]
	var vc: float = c["vc"]
	var hs: float = c["hs"]
	var u0: float = (lo.x if ridge_x else lo.y)
	var u1: float = (hi.x if ridge_x else hi.y)
	var w_front: float = hs * 0.52
	var w_back: float = w_front - 0.55
	var y_f: float = BuildingMesh.roof_y_at(levels, w_front)
	var y_b: float = BuildingMesh.roof_y_at(levels, w_back)
	var dw: float = 0.66
	var face_h: float = 0.58
	var y_top: float = y_f + face_h
	# 지붕이 양 끝에서 안쪽으로 들어간 만큼(모임지붕·맨사드·반 박공)은 지붕창을 놓지 않는다. 지붕 끝 바깥으로 삐져나와 떠 보이는 것을 막는다.
	var inset: float = BuildingMesh.roof_inset_at(levels, w_front)
	var edge: float = 0.14 + inset + dw * 0.5 + 0.2
	var span_lo: float = u0 - 0.14 + edge
	var span_hi: float = minf(u1 + 0.14 - edge, u1 - 1.7)  # 굴뚝(+u 끝)을 피한다
	var ts: int = p["ts"]
	var face_spec: Dictionary = VillageAssets.spec(PlaceholderTextures.flat_color(ts, c["plaster"]), Color.WHITE, "dormer_front", "지붕창 앞면 회반죽 단색 %d×%d" % [ts, ts])
	var side_spec: Dictionary = c["wall_spec"]
	var rt: Dictionary = c["roof_spec"]

	if span_hi - span_lo < 0.2:
		count = 1
		span_lo = (u0 + u1) * 0.5 - 0.4
		span_hi = span_lo

		if span_lo < u0 + edge - 0.14 or span_lo > u1 - edge + 0.14:
			return  # 지붕이 너무 짧아서 놓을 자리가 없다

	for k in range(count):
		var uc: float = (span_lo + span_hi) * 0.5 if count == 1 else lerpf(span_lo, span_hi, float(k) / float(count - 1))
		# 앞면(수직 판): 아래는 지붕 표면에 닿는 높이
		var fa: Vector3 = BuildingMesh._p(ridge_x, uc - dw * 0.5, vc + w_front, y_f - 0.02)
		var fb: Vector3 = BuildingMesh._p(ridge_x, uc + dw * 0.5, vc + w_front, y_f - 0.02)
		var fc: Vector3 = BuildingMesh._p(ridge_x, uc + dw * 0.5, vc + w_front, y_top)
		var fd: Vector3 = BuildingMesh._p(ridge_x, uc - dw * 0.5, vc + w_front, y_top)
		var st: SurfaceTool = b.new_part(face_spec, fa, fc)
		var nf: Vector3 = BuildingMesh._n(ridge_x, 0.0, 1.0, 0.0)
		BuildingMesh._quad(st, fa, fb, fc, fd, nf, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
		# 창: 앞면 평면에 작은 창 하나(앞쪽이 +z 면 win_on_z, +x 면 win_on_x)
		var wparts: Dictionary = win_parts(b, p, fa, fc + Vector3(0.1, 0.0, 0.1))
		var wy0: float = y_f + face_h * 0.22
		var wy1: float = y_f + face_h * 0.82

		if ridge_x:
			win_on_z(wparts, uc, wy0, wy1, dw * 0.26, vc + w_front, false)
		else:
			win_on_x(wparts, uc, wy0, wy1, dw * 0.26, vc + w_front, false)

		# 양 볼(지붕 경사를 따라 아래가 비스듬한 사다리꼴)
		for sg in [-1.0, 1.0]:
			var ua: float = uc + sg * dw * 0.5
			var s0: Vector3 = BuildingMesh._p(ridge_x, ua, vc + w_back, y_b - 0.02)
			var s1: Vector3 = BuildingMesh._p(ridge_x, ua, vc + w_front, y_f - 0.02)
			var s2: Vector3 = BuildingMesh._p(ridge_x, ua, vc + w_front, y_top)
			var s3: Vector3 = BuildingMesh._p(ridge_x, ua, vc + w_back, y_top)
			var stc: SurfaceTool = b.new_part(side_spec, s0, s2)
			BuildingMesh._quad(stc, s0, s1, s2, s3, BuildingMesh._n(ridge_x, sg, 0.0, 0.0), Vector2(0, 1), Vector2(0.6, 1), Vector2(0.6, 0), Vector2(0, 0))

		# 작은 박공 지붕: 용마루가 앞뒤(경사 방향)로 달린다
		var yr: float = y_top
		var ph: float = 0.32
		var wf: float = w_front + 0.08
		var wb: float = w_back
		var a0: float = uc - dw * 0.5 - 0.07
		var a1: float = uc + dw * 0.5 + 0.07

		if ridge_x:
			VillageAssets.roof_prism(b, "dormer_roof", rt, a0, a1, vc + wb, vc + wf, yr, ph, false)
		else:
			VillageAssets.roof_prism(b, "dormer_roof", rt, vc + wb, vc + wf, a0, a1, yr, ph, true)


# ---------------------------------------------------------------- 창문 부품(벽 질감에 창을 그리지 않고 따로 붙인다)

const WIN_W: float = 0.46
const WIN_FRAME: float = 0.045


static func _fractions_front(width: float, upper: bool) -> Array:
	if upper:
		return [0.2, 0.5, 0.8] if width < 5.4 else [0.13, 0.37, 0.63, 0.87]

	return [0.2, 0.8] if width < 5.4 else [0.13, 0.31, 0.69, 0.87]


static func _fractions_side(depth: float) -> Array:
	if depth < 3.2:
		return [0.5]

	return [0.3, 0.7] if depth < 5.2 else [0.18, 0.5, 0.82]


# 창 자리 목록. 반환: {"z": [{c,y0,y1,w,upper}], "x": [...]}  (z: 앞벽(+z)면의 x 위치, x: 옆벽(+x)면의 z 위치)
# front: 앞벽에 창을 놓을지(가게 앞벽은 질감에 진열창이 있으므로 false), skip_front/skip_side: 건너뛸 구간(포치·돌출 창·탑·별채가 있는 곳)
static func window_slots(lo: Vector2, hi: Vector2, wall_h: float, story_frac: float, floors: int, front: bool, skip_front: Array, skip_side: Array, wing_w: float) -> Dictionary:
	var width: float = hi.x - lo.x
	var depth: float = hi.y - lo.y
	var h_low: float = wall_h * story_frac
	var out: Dictionary = {"z": [], "x": []}
	var stories: Array = [{"y0": h_low * 0.44, "y1": h_low * 0.8, "upper": false}]

	if floors >= 2:
		var up_h: float = wall_h - h_low
		stories.append({"y0": h_low + up_h * 0.3, "y1": h_low + up_h * 0.8, "upper": true})

	for st in stories:
		if front:
			for f in _fractions_front(width, bool(st["upper"])):
				var cx: float = lo.x + width * float(f)

				if wing_w > 0.0 and cx < lo.x + wing_w + 0.3:
					continue

				if _in_ranges(cx, skip_front) and not bool(st["upper"]):
					continue

				out["z"].append({"c": cx, "y0": st["y0"], "y1": st["y1"], "w": WIN_W, "upper": st["upper"]})

		for f2 in _fractions_side(depth):
			var cz: float = hi.y - depth * float(f2)

			if _in_ranges(cz, skip_side) and not bool(st["upper"]):
				continue

			out["x"].append({"c": cz, "y0": st["y0"], "y1": st["y1"], "w": WIN_W, "upper": st["upper"]})

	return out


static func _in_ranges(v: float, ranges: Array) -> bool:
	for r in ranges:
		if v >= float(r[0]) and v <= float(r[1]):
			return true

	return false


# 창 부품(틀·유리·창살·창턱)을 담을 면 네 개를 만든다. 같은 재질은 면 하나로 모아 면 수를 줄인다.
static func win_parts(b, p: Dictionary, a: Vector3, c: Vector3) -> Dictionary:
	var ts: int = p["ts"]
	var frame_spec: Dictionary = VillageAssets.spec(PlaceholderTextures.flat_color(ts, Color(0.95, 0.92, 0.84)), Color.WHITE, "window_frame", "창틀 크림 단색 %d×%d" % [ts, ts])
	var glass_spec: Dictionary = VillageAssets.spec(PlaceholderTextures.flat_color(ts, Color(0.5, 0.74, 0.92)), Color.WHITE, "window_glass", "창 유리 하늘색 단색 %d×%d" % [ts, ts])
	var mull_spec: Dictionary = VillageAssets.spec(PlaceholderTextures.flat_color(ts, Color(0.95, 0.92, 0.84)), Color.WHITE, "window_mullion", "창살 크림 단색 %d×%d" % [ts, ts])
	var sill_spec: Dictionary = VillageAssets.spec(PlaceholderTextures.flat_color(ts, Color(0.84, 0.8, 0.74)), Color.WHITE, "window_sill", "창턱 돌 단색 %d×%d" % [ts, ts])
	return {
		"sill": b.new_part(sill_spec, a, c, 0.0),
		"frame": b.new_part(frame_spec, a, c, 0.3),
		"glass": b.new_part(glass_spec, a, c, 0.6),
		"mull": b.new_part(mull_spec, a, c, 0.9),
	}


# +z 면(평면 z0)에 붙는 창: 가운데 x=cc, 높이 y0~y1, 반폭 hw
static func win_on_z(parts: Dictionary, cc: float, y0: float, y1: float, hw: float, z0: float, sill: bool = true) -> void:
	var fw: float = WIN_FRAME
	var ym: float = (y0 + y1) * 0.5
	VillageAssets.box_st(parts["frame"], Vector3(cc - hw - fw, y0 - fw, z0), Vector3(cc + hw + fw, y1 + fw, z0 + 0.05))
	VillageAssets.box_st(parts["glass"], Vector3(cc - hw, y0, z0), Vector3(cc + hw, y1, z0 + 0.065))
	VillageAssets.box_st(parts["mull"], Vector3(cc - 0.014, y0, z0), Vector3(cc + 0.014, y1, z0 + 0.08))
	VillageAssets.box_st(parts["mull"], Vector3(cc - hw, ym - 0.014, z0), Vector3(cc + hw, ym + 0.014, z0 + 0.08))

	if sill:
		VillageAssets.box_st(parts["sill"], Vector3(cc - hw - fw - 0.05, y0 - fw - 0.05, z0), Vector3(cc + hw + fw + 0.05, y0 - fw, z0 + 0.11))


# +x 면(평면 x0)에 붙는 창: 가운데 z=cc
static func win_on_x(parts: Dictionary, cc: float, y0: float, y1: float, hw: float, x0: float, sill: bool = true) -> void:
	var fw: float = WIN_FRAME
	var ym: float = (y0 + y1) * 0.5
	VillageAssets.box_st(parts["frame"], Vector3(x0, y0 - fw, cc - hw - fw), Vector3(x0 + 0.05, y1 + fw, cc + hw + fw))
	VillageAssets.box_st(parts["glass"], Vector3(x0, y0, cc - hw), Vector3(x0 + 0.065, y1, cc + hw))
	VillageAssets.box_st(parts["mull"], Vector3(x0, y0, cc - 0.014), Vector3(x0 + 0.08, y1, cc + 0.014))
	VillageAssets.box_st(parts["mull"], Vector3(x0, ym - 0.014, cc - hw), Vector3(x0 + 0.08, ym + 0.014, cc + hw))

	if sill:
		VillageAssets.box_st(parts["sill"], Vector3(x0, y0 - fw - 0.05, cc - hw - fw - 0.05), Vector3(x0 + 0.11, y0 - fw, cc + hw + fw + 0.05))


# attic: 박공 끝벽 가운데의 작은 창 {face: "x"|"z", c, y0, y1, w}
static func add_windows(b, p: Dictionary, lo: Vector2, hi: Vector2, wall_h: float, slots: Dictionary, attic: Dictionary) -> void:
	var parts: Dictionary = win_parts(b, p, Vector3(lo.x, 0.0, lo.y), Vector3(hi.x + 0.12, wall_h, hi.y + 0.12))

	for sl in slots["z"]:
		win_on_z(parts, sl["c"], sl["y0"], sl["y1"], float(sl["w"]) * 0.5, hi.y)

	for sx in slots["x"]:
		win_on_x(parts, sx["c"], sx["y0"], sx["y1"], float(sx["w"]) * 0.5, hi.x)

	if not attic.is_empty():
		if attic["face"] == "z":
			win_on_z(parts, attic["c"], attic["y0"], attic["y1"], float(attic["w"]) * 0.5, hi.y, false)
		else:
			win_on_x(parts, attic["c"], attic["y0"], attic["y1"], float(attic["w"]) * 0.5, hi.x, false)
