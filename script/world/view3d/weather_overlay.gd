class_name WeatherOverlay
extends Control
## 비·눈 입자(화면 위 도트). 3D 화면과 같은 굵은 도트 크기(pixel)로 그려서 도트 그림과 어울리게 한다. 마우스는 통과.

const MAX_RAIN: int = 420
const MAX_SNOW: int = 240

var kind: String = "clear"
var intensity: float = 0.0
var pixel: int = 3
var _t: float = 0.0
var _seeds: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242

	for i in range(MAX_RAIN):
		_seeds.append(Vector3(rng.randf(), rng.randf(), rng.randf()))


func set_weather(new_kind: String, new_intensity: float) -> void:
	kind = new_kind
	intensity = new_intensity
	visible = kind != "clear" and intensity > 0.01


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _draw() -> void:
	var size_px: Vector2 = get_viewport_rect().size

	if kind == "rain":
		_draw_rain(size_px)
	elif kind == "snow":
		_draw_snow(size_px)


func _draw_rain(size_px: Vector2) -> void:
	var n: int = int(float(MAX_RAIN) * intensity)
	var col := Color(0.78, 0.86, 1.0, 0.55)
	var len_px: float = float(pixel) * (3.0 + 2.0 * intensity)
	var slant: float = 0.18 + 0.22 * intensity  # 센 비는 더 비스듬히(바람)

	for i in range(n):
		var s: Vector3 = _seeds[i]
		var speed: float = 900.0 + s.z * 500.0
		var y: float = fposmod(s.y * (size_px.y + len_px) + _t * speed, size_px.y + len_px) - len_px
		var x: float = fposmod(s.x * (size_px.x + 200.0) - y * slant, size_px.x + 200.0) - 100.0
		x = floorf(x / float(pixel)) * float(pixel)
		y = floorf(y / float(pixel)) * float(pixel)
		draw_line(Vector2(x, y), Vector2(x - len_px * slant, y + len_px), col, float(pixel), false)

		# 일부는 바닥에 닿는 작은 물튀김(가로 도트)
		if s.z > 0.85 and y > size_px.y * 0.35 and fmod(_t * 6.0 + s.x * 10.0, 1.0) < 0.25:
			draw_rect(Rect2(x - float(pixel), y + len_px, float(pixel) * 3.0, float(pixel)), Color(0.85, 0.9, 1.0, 0.35))


func _draw_snow(size_px: Vector2) -> void:
	var n: int = int(float(MAX_SNOW) * intensity)
	var col := Color(1.0, 1.0, 1.0, 0.85)

	for i in range(n):
		var s: Vector3 = _seeds[i]
		var speed: float = 70.0 + s.z * 90.0
		var y: float = fposmod(s.y * size_px.y + _t * speed, size_px.y)
		var x: float = fposmod(s.x * size_px.x + sin(_t * (0.8 + s.z) + s.y * 20.0) * 24.0 + _t * 18.0, size_px.x)
		var sz: float = float(pixel) * (2.0 if s.z > 0.7 else 1.0)
		draw_rect(Rect2(floorf(x / float(pixel)) * float(pixel), floorf(y / float(pixel)) * float(pixel), sz, sz), col)
