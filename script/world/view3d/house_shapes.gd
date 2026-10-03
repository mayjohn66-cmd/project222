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
	var half: float = clampf(cell_w * 0.4, 0.4, 0.62)
	var y0: float = 0.14
	var y1: float = c["wall_h"] * 0.66
	var ts: int = p["ts"]
	var tex: ImageTexture = window_tex(int(half * 2.0 * float(ts)), int((y1 - y0) * float(ts) * 1.2), c["plaster"], c["timber"])
	var spec: Dictionary = VillageAssets.spec(tex, Color.WHITE, "bay_window", "돌출 창 앞·옆면 %d×%d" % [tex.get_width(), tex.get_height()])
	VillageAssets.box(b, "bay", spec, Vector3(cx - half, y0, hi.y), Vector3(cx + half, y1, hi.y + 0.4))
	var rt: Dictionary = c["roof_spec"]
	VillageAssets.slope(b, "bay_roof", rt, Vector3(cx - half - 0.06, y1 + 0.2, hi.y), Vector3(cx + half + 0.06, y1 + 0.2, hi.y), Vector3(cx + half + 0.06, y1, hi.y + 0.48), Vector3(cx - half - 0.06, y1, hi.y + 0.48), Vector3(0.0, 0.48, 0.2).normalized(), 2.0 * half + 0.12, 0.52)


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
	var tex: ImageTexture = window_tex(int((z1 - z0) * float(ts)), int(ah * float(ts) * 1.1), c["plaster"], c["timber"])
	var spec: Dictionary = VillageAssets.spec(tex, Color.WHITE, "annex_wall", "별채 벽 %d×%d" % [tex.get_width(), tex.get_height()])
	VillageAssets.box(b, "annex", spec, Vector3(hi.x - 0.05, 0.0, z0), Vector3(hi.x + run - 0.1, ah, z1))
	var rt: Dictionary = c["roof_spec"]
	var drop: float = 0.3
	VillageAssets.slope(b, "annex_roof", rt, Vector3(hi.x - 0.02, ah + drop, z0 - 0.1), Vector3(hi.x - 0.02, ah + drop, z1 + 0.1), Vector3(hi.x + run + 0.12, ah, z1 + 0.1), Vector3(hi.x + run + 0.12, ah, z0 - 0.1), Vector3(drop, run + 0.14, 0.0).normalized(), z1 - z0 + 0.2, run + 0.16)
	VillageAssets.box(b, "annex_fascia", c["trim_spec"], Vector3(hi.x + run + 0.08, ah - 0.06, z0 - 0.1), Vector3(hi.x + run + 0.14, ah + 0.02, z1 + 0.1))


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
	var tex: ImageTexture = window_tex(int(r * 2.0 * float(ts) * 0.8), int(th * float(ts) * 0.5), c["plaster"], c["timber"])
	var spec: Dictionary = VillageAssets.spec(tex, Color.WHITE, "tower_wall", "코너 탑 벽 %d×%d" % [tex.get_width(), tex.get_height()])
	VillageAssets.oct(b, "tower_body", spec, cx, cz, r, 0.0, th)
	VillageAssets.oct(b, "tower_cap_ring", c["trim_spec"], cx, cz, r + 0.08, th, th + 0.1)
	VillageAssets.oct(b, "tower_roof", c["roof_spec"], cx, cz, r + 0.16, th + 0.1, th + 0.1 + 1.15, 0.03)


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
	var dw: float = 0.78
	var face_h: float = 0.7
	var y_top: float = y_f + face_h
	var span_lo: float = u0 + 0.9
	var span_hi: float = u1 - 1.7  # 굴뚝(+u 끝)을 피한다
	var ts: int = p["ts"]
	var tex: ImageTexture = window_tex(int(dw * float(ts)), int(face_h * float(ts) * 1.25), c["plaster"], c["timber"])
	var face_spec: Dictionary = VillageAssets.spec(tex, Color.WHITE, "dormer_front", "지붕창 앞면 %d×%d" % [tex.get_width(), tex.get_height()])
	var side_spec: Dictionary = c["wall_spec"]
	var rt: Dictionary = c["roof_spec"]

	if span_hi - span_lo < 0.2:
		count = 1
		span_lo = (u0 + u1) * 0.5 - 0.5
		span_hi = span_lo

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
		var ph: float = 0.36
		var wf: float = w_front + 0.08
		var wb: float = w_back
		var a0: float = uc - dw * 0.5 - 0.07
		var a1: float = uc + dw * 0.5 + 0.07

		if ridge_x:
			VillageAssets.roof_prism(b, "dormer_roof", rt, a0, a1, vc + wb, vc + wf, yr, ph, false)
		else:
			VillageAssets.roof_prism(b, "dormer_roof", rt, vc + wb, vc + wf, a0, a1, yr, ph, true)
