@tool
extends EditorPlugin
var csv_exporter: EditorExportPlugin
func _enter_tree() -> void:
	csv_exporter = preload("res://addons/runtime_csv_export/runtime_csv_export.gd").new()
	add_export_plugin(csv_exporter)
func _exit_tree() -> void:
	if csv_exporter != null: remove_export_plugin(csv_exporter)
