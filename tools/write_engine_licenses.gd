extends SceneTree
func _init() -> void:
	var destination := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): destination=arg.trim_prefix("--out=")
	if destination.is_empty():
		push_error("--out=<absolute file> required")
		quit(1)
		return
	var file := FileAccess.open(destination,FileAccess.WRITE)
	if file == null:
		push_error("Cannot write engine license file")
		quit(1)
		return
	file.store_string(Engine.get_license_text()+"\n\nCOMPONENT COPYRIGHTS\n"+JSON.stringify(Engine.get_copyright_info(),"  ")+"\n\nLICENSE TEXTS\n")
	var licenses := Engine.get_license_info()
	for name in licenses: file.store_string("\n\n"+str(name)+"\n"+str(licenses[name])+"\n")
	quit(0)
