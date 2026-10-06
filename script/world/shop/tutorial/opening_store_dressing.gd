class_name OpeningStoreDressing
extends RefCounted
## 새 게임 프롤로그의 가게 안 장식(새 그림 파일 없음, 입방체와 색만).
##   `build_modern()`  전이 전: 현대 편의점답게 음료 냉장 진열장·곤돌라 진열대·과자 선반과 알록달록한 상품을 늘어놓는다.
##   `smash()`         전이 뒤: 그 진열대를 전부 부수고 부서진 판자·쏟아진 상품·유리 조각을 흩어 놓는다. 시작 배치의 진열대 하나(2,2)만 멀쩡하다.
##   `clear_debris_step()` 정리를 시작하면 잔해를 몇 개씩 치운다.
## 항목 이름은 `cut_s` 로 시작해 도시 장식(`cut_`)·매장 벽과 섞이지 않는다. 배치 수치는 아래 상수와 `_footprints()`에서 조정한다.

const KEY_PREFIX := "cut_s"
const GOODS_COLORS := [
	Color(0.95, 0.35, 0.3), Color(0.98, 0.8, 0.3), Color(0.3, 0.7, 0.95), Color(0.45, 0.85, 0.5),
	Color(0.95, 0.55, 0.8), Color(0.95, 0.95, 0.98), Color(0.62, 0.48, 0.92), Color(0.98, 0.6, 0.25),
]
const BODY := Color(0.86, 0.89, 0.93)
const COOLER_BODY := Color(0.8, 0.88, 0.98)
const COOLER_LIGHT := Color(0.6, 1.0, 2.2)
const WOOD := Color(0.62, 0.43, 0.28)
const GLASS := Color(0.7, 0.92, 1.0)
const DEBRIS_PER_SPOT := 9
const SEED_VALUE := 5

# 부서진 잔해를 놓지 않는 곳: 남은 진열대(2,2)·계산대 주변·문 앞 통로. (칸 좌표 사각형 lo, hi)
const KEEP_CLEAR := [Rect2(1.3, 1.3, 1.4, 1.4), Rect2(3.2, 2.2, 2.6, 1.6), Rect2(-0.5, 3.3, 2.6, 1.5)]

var view: Node                      # StoreView3D
var keys: Array[String] = []
var debris: Array[String] = []
var _count: int = 0


func _init(store_view: Node) -> void:
	view = store_view


func built() -> bool:
	return not keys.is_empty()


# ---------------------------------------------------------------- 전이 전

func build_modern() -> void:
	if built() or view == null:
		return

	for spot in _footprints():
		match str(spot["kind"]):
			"cooler":
				_cooler(spot["lo"], spot["hi"])
			"gondola":
				_gondola(spot["lo"], spot["hi"], bool(spot["along_x"]))
			"rack":
				_rack(spot["lo"], spot["hi"])


# 진열대 자리(전이 전 모양과 부서진 뒤 잔해가 같은 자리를 쓴다).
func _footprints() -> Array:
	return [
		{"kind": "cooler", "lo": Vector2(2.7, -0.42), "hi": Vector2(9.3, 0.42), "along_x": true},
		{"kind": "gondola", "lo": Vector2(5.9, 1.25), "hi": Vector2(8.9, 1.75), "along_x": true},
		{"kind": "gondola", "lo": Vector2(6.3, 4.7), "hi": Vector2(9.3, 5.2), "along_x": true},
		{"kind": "rack", "lo": Vector2(1.0, 6.2), "hi": Vector2(1.7, 6.9), "along_x": true},
	]


func _put(name: String, lo: Vector2, hi: Vector2, height: float, tint: Color, base: float = 0.0, kind: String = "tile") -> String:
	_count += 1
	var key: String = "%s%s%d" % [KEY_PREFIX, name, _count]
	view._set_item(key, lo, hi, height, kind, tint, "", base)
	return key


func _good_color(i: int) -> Color:
	return GOODS_COLORS[i % GOODS_COLORS.size()]


# 음료 냉장 진열장: 벽에 붙은 흰 몸통, 앞면에 층마다 알록달록한 음료, 위쪽 파란 조명
func _cooler(lo: Vector2, hi: Vector2) -> void:
	keys.append(_put("cb", lo, hi, 1.9, COOLER_BODY))
	keys.append(_put("cl", Vector2(lo.x + 0.1, lo.y + 0.1), Vector2(hi.x - 0.1, hi.y - 0.1), 0.08, COOLER_LIGHT, 1.9))
	var n: int = int((hi.x - lo.x) / 0.55)

	for level in range(4):
		for i in range(n):
			var x0: float = lo.x + 0.15 + float(i) * 0.55
			keys.append(_put("cg", Vector2(x0, hi.y), Vector2(x0 + 0.42, hi.y + 0.1), 0.26, _good_color(i * 3 + level), 0.2 + float(level) * 0.42))


