class_name FurnitureVariantAssets
extends RefCounted
## 가구 카탈로그의 새 집기를 실제 매장에 표현한다. 기존 가구 모델은 그대로 사용한다.

static func has_model(id: String) -> bool:
	var row := FurnitureObjectCatalog.get_object(id)
	return not row.is_empty() and str(row["family"]) != "shelf"

static func build(id: String, lo: Vector2, hi: Vector2, rotation: int, p: Dictionary, extra: Dictionary) -> Dictionary:
	var row := FurnitureObjectCatalog.get_object(id)
	var params := p.duplicate()
	params["furniture_stage"] = row["stage"]
	var f := FurnitureAssets.Frame.new(lo, hi, rotation, params)
	if row["family"] == "warehouse_storage": return FurnitureAssets._rack(f, extra)
	var modern: bool = row["stage"] == "modern"
	var body: Dictionary = f.flat(Color(0.84, 0.88, 0.9), "variant_counter_metal") if modern else f.wood(Color(0.65, 0.43, 0.25), "variant_counter_wood")
	var top: Dictionary = f.flat(Color(0.18, 0.21, 0.24), "variant_counter_top") if modern else f.wood(Color(0.87, 0.67, 0.41), "variant_counter_plank")
	var dark := f.flat(Color(0.13, 0.17, 0.18), "variant_counter_detail")
	f.box(body, 0.03, f.length - 0.03, 0.03, f.depth - 0.03, 0.05, 0.77)
	f.box(top, 0.0, f.length, 0.0, f.depth, 0.77, 0.84)
	if modern:
		var screen := f.flat(Color(0.25, 0.85, 0.68), "variant_counter_screen", 0.4)
		f.box(dark, f.length * 0.6, f.length * 0.9, f.depth * 0.35, f.depth * 0.7, 0.84, 0.9)
		f.box(dark, f.length * 0.72, f.length * 0.8, f.depth * 0.25, f.depth * 0.35, 0.9, 1.12)
		f.box(screen, f.length * 0.62, f.length * 0.9, f.depth * 0.2, f.depth * 0.27, 0.97, 1.1)
		var trim := f.flat(Color(0.32, 0.65, 0.48), "variant_counter_stripe")
		f.box(trim, 0.03, f.length - 0.03, f.depth - 0.045, f.depth - 0.025, 0.5, 0.6)
	else:
		f.box(dark, f.length * 0.65, f.length * 0.92, f.depth * 0.3, f.depth * 0.85, 0.84, 0.93)
		var coin := f.flat(Color(0.91, 0.73, 0.31), "variant_counter_coin")
		f.cyl(coin, f.length * 0.79, f.depth * 0.57, 0.055, 0.93, 0.95)
	return f.finish(1.12 if modern else 0.95)

static func shelf_materials(p: Dictionary) -> Array:
	var stage := str(p.get("furniture_stage", ""))
	if stage == "modern":
		return [VillageAssets._flat_spec(int(p["ts"]), Color(0.65, 0.71, 0.76), "shelf_metal_frame"), VillageAssets._flat_spec(int(p["ts"]), Color(0.8, 0.83, 0.86), "shelf_metal_back"), VillageAssets._flat_spec(int(p["ts"]), Color(0.95, 0.95, 0.91), "shelf_white_board")]
	return [VillageAssets.wood(p, Color(0.78, 0.56, 0.34), "shelf_frame"), VillageAssets.wood(p, Color(0.52, 0.36, 0.24), "shelf_back"), VillageAssets.wood(p, Color(0.9, 0.7, 0.44), "shelf_board")]
