extends "res://dev/script/world_art_preview.gd"
func _place_samples() -> void:
 super._place_samples()
 var tab: int = 0
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--tab="): tab=int(arg.trim_prefix("--tab="))
 $UI/ManagementMenu.open_menu(tab)
 if OS.get_cmdline_user_args().has("--recipes"):
  $UI/ManagementMenu.management_production._select_production_tab(false)
  $UI/ManagementMenu.management_production.select_recipe("bake_bread")
 await get_tree().process_frame
 await get_tree().process_frame
 var area = $UI/ManagementMenu.get_node("DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea")
 print("MANAGEMENT_AREA ",area.size," tab ",tab)

 if OS.get_cmdline_user_args().has("--flip"):
  await get_tree().create_timer(0.4).timeout
  $UI/ManagementMenu.select_tab(2)
  var turn = area.get_node("PageTurn")
  assert(turn.visible)
  await get_tree().create_timer(0.12).timeout
  assert(turn.progress > 0.0 and turn.progress < 1.0)
  await get_tree().create_timer(0.5).timeout
  assert(not turn.visible)
  $UI/ManagementMenu.select_tab(3)
  $UI/ManagementMenu.select_tab(0)
  await get_tree().create_timer(0.6).timeout
  assert(not turn.visible)
  assert($UI/ManagementMenu.current_tab == 0)
  print("BOOK_PAGE_TURN_PASS")
 if OS.get_cmdline_user_args().has("--hold"):
  var button = $UI/ManagementMenu.management_inventory.furniture_button
  var point: Vector2 = button.get_global_rect().get_center()
  var motion := InputEventMouseMotion.new()
  motion.position = point
  Input.parse_input_event(motion)
  var down := InputEventMouseButton.new()
  down.position = point
  down.button_index = MOUSE_BUTTON_LEFT
  down.pressed = true
  Input.parse_input_event(down)
  await get_tree().process_frame
  button.button_pressed = true
  button.grab_focus()
  button.notification(Control.NOTIFICATION_MOUSE_ENTER)
  assert(button.get_draw_mode() == BaseButton.DRAW_HOVER_PRESSED)
  assert(button.get_theme_stylebox("hover_pressed") is StyleBoxFlat)
  assert(button.get_theme_stylebox("focus") is StyleBoxFlat)
  print("MANAGEMENT_HELD_BUTTON_PASS")
 if OS.get_cmdline_user_args().has("--smoke"):
  var menu = $UI/ManagementMenu
  var buttons = [menu.inventory_button, menu.production_button, menu.employee_button, menu.blueprint_button, menu.construction_button, menu.schedule_button, menu.history_button]
  for i in range(buttons.size()):
   buttons[i].pressed.emit()
   await get_tree().process_frame
   assert(menu.current_tab == i)
  for i in range(4):
   menu.select_info_tab(i)
   await get_tree().process_frame
  menu.select_tab(2)
  var employees = menu.employee_content
  for i in range(4):
   employees._select_employee_tab(i)
   await get_tree().process_frame
  menu.select_tab(0)
  for group in ["shelf", "furniture", "expedition"]:
   menu.management_inventory.select_inventory_group(group)
   await get_tree().process_frame
  menu.close_button.pressed.emit()
  assert(not menu.visible)
  assert(not get_tree().paused)
  menu.open_menu(0)
  assert(menu.visible and get_tree().paused)
  menu.close_menu()
  print("MANAGEMENT_SMOKE_PASS")
