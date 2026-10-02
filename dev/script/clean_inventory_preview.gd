extends "res://dev/script/world_art_preview.gd"
func _place_samples() -> void:
	super._place_samples()
	if OS.get_cmdline_user_args().has("--management"):
		$UI/ManagementMenu.open_menu()
	else:
		$UI/InventoryPanel.open_inventory()
