class_name ExpeditionEnvironmentCard
extends RefCounted

static func install(prep: Control) -> void:
	# 환경 단서가 길어져도 난이도 버튼을 카드 밖으로 밀지 않는다.
	var label: Label = prep.region_description_label
	var column: VBoxContainer = prep.region_card_column
	var index := label.get_index()
	var scroll := ScrollContainer.new()
	scroll.name = "EnvironmentDescriptionScroll"
	scroll.custom_minimum_size.y = 70
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	column.move_child(scroll, index)
	label.reparent(scroll)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
