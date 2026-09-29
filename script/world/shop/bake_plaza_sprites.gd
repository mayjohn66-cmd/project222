extends SceneTree
## Bake one straight affine projection per sprite. Straight timber stays straight.

const HERB_SOURCE = "res://art/world/plaza_props_v1/herb_stall_tile_aligned_v2.png"
const HERB_OUTPUT = "res://art/world/plaza_props_v1/herb_stall_tile_aligned_v4.png"
const CART_SOURCE = "res://art/world/plaza_props_v1/supply_cart.png"
const CART_OUTPUT = "res://art/world/plaza_props_v1/supply_cart_tile_aligned_v3.png"

func _initialize() -> void:
	call_deferred("_bake")

func _bake() -> void:
	# Measured bottom edges: the original stall's near-left and near-right
	# slopes are about +0.48 and -0.35. This single affine basis maps both
	# to the tile's +0.5 / -0.5 axes, without bowing any timber or cloth edge.
	var herb_anchor := Vector2(679,997)
	var herb_output_anchor := herb_anchor+Vector2(0,110)
	var herb_x_axis := Vector2(0.91,-0.072)
	var herb_y_axis := Vector2(0.0,1.10)
	var herb_transform := Transform2D(herb_x_axis,herb_y_axis,herb_output_anchor-herb_x_axis*herb_anchor.x-herb_y_axis*herb_anchor.y)
	var herb_ok := await _bake_one(HERB_SOURCE,HERB_OUTPUT,herb_transform,Vector2i(1536,1152))
	# The cart body was measured at roughly +0.58 / -0.50.
	var cart_anchor := Vector2(790,760)
	var cart_x_axis := Vector2(1.0,-0.037)
	var cart_y_axis := Vector2(0.0,0.92)
	var cart_transform := Transform2D(cart_x_axis,cart_y_axis,cart_anchor-cart_x_axis*cart_anchor.x-cart_y_axis*cart_anchor.y)
	var cart_ok := await _bake_one(CART_SOURCE,CART_OUTPUT,cart_transform,Vector2i(1536,1024))
	quit(0 if herb_ok and cart_ok else 1)

func _bake_one(source_path: String, output_path: String, sprite_transform: Transform2D, canvas_size: Vector2i) -> bool:
	var viewport := SubViewport.new()
	viewport.size = canvas_size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = load(source_path)
	sprite.transform = sprite_transform
	viewport.add_child(sprite)
	for frame in range(5):
		await process_frame
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Could not render "+source_path)
		viewport.queue_free()
		return false
	var error := image.save_png(ProjectSettings.globalize_path(output_path))
	viewport.queue_free()
	if error != OK:
		push_error("Could not save "+output_path+": "+str(error))
		return false
	print("BAKED_PLAZA_SPRITE: "+output_path)
	return true
