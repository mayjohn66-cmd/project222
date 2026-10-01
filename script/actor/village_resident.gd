class_name VillageResident
extends CharacterBody2D

const VISUAL = preload("res://script/actor/character_visual.gd")
var resident_id: String
var customer_type_id: String
var customer_group_id: String
var title: Label
var route := PackedVector2Array()
var destination := Vector2.INF
var routine_label := "머무는 곳"
var retry_elapsed := 0.0

func _ready() -> void:
	y_sort_enabled = true
	collision_layer = 0
	collision_mask = 1
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = VillageLifeFlow.SETTINGS.resident_radius
	collision.shape = shape
	var visual := AnimatedSprite2D.new()
	visual.set_script(VISUAL)
	visual.actor_role = "customer"
	add_child(visual)
	add_child(collision)
	title = Label.new()
	title.position = Vector2(-110, -88)
	title.size = Vector2(220, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("fff0d0"))
	title.add_theme_color_override("font_outline_color", Color("302415"))
	title.add_theme_constant_override("outline_size", 4)
	add_child(title)

func refresh_title(entry: Dictionary) -> void:
	title.text = str(entry["name"]) + " [E]\n" + VillageLifeFlow.friendship_name(resident_id)

func set_destination(point: Vector2, label_text: String) -> void:
	routine_label = label_text
	if destination.distance_squared_to(point) < 1.0: return
	destination = point
	retry_elapsed = 0.0
	route = VillageRoutine.route(get_parent().get_parent(),global_position,destination)

func _physics_process(delta: float) -> void:
	var world := get_parent().get_parent()
	velocity = Vector2.ZERO
	if not visible or world.get_node("WorldInteractions").blocked(): return
	if world.get_node("DayManager").hour_timer.paused: return
	var editor = world.get_node_or_null("VillageMapEditor")
	if editor != null and editor.active: return
	var player = world.get_node("Actors/Player")
	# Wait for a nearby player so a moving neighbor remains easy to greet.
	if player.global_position.distance_to(global_position) <= VillageLifeFlow.SETTINGS.interaction_distance: return
	if destination == Vector2.INF or global_position.distance_to(destination) <= 2.0: return
	retry_elapsed += delta
	if route.is_empty():
		if retry_elapsed >= VillageLifeFlow.SETTINGS.route_retry_seconds:
			retry_elapsed = 0.0
			route = VillageRoutine.route(world,global_position,destination)
		return
	var point := route[0]
	if global_position.distance_to(point) <= 2.0:
		route.remove_at(0)
		return
	velocity = (point - global_position).normalized() * minf(VillageLifeFlow.SETTINGS.walk_speed,global_position.distance_to(point) / delta)
	move_and_slide()
	if get_slide_collision_count() > 0: route.clear()

func routine_status() -> String:
	return "이동 중 · " + routine_label if destination != Vector2.INF and global_position.distance_to(destination) > 2.0 else routine_label
