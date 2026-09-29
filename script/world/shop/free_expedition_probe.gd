extends Node
func run() -> void:
 for day in range(1,8):
  var world = get_tree().current_scene
  var manager = world.get_node("DayManager")
  var interaction = world.get_node("WorldInteractions")
  var actor = world.get_node("Actors/Player")
  GameState.current_day = day
  manager.current_day = day
  manager.update_phase()
  assert(manager.current_phase == manager.GamePhase.SHOP)
  var door = get_tree().get_nodes_in_group("door")[0]
  actor.global_position = door.global_position
  manager.current_hour = 13
  if day == 1:
   var event := InputEventKey.new()
   event.physical_keycode = KEY_E
   event.keycode = KEY_E
   event.pressed = true
   Input.parse_input_event(event)
   for i in range(4): await get_tree().process_frame
   event.pressed = false
   Input.parse_input_event(event)
  else:
   assert(interaction.try_interact())
  assert(manager.shop_open)
  assert(not manager.hour_timer.is_stopped())
  assert(interaction.try_interact())
  assert(not manager.shop_open and manager.hour_timer.is_stopped())
  assert(GameState.current_day == day and manager.current_hour == 13)
  actor.daily_revenue = 1234
  var exterior = world.get_node("StoreExterior")
  var departure: Vector2i = exterior.get_expedition_departure_cell()
  var offsets := [Vector2i.ZERO,Vector2i(2,0),Vector2i(-2,0),Vector2i(0,2),Vector2i(0,-2),Vector2i(2,2),Vector2i(-2,-2)]
  actor.global_position = exterior.to_global(exterior.grid_to_local(departure+Vector2i(3,0)))
  assert(not interaction.near_dungeon())
  actor.global_position = exterior.to_global(exterior.grid_to_local(departure+offsets[day-1]))
  assert(interaction.near_dungeon())
  for i in range(2): await get_tree().process_frame
  assert(interaction.prompt.text.contains("원정"))
  var enter_event := InputEventKey.new()
  enter_event.physical_keycode = KEY_E
  enter_event.keycode = KEY_E
  enter_event.pressed = true
  Input.parse_input_event(enter_event)
  for i in range(4): await get_tree().process_frame
  enter_event.pressed = false
  Input.parse_input_event(enter_event)
  for i in range(12): await get_tree().process_frame
  var expedition = get_tree().current_scene
  assert(expedition.scene_file_path == GameConfig.EXPEDITION_SCENE_PATH)
  assert(expedition.current_day == day and GameState.current_day == day)
  assert(expedition.current_expedition_phase == expedition.ExpeditionPhase.PREP)
  assert(expedition.prep_panel.visible)
  assert(not expedition.prep_panel.get_node("ModeTabs").visible)
  assert(not expedition.prep_panel.has_node("ShopContent"))
  assert(not expedition.prep_panel.has_node("MaintenanceContent"))
  assert(not expedition.game_menu.visible)
  assert(not expedition.get_node("PreparationVillage").clock_hud.visible)
  assert(not expedition.get_node("PreparationVillage").hud.visible)
  assert(expedition.map_content.get_node("WorldMap").texture != null)
  assert(expedition.map_content.region_buttons.size() == 4)
  assert(not expedition.start_expedition_button.visible)
  assert(expedition.prep_panel.current_tab == expedition.prep_panel.PrepTab.MAP)
  assert(expedition.map_content.visible)
  assert(expedition.prep_panel.get_selected_region_id().is_empty())
  assert(not expedition.bag_content.visible)
  assert(expedition.map_content.forest_button.icon != null)
  assert(expedition.map_content.mine_button.icon != null)
  assert(expedition.map_content.swamp_button.icon != null)
  assert(expedition.map_content.special_button.icon != null)
  if day == 2:
   expedition.map_content.mine_button.pressed.emit()
   assert(expedition.prep_panel.get_selected_region_id() == "mine")
   assert(expedition.start_expedition_button.text == "원정 출발")
   assert(expedition.prep_panel.get_node("RegionInfoCard/CardMargin/CardColumn/RegionNameLabel").text == "광산")
  elif day == 3:
   expedition.map_content.swamp_button.pressed.emit()
   assert(expedition.prep_panel.get_selected_region_id() == "swamp")
  elif day == 4:
   expedition.map_content.special_button.pressed.emit()
   assert(expedition.prep_panel.get_selected_region_id() == "hidden_ruins")
   assert(expedition.start_expedition_button.disabled)
   assert(expedition.prep_panel.get_node("RegionInfoCard/CardMargin/CardColumn/RegionRequirementLabel").text.contains("입장 조건"))
   expedition.prep_panel.select_tab(expedition.prep_panel.PrepTab.MAP)
   expedition.map_content.forest_button.pressed.emit()
  else:
   expedition.map_content.forest_button.pressed.emit()
  assert(expedition.bag_content.visible)
  assert(expedition.prep_panel.get_node("RegionInfoCard").visible)
  assert(expedition.start_expedition_button.visible)
  assert(expedition.prep_panel.get_node("RegionInfoCard/CardMargin/CardColumn/RegionNameLabel").text.length() > 0)
  if day == 2:
   expedition.prep_panel.get_node("RegionInfoCard/CardMargin/CardColumn/BackToMapButton").pressed.emit()
   assert(not expedition.bag_content.visible)
   assert(not expedition.start_expedition_button.visible)
   expedition.map_content.mine_button.pressed.emit()
  if day == 1:
   expedition.cancel_preparation_button.pressed.emit()
   for i in range(12): await get_tree().process_frame
   world = get_tree().current_scene
   assert(world.scene_file_path == GameConfig.MAIN_SCENE_PATH)
   interaction = world.get_node("WorldInteractions")
   assert(interaction.near_dungeon())
   assert(interaction.try_interact())
   for i in range(12): await get_tree().process_frame
   expedition = get_tree().current_scene
   assert(expedition.scene_file_path == GameConfig.EXPEDITION_SCENE_PATH)
   assert(expedition.current_expedition_phase == expedition.ExpeditionPhase.PREP)
   assert(not expedition.start_expedition_button.visible)
   expedition.map_content.forest_button.pressed.emit()
  expedition.start_expedition_button.pressed.emit()
  assert(expedition.current_expedition_phase == expedition.ExpeditionPhase.RUN)
  if day == 2: assert(expedition.current_region_id == "mine")
  elif day == 3: assert(expedition.current_region_id == "swamp")
  assert(expedition.game_menu.visible)
  assert(expedition.get_node("PreparationVillage").clock_hud.visible)
  assert(expedition.create_expedition_checkpoint_data().get("shop_return_context",{}).get("hour") == 13)
  expedition.finish_expedition()
  for i in range(12): await get_tree().process_frame
  world = get_tree().current_scene
  assert(world.scene_file_path == GameConfig.MAIN_SCENE_PATH)
  assert(GameState.current_day == day)
  assert(world.get_node("DayManager").current_hour == 13)
  assert(world.get_node("Actors/Player").daily_revenue == 1234)
  assert(not world.get_node("DayManager").shop_open)
  print("ANY_DAY_DOOR_ROUNDTRIP_PASS ",day)
 print("ALL_WEEKDAYS_EXPEDITION_PASS")
