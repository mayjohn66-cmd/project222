class_name DecorationEffectService
extends RefCounted


# 원래 합계가 HALF_VALUE일 때 최대 보너스의 절반 적용
const REPUTATION_HALF_VALUE: float = 10.0
const REPUTATION_MAX_VISIT_BONUS: float = 0.50

const CUSTOMER_WEIGHT_HALF_VALUE: float = 1.0
const CUSTOMER_WEIGHT_MAX_BONUS: float = 1.0

const PURCHASE_DESIRE_HALF_VALUE: float = 1.0
const PURCHASE_DESIRE_MAX_CHANCE: float = 0.50


static func apply_diminishing_returns(
	raw_value: float,
	half_value: float,
	max_bonus: float
) -> float:
	if (
		not is_finite(raw_value)
		or raw_value <= 0.0
		or half_value <= 0.0
		or max_bonus <= 0.0
	):
		return 0.0

	return max_bonus * (
		raw_value / (half_value + raw_value)
	)


static func get_reputation_visit_bonus(
	reputation: float
) -> float:
	return apply_diminishing_returns(
		reputation,
		REPUTATION_HALF_VALUE,
		REPUTATION_MAX_VISIT_BONUS
	)


static func calculate(
	layout: Array[Dictionary]
) -> Dictionary:
	var reputation_total: float = 0.0
	var purchase_desire_total: float = 0.0
	var raw_customer_bonuses: Dictionary = {}

	for entry in layout:
		# 매장에 배치한 가구만 적용
		if str(entry.get("room_id", "store")) != "store":
			continue

		var build_id: String = str(
			entry.get("build_id", "")
		)

		if build_id.is_empty():
			continue

		if BuildObjectData.get_build_type(build_id) != "decoration":
			continue

		var effect: Dictionary = FurnitureData.get_effect_data(
			build_id
		)

		if effect.is_empty():
			continue

		var value: float = float(
			effect.get("effect_value", 0.0)
		)

		if not is_finite(value) or value <= 0.0:
			continue

		var effect_type: String = str(
			effect.get("effect_type", "")
		)

		match effect_type:
			"reputation":
				reputation_total += value

			"purchase_desire":
				purchase_desire_total += value

			"customer_weight":
				var target: String = str(
					effect.get("effect_target", "")
				)

				if not CustomerTypeData.has_customer_type(target):
					continue

				raw_customer_bonuses[target] = (
					float(raw_customer_bonuses.get(target, 0.0))
					+ value
				)

	# 대상 손님별 합계에 곡선을 한 번만 적용
	var customer_bonuses: Dictionary = {}

	for raw_target in raw_customer_bonuses:
		var target: String = str(raw_target)

		customer_bonuses[target] = apply_diminishing_returns(
			float(raw_customer_bonuses[target]),
			CUSTOMER_WEIGHT_HALF_VALUE,
			CUSTOMER_WEIGHT_MAX_BONUS
		)

	return {
		# 평판은 방문 간격 계산 시 곡선 적용
		"reputation": reputation_total,

		# 아래 두 항목은 곡선이 적용된 실제 보너스
		"purchase_desire": apply_diminishing_returns(
			purchase_desire_total,
			PURCHASE_DESIRE_HALF_VALUE,
			PURCHASE_DESIRE_MAX_CHANCE
		),
		"customer_weight": customer_bonuses
	}
