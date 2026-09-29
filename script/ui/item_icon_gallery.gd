extends Control

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("241d17")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.position = Vector2(210,50)
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	add_child(grid)
	for id in ItemCatalog.ITEMS:
		var column := VBoxContainer.new()
		grid.add_child(column)
		var card = GameConfig.ITEM_CARD_SCENE.instantiate()
		column.add_child(card)
		card.setup(id,12)
		var caption := Label.new()
		caption.text = ItemData.get_item_name(id)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size",14)
		caption.add_theme_color_override("font_color",Color("f5deb4"))
		column.add_child(caption)
