extends "res://script/world/shop/dungeon_route_preview.gd"
func _place_samples() -> void:
 await super._place_samples()
 for i in range(6): await get_tree().process_frame
 if OS.get_cmdline_user_args().has("--all-days"):
  var probe = preload("res://script/world/shop/free_expedition_probe.gd").new()
  get_tree().root.add_child(probe)
  probe.run()
 else:
  var door = get_tree().get_nodes_in_group("door")[0]
  $Actors/Player.global_position = door.global_position+Vector2(0,32)
