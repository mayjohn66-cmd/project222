class_name OpeningCityArt
extends RefCounted
## 현대 도시 그림을 기존 바닥 좌표와 깊이 정렬에 연결한다.
const DATA := "res://data/art/opening_city_assets.json"
const BUILDINGS := ["small_shop","apartment","office","cafe"]
const VEHICLES := ["sedan","taxi","truck"]
const GROUND_SHADER := preload("res://script/world/shop/tutorial/opening_city_floor.gdshader")
static var _rows: Dictionary = {}
static var _loaded := false

static func rows() -> Dictionary:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(DATA):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
			if parsed is Dictionary:
				for value in parsed.get("assets",[]): _rows[str(value.id)] = value
	return _rows

static func texture(id: String, mirrored: bool = false) -> Texture2D:
	var row: Dictionary = rows().get(id,{})
	return null if row.is_empty() else VillageSpriteArt.texture_for(str(row.path),mirrored)

static func vehicle_id(index: int, axis: String, speed: float) -> String:
	var direction := ("south_east" if speed >= 0 else "north_west") if axis == "x" else ("south_west" if speed >= 0 else "north_east")
	return VEHICLES[posmod(index,VEHICLES.size())]+"_"+direction

static func draw(view: StoreView3D, key: String, id: String, lo: Vector2, hi: Vector2,
		mirrored: bool = false, height_blocks: float = 0.0) -> bool:
	var row: Dictionary = rows().get(id,{})
	var tex := texture(id,mirrored)
	if row.is_empty() or tex == null: return false
	var anchor := Vector2(float(row.anchor[0]),float(row.anchor[1]))
	if mirrored: anchor.x = tex.get_width()-anchor.x
	var above := maxf(anchor.y-float(tex.get_image().get_used_rect().position.y),1.0)
	var factor := ((hi.x-lo.x)+(hi.y-lo.y))*32.0 / float(row.footprint_width)
	if height_blocks > 0.0:
		var fit_height := height_blocks*view.block_px/above
		factor = fit_height if id in ["streetlamp","traffic_signal","bus_stop"] else minf(factor,fit_height)
	ReceivedWorldArt.billboard(view,key,tex,anchor,lo,hi,(lo+hi)*0.5,"city:"+id,Color.WHITE,factor)
	view._items[key]["city_sprite_id"] = id
	view._items[key]["city_sprite_path"] = str(row.path)
	view._items[key]["city_sprite_scale"] = factor
	return true

static func lamp_light(view: StoreView3D, key: String) -> void:
	var light := OmniLight3D.new()
	light.name = "CityStreetLight"
	light.light_color = Color(1.0,0.87,0.66)
	light.light_energy = 0.6
	light.omni_range = 4.0
	light.position = Vector3(-0.2,view.block_height(3.4),0.05)
	(view._items[key].mesh as Node3D).add_child(light)

static func ground(view: StoreView3D, key: String, lo: Vector2, hi: Vector2, kind: String) -> bool:
	var material := ReceivedWorldArt.floor_material(kind)
	if material == null: return false
	material.shader = GROUND_SHADER
	# 셰이더 교체는 기존 매개변수를 초기화하므로 동일 이름도 다시 연결한다.
	for index in range(1,4):
		var tex := ReceivedWorldArt.texture("res://art/received/floors/%s_%d.png" % [kind,index])
		material.set_shader_parameter("tile_%d" % index,tex)
		material.set_shader_parameter("normal_%d" % index,SpriteNormalMaps.texture(tex))
	material.set_shader_parameter("asphalt",kind == "road")
	var mesh := PlaneMesh.new()
	mesh.size = hi-lo
	view._set_mesh_item(key,mesh,[material],lo,hi,0.06,"city-ground:"+kind,-0.7 if kind == "road" else -0.85,false)
	for node in [view._items[key].mesh,view._items[key].id_mesh]:
		node.position = Vector3((lo.x+hi.x)*0.5,0.025,(lo.y+hi.y)*0.5)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view._items[key]["city_ground_kind"] = kind
	return true
