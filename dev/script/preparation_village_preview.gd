extends "res://script/expedition/expedition.gd"
func _ready() -> void:
 super._ready()
 call_deferred("_check_road")
func key(code: Key, down: bool) -> void:
 var event := InputEventKey.new()
 event.physical_keycode = code
 event.keycode = code
 event.pressed = down
 Input.parse_input_event(event)
func _check_road() -> void:
 for i in range(4): await get_tree().process_frame
 var road = $PreparationVillage
 if OS.get_cmdline_user_args().has("--exit"):
  road.player.position = road.grid(road.EXIT_CELL)
  road.camera.reset_smoothing()
  return
 if not OS.get_cmdline_user_args().has("--smoke"): return
 assert(not road.has_node("VillageObjects"))
 assert(not prep_panel.visible)
 road.try_departure()
 assert(current_expedition_phase == ExpeditionPhase.PREP)
 var before: Vector2 = road.player.position
 key(KEY_D,true)
 key(KEY_W,true)
 for i in range(12): await get_tree().physics_frame
 key(KEY_D,false)
 key(KEY_W,false)
 assert(road.player.position.x > before.x+10)
 assert(road.player.position.y < before.y-10)
 assert(road.on_road(road.player.position))
 road.player.position = road.grid(Vector2(9.34,8))
 key(KEY_D,true)
 for i in range(8): await get_tree().physics_frame
 key(KEY_D,false)
 assert(road.on_road(road.player.position))
 road.player.position = road.grid(road.EXIT_CELL)
 assert(road.near_exit())
 road.camera.reset_smoothing()
 assert(road.clock_hud.visible)
 key(KEY_E,true)
 await get_tree().process_frame
 key(KEY_E,false)
 for i in range(4): await get_tree().process_frame
 assert(current_expedition_phase == ExpeditionPhase.RUN)
 assert(not road.visible and not road.hud.visible)
 assert(road.clock_hud.visible)
 set_expedition_phase(ExpeditionPhase.PREP)
 assert(road.visible and not prep_panel.visible)
 assert(road.player.position == road.grid(road.START_CELL))
 print("ROAD_ONLY_EXPEDITION_PASS")
