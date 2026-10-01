class_name VillageSettlement
extends Node

var elapsed := 0.0

func _ready() -> void:
	apply_world(get_parent())

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.25: return
	elapsed = 0.0
	apply_world(get_parent())

static func apply_world(world: Node) -> void:
	if Engine.is_editor_hint(): return
	var editor := world.get_node_or_null("VillageMapEditor")
	var editing: bool = editor != null and editor.active
	var open_sites: Dictionary = {}
	for path in CommunityRequestFlow.unlocked_paths():
		var site := find_site(world, path)
		if site != null: open_sites[site.get_instance_id()] = true
	for landmark in ResidentStoryFlow.SETTINGS.landmarks:
		if not ResidentRequestFlow.done(str(landmark["request"])): continue
		var paths: Array = [str(landmark["path"])]
		paths.append_array(landmark.get("additional_paths", []))
		for path in paths:
			var site := find_site(world, str(path))
			if site != null: open_sites[site.get_instance_id()] = true
	for group_name in ResidentStoryFlow.SETTINGS.managed_groups:
		var group := world.get_node_or_null(NodePath(group_name))
		if group == null: continue
		for object in group.get_children():
			if not object is StaticBody2D: continue
			var path := str(object.get_meta("settlement_source", group_name + "/" + str(object.name)))
			var unlocked := false
			# 황무지의 자연물은 남기고, 사람이 만든 시설은 정착 이야기로 연다.
			if path.begins_with("VillageDecor/OrchardTree") or path == "VillageGathering/FlowerBed": unlocked = true
			if open_sites.has(object.get_instance_id()): unlocked = true
			if not object.has_meta("settlement_original_visible"):
				object.set_meta("settlement_original_visible", object.visible)
				object.set_meta("settlement_original_layer", object.collision_layer)
			object.visible = (unlocked or editing) and bool(object.get_meta("settlement_original_visible")) and not bool(object.get_meta("settlement_layout_removed", false))
			object.collision_layer = int(object.get_meta("settlement_original_layer")) if object.visible else 0

# 편집된 맵에서는 제거된 원본 대신 같은 이미지의 배치 중 가장 가까운 한 곳을 연다.
# 복제된 집을 모두 한꺼번에 열거나 사용자가 지운 건물을 복구하지 않는다.
static func find_site(world: Node, source_path: String) -> StaticBody2D:
	var group := world.get_node_or_null(NodePath(source_path.get_slice("/",0)))
	if group == null: return null
	var original := world.get_node_or_null(NodePath(source_path)) as StaticBody2D
	if original != null and not bool(original.get_meta("settlement_layout_removed", false)): return original
	var floor_node := world.get_node_or_null("Floor") as Node2D
	var origin := floor_node.global_position if floor_node != null else Vector2.ZERO
	var best: StaticBody2D = null
	var best_distance := INF
	for object in group.get_children():
		if not object is StaticBody2D or bool(object.get_meta("settlement_layout_removed", false)): continue
		if str(object.get_meta("settlement_source", "")) != source_path: continue
		var distance: float = object.global_position.distance_squared_to(origin)
		if distance < best_distance:
			best_distance = distance
			best = object
	return best
