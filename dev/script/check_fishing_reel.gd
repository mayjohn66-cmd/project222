extends Node
## 낚시 당기기(입질 타이밍 + 당기기 미니게임) 규칙 검사. 화면 없이 `FishingReel` 규칙과 희귀도별 값, 데이터 연결을 확인한다.
var checks := 0
var failures := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	var table: Dictionary = FishingData.data()["settings"]["reel"]
	check(table.has("common") and table.has("seasonal") and table.has("rare"), "희귀도 세 단계의 당기기 값이 데이터에 있음")
	# 희귀할수록 어렵다: 챔질 시간·구역이 줄고 물고기는 빨라진다.
	check(float(table["common"]["bite_window"]) > float(table["seasonal"]["bite_window"]) and float(table["seasonal"]["bite_window"]) > float(table["rare"]["bite_window"]), "희귀할수록 챔질 시간이 짧음")
	check(float(table["common"]["zone_size"]) > float(table["seasonal"]["zone_size"]) and float(table["seasonal"]["zone_size"]) > float(table["rare"]["zone_size"]), "희귀할수록 구역이 좁음")
	check(float(table["common"]["fish_speed"]) < float(table["seasonal"]["fish_speed"]) and float(table["seasonal"]["fish_speed"]) < float(table["rare"]["fish_speed"]), "희귀할수록 물고기가 빠름")
	check(is_equal_approx(FishingReel.bite_window("common"), 1.5) and FishingReel.bite_window("rare") < 1.0, "챔질 시간 조회")
	check(float(FishingReel.params_for("없는희귀도")["zone_size"]) == float(table["common"]["zone_size"]), "모르는 희귀도는 일반 값으로 처리")
	# 모든 물고기의 희귀도가 값 표에 있다.
	var all_known := true
	for fish in FishingData.entries("fish"):
		if not table.has(str(fish["rarity"])):
			all_known = false
	check(all_known, "모든 물고기 희귀도에 당기기 값이 있음")

	# 아무것도 안 하면(놓고 있으면) 거의 항상 도망간다.
	var idle_escapes := 0
	for seed in range(30):
		rng.seed = seed + 1
		var idle := FishingReel.new()
		idle.start("common", rng)
		for i in range(2400):
			idle.step(1.0 / 60.0, false)
			if idle.result != "": break
		if idle.result == FishingReel.RESULT_ESCAPED: idle_escapes += 1
	check(idle_escapes >= 24, "버튼을 안 누르면 대부분 도망감(%d/30)" % idle_escapes)

	# 사람처럼 0.25초 늦게 물고기를 보고 따라가는 플레이어: 일반은 대부분 건지고 희귀는 자주 놓친다.
	var land := {}
	for rarity in ["common", "seasonal", "rare"]:
		land[rarity] = _landed_rate(rarity, 0.25, 40)
	check(land["common"] >= 0.9, "일반 물고기는 따라가면 대부분 건짐(%d%%)" % int(land["common"] * 100))
	check(land["seasonal"] <= land["common"] and land["rare"] < land["seasonal"], "희귀할수록 더 자주 놓침(일반 %d%% · 계절 %d%% · 희귀 %d%%)" % [int(land["common"] * 100), int(land["seasonal"] * 100), int(land["rare"] * 100)])
	check(land["rare"] <= 0.7 and land["rare"] > 0.0, "희귀 물고기는 어렵지만 불가능하지는 않음(%d%%)" % int(land["rare"] * 100))

	# 시간 제한
	var timed := FishingReel.new()
	timed.start("common", rng)
	timed.progress = 0.5
	timed.params = timed.params.duplicate()
	timed.params["gain"] = 0.0
	timed.params["drain"] = 0.0
	var timeout_result := ""
	for i in range(1200):
		timeout_result = timed.step(1.0 / 30.0, false)
		if timeout_result != "": break
	check(timeout_result == FishingReel.RESULT_ESCAPED, "제한 시간이 지나면 도망감")
	# 끝난 뒤에는 더 진행하지 않는다.
	check(timed.step(1.0, true) == FishingReel.RESULT_ESCAPED, "끝난 당기기는 결과가 유지됨")
	print("CHECK_FISHING_REEL checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)


# 물고기 위치를 delay초 늦게 보고, 0.08초보다 자주 바꾸지 못하는 플레이어를 흉내 낸다.
func _landed_rate(rarity: String, delay: float, seeds: int) -> float:
	var rng := RandomNumberGenerator.new()
	var wins := 0
	for seed in range(seeds):
		rng.seed = seed + 7
		var game := FishingReel.new()
		game.start(rarity, rng)
		var history: Array = []
		var hold := false
		var since := 0.0
		for i in range(3000):
			history.append(game.fish)
			var seen: float = history[maxi(0, history.size() - 1 - int(delay * 60.0))]
			since += 1.0 / 60.0
			if since >= 0.08 and (seen > game.zone) != hold:
				hold = seen > game.zone
				since = 0.0
			game.step(1.0 / 60.0, hold)
			if game.result != "": break
		if game.result == FishingReel.RESULT_LANDED: wins += 1
	return float(wins) / seeds
