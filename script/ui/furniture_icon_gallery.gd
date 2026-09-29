extends Control

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("241d17")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.position = Vector2(180,130)
	grid.add_theme_constant_override("h_separation",20)
	grid.add_theme_constant_override("v_separation",20)
	add_child(grid)
	for data in FurnitureData.get_all_furniture():
		var id: String = data.id
		var texture := FurnitureData.get_furniture_icon(id)
		assert(texture != null and texture.get_size() == Vector2(64,64), id)
		var column := VBoxContainer.new()
		grid.add_child(column)
		var card = GameConfig.ITEM_CARD_SCENE.instantiate()
		column.add_child(card)
		card.setup_furniture(id,1)
		assert(card.icon_rect.texture == texture)
		var caption := Label.new()
		caption.text = FurnitureData.get_furniture_name(id)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size",14)
		caption.add_theme_color_override("font_color",Color("f5deb4"))
		column.add_child(caption)
	print("FURNITURE_ICONS_OK: all 12 real inventory cards have 64x64 icons")
