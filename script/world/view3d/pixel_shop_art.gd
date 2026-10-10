class_name PixelShopArt
extends RefCounted
## 표시 전용. 실제 슬롯에서 상품을 합성하며 게임 좌표/충돌/저장값은 바꾸지 않는다.
const SHELL := "res://art/received/shop_shell/"
const STORAGE := "res://art/received/shop_storage/"
const DATA := "res://data/art/pixel_shop_frames.json"
static var _frames: Dictionary = {}
static var _goods: Dictionary = {}
static var _glyphs: Dictionary = {}
static var _data: Dictionary = {}

static func prepare() -> void:
	if not _data.is_empty(): return
	_data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	for f in _data.frames:
		_frames["%s:%d:%d" % [f.build_id, int(f.view), int(f.get("stack", 1))]] = f
	for item in _data.items: _goods[item.item_id] = STORAGE + item.glyph

static func frame(build_id: String, rotation: int, stack: int = 1) -> Dictionary:
	prepare()
	var v: int = int(_data.rotation_views[posmod(rotation, 4)])
	return _frames.get("%s:%d:%d" % [build_id, v, stack], {})

static func door_open(view: StoreView3D, build_id: String) -> bool:
	if build_id == "door":
		var day := view.world.get_node_or_null("DayManager")
		return day != null and bool(day.get("shop_open"))
	if view.player == null: return false
	if build_id == "production_door": return bool(view.player.get("in_production_room"))
	if build_id == "warehouse_door": return bool(view.player.get("in_warehouse_room"))
	return false

static func door_path(build_id: String, rotation: int, opened: bool) -> String:
	var kind := "entrance" if build_id == "door" else build_id.trim_suffix("_door")
	return SHELL + "%s_%d_%s.png" % [kind, posmod(rotation, 4), "open" if opened else "closed"]

static func glyph(item_id: String) -> Image:
	if _glyphs.has(item_id): return _glyphs[item_id]
	var tex := ReceivedWorldArt.texture(str(_goods.get(item_id, "")))
	if tex == null: return null
	var im := tex.get_image()
	if im.is_compressed(): im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	var cropped := im.get_region(im.get_used_rect())
	_glyphs[item_id] = cropped
	return cropped

static func compose(f: Dictionary, slots: Array, rack: bool = false) -> Image:
	var tex := ReceivedWorldArt.texture(STORAGE + str(f.body))
	if tex == null: return null
	var body := tex.get_image()
	if body.is_compressed(): body.decompress()
	body.convert(Image.FORMAT_RGBA8)
	var result := body.duplicate() as Image
	var limit: int = int(_data.warehouse_max_visible_goods if rack else _data.max_visible_goods)
	var anchors: Array = f.get("slot_anchors", [])
	for j in mini(slots.size(), anchors.size()):
		var slot: Dictionary = slots[j]
		var count := clampi(int(slot.get("amount" if rack else "stock", 0)), 0, limit)
		if count == 0: continue
		var icon := glyph(str(slot.get("item_id", "")))
		if icon == null: continue
		var a: Array = anchors[j]
		var budget := maxi(4, floori(float(a[2]) / count) - 1)
		var scale := minf(1.0, float(budget) / icon.get_width())
		var good := icon.duplicate() as Image
		good.resize(maxi(1, roundi(icon.get_width() * scale)), maxi(1, roundi(icon.get_height() * scale)), Image.INTERPOLATE_NEAREST)
		for n in count:
			var x := float(a[0]) + (n - (count - 1) * 0.5) * minf(budget + 1, float(a[2]) / count)
			var y := float(a[1]) + (x - float(a[0])) * (0.5 if int(f.view) == 0 else -0.5)
			var pos := Vector2i(roundi(x - good.get_width() * 0.5), roundi(y - good.get_height()))
			var placed := good.duplicate() as Image
			# 닫힌 몸체 바깥으로 상품이 튀어나오지 않도록 알파를 동일하게 제한한다.
			if not rack:
				for gx in good.get_width():
					for gy in good.get_height():
						var at := pos + Vector2i(gx, gy)
						if not Rect2i(Vector2i.ZERO, body.get_size()).has_point(at) or body.get_pixelv(at).a == 0:
							placed.set_pixel(gx, gy, Color.TRANSPARENT)
			result.blend_rect(placed, Rect2i(Vector2i.ZERO, good.get_size()), pos)
	return result

static func furniture(view: StoreView3D, key: String, node: Node, build_id: String,
		rotation: int, lo: Vector2, hi: Vector2, base: Vector2, signature: String,
		preview: bool, valid: bool) -> bool:
	var tint := Color.WHITE
	if preview: tint = tint.lerp(Color(0.55, 1.0, 0.9) if valid else Color(1.0, 0.25, 0.25), 0.4 if valid else 0.65)
	if build_id in ["door", "production_door", "warehouse_door"]:
		var path := door_path(build_id, rotation, not preview and door_open(view, build_id))
		var tex := ReceivedWorldArt.texture(path)
		if tex == null: return false
		ReceivedWorldArt.billboard(view, key, tex, Vector2(32,104), lo, hi, base, signature, tint)
		return true
	var stack := 1
	if node.get("stack_level") != null: stack = int(node.get("stack_level"))
	if preview: stack = int(node.get_meta("preview_stack", 1))
	var f := frame(build_id, rotation, stack)
	if f.is_empty(): return false
	var rack := build_id.ends_with("warehouse_rack")
	var slots: Array = []
	if not preview: slots = node.get("storage_slots" if rack else "slots")
	var image := compose(f, slots, rack)
	if image == null: return false
	var tex := ImageTexture.create_from_image(image)
	ReceivedWorldArt.billboard(view, key, tex, Vector2(f.anchor[0],f.anchor[1]), lo, hi, base, signature, tint)
	view._items[key]["received_art"] = STORAGE + str(f.body)
	view._items[key]["pixel_stock"] = slots.duplicate(true)
	return true

static func wall_run(view: StoreView3D, key: String, lo: Vector2, hi: Vector2,
		direction: int, tall: bool, cutaway: bool) -> bool:
	var along_x := direction == 0 or direction == 2
	var length := hi.x - lo.x if along_x else hi.y - lo.y
	# 한 칸의 중앙 면만 반복한다. 끝기둥이 매 칸 중복되는 것을 방지한다.
	var tex := ReceivedWorldArt.texture(SHELL + "%s_%d_tile.png" % ["wall_full" if tall else "window", direction])
	if tex == null: return false
	var count := maxi(1, roundi(length))
	for i in count:
		var a := lo
		var b := hi
		if along_x:
			a.x = lo.x + i * length / count
			b.x = lo.x + (i + 1) * length / count
		else:
			a.y = lo.y + i * length / count
			b.y = lo.y + (i + 1) * length / count
		var panel_key := key + "_" + str(i)
		var base := (a + b) * 0.5
		# 이미지 면은 바닥 경계에 놓는다. 3D 벽 두께의 중심에 놓으면 모서리에 틈이 생긴다.
		if along_x: base.y = hi.y if direction == 0 else lo.y
		else: base.x = hi.x if direction == 3 else lo.x
		ReceivedWorldArt.billboard(view, panel_key, tex, Vector2(32,104), a, b, base, "pixel_wall")
		if cutaway:
			view._items[panel_key]["cutaway"] = {"rect": Rect2(a,b-a), "h": 0.0, "factor":1.0, "base_origin":true}
	return true
