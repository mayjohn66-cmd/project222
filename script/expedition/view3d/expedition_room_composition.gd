class_name ExpeditionRoomComposition
extends RefCounted
## 주변은 배경 그림, 가까운 장식은 정해 둔 작은 무리만 배치한다.
const DATA := "res://data/art/expedition_scene_compositions.json"
static var _profiles: Dictionary = {}

static func profile(region: String) -> Dictionary:
	if _profiles.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if data is Dictionary: _profiles = data.get("profiles", {})
	return _profiles.get(region, _profiles.get("forest", {}))

static func build(scenery: ExpeditionScenery, model: RefCounted, rng: RandomNumberGenerator) -> void:
	var stage := scenery.st
	var chosen := profile(str(stage.view.region_id))
	for entry in chosen.get("outside", []):
		var key := str(entry.key)
		scenery._cache[key] = ExpeditionEnvironmentArt.template(key)
		var node := ExpeditionEnvironmentArt.create(stage,key,Vector2(float(entry.x),float(entry.y)),float(entry.scale),float(entry.get("yaw",0)))
		if node != null: node.set_meta("composition_group", "outside")
	var placed := 0
	var avoid := scenery._keepout(model)
	for entry in chosen.get("floor", []):
		if placed >= int(chosen.get("floor_limit", 3)): break
		var at := Vector2(float(entry.x),float(entry.y))
		var blocked := false
		for area in avoid:
			if (area as Rect2).has_point(at): blocked = true; break
		if blocked: continue
		var key := str(entry.key)
		scenery._cache[key] = ExpeditionEnvironmentArt.template(key)
		var node := ExpeditionEnvironmentArt.create(stage,key,at,float(entry.scale))
		if node != null:
			node.set_meta("composition_group", "floor")
			placed += 1
	for point in chosen.get("puddles", []):
		ExpeditionEnvironmentArt.puddle(stage,Vector2(float(point.x),float(point.y)),float(point.radius))
	match stage._theme_id:
		"mine": scenery._exit_mine()
		"swamp": scenery._exit_swamp()
		"hidden_ruins": scenery._exit_ruins()
		_:
			scenery._forest_path(rng)
			scenery._exit_forest()
