extends "res://dev/script/world_art_preview.gd"
func _place_samples() -> void:
 super._place_samples()
 await get_tree().process_frame
 await get_tree().process_frame
 var menu = $UI/GameMenu
 var builder = $BuildManager
 var bar = $UI/BuildQuickSlotBar
 menu.menu_button.pressed.emit()
 await get_tree().create_timer(0.45).timeout
 assert(menu.menu_open and is_equal_approx(menu.menu_progress,1.0))
 assert(menu.info_button.text == "건설")
 if OS.get_cmdline_user_args().has("--menu"):
  for button in menu.main_menu_panel.get_node("MenuVBox").get_children():
   assert(button.size.is_equal_approx(menu.menu_button.size))
  print("MATCHED_MENU_BUTTONS_PASS ",menu.menu_button.size)
  return
 menu.info_button.pressed.emit()
 assert(builder.build_mode and get_tree().paused)
 assert(not menu.visible)
 for child in builder.hidden_build_ui:
  assert(not child.visible)
 if OS.get_cmdline_user_args().has("--bag"):
  bar.bag_button.pressed.emit()
  await get_tree().create_timer(0.45).timeout
  assert(bar.inventory_open)
 if OS.get_cmdline_user_args().has("--smoke"):
  bar.set_inventory_open(true)
  await get_tree().create_timer(0.45).timeout
  var drag := {"type":"build_furniture_registration","build_id":"shelf_2x1"}
  assert(bar._can_drop_on_quick_slot(Vector2.ZERO,drag,2))
  bar._drop_on_quick_slot(Vector2.ZERO,drag,2)
  assert(GameState.get_build_quick_slot(2) == "shelf_2x1")
  var back := {"type":"build_quick_slot_return","build_id":"shelf_2x1","slot_index":2}
  bar._return_quick_slot(Vector2.ZERO,back)
  assert(GameState.get_build_quick_slot(2).is_empty())
  bar.set_inventory_open(false)
  bar.get_node("FinishBuildButton").pressed.emit()
  assert(builder.build_confirm_center.visible)
  builder.cancel_build_confirmation()
  assert(builder.build_mode)
  builder.confirm_build_changes()
  assert(not builder.build_mode and not get_tree().paused)
  assert(menu.visible and not menu.menu_open)
  menu.toggle_main_menu()
  await get_tree().create_timer(0.08).timeout
  menu.toggle_main_menu()
  await get_tree().create_timer(0.45).timeout
  assert(not menu.menu_open and not menu.menu_clip.visible)
  print("BUILD_MENU_SMOKE_PASS")
 print("BUILD_MENU_PREVIEW_PASS")
