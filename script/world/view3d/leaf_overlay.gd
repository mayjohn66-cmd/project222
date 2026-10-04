class_name LeafOverlay
extends Control
## 가을 낙엽: 바람을 타고 흔들리며 떨어지는 도트 낙엽(화면 위 입자). 가끔 바람이 세게 불어 한꺼번에 많이 떨어진다. 마우스는 통과.

const MAX_LEAVES: int = 90
const COLORS: Array = [Color(0.92, 0.5, 0.15), Color(0.8, 0.24, 0.14), Color(0.96, 0.8, 0.26), Color(0.6, 0.38, 0.2)]

var pixel: int = 3
var amount: float = 0.0  # 0~1 (비·눈이 오면 줄인다)
var _t: float = 0.0
var _seeds: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777

	for i in range(MAX_LEAVES):
		_seeds.append(Vector4(rng.randf(), rng.randf(), rng.randf(), rng.randf()))


func set_amount(value: float) -> void:
	amount = value
	visible = amount > 0.02


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _draw() -> void:
	var size_px: Vector2 = get_viewport_rect().size
	var gust: float = pow(0.5 + 0.5 * sin(_t * 0.23 + 1.0), 3.0)  # 가끔 세게 부는 바람
	var n: int = int((5.0 + 14.0 * gust) * amount)

	for i in range(mini(n, MAX_LEAVES)):
		var s: Vector4 = _seeds[i]
		var speed: float = 38.0 + s.z * 52.0 + gust * 30.0
		var y: float = fposmod(s.y * size_px.y + _t * speed, size_px.y + 20.0) - 10.0
		var sway: float = sin(_t * (0.9 + s.w * 1.4) + s.x * 12.0) * (18.0 + 26.0 * s.w)
		var x: float = fposmod(s.x * size_px.x + sway + _t * (14.0 + gust * 60.0), size_px.x)
		var px: float = float(pixel)
		var flip: bool = int(_t * (2.0 + s.w * 3.0) + s.z * 10.0) % 2 == 0  # 팔랑이며 뒤집힘
		var col: Color = COLORS[int(s.z * 100.0) % COLORS.size()]
		var w: float = px * (3.0 if flip else 2.0)
		var h: float = px * (2.0 if flip else 3.0)
		draw_rect(Rect2(floorf(x / px) * px, floorf(y / px) * px, w, h), col)
		draw_rect(Rect2(floorf(x / px) * px, floorf(y / px) * px, px, px), col.darkened(0.25))
