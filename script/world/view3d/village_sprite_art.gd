class_name VillageSpriteArt
extends RefCounted
## 기존 마을 원본을 정리한 정지 그림. 그림의 바닥 다각형을 충돌·정렬 기준으로 공유한다.
const DATA_PATH := "res://data/art/village_sprite_assets.json"
static var _rows: Dictionary = {}
static var _loaded := false
static var _mirrors: Dictionary = {}

static func row_for(path: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			for row in parsed.get("assets", []):
				for alias in row.aliases: _rows[str(alias)] = row
	return _rows.get(path, {})

static func sprite_of(body: StaticBody2D) -> VillageArt:
	if body == null: return null
	for child in body.get_children():
		if child is VillageArt: return child as VillageArt
	return null

static func render(view: StoreView3D, key: String, body: StaticBody2D,
		lo: Vector2, hi: Vector2, signature: String) -> Dictionary:
	if not ReceivedWorldArt.ENABLED: return {}
	var art := sprite_of(body)
	if art == null: return {}
	var row := row_for(art.art_path)
	if row.is_empty(): return {}
	var path := str(row.path)
	var roof_colour := str(art.get_meta("roof_color", ""))
	if row.get("roof_variants", {}).has(roof_colour):
		path = str(row.roof_variants[roof_colour].path)
	var tex := ReceivedWorldArt.texture(path)
	if tex == null: return {}
	var anchor := Vector2(float(row.anchor[0]),float(row.anchor[1]))
	var points := PackedVector2Array()
	var left := INF
	var right := -INF
	for point in row.footprint:
		var p := Vector2(float(point[0]),float(point[1]))
		points.append(p)
		left = minf(left,p.x)
		right = maxf(right,p.x)
	var mirrored := art.scale.x < 0.0
	if mirrored:
		if not _mirrors.has(path):
			var image := tex.get_image()
			if image.is_compressed(): image.decompress()
			image.flip_x()
			_mirrors[path] = ImageTexture.create_from_image(image)
		tex = _mirrors[path]
		anchor.x = tex.get_width() - anchor.x
		for i in points.size(): points[i].x = tex.get_width() - points[i].x
	# 64×32 등각 칸의 화면 폭에 맞춘 균일 배율. 원본의 종횡비를 바꾸지 않는다.
	var scale_factor := ((hi.x-lo.x)+(hi.y-lo.y)) * 32.0 / maxf(right-left,1.0)
	var base := (lo+hi)*0.5
	var footprint := PackedVector2Array()
	for p in points:
		var delta: Vector2 = (p-anchor)*scale_factor
		footprint.append(base + Vector2(delta.x/64.0+delta.y/32.0, -delta.x/64.0+delta.y/32.0))
	var rect := Rect2(footprint[0],Vector2.ZERO)
	for p in footprint: rect = rect.expand(p)
	ReceivedWorldArt.billboard(view,key,tex,anchor,rect.position,rect.end,base,signature,Color.WHITE,scale_factor,str(row.path) if not mirrored else "")
	var item: Dictionary = view._items[key]
	item["village_sprite_id"] = str(row.id)
	item["village_sprite_path"] = path
	item["village_footprint"] = footprint
	item["village_mirrored"] = mirrored
	# 지붕의 돌출은 보행을 막지 않는다. 빛과 마스크는 동일한 그림을 사용한다.
	if view.sync_collision:
		var collider := body.get_node_or_null(VillageMirror.COLLISION_3D) as CollisionPolygon2D
		if collider != null:
			var polygon := PackedVector2Array()
			for p in footprint:
				polygon.append(body.to_local(view.cell_to_world(base+(p-base)*0.97)))
			collider.polygon = polygon
	return {"rect":rect,"footprint":footprint}
