extends "res://tools/check_expedition_run.gd"
# Extra complete runs cover the optional wheat and required water region choices.
func _ready() -> void:
	if not OS.get_user_data_dir().contains("foodbag_checks"):
		push_error("Run only in isolated foodbag_checks project")
		get_tree().quit(1)
		return
	seed(53241)
	for region in ["meadow","river_valley"]:
		for n in range(2): await _run_once(region,1)
	print("CHECK_EXPEDITION_PROGRESSION_RUNS ",report)
	var ok: bool = int(report["clears"]) == 4 and int(report["boss_had_starter"]) == 4 and int(report["starter_before_boss"]) == 0 and int(report["stuck"]) == 0
	get_tree().quit(0 if ok else 1)