# 곤돌라 진열대: 회색 몸통, 위·양면에 층마다 상품
func _gondola(lo: Vector2, hi: Vector2, along_x: bool) -> void:
	keys.append(_put("gb", lo, hi, 1.1, BODY))
	var length: float = (hi.x - lo.x) if along_x else (hi.y - lo.y)
	var n: int = int(length / 0.6)

	for i in range(n):
		var at: float = 0.12 + float(i) * 0.6

		if along_x:
			keys.append(_put("gt", Vector2(lo.x + at, lo.y + 0.08), Vector2(lo.x + at + 0.45, hi.y - 0.08), 0.3, _good_color(i + 1), 1.1))
			keys.append(_put("gf", Vector2(lo.x + at, hi.y), Vector2(lo.x + at + 0.45, hi.y + 0.09), 0.24, _good_color(i), 0.2))
			keys.append(_put("gf", Vector2(lo.x + at, hi.y), Vector2(lo.x + at + 0.45, hi.y + 0.09), 0.24, _good_color(i + 4), 0.62))
			keys.append(_put("gr", Vector2(lo.x + at, lo.y - 0.09), Vector2(lo.x + at + 0.45, lo.y), 0.24, _good_color(i + 2), 0.2))
			keys.append(_put("gr", Vector2(lo.x + at, lo.y - 0.09), Vector2(lo.x + at + 0.45, lo.y), 0.24, _good_color(i + 5), 0.62))


# 입구 쪽 과자 선반
func _rack(lo: Vector2, hi: Vector2) -> void:
	keys.append(_put("rb", lo, hi, 1.2, BODY))

	for i in range(3):
		keys.append(_put("rg", Vector2(lo.x + 0.08 + float(i) * 0.2, lo.y + 0.1), Vector2(lo.x + 0.24 + float(i) * 0.2, hi.y - 0.1), 0.3, _good_color(i * 2), 1.2))


# ---------------------------------------------------------------- 전이 뒤

# 현대 진열대를 모두 치우고 잔해를 깐다.
func smash() -> void:
	for k in keys:
		view._remove_item(k)

	keys.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_VALUE

	for spot in _footprints():
		var lo: Vector2 = spot["lo"] - Vector2(0.4, 0.4)
		var hi: Vector2 = spot["hi"] + Vector2(0.4, 0.4)

		# 부서진 판자(눕거나 비스듬히 박힌 것처럼 짧고 낮은 막대)
		for i in range(DEBRIS_PER_SPOT):
			var at := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
			var wide: bool = rng.randf() < 0.5
			var size := Vector2(rng.randf_range(0.45, 0.9), 0.13) if wide else Vector2(0.13, rng.randf_range(0.45, 0.9))
			_add_debris("dp", at, size, rng.randf_range(0.05, 0.16), WOOD * rng.randf_range(0.8, 1.15))

		# 쏟아진 상품
		for i in range(DEBRIS_PER_SPOT):
			var at2 := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
			_add_debris("dg", at2, Vector2(0.2, 0.2), rng.randf_range(0.1, 0.18), GOODS_COLORS[rng.randi() % GOODS_COLORS.size()])

		# 꺾여 남은 기둥
		for i in range(2):
			var at3 := Vector2(rng.randf_range(lo.x + 0.3, hi.x - 0.3), rng.randf_range(lo.y + 0.3, hi.y - 0.3))
			_add_debris("ds", at3, Vector2(0.11, 0.11), rng.randf_range(0.35, 0.8), WOOD * 0.8)

		# 유리 조각
		if str(spot["kind"]) == "cooler":
			for i in range(8):
				var at4 := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(spot["hi"].y, spot["hi"].y + 1.0))
				_add_debris("dh", at4, Vector2(rng.randf_range(0.12, 0.3), rng.randf_range(0.12, 0.3)), 0.03, GLASS)


func _add_debris(name: String, at: Vector2, size: Vector2, height: float, tint: Color) -> void:
	for clear in KEEP_CLEAR:
		if (clear as Rect2).intersects(Rect2(at - size * 0.5, size)):
			return

	debris.append(_put(name, at - size * 0.5, at + size * 0.5, height, tint))


# 잔해를 몇 개씩 치운다. 남은 개수를 돌려준다.
func clear_debris_step(count: int) -> int:
	for i in range(mini(count, debris.size())):
		view._remove_item(debris.pop_back())

	return debris.size()


func clear_all() -> void:
	for k in keys:
		view._remove_item(k)

	for k in debris:
		view._remove_item(k)

	keys.clear()
	debris.clear()
