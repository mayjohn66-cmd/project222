extends AnimatedSprite2D
## Shared movement visuals; observes actual movement, including entrance tweens.
@export_enum("player", "employee", "customer") var actor_role: String = "player"
const ROOT := "res://art/characters/cozy_v1/"
const DIRECTION_NAMES := ["right", "down_right", "down", "down_left", "left", "up_left", "up", "up_right"]
var profile_id: String = ""
var facing: String = "down"
var previous_position := Vector2.ZERO
var stationary_time: float = 1.0

func _ready() -> void:
	process_priority = 100
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	position = Vector2(0,-32)
	previous_position = get_parent().global_position
	refresh_profile()

func refresh_profile() -> void:
	var wanted := "player"
	if actor_role == "employee": wanted = str(get_parent().get("employee_id"))
	elif actor_role == "customer": wanted = str(get_parent().get("customer_type_id"))
	if wanted == profile_id: return
	var path := ROOT + wanted + "/frames.tres"
	if not ResourceLoader.exists(path) and actor_role == "customer":
		# 소분류 그림이 없으면 대분류 그림을 쓴다.
		path = ROOT + str(get_parent().get("customer_group_id")) + "/frames.tres"
	if not ResourceLoader.exists(path):
		path = ROOT + ("normal" if actor_role == "customer" else "player") + "/frames.tres"
	profile_id = wanted
	sprite_frames = load(path)
	play("idle_" + facing)

func _process(delta: float) -> void:
	refresh_profile()
	var current: Vector2 = get_parent().global_position
	var displacement := current - previous_position
	previous_position = current
	if not is_visible_in_tree() or displacement.length() > 80.0:
		stationary_time = 1.0
		show_idle()
		return
	update_motion(displacement,delta)

func update_motion(displacement: Vector2, delta: float) -> void:
	if displacement.length_squared() > 0.0025:
		stationary_time = 0.0
		var sector := posmod(roundi(displacement.angle() / (PI / 4.0)),8)
		facing = DIRECTION_NAMES[sector]
		flip_h = facing in ["right", "down_right", "up_right"]
		speed_scale = clampf(displacement.length() / maxf(delta,0.001) / 120.0,0.7,1.5)
		play("walk_" + facing)
	else:
		stationary_time += delta
		# Brief grace avoids an idle flash at every pathfinding cell boundary.
		if stationary_time >= 0.10: show_idle()

func show_idle() -> void:
	speed_scale = 1.0
	flip_h = facing in ["right", "down_right", "up_right"]
	play("idle_" + facing)
