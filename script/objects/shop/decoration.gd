extends StaticBody2D


var furniture_id: String = ""
var furniture_data: Dictionary = {}


func configure_decoration(
	build_id: String
) -> void:
	if build_id.is_empty():
		push_error(
			"[치장] build_id가 비어 있습니다."
		)
		return

	if (
		furniture_id == build_id
		and not furniture_data.is_empty()
	):
		return

	var data: Dictionary = (
		FurnitureData.get_furniture(
			build_id
		)
	)

	if data.is_empty():
		push_error(
			"[치장] 가구 데이터 없음: "
			+ build_id
		)
		return

	furniture_id = build_id
	furniture_data = data

	set_meta(
		"build_id",
		build_id
	)


func get_decoration_effect_data() -> Dictionary:
	if furniture_data.is_empty():
		return {}

	# 실제 계산은 DecorationEffectService에서 처리합니다.
	return {
		"effect_type": str(
			furniture_data.get(
				"effect_type",
				""
			)
		),

		"effect_value": float(
			furniture_data.get(
				"effect_value",
				0.0
			)
		),

		"effect_target": str(
			furniture_data.get(
				"effect_target",
				""
			)
		)
	}
