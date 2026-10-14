class_name WallTopArt
extends RefCounted
## 벽 전체 길이에 원본 몰딩 색을 쓰는 윗면을 연결한다. 바닥/충돌/PNG는 바꾸지 않는다.
# 원본 테두리 두 줄을 윗면으로 대체하고 1px 겹쳐 래스터 틈을 막는다.
const TOP_PIXELS := 57.0

static func attach_face(view: StoreView3D, key: String, direction: int) -> void:
	for material in [view._items[key].material,view._items[key].id_material]:
		material.set_shader_parameter("wall_top_attached",true)
		material.set_shader_parameter("wall_top_profile_sign",1.0 if direction in [0,2] else -1.0)

static func strip(view: StoreView3D, key: String, source: Texture2D, lo: Vector2, hi: Vector2,
		base: Vector2, direction: int, cutaway: bool) -> void:
	var sign_x := 1.0 if direction in [0,2] else -1.0
	var outward := [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT][direction] as Vector2
	var delta := _project(outward * StoreView3D.WALL_THICKNESS)
	var start := Vector2(-16,-TOP_PIXELS-sign_x*8)
	_make(view, key, source, lo, hi, base, start, Vector2(32,sign_x*16), delta, sign_x, false, cutaway)

static func _project(cell: Vector2) -> Vector2:
	return Vector2((cell.x-cell.y)*32,(cell.x+cell.y)*16)

static func corners(view: StoreView3D, prefix: String, runs: Array) -> void:
	var made: Dictionary = {}
	for wall in runs:
		if not bool(wall.tall): continue
		for corner in WallJunctionArt.endpoints(wall):
			for other in runs:
				if not bool(other.tall) or bool(other.along_x) == bool(wall.along_x): continue
				var ends := WallJunctionArt.endpoints(other)
				if not corner.is_equal_approx(ends[0]) and not corner.is_equal_approx(ends[1]): continue
				var tag := "%0.3f:%0.3f" % [corner.x,corner.y]
				if made.has(tag): continue
				made[tag] = true
				var a := [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT][int(wall.direction)] as Vector2
				var b := [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT][int(other.direction)] as Vector2
				var outer_a: Vector2 = corner+a*StoreView3D.WALL_THICKNESS
				var outer_b: Vector2 = corner+b*StoreView3D.WALL_THICKNESS
				var lo: Vector2 = corner.min(outer_a).min(outer_b).min(outer_a+outer_b-corner)
				var hi: Vector2 = corner.max(outer_a).max(outer_b).max(outer_a+outer_b-corner)
				var source := ReceivedWorldArt.texture(PixelShopArt.SHELL+"wall_full_%d_tile.png" % int(wall.direction))
				_make(view, prefix+str(made.size()), source, lo, hi, corner, Vector2(0,-TOP_PIXELS),
					_project(a*StoreView3D.WALL_THICKNESS),_project(b*StoreView3D.WALL_THICKNESS),
					1.0 if int(wall.direction) in [0,2] else -1.0, true, int(wall.direction) in [1,2] or int(other.direction) in [1,2])

static func _make(view: StoreView3D, key: String, source: Texture2D, lo: Vector2, hi: Vector2,
		base: Vector2, start: Vector2, along: Vector2, outward: Vector2, sign_x: float, corner: bool, cutaway: bool) -> void:
	if source == null: return
	var mn := start.min(start+along).min(start+outward).min(start+along+outward)
	var mx := start.max(start+along).max(start+outward).max(start+along+outward)
	var size := mx-mn
	ReceivedWorldArt.billboard(view,key,source,Vector2(32,104),lo,hi,base,"pixel_wall_top")
	var item: Dictionary = view._items[key]
	var quad: QuadMesh = item.mesh.mesh
	var unit := sqrt(2.0)/ReceivedWorldArt.TILE_WIDTH
	quad.size = size*unit
	var offset := (mn+size*0.5)*Vector2(unit,-unit)
	for material in [item.material,item.id_material]:
		material.set_shader_parameter("frame_offset",offset)
		material.set_shader_parameter("wall_top_enabled",true)
		material.set_shader_parameter("wall_top_corner",corner)
		material.set_shader_parameter("wall_top_bounds",Vector4(mn.x,mn.y,size.x,size.y))
		material.set_shader_parameter("wall_top_start",start)
		material.set_shader_parameter("wall_top_along",along)
		material.set_shader_parameter("wall_top_outward",outward)
		material.set_shader_parameter("wall_top_profile_sign",sign_x)
	item.material.set_shader_parameter("normal_base",Vector3.UP)
	item.material.set_shader_parameter("normal_strength",0.15)
	item["wall_top"] = true
	item["min"].z = TOP_PIXELS
	item["max"].z = TOP_PIXELS
	if cutaway: item["cutaway"] = {"rect":Rect2(lo,hi-lo),"h":0.0,"factor":1.0,"base_origin":true}
