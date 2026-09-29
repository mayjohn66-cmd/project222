extends RefCounted


const PREVIEW_Z_INDEX: int = 100

const VALID_PREVIEW_COLOR: Color = Color(
	1.0,
	1.0,
	1.0,
	0.5
)

const INVALID_PREVIEW_COLOR: Color = Color(
	1.0,
	0.2,
	0.2,
	0.5
)

const GAMEPLAY_GROUPS: Array[String] = [
	"shelf",
	"register",
	"door",
	"production_facility"
]


var preview_node: Node2D = null


func create_preview(
	parent_node: Node,
	scene: PackedScene,
	build_id: String
) -> Node2D:
	clear_preview()

	if scene == null:
		push_error(
			"[건축 미리보기] 씬이 없습니다: "
			+ build_id
		)

		return null

	var instance: Node = scene.instantiate()

	if not instance is Node2D:
		push_error(
			"[건축 미리보기] Node2D가 아닌 씬: "
			+ build_id
		)

		instance.queue_free()
		return null

	preview_node = instance as Node2D

	parent_node.add_child(
		preview_node
	)

	_remove_gameplay_groups()
	_apply_preview_settings(build_id)
	_disable_preview_collision()

	return preview_node


func clear_preview() -> void:
	if is_instance_valid(preview_node):
		preview_node.queue_free()

	preview_node = null


func get_preview() -> Node2D:
	if not is_instance_valid(preview_node):
		return null

	return preview_node


func has_preview() -> bool:
	return is_instance_valid(preview_node)


func show_preview() -> void:
	if has_preview():
		preview_node.visible = true


func hide_preview() -> void:
	if has_preview():
		preview_node.visible = false


func set_preview_position(
	world_position: Vector2
) -> void:
	if has_preview():
		preview_node.global_position = world_position


func set_preview_color(
	color: Color
) -> void:
	if has_preview():
		preview_node.modulate = color


func set_placement_valid(
	is_valid: bool
) -> void:
	if is_valid:
		set_preview_color(
			VALID_PREVIEW_COLOR
		)
	else:
		set_preview_color(
			INVALID_PREVIEW_COLOR
		)


func _remove_gameplay_groups() -> void:
	for group_name in GAMEPLAY_GROUPS:
		if preview_node.is_in_group(group_name):
			preview_node.remove_from_group(
				group_name
			)


func _apply_preview_settings(
	build_id: String
) -> void:
	preview_node.set_meta(
		"is_build_preview",
		true
	)

	preview_node.set_meta(
		"build_id",
		build_id
	)

	preview_node.z_index = PREVIEW_Z_INDEX

	if preview_node.has_method(
		"set_checkout_preview_visible"
	):
		preview_node.set_checkout_preview_visible(
			true
		)


func _disable_preview_collision() -> void:
	var collision: Node = (
		preview_node.get_node_or_null(
			"Collision"
		)
	)

	if collision == null:
		return

	if collision.has_method("set_blocking"):
		collision.set_blocking(false)
	else:
		collision.set_deferred(
			"disabled",
			true
		)
