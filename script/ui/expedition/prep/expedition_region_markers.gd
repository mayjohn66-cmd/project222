class_name ExpeditionRegionMarkers
extends RefCounted
const CONTENT = preload("res://scenes/expedition/rooms/default_content_settings.tres")

# CSV의 새 지역은 기존 픽셀 아이콘을 재사용한다. 이름은 지도에 항상 표시한다.
static func add_regions(map: Control, buttons: Dictionary, template: Button) -> void:
	for id in ExpeditionMapData.get_region_ids():
		if buttons.has(id): continue
		var profile := CONTENT.region_profile(id)
		var button: Button = template.duplicate()
		button.name = "Region_" + id
		var x := float(profile.get("map_x",0.5))
		var y := float(profile.get("map_y",0.5))
		button.anchor_left = x
		button.anchor_right = x
		button.anchor_top = y
		button.anchor_bottom = y
		var icon := str(profile.get("map_icon",""))
		if ResourceLoader.exists(icon): button.icon = load(icon)
		map.add_child(button)
		buttons[id] = button
	for id in buttons:
		var button: Button = buttons[id]
		var label := Label.new()
		label.name = "RegionName"
		label.text = str(ExpeditionMapData.get_region_data(str(id)).get("name",id))
		label.anchor_left = 0.5
		label.anchor_right = 0.5
		label.anchor_top = 1.0
		label.anchor_bottom = 1.0
		label.offset_left = -80
		label.offset_right = 80
		label.offset_top = 4
		label.offset_bottom = 32
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size",18)
		label.add_theme_color_override("font_color",Color("fff0d0"))
		label.add_theme_color_override("font_outline_color",Color("3a392c"))
		label.add_theme_constant_override("outline_size",4)
		button.add_child(label)
