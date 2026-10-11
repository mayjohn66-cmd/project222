class_name FishingTileArt
extends RefCounted
## Tiles share the ground shader, generated normals and the world's day lighting.
static func path(tile: String) -> String:
	return "res://art/received/floors/" + tile + ".png" if tile.begins_with("wood_") else "res://art/received/fishing/" + tile + ".png"
static func install(view: Node, key: String, cells: Array, tile: String) -> void:
	var texture := ReceivedWorldArt.texture(path(tile))
	if texture == null: return
	var material := ShaderMaterial.new()
	material.shader = ReceivedWorldArt.FLOOR_SHADER
	for i in range(1, 4):
		material.set_shader_parameter("tile_%d" % i, texture)
		material.set_shader_parameter("normal_%d" % i, SpriteNormalMaps.texture(texture))
	material.set_shader_parameter("normal_strength", 0.3 if tile.begins_with("water") else 0.55)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell: Vector2i in cells:
		for offset in [Vector2(-0.5,-0.5),Vector2(0.5,-0.5),Vector2(0.5,0.5),Vector2(-0.5,-0.5),Vector2(0.5,0.5),Vector2(-0.5,0.5)]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(cell.x+offset.x, 0.02, cell.y+offset.y))
	view._set_mesh_item(key, surface.commit(), [material], Vector2.ZERO, Vector2.ONE, 0.0, "fishing_tiles", -0.4, false)
