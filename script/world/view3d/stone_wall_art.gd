class_name StoneWallArt
extends RefCounted
## One selected 1-cell picture, repeated without scaling its individual stones.
static var _textures: Dictionary = {}

static func composed(path: String, count: int, axis_y: bool) -> Texture2D:
	var cache_key := "%s:%d:%s" % [path, count, axis_y]
	if _textures.has(cache_key): return _textures[cache_key]
	var source := ReceivedWorldArt.texture(path)
	if source == null: return null
	var image := source.get_image()
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var out := Image.create(image.get_width() + (count-1)*32,
		image.get_height() + (count-1)*16, false, Image.FORMAT_RGBA8)
	for index in count:
		out.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(index*32,index*16))
	if axis_y: out.flip_x()
	var texture := ImageTexture.create_from_image(out)
	_textures[cache_key] = texture
	return texture

static func render(view: StoreView3D, key: String, body: StaticBody2D,
		lo: Vector2, hi: Vector2, signature: String, row: Dictionary) -> Dictionary:
	var size := hi-lo
	var axis_y := size.y > size.x
	var length := maxf(size.x,size.y)
	var count := maxi(1,roundi(length))
	var texture := composed(str(row.path),count,axis_y)
	if texture == null: return {}
	# Existing canonical walls are 4 cells. Fractional layouts use one uniform factor.
	var uniform_scale := length/float(count)
	var anchor := Vector2(float(row.anchor[0])+(count-1)*16.0,
		float(row.anchor[1])+(count-1)*8.0)
	if axis_y: anchor.x = texture.get_width()-anchor.x
	var base := (lo+hi)*0.5
	ReceivedWorldArt.billboard(view,key,texture,anchor,lo,hi,base,signature,Color.WHITE,uniform_scale)
	var item: Dictionary = view._items[key]
	item["village_sprite_id"] = str(row.id)
	item["village_sprite_path"] = str(row.path)
	item["village_mirrored"] = VillageSpriteArt.sprite_of(body).scale.x < 0.0
	item["stone_wall_module_count"] = count
	item["stone_wall_axis_y"] = axis_y
	item["stone_wall_uniform_scale"] = uniform_scale
	var footprint := PackedVector2Array([lo,Vector2(hi.x,lo.y),hi,Vector2(lo.x,hi.y)])
	item["village_footprint"] = footprint
	# The editable-map collider and construction unlocks stay owned by VillageMirror.
	return {"rect":Rect2(lo,size),"footprint":footprint}
