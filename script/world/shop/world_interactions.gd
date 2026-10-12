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
 prompt.add_theme_font_size_override("font_size",UiTypography.size(19))
 prompt.add_theme_color_override("font_color",Color("fff0d0"))
 prompt.add_theme_color_override("font_outline_color",Color("3a392c"))
 prompt.add_theme_constant_override("outline_size",5)
 get_parent().get_node("UI").add_child(prompt)

func blocked() -> bool:
 var world = get_parent()
 if bool(world.get_meta("employee_recruitment_open",false)): return true
 if bool(world.get_meta("fishing_open",false)): return true
 if bool(world.get_meta("act_four_open",false)): return true
 if bool(world.get_meta("checkout_tutorial_dialogue",false)): return true
 if bool(world.get_meta("progressive_tutorial_dialogue",false)): return true
 if bool(world.get_meta("village_life_dialogue",false)): return true
 if bool(world.get_meta("community_board_open",false)): return true
 if bool(world.get_meta("resident_trade_open",false)): return true
 if bool(world.get_meta("village_smithy_open",false)): return true
 if bool(world.get_meta("blacksmith_open",false)): return true
 if bool(world.get_meta("village_journal_open",false)): return true
 if bool(world.get_meta("village_gathering_open",false)): return true
 if bool(world.get_meta("village_market_open",false)): return true
 if bool(world.get_meta("village_rest_open",false)): return true
 if bool(world.get_meta("seasonal_village_open",false)): return true
 if bool(world.get_meta("regular_customer_open",false)): return true
 if bool(world.get_meta("expedition_contact_open",false)): return true
 if bool(world.get_meta("weather_life_open",false)): return true
 if bool(world.get_meta("village_expansion_open",false)): return true
 if bool(world.get_meta("lantern_wayfarer_open",false)): return true
 if world.get_node("BuildManager").build_mode or get_tree().paused: return true
 if manager.closing_shop or manager.summary_open: return true
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
 var recruitment = get_parent().get_node_or_null("EmployeeRecruitmentDirector")
 if recruitment != null and not recruitment.interaction_hint().is_empty():
  prompt.text = recruitment.interaction_hint()
  return
 var fishing = get_parent().get_node_or_null("FishingDirector")
 if fishing != null and not fishing.interaction_hint().is_empty():
  prompt.text = fishing.interaction_hint()
  return
 var act_four = get_parent().get_node_or_null("VillageLifeDirector/ActFourDirector")
 if act_four != null and not act_four.interaction_hint().is_empty():
  prompt.text = act_four.interaction_hint()
  return
 var power = get_parent().get_node_or_null("ManualCheckoutController/PowerRepairDirector")
 if power != null and not power.interaction_hint().is_empty():
  prompt.text = power.interaction_hint()
  return
 var weather = get_parent().get_node_or_null("VillageLifeDirector/WeatherLifeDirector")
 if weather != null and not weather.interaction_hint().is_empty():
  prompt.text = weather.interaction_hint()
  return
 var contact = get_parent().get_node_or_null("VillageLifeDirector/ExpeditionContactDirector")
 if contact != null and not contact.interaction_hint().is_empty():
  prompt.text = contact.interaction_hint()
  return
 var regular = get_parent().get_node_or_null("VillageLifeDirector/RegularCustomerDirector")
 if regular != null and not regular.interaction_hint().is_empty():
  prompt.text = regular.interaction_hint()
  return
 var expansion = get_parent().get_node_or_null("VillageLifeDirector/VillageExpansionDirector")
 if expansion != null and not expansion.interaction_hint().is_empty():
  prompt.text = expansion.interaction_hint()
  return
 var seasonal = get_parent().get_node_or_null("VillageLifeDirector/SeasonalVillageDirector")
 if seasonal != null and not seasonal.interaction_hint().is_empty():
  prompt.text = seasonal.interaction_hint()
  return
 var rest = get_parent().get_node_or_null("VillageLifeDirector/VillageRestDirector")
 if rest != null and not rest.interaction_hint().is_empty():
  prompt.text = rest.interaction_hint()
  return
 var market = get_parent().get_node_or_null("VillageLifeDirector/VillageMarketDirector")
 if market != null and not market.interaction_hint().is_empty():
  prompt.text = market.interaction_hint()
  return
 var wayfarer = get_parent().get_node_or_null("LanternWayfarerDirector")
 if wayfarer != null and not wayfarer.interaction_hint().is_empty():
  prompt.text = wayfarer.interaction_hint()
  return
 var gathering = get_parent().get_node_or_null("VillageGatheringDirector")
 if gathering != null and not gathering.interaction_hint().is_empty():
  prompt.text = gathering.interaction_hint()
  return
 var board = get_parent().get_node_or_null("CommunityBoardDirector")
 if board != null and not board.interaction_hint().is_empty():
  prompt.text = board.interaction_hint()
  return
 var blacksmith = get_parent().get_node_or_null("BlacksmithDirector")
 if blacksmith != null and not blacksmith.interaction_hint().is_empty():
  prompt.text = blacksmith.interaction_hint()
  return
 var life = get_parent().get_node_or_null("VillageLifeDirector")
 if life != null and not life.interaction_hint().is_empty():
  prompt.text = life.interaction_hint()
  return
 var trade = get_parent().get_node_or_null("ResidentTradeDirector")
 if trade != null and not trade.interaction_hint().is_empty():
  prompt.text = trade.interaction_hint()
  return
 var smithy = get_parent().get_node_or_null("VillageSmithyDirector")
 if smithy != null and not smithy.interaction_hint().is_empty():
  prompt.text = smithy.interaction_hint()
  return
 if near_dungeon():
  prompt.text = "[E] 원정으로 출발하기"
  return
 if nearest_door(): prompt.text = "[E] 가게 닫기 · 영업 중" if manager.shop_open else "[E] 가게 열기 · 영업 종료"
 else: prompt.text = ""

