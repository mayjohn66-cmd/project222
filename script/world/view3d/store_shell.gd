class_name StoreShell
extends RefCounted
## 현대 편의점 껍데기: 매장·창고·생산실의 벽을 만든다. 편의점이 통째로 이세계에 온 설정이라 마을 건물(나무·돌)과 달리 현대식으로 꾸민다.
##  - 안쪽 벽(높은 벽): 흰 벽 + 아래 걸레받이 + 브랜드색 띠 + 위 몰딩
##  - 길 쪽 낮은 벽: 유리 진열창(알루미늄 창틀 + 푸른 유리) + 아래 흰 낮은 벽 + 브랜드색 띠 + 위 알루미늄 틀
## 좌표는 칸 좌표. lo/hi 는 벽 상자(두께 0.3)의 모서리이고, 긴 쪽이 벽이 이어지는 방향이다.

const PLASTER := Color(0.95, 0.95, 0.92)
const BASEBOARD := Color(0.42, 0.45, 0.5)
const CORNICE := Color(0.82, 0.84, 0.86)
const ALUMINUM := Color(0.78, 0.8, 0.84)
const GLASS := Color(0.6, 0.82, 0.94)
const BRAND := Color(0.08, 0.62, 0.56)  # 편의점 브랜드색(청록)
const MULLION_STEP: float = 1.0


static func build_wall(lo: Vector2, hi: Vector2, tall: bool, accent: Color, p: Dictionary) -> Dictionary:
	var b := VillageAssets.PartBuilder.new()
	var parts: Dictionary = {}
	var along_x: bool = (hi.x - lo.x) >= (hi.y - lo.y)
	var length: float = (hi.x - lo.x) if along_x else (hi.y - lo.y)
	var width: float = (hi.y - lo.y) if along_x else (hi.x - lo.x)
	var ts: int = int(p["ts"])
	var wrap: float = 0.012  # 띠가 벽 양면에 살짝 튀어나와 보이게

	var spec := func(color: Color, name: String, emit: float = 0.0) -> Dictionary:
		var sp: Dictionary = VillageAssets._flat_spec(ts, color, name)

		if emit > 0.0:
			sp["emit"] = emit

		return sp

	var add := func(sp: Dictionary, u0: float, u1: float, w0: float, w1: float, y0: float, y1: float) -> void:
		var a := Vector3(lo.x + u0, y0, lo.y + w0) if along_x else Vector3(lo.x + w0, y0, lo.y + u0)
		var c := Vector3(lo.x + u1, y1, lo.y + w1) if along_x else Vector3(lo.x + w1, y1, lo.y + u1)
		var key: String = str(sp["name"])

		if not parts.has(key):
			parts[key] = b.new_part(sp, Vector3(lo.x, 0.0, lo.y), Vector3(hi.x, 2.0, hi.y))

		VillageAssets.box_st(parts[key], Vector3(minf(a.x, c.x), minf(a.y, c.y), minf(a.z, c.z)), Vector3(maxf(a.x, c.x), maxf(a.y, c.y), maxf(a.z, c.z)))

	var plaster: Dictionary = spec.call(PLASTER, "shell_plaster")
	var base: Dictionary = spec.call(BASEBOARD, "shell_base")
	var stripe: Dictionary = spec.call(accent, "shell_accent_" + accent.to_html(false))
	var cornice: Dictionary = spec.call(CORNICE, "shell_cornice")
	var total: float

	if tall:
		total = 2.0
		add.call(plaster, 0.0, length, 0.0, width, 0.0, 2.0)
		add.call(base, 0.0, length, -wrap, width + wrap, 0.0, 0.12)
		add.call(stripe, 0.0, length, -wrap, width + wrap, 0.94, 1.06)
		add.call(cornice, 0.0, length, -wrap, width + wrap, 1.9, 2.0)
	else:
		# 길 쪽 낮은 벽 = 유리 진열창
		total = 1.3
		var alu: Dictionary = spec.call(ALUMINUM, "shell_alu")
		var glass: Dictionary = spec.call(GLASS, "shell_glass", 0.28)
		add.call(plaster, 0.0, length, 0.0, width, 0.0, 0.46)
		add.call(base, 0.0, length, -wrap, width + wrap, 0.0, 0.1)
		add.call(stripe, 0.0, length, -wrap, width + wrap, 0.3, 0.4)
		add.call(glass, 0.0, length, width * 0.4, width * 0.6, 0.46, 1.22)
		add.call(alu, 0.0, length, -wrap, width + wrap, 1.22, 1.3)
		add.call(alu, 0.0, length, -wrap, width + wrap, 0.46, 0.5)
		var n: int = maxi(1, int(round(length / MULLION_STEP)))

		for i in range(n + 1):
			var u: float = length * float(i) / float(n)
			add.call(alu, maxf(0.0, u - 0.04), minf(length, u + 0.04), -wrap, width + wrap, 0.46, 1.22)

	var mesh := ArrayMesh.new()
	var specs: Array = b.commit_into(mesh)
	return {"mesh": mesh, "specs": specs, "total_blocks": total, "lo": lo, "hi": hi}
