extends Node
## 가격 단계(ShopPricing) 검사: 단계 계산, 마감 할인과의 곱, 손님 반응, 저장·옛 저장 호환, 데이터 일관성.
var checks := 0
var failures := 0


class FakeCustomer extends Node:
	var wanted_event_id: String = ""
	var type_id: String = "normal"
	func get_customer_type_id() -> String:
		return type_id


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _ready() -> void:
	var original: Dictionary = GameState.create_save_data()
	GameState.price_steps.clear()
	var ids: Array = ShopPricingData.step_ids()
	check(ids == [-2, -1, 0, 1, 2], "가격 단계는 5개(-2~2)")
	check(is_equal_approx(ShopPricing.multiplier_of_step(0), 1.0) and ShopPricing.label(0) == "기본", "기본 단계는 x1.0")
	check(ShopPricing.multiplier_of_step(-2) < ShopPricing.multiplier_of_step(-1) and ShopPricing.multiplier_of_step(1) < ShopPricing.multiplier_of_step(2), "단계가 오를수록 배율이 큼")

	# 가격 계산
	var base: int = ItemData.get_item_price("bread")
	check(base > 0 and ShopPricing.sale_price("bread") == base, "기본 단계에서는 기존 가격 그대로(%dG)" % base)
	ShopPricing.set_step("bread", 1)
	check(ShopPricing.sale_price("bread") == roundi(base * 1.2), "비쌈 단계 가격 = 기본가 x 1.2 (%dG)" % ShopPricing.sale_price("bread"))
	ShopPricing.set_step("bread", 99)
	check(ShopPricing.step_of("bread") == 2, "범위를 넘는 단계는 끝 단계로 맞춤")
	ShopPricing.set_step("bread", -99)
	check(ShopPricing.step_of("bread") == -2, "아래로 넘는 단계도 끝 단계로")
	check(ShopPricing.shift("bread", -1) == -2, "끝에서 더 내려도 멈춤")
	ShopPricing.set_step("bread", 0)
	check(not GameState.price_steps.has("bread"), "기본 단계는 저장하지 않음")
	check(ShopPricing.sale_price("없는상품") == ItemData.get_item_price("없는상품"), "없는 상품은 가격 처리를 건드리지 않음")

	# 마감 할인은 단계 가격 위에 곱해진다(자동 유지)
	FoodShelfLife.state()["markdown"] = true
	var rule_days: int = int(FoodShelfLife.rules()["bread"]["days"])
	var old_age: int = (rule_days - 1) * FoodShelfLife.SETTINGS.ambient_age
	var batch := {"age": old_age, "amount": 1}
	var discounted: int = FoodShelfLife.unit_price("bread", batch)
	var percent: int = FoodShelfLife.SETTINGS.markdown_percent
	check(discounted == maxi(1, base * (100 - percent) / 100), "기본 단계 + 마감 할인 = 기존과 같음(%dG)" % discounted)
	ShopPricing.set_step("bread", 1)
	var stepped: int = ShopPricing.sale_price("bread")
	check(FoodShelfLife.unit_price("bread", batch) == maxi(1, stepped * (100 - percent) / 100), "비쌈 단계 + 마감 할인 = 단계 가격에 할인이 곱해짐")
	check(FoodShelfLife.unit_price("bread", {"age": 0, "amount": 1}) == stepped, "할인이 없으면 단계 가격 그대로")
	ShopPricing.set_step("bread", 0)

	# 손님 반응
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var child := FakeCustomer.new(); child.type_id = "child"
	var collector := FakeCustomer.new(); collector.type_id = "collector"
	add_child(child); add_child(collector)
	check(not ShopPricing.react(child, "bread", 1, 5, rng)["walkout"], "기본 가격에서는 아무도 나가지 않음")
	ShopPricing.set_step("bread", 2)
	var child_out := 0
	var collector_out := 0
	for i in range(400):
		if ShopPricing.react(child, "bread", 1, 5, rng)["walkout"]: child_out += 1
		if ShopPricing.react(collector, "bread", 1, 5, rng)["walkout"]: collector_out += 1
	check(child_out > collector_out + 80, "아주 비싸면 아이가 수집가보다 훨씬 자주 나감(%d vs %d / 400)" % [child_out, collector_out])
	check(child_out > 200 and collector_out > 0, "아이는 절반 이상 나가고 수집가도 일부는 나감")
	var walk: Dictionary = {}
	for i in range(50):
		walk = ShopPricing.react(child, "bread", 2, 5, rng)
		if walk["walkout"]: break
	check(walk["walkout"] and int(walk["lost"]) == ShopPricing.sale_price("bread") * 2, "나간 손님의 놓친 매출 = 단계 가격 x 수량")
	ShopPricing.set_step("bread", -2)
	var bonus := 0
	var no_stock := 0
	for i in range(400):
		bonus += int(ShopPricing.react(child, "bread", 1, 5, rng)["bonus"])
		no_stock += int(ShopPricing.react(child, "bread", 1, 1, rng)["bonus"])
	check(bonus > 100 and no_stock == 0, "아주 싸면 아이가 한 개 더 사는 일이 잦고, 진열대에 재고가 모자라면 더 사지 않음(%d/400)" % bonus)
	check(not ShopPricing.react(child, "bread", 1, 5, rng)["walkout"], "싼 단계에서는 나가지 않음")
	# 이야기 손님·행사 손님은 가격과 상관없이 산다
	ShopPricing.set_step("bread", 2)
	var story := FakeCustomer.new(); story.type_id = "child"; story.set_meta("regular_story_item", "bread")
	var event := FakeCustomer.new(); event.type_id = "child"; event.wanted_event_id = "event_x"
	add_child(story); add_child(event)
	var story_out := 0
	for i in range(100):
		if ShopPricing.react(story, "bread", 1, 5, rng)["walkout"] or ShopPricing.react(event, "bread", 1, 5, rng)["walkout"]: story_out += 1
	check(story_out == 0, "이야기·행사 손님은 비싸도 나가지 않음")
	check(ShopPricing.accept_chance("child", 1.4) < ShopPricing.accept_chance("child", 1.2) and ShopPricing.accept_chance("child", 1.2) < 1.0, "비쌀수록 구매 확률이 낮아짐")
	check(ShopPricing.accept_chance("child", 5.0) >= 0.05, "구매 확률에는 하한이 있음")
	check(ShopPricing.walkout_line("child") != ShopPricing.walkout_line("normal"), "손님 종류별 나가는 말이 다름")
	ShopPricing.set_step("bread", 0)

	# 저장·불러오기
	ShopPricing.set_step("bread", 2)
	ShopPricing.set_step("water", -1)
	var data: Dictionary = GameState.create_save_data()
	check(data["price_steps"] == {"bread": 2, "water": -1}, "저장 데이터에 가격 단계가 들어감")
	GameState.price_steps.clear()
	check(GameState.apply_save_data(data) and ShopPricing.step_of("bread") == 2 and ShopPricing.step_of("water") == -1, "불러오면 가격 단계가 복원됨")
	var old_save: Dictionary = data.duplicate(true)
	old_save.erase("price_steps")
	GameState.price_steps = {"bread": 2}
	check(GameState.apply_save_data(old_save) and GameState.price_steps.is_empty(), "가격 단계가 없는 옛 저장은 모두 기본으로 불러옴")
	var broken: Dictionary = data.duplicate(true)
	broken["price_steps"] = {"bread": 99, "water": "x", "milk": 1}
	check(GameState.apply_save_data(broken) and ShopPricing.step_of("bread") == 0 and ShopPricing.step_of("milk") == 1, "범위 밖·잘못된 가격 단계는 기본으로 버림")

	# 데이터 일관성: 모든 손님 대분류에 민감도가 있다
	var groups_ok := true
	for g in ["normal", "traveler", "adventurer", "miner", "herbalist", "child", "collector", "marsh_local"]:
		if not ShopPricingData.sensitivity.has(g): groups_ok = false
	check(groups_ok, "모든 손님 대분류에 가격 민감도가 있음")
	check(ShopPricing.sensitivity("child") > ShopPricing.sensitivity("normal") and ShopPricing.sensitivity("normal") > ShopPricing.sensitivity("collector"), "민감도 순서: 아이 > 일반 > 수집가")

	GameState.price_steps.clear()
	check(GameState.apply_save_data(original), "원래 메모리 상태 복원")
	print("CHECK_SHOP_PRICING checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
