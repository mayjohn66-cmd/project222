class_name OpeningWindowCityArt
extends RefCounted
## 눈높이 원경과 실제로 움직이는 옆면 차량을 창밖 전용 세계에 표시한다.

static func quad(parent: Node3D, id: String, width: float, side: bool = false) -> MeshInstance3D:
	var tex := OpeningCityArt.texture(id)
	if tex == null: return null
	var row: Dictionary = OpeningCityArt.rows()[id]
	var mesh := QuadMesh.new()
	var unit := width/float(tex.get_width())
	mesh.size = Vector2(tex.get_size())*unit
	var material := StandardMaterial3D.new()
	material.albedo_texture = tex
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if str(row.group) != "background":
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5
		material.normal_enabled = true
		material.normal_texture = SpriteNormalMaps.texture(tex)
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	else: material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.set_meta("city_sprite_id",id)
	if side: node.position.y = (float(row.anchor[1])-tex.get_height()*0.5)*unit
	parent.add_child(node)
	return node

static func background(root: Node3D) -> bool:
	var node := quad(root,"window_street",34.0)
	if node == null: return false
	node.name = "CityFacadeBackdrop"
	node.position = Vector3(0,(node.mesh as QuadMesh).size.y*0.5+0.04,-10.0)
	return true

static func style_car(pov: OpeningWindowPov, car: Dictionary, first: bool, spread: float) -> bool:
	if OpeningCityArt.texture("sedan_side_right") == null: return false
	var node: Node3D = car.node
	var lane := int(car.lane)
	var direction := 1.0 if lane == 0 else -1.0
	var roll := pov._rng.randf()
	var kind := "sedan" if roll < 0.4 else "taxi" if roll < 0.7 else "truck"
	var id := kind+"_side_right" if direction>0 else kind+"_side_left"
	quad(node,id,5.0 if kind=="truck" else 4.4,true)
	car["speed"] = direction*pov._rng.randf_range(3.2,6.2)
	node.position = Vector3(-direction*(OpeningWindowPov.WRAP_X+3.0)+direction*(spread*5.0 if first else 0.0),0,OpeningWindowPov.LANE_Z[lane])
	return true
