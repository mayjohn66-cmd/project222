class_name EmployeeApplicant
extends VillageResident
var employee_id := ""
var sprite: AnimatedSprite2D
func _ready() -> void:
	super._ready()
	resident_id = "employee_applicant:" + employee_id
	set_meta("look_key", "worker")
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = load("res://art/characters/cozy_v1/" + employee_id + "/frames.tres")
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position.y = -18
	add_child(sprite)
	title.text = EmployeeData.get_employee(employee_id)["display_name"] + " · 지원자 [E]"
	sprite.play("idle_down")
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var direction := "down"
	if velocity.length_squared() > 1:
		direction = ("right" if velocity.x > 0 else "left") if absf(velocity.x) > absf(velocity.y) else ("down" if velocity.y > 0 else "up")
	var animation := ("walk_" if velocity.length_squared() > 1 else "idle_") + direction
	if sprite.sprite_frames.has_animation(animation): sprite.play(animation)