func try_interact() -> bool:
 var recruitment = get_parent().get_node_or_null("EmployeeRecruitmentDirector")
 if recruitment != null and recruitment.try_interact(): return true
 var fishing = get_parent().get_node_or_null("FishingDirector")
 if fishing != null and fishing.try_interact(): return true
 var act_four = get_parent().get_node_or_null("VillageLifeDirector/ActFourDirector")
 if act_four != null and act_four.try_interact(): return true
 var power = get_parent().get_node_or_null("ManualCheckoutController/PowerRepairDirector")
 if power != null and power.try_interact(): return true
 var weather = get_parent().get_node_or_null("VillageLifeDirector/WeatherLifeDirector")
 if weather != null and weather.try_interact(): return true
 var contact = get_parent().get_node_or_null("VillageLifeDirector/ExpeditionContactDirector")
 if contact != null and contact.try_interact(): return true
 var regular = get_parent().get_node_or_null("VillageLifeDirector/RegularCustomerDirector")
 if regular != null and regular.try_interact(): return true
 if blocked(): return false
 var expansion = get_parent().get_node_or_null("VillageLifeDirector/VillageExpansionDirector")
 if expansion != null and expansion.try_interact(): return true
 var seasonal = get_parent().get_node_or_null("VillageLifeDirector/SeasonalVillageDirector")
 if seasonal != null and seasonal.try_interact(): return true
 var rest = get_parent().get_node_or_null("VillageLifeDirector/VillageRestDirector")
 if rest != null and rest.try_interact(): return true
 var market = get_parent().get_node_or_null("VillageLifeDirector/VillageMarketDirector")
 if market != null and market.try_interact(): return true
 var wayfarer = get_parent().get_node_or_null("LanternWayfarerDirector")
 if wayfarer != null and wayfarer.try_interact(): return true
 var gathering = get_parent().get_node_or_null("VillageGatheringDirector")
 if gathering != null and gathering.try_interact(): return true
 if blocked(): return false
 var tutorial = get_parent().get_node_or_null("TutorialDirector")
 if tutorial != null and tutorial.try_interact(): return true
 var requests = get_parent().get_node_or_null("ResidentRequestDirector")
 if requests != null and requests.try_interact(): return true
 var board = get_parent().get_node_or_null("CommunityBoardDirector")
 if board != null and board.try_interact(): return true
 var blacksmith = get_parent().get_node_or_null("BlacksmithDirector")
 if blacksmith != null and blacksmith.try_interact(): return true
 var life = get_parent().get_node_or_null("VillageLifeDirector")
 if life != null and life.try_interact(): return true
 var trade = get_parent().get_node_or_null("ResidentTradeDirector")
 if trade != null and trade.try_interact(): return true
 var smithy = get_parent().get_node_or_null("VillageSmithyDirector")
 if smithy != null and smithy.try_interact(): return true
 var cashier = get_parent().get_node_or_null("ManualCheckoutController")
 if cashier != null and cashier.try_interact(): return true
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
