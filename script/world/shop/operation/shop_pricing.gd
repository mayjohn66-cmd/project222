class_name ShopPricing
extends RefCounted
## 상품 가격 단계(2026-10-13). 플레이어는 상품마다 5단계(아주 저렴 ~ 아주 비쌈)로 판매 가격을 정한다.
##   - 판매가 = 기본가(아이템 데이터) x 단계 배율. 마감 할인은 이 값 위에 그대로 곱해진다(자동 유지).
##   - 손님은 진열대 앞에서 가격을 보고, 비싸면 사지 않고 나간다(민감한 손님일수록 잘 나감). 싸면 민감한 손님이 한 개 더 산다.
##   - 단계 저장: GameState.price_steps {item_id: step}. 기본(0)이면 저장하지 않는다.
##   - 수치: data/shop/catalogs/economy/pricing_steps.csv · pricing_sensitivity.csv · pricing_settings.csv


static func step_of(item_id: String) -> int:
	return int(GameState.price_steps.get(item_id, 0))


static func set_step(item_id: String, step: int) -> void:
	var ids: Array = ShopPricingData.step_ids()
	step = clampi(step, int(ids.front()), int(ids.back()))
	if step == 0:
		GameState.price_steps.erase(item_id)
	else:
		GameState.price_steps[item_id] = step


# 현재 단계에서 한 칸 올리거나(+1) 내린다(-1). 끝에서는 멈춘다.
static func shift(item_id: String, direction: int) -> int:
	set_step(item_id, step_of(item_id) + direction)
	return step_of(item_id)


static func label(step: int) -> String:
	ShopPricingData.ensure_loaded()
	return str(ShopPricingData.steps.get(step, ShopPricingData.steps.get(0, {"label": "기본"}))["label"])


static func multiplier_of_step(step: int) -> float:
	ShopPricingData.ensure_loaded()
	return float(ShopPricingData.steps.get(step, {"multiplier": 1.0})["multiplier"])


static func multiplier(item_id: String) -> float:
	return multiplier_of_step(step_of(item_id))


# 선택한 단계가 반영된 개당 판매가(마감 할인 전).
static func sale_price(item_id: String) -> int:
	var base: int = ItemData.get_item_price(item_id)
	if base <= 0:
		return base
	return maxi(1, roundi(float(base) * multiplier(item_id)))


static func sensitivity(group_id: String) -> float:
	ShopPricingData.ensure_loaded()
	return float(ShopPricingData.sensitivity.get(group_id, 1.0))


static func _setting(key: String) -> float:
	ShopPricingData.ensure_loaded()
	return float(ShopPricingData.settings[key])


# 이 가격에서 이 손님이 사 갈 확률(비싼 단계에서만 1보다 작아진다).
static func accept_chance(group_id: String, ratio: float) -> float:
	if ratio <= 1.0:
		return 1.0
	return clampf(1.0 - sensitivity(group_id) * (ratio - 1.0) * _setting("expensive_slope"), _setting("min_accept"), 1.0)


# 싼 단계에서 한 개 더 살 확률.
static func bonus_chance(group_id: String, ratio: float) -> float:
	if ratio >= 1.0:
		return 0.0
	return clampf(sensitivity(group_id) * (1.0 - ratio) * _setting("cheap_bonus_slope"), 0.0, _setting("max_bonus"))


# 가격 반응이 적용되는 손님인가: 이야기 손님(단골·원정 만남·날씨 인사)과 매장 행사 손님은 가격과 상관없이 산다.
static func applies_to(customer: Node) -> bool:
	return not customer.has_meta("regular_story_item") and str(customer.get("wanted_event_id")).is_empty()


# 진열대 앞에서의 반응. {"walkout": bool, "bonus": int, "lost": int}. stock = 진열대에 남은 이 상품 수.
static func react(customer: Node, item_id: String, amount: int, stock: int, random: RandomNumberGenerator = null) -> Dictionary:
	var result := {"walkout": false, "bonus": 0, "lost": 0}
	if not applies_to(customer):
		return result
	var ratio: float = multiplier(item_id)
	if ratio == 1.0:
		return result
	var group_id: String = CustomerTypeData.get_group_id(customer.get_customer_type_id())
	var roll: float = random.randf() if random != null else randf()
	if ratio > 1.0:
		if roll > accept_chance(group_id, ratio):
			result["walkout"] = true
			result["lost"] = sale_price(item_id) * amount
	elif stock > amount and roll < bonus_chance(group_id, ratio):
		result["bonus"] = 1
	return result


static func walkout_line(group_id: String) -> String:
	match group_id:
		"child": return "이 값이면 못 사… 용돈이 모자라."
		"collector": return "탐나지만 이 값은 아니군."
		"traveler": return "길에서 이 값은 좀 그렇네. 다른 데 알아볼게."
		"miner": return "일당으로 이건 무리야."
	return "너무 비싸네. 다음에 올게."
