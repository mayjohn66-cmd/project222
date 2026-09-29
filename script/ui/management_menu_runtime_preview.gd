extends Control


func _ready() -> void:
	var menu: Control = $ManagementMenu
	menu.visible = true
	if menu.has_method("refresh_common_info"):
		menu.call("refresh_common_info")
