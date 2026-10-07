extends "res://dev/spike3d/art_request_export.gd"
## 실제 그림(art/world3d)을 적용한 3D 미리보기와 임시 질감 미리보기를 나란히 저장한다(그림 넣은 뒤 눈으로 확인용).
## 인자: --only <자산id> --out <폴더>  →  <폴더>/<id>__before.png, <id>__after.png


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = ProjectSettings.globalize_path("res://screenshots")
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size(): out_dir = args[i + 1]
		if args[i] == "--only" and i + 1 < args.size(): only_id = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rules: Array = VillageMirror.load_rules()
	for a in _read_assets():
		if only_id != "" and str(a["id"]) != only_id: continue
		var rule: Dictionary = VillageMirror.find_rule(rules, str(a["sprite"]).to_lower())
		if rule.is_empty(): continue
		var cw: float = float(rule.get("canon_w", 2.0))
		var cd: float = float(rule.get("canon_d", 2.0))
		var lo := Vector2(-cw * 0.5, -cd * 0.5)
		var hi := Vector2(cw * 0.5, cd * 0.5)
		for use_art in [false, true]:
			var p: Dictionary = VillageAssets.default_params(18, 22.0, TILE_LOW, use_art)
			var built: Dictionary = VillageAssets.build_gable(lo, hi, rule, p) if str(rule["kind"]) == "gable" else VillageAssets.build_prop(str(rule.get("style", "")), lo, hi, rule, p)
			await _render_preview("%s/%s__%s.png" % [out_dir, a["id"], "after" if use_art else "before"], built, p, PREVIEW_BUILDING if str(a["kind_group"]) == "building" else PREVIEW_PROP)
	print("done")
	get_tree().quit()
