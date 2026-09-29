extends Node
var player: Node2D
var manager: Node
var terrain: Node2D
var prompt: Label
var message_until := 0
var message_origin := Vector2.INF

func _ready() -> void:
 player = get_parent().get_node("Actors/Player")
 manager = get_parent().get_node("DayManager")
 terrain = get_parent().get_node("StoreExterior")
 prompt = Label.new()
 prompt.name = "WorldInteractionHint"
 prompt.position = Vector2(240,566)
 prompt.size = Vector2(672,48)
 prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
 prompt.add_theme_font_size_override("font_size",19)
 prompt.add_theme_color_override("font_color",Color("fff0d0"))
 prompt.add_theme_color_override("font_outline_color",Color("3a392c"))
 prompt.add_theme_constant_override("outline_size",5)
 get_parent().get_node("UI").add_child(prompt)

func blocked() -> bool:
 var world = get_parent()
 if world.get_node("BuildManager").build_mode or get_tree().paused: return true
 if manager.closing_shop or manager.summary_open or manager.night_auto_running or manager.fast_forwarding_to_morning: return true
 var menu = world.get_node_or_null("UI/GameMenu")
 return (menu != null and (menu.menu_open or menu.settings_panel.visible or menu.save_slot_panel.visible or menu.quit_game_dialog.visible or menu.return_title_dialog.visible)) or manager.management_menu.visible

func nearest_door() -> Node2D:
 if player.in_production_room or player.in_warehouse_room: return null
 var result: Node2D = null
 var distance := 70.0
 for door in get_tree().get_nodes_in_group("door"):
  if not is_instance_valid(door) or door.is_queued_for_deletion() or door.get_meta("is_build_preview",false): continue
  if door.get_parent() != get_parent().get_node("Objects"): continue
  var value: float = player.global_position.distance_to(door.global_position)
  if value < distance:
   distance = value
   result = door
 return result

func near_dungeon() -> bool:
 return not player.in_production_room and not player.in_warehouse_room and terrain.is_at_expedition_departure(player.global_position)

func _process(_delta: float) -> void:
 prompt.visible = not blocked()
 if not prompt.visible: return
 if Time.get_ticks_msec() < message_until and player.global_position.distance_to(message_origin) < 96: return
 if near_dungeon():
  prompt.text = "[E] 원정으로 출발하기"
  return
 if nearest_door(): prompt.text = "[E] 가게 닫기 · 영업 중" if manager.shop_open else "[E] 가게 열기 · 영업 종료"
 else: prompt.text = ""

func try_interact() -> bool:
 if blocked(): return false
 if near_dungeon():
  manager.enter_expedition_scene()
  return true
 if nearest_door():
  show_message(manager.toggle_shop_at_door())
  return true
 return false

func show_message(message: String) -> void:
 prompt.text = message
 message_origin = player.global_position
 message_until = Time.get_ticks_msec()+4000
