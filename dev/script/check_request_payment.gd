extends Node

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void: call_deferred("run")

func run() -> void:
	PlayerProgress.reset()
	var progress := PlayerProgress.to_save_data().duplicate(true)
	var stock := GameState.inventory.duplicate(true)
	var money := GameState.money
	var panel := VillageRequestsPanel.new()
	add_child(panel)
	panel.display()
	var ids := ["well_gathering", "naru_market_juice", "doyun_market_soup", "sora_market_drink", "naru_thanks_snack", "naru_lunch_extra", "doyun_waterside_flask", "sora_autumn_tea", "doyun_winter_breakfast", "festival_spring", "festival_summer", "festival_autumn", "festival_winter"]
	for id in ids:
		var key: String = id
		if id.begins_with("festival_"): key = VillageExpansionFlow.JOURNAL_PREFIX + id
		elif id != "well_gathering": key = "personal:" + id
		var text: String = panel.cards[key]["info"].text
		check(text.contains("나눔 부탁") and text.contains("물품 대금은 별도로 받지 않습니다.") and text.contains("답례"), "actual donation card distinguishes payment from thanks: " + id)
	var ordinary_checked := false
	for entry in CommunityRequestFlow.SETTINGS.requests:
		if entry.has("payment_kind"): continue
		var text: String = panel.cards[str(entry["id"])]["info"].text
		check(text.contains("보상:") and not text.contains("나눔 부탁"), "ordinary community reward is unchanged")
		ordinary_checked = true
		break
	check(ordinary_checked, "ordinary community fixture exists")
	check(VillageMarketFlow.SETTINGS.payment_kind == "gift", "first market is the fourteenth donation")
	panel.refresh()
	panel.close()
	check(GameState.inventory == stock and GameState.money == money and PlayerProgress.to_save_data() == progress, "opening and refreshing donation UI does not consume, pay or advance")
	print("CHECK_REQUEST_PAYMENT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
