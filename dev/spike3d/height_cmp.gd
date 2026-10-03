extends Node
## 개발용: 2D 건물 스프라이트와 3D 건물의 화면 높이(px)를 건물별로 비교해 출력한다.
func _ready() -> void:
	var scene = load("res://scenes/shop/main.tscn").instantiate()
	add_child(scene)
	for i in range(30): await get_tree().process_frame
	var settle = scene.get_node_or_null("VillageSettlement")
	if settle != null: settle.free()
	for g in ResidentStoryFlow.SETTINGS.managed_groups:
		var grp = scene.get_node_or_null(NodePath(g))
		if grp == null: continue
		for o in grp.get_children():
			if o is StaticBody2D and not bool(o.get_meta("settlement_layout_removed", false)):
				o.visible = true
				o.collision_layer = 1
	var view = scene.get_node("StoreView3D")
	var terrain = scene.get_node("StoreExterior")
	var player = scene.get_node("Actors/Player")
	view.mode = StoreView3D.Mode.OVERLAY
	var mz: float = view.match_zoom
	var rows: Array = []
	for cname in ["VillageBuildings", "NearbyHouses", "VillageExtraHouses", "VillageBlacksmith", "VillageToolShop"]:
		var grp = scene.get_node_or_null(cname)
		if grp == null: continue
		for body in grp.get_children():
			if not (body is StaticBody2D) or not body.visible: continue
			# 카메라를 건물 근처로 옮겨 3D 가 그 구역을 만들게 한다
			player.global_position = body.global_position + Vector2(0, 60)
			for i in range(20): await get_tree().process_frame
			var spr: Sprite2D = null
			for k in body.get_children():
				if k is Sprite2D: spr = k
			if spr == null or spr.texture == null:
				print("CMP skip(no sprite) ", body.name); continue
			var img: Image = spr.texture.get_image()
			var r: Rect2i = img.get_used_rect()  # 불투명 영역
			var scl: float = spr.scale.y
			var h2d: float = float(r.size.y) * scl * mz
			var key: String = "vil%d" % body.get_instance_id() + "a"
			if not view._items.has(key):
				print("CMP skip(no 3d) ", body.name, " items=", view._items.size()); continue
			var inst: MeshInstance3D = view._items[key]["mesh"]
			var ab: AABB = inst.global_transform * inst.get_aabb()
			var ys: Array = []
			for ix in [0, 1]:
				for iy in [0, 1]:
					for iz in [0, 1]:
						var p := ab.position + Vector3(ab.size.x * ix, ab.size.y * iy, ab.size.z * iz)
						ys.append(view._camera.unproject_position(p).y * float(view.shrink))
			var h3d: float = float(ys.max()) - float(ys.min())
			var w2d: float = float(r.size.x) * spr.scale.x * mz
			var xs: Array = []
			for ix in [0, 1]:
				for iy in [0, 1]:
					for iz in [0, 1]:
						var p := ab.position + Vector3(ab.size.x * ix, ab.size.y * iy, ab.size.z * iz)
						xs.append(view._camera.unproject_position(p).x * float(view.shrink))
			var w3d: float = float(xs.max()) - float(xs.min())
			rows.append("%s/%s  높이 2D=%d  3D=%d (%.2f배)  너비 2D=%d  3D=%d (%.2f배)" % [cname, body.name, h2d, h3d, h3d / h2d, w2d, w3d, w3d / w2d])
	for r in rows: print("CMP ", r)
	get_tree().quit()
