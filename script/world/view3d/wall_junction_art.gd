class_name WallJunctionArt
extends RefCounted
## 높은 벽과 낮은 창문 벽의 접점에만 원래 벽 타일의 좁은 끝단 면을 붙인다.
## 원본 PNG·기울기·픽셀 배율을 유지하며 색/법선/ID 마스크는 같은 영역을 참조한다.
const TILE_FACE_WIDTH := 32
const TILE_FACE_LEFT := 16
const TILE_FACE_RIGHT := 48

static func endpoints(run: Dictionary) -> Array[Vector2]:
	if bool(run.along_x):
		return [Vector2(run.lo, run.line), Vector2(run.hi, run.line)]
	return [Vector2(run.line, run.lo), Vector2(run.line, run.hi)]

static func sync(view: StoreView3D, runs: Array) -> void:
	for index in runs.size():
		var wall: Dictionary = runs[index]
		if not bool(wall.tall): continue
		for end_index in 2:
			var corner := endpoints(wall)[end_index]
			for other in runs:
				if bool(other.tall) or bool(other.along_x) == bool(wall.along_x): continue
				var ends := endpoints(other)
				if not corner.is_equal_approx(ends[0]) and not corner.is_equal_approx(ends[1]): continue
				_draw(view, "wall_endcap_%d_%d" % [index, end_index], corner, int(wall.direction), int(other.direction))
				break

static func _draw(view: StoreView3D, key: String, corner: Vector2, wall_direction: int, face_direction: int) -> void:
	var source := ReceivedWorldArt.texture(PixelShopArt.SHELL + "wall_full_%d_tile.png" % face_direction)
	if source == null: return
	var outward := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT][wall_direction] as Vector2
	var width := maxi(1, roundi(StoreView3D.WALL_THICKNESS * TILE_FACE_WIDTH))
	var region_x := TILE_FACE_LEFT if outward.x - outward.y > 0.0 else TILE_FACE_RIGHT - width
	var crop := Rect2i(region_x, 0, width, source.get_height())
	var outer := corner + outward * StoreView3D.WALL_THICKNESS
	var lo := corner.min(outer)
	var hi := corner.max(outer)
	# 원래 한 장의 기준점을 유지하고 두께에 해당하는 끝단 픽셀만 참조한다. 면을 늘리지 않는다.
	var base := corner + outward * 0.5
	ReceivedWorldArt.billboard(view, key, source, Vector2(32,104), lo, hi, base,
		"pixel_wall_endcap", Color.WHITE, 1.0, "", crop)
	var item: Dictionary = view._items[key]
	item["wall_endcap"] = true
	WallTopArt.attach_face(view,key,face_direction)
	item.material.set_shader_parameter("normal_base", Vector3(0,0,1) if face_direction in [0,2] else Vector3(1,0,0))
	if face_direction in [1,2]:
		item["cutaway"] = {"rect": Rect2(lo,hi-lo), "h": 0.0, "factor": 1.0, "base_origin": true}
