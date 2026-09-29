extends "res://script/world/shop/world_art_preview.gd"

func _place_samples() -> void:
	super._place_samples()
	var night: bool = "--night" in OS.get_cmdline_user_args()
	if night:
		$DayManager.current_hour = 22
		$DayManager.night_auto_running = true
		GameState.money = 999999999
		$Actors/Player.update_money_ui()
	$DayManager.update_time_ui()
	$DayManager.update_day_ui()
	$UI/HUD._update_sky()
	var checked: int = 0
	for id in ItemCatalog.ITEMS:
		var texture: Texture2D = ItemData.get_item_icon(id)
		assert(texture != null, "Missing icon: " + id)
		assert(texture.get_size() == Vector2(64,64), "Wrong icon size: " + id)
		checked += 1
	assert(checked == 17)
	assert($UI/HUD/DayLabel.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	print("ITEMS_HUD_OK: ", checked, " icons loaded; ", "night/large money" if night else "day")
