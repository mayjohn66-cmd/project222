class_name ExpeditionDamageDigits
extends RefCounted
## 실제 피해를 숫자별 PNG로 조합한다. 글꼴 숫자나 공격력 추정치는 사용하지 않는다.
const LIFETIME := 0.85
const DIGIT_SIZE := Vector2(12, 16)
const SCALE := 2.0
const GAP := 2.0
const RISE := 32.0
const FINISH_DELAY := 0.45
static var _textures: Array[Texture2D] = []

static func textures() -> Array[Texture2D]:
	if _textures.is_empty():
		for digit in 10:
			_textures.append(load("res://art/ui/damage_digits/digit_%d.png" % digit) as Texture2D)
	return _textures

static func digits(amount: int) -> Array[int]:
	var result: Array[int] = []
	for character in str(maxi(0, amount)): result.append(int(character))
	return result

static func draw_number(canvas: CanvasItem, center: Vector2, amount: int, life: float) -> void:
	var remaining := clampf(life / LIFETIME, 0, 1)
	var sequence := digits(amount)
	var extent := DIGIT_SIZE * SCALE
	var width := sequence.size() * extent.x + (sequence.size() - 1) * GAP
	var origin := center - Vector2(width * 0.5, extent.y + RISE * (1.0 - remaining))
	var tint := Color(1, 1, 1, minf(1, remaining * 4.0))
	var pictures := textures()
	for i in sequence.size():
		canvas.draw_texture_rect(pictures[sequence[i]], Rect2(origin + Vector2(i * (extent.x + GAP), 0), extent), false, tint)

static func finish_room(controller: ExpeditionRoomController, room: ExpeditionRoomModel) -> void:
	var view := controller.view
	await view.get_tree().create_timer(FINISH_DELAY).timeout
	if is_instance_valid(view) and view.visible and view.model == room and room.finished and room.player_hp > 0:
		controller._exit()
