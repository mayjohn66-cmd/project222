class_name PixelShopArt
extends RefCounted
## 표시 전용. 빈/물품이 놓인 고정 그림만 사용하며 물품 종류·수량별 합성은 하지 않는다.
const SHELL := "res://art/received/shop_shell/"
const STORAGE := "res://art/received/shop_storage/"
const DATA := "res://data/art/pixel_shop_frames.json"
static var _frames: Dictionary = {}
static var _data: Dictionary = {}

static func prepare() -> void:
	if not _data.is_empty(): return
	_data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	for f in _data.frames:
		_frames["%s:%d:%d" % [f.build_id, int(f.view), int(f.get("stack", 1))]] = f

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

static func storage_path(f: Dictionary, rotation: int, stocked: bool) -> String:
	if stocked: return STORAGE + "stocked/" + str(f.body).get_file()
	if str(f.build_id) in ["warehouse_rack","steel_warehouse_rack"]:
		return ReceivedWorldArt.furniture_path(str(f.build_id),rotation)
	return STORAGE + str(f.body)


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
	if ContainerStockArt.COLD_UNITS.has(build_id):
		var stocked := ContainerStockArt.filled(node,build_id,preview)
		var pair := ContainerStockArt.cold_pair(build_id,rotation)
		var path: String = pair.filled if stocked else pair.empty
		var tex := ReceivedWorldArt.texture(path)
		if tex == null: return false
		ReceivedWorldArt.billboard(view,key,tex,Vector2(tex.get_width()*0.5,tex.get_height()-24.0),lo,hi,base,signature,tint)
		view._items[key]["stocked"] = stocked
		view._items[key]["stock_art_ready"] = pair.ready
		return true
	var stack := 1
	if node.get("stack_level") != null: stack = int(node.get("stack_level"))
	if preview: stack = int(node.get_meta("preview_stack", 1))
	var f := frame(build_id, rotation, stack)
	if f.is_empty(): return false
	var stocked := ContainerStockArt.filled(node,build_id,preview)
	var path := storage_path(f,rotation,stocked)
	var tex := ReceivedWorldArt.texture(path)
	if tex == null: return false
	ReceivedWorldArt.billboard(view, key, tex, Vector2(f.anchor[0],f.anchor[1]), lo, hi, base, signature, tint)
	view._items[key]["stocked"] = stocked
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
		view._items[panel_key].material.set_shader_parameter("normal_base",Vector3(0,0,1) if along_x else Vector3(1,0,0))
		if cutaway:
			view._items[panel_key]["cutaway"] = {"rect": Rect2(a,b-a), "h": 0.0, "factor":1.0, "base_origin":true}
	return true
