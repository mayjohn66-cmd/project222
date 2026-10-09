class_name ExpeditionRoomController
extends RefCounted

const ROOM_SCENE = preload("res://scenes/expedition/rooms/expedition_room.tscn")
const SETTINGS = preload("res://scenes/expedition/rooms/default_room_settings.tres")
var host
var view: ExpeditionRoomView
var model: ExpeditionRoomModel
var loadout: ExpeditionWeaponLoadout = ExpeditionWeaponLoadout.new()
var event: Dictionary = {}
var node_type: String = ""
var pending_loot: Array[Dictionary] = []
var boss: bool = false
var map_retreat_button: Button
var contact: ExpeditionContactRoom

func setup(new_host) -> void:
	host = new_host
	view = ROOM_SCENE.instantiate()
	host.get_node("UI").add_child(view)
	contact = ExpeditionContactRoom.new()
	contact.controller = self
	view.add_child(contact)
	view.z_index = 10
	view.hide()
	view.progress_guide = ExpeditionRoomProgressGuide.new()
	view.progress_guide.controller = self
	view.add_child(view.progress_guide)
	view.blocked = Callable(self, "_menu_open")
	view.retreat_requested.connect(_retreat)
	map_retreat_button = Button.new()
	map_retreat_button.text = "철수"
	map_retreat_button.position = Vector2(16, 16)
	map_retreat_button.custom_minimum_size = Vector2(80, 40)
	map_retreat_button.z_index = 10
	host.get_node("UI").add_child(map_retreat_button)
	map_retreat_button.pressed.connect(func(): host.open_result_phase(host.ExpeditionEndReason.RETREAT))
	host.map_panel.visibility_changed.connect(_sync_retreat_button)
	view.visibility_changed.connect(_sync_retreat_button)
	_sync_retreat_button()

func _sync_retreat_button() -> void:
	map_retreat_button.visible = host.current_expedition_phase == host.ExpeditionPhase.RUN \
		and host.map_panel.visible and not is_active()

func is_active() -> bool:
	return is_instance_valid(view) and view.visible

func _menu_open() -> bool:
	return (contact != null and contact.open) or host.game_menu.menu_open or host.game_menu.settings_panel.visible \
		or host.game_menu.save_slot_panel.visible or host.management_menu.visible \
		or host.game_menu.quit_game_dialog.visible or host.game_menu.return_title_dialog.visible

func enter(event_data: Dictionary, room_type: String) -> void:
	host.expedition_loot_service.environment = host.expedition_map.environment.duplicate(true)
	event = event_data.duplicate(true)
	node_type = room_type
	boss = node_type == ExpeditionMap.NODE_BOSS
	pending_loot.clear()
	retreat_pending = false
	host.apply_bag_equipment_stats()
	var result_type: String = str(event.get("result_type", "none"))
	var enemy: Dictionary = EnemyData.get_enemy(str(event.get("target_id", ""))) if result_type == "battle" else {}
	if not enemy.is_empty(): enemy["id"] = str(event.get("target_id", ""))
	var kind: String = ""
	if result_type == "loot": kind = "gather" if room_type == ExpeditionMap.NODE_GATHER else "chest"
	if result_type == "heal": kind = "heal"
	# 가방의 무기(최대 2개) 중 처음 든 무기로 시작하고, 방 안에서 교체할 수 있다.
	loadout.build(SETTINGS, host.expedition_bag)
	model = ExpeditionRoomModel.new()
	model.setup(SETTINGS, loadout.active_profile(), host.combat_player_hp,
		host.combat_player_max_hp, host.BASE_PLAYER_ATTACK + loadout.active_bonus(), host.combat_player_defense,
		enemy, host.get_run_difficulty(), boss, kind, loadout)
	var region_profile: Dictionary = model.CONTENT.region_profile(host.current_region_id)
	model.configure_region(region_profile)
	model.configure_gathering(model.CONTENT.gathering(str(event.get("event_id", ""))))
	model.object_used.connect(_object_used)
	model.enemies_cleared.connect(_enemies_cleared)
	model.exited.connect(_exit)
	model.defeated.connect(_defeat)
	view.model = model
	view.notice = "두 지점 중 한 곳에서 [E] · 한 방에서 한 곳만 채집할 수 있어요." if model.gathering_sites.size() > 1 else ("채집 지점에 다가가 [E] · 한 번만 채집할 수 있어요." if model.gathering_sites.size() == 1 else "")
	view.title_label.text = "%s · %s" % [str(ExpeditionMapData.get_region_data(host.current_region_id).get("name", host.current_region_id)),
		host.get_map_node_display_name(room_type)]
	view.region_id = host.current_region_id
	view.title_label.text += " · " + ExpeditionEnvironment.label(host.expedition_map.environment)
	view.weather_overlay.environment = host.expedition_map.environment.duplicate(true)
	view.weather_overlay.environment["indoors"] = region_profile.get("floor", "grass") == "paving"
	view.weather_overlay.queue_redraw()
	view.ground_overlay = ExpeditionEnvironment.ground_overlay(host.expedition_map.environment, region_profile.get("floor", "grass") == "grass")
	host.map_panel.hide()
	host.bag_panel.hide()
	host.battle_panel.hide()
	host.battle_timer.stop()
	host.battle_active = true # 방 진행 중에는 체크포인트 저장/지도 선택을 막는다.
	view.show()
	contact.enter()
	view.progress_guide.bind_model()

func _enemies_cleared() -> void:
	# 방 전체 보상은 한 번만 굴린다. 몬스터 수가 드롭량을 늘리지 않는다.
	host.combat_enemy_id = str(event.get("target_id", ""))
	host.expedition_battle_controller.generate_loot(host.combat_enemy_id)
	pending_loot = host.temporary_loot.duplicate(true)
	host.temporary_loot.clear()
	view.notice = "몬스터 처치! 출구로 이동하세요."
	if boss:
		model.finished = true
		# 공격 반복문의 호출 스택을 벗어난 뒤 결과 흐름으로 넘어간다.
		Callable(self, "_exit").call_deferred()

func _object_used() -> void:
	if model.object_kind == "heal":
		var healed: int = mini(maxi(0, int(event.get("value", 0))), model.player_max_hp - model.player_hp)
		model.player_hp += healed
		view.notice = "체력을 회복했다" if healed > 0 else "체력이 가득 차 있다"
		return
	var table_id: String = str(event.get("target_id", ""))
	if not model.selected_loot_table.is_empty(): table_id = model.selected_loot_table
	var result: Dictionary = host.expedition_gathering_service.resolve_gathering(table_id,
		host.expedition_bag, host.expedition_loot_service, host.get_run_difficulty())
	if not bool(result.get("handled", false)):
		result = host.expedition_loot_service.roll_loot_table(table_id, host.get_run_difficulty())
	if not bool(result.get("success", false)) or not bool(result.get("gathered", true)):
		view.notice = str(result.get("message", "채집하지 못했습니다."))
		return
	var item_id: String = str(result.get("item_id", ""))
	var amount: int = int(result.get("amount", 0))
	if not item_id.is_empty() and amount > 0:
		pending_loot.append({"item_id": item_id, "amount": amount})
		if model.object_kind == "gather": VillageExpansionFlow.record_gather(host.current_region_id,item_id,amount)
		view.notice = "%s ×%d 획득" % [ItemData.get_item_name(item_id), amount]

func _close() -> void:
	contact.clear()
	view.progress_guide.clear_model()
	host.combat_player_hp = model.player_hp
	host.battle_active = false
	view.hide()
	host.bag_panel.show()
	host.update_battle_ui()

func _exit() -> void:
	if not is_active(): return
	_close()
	host.temporary_loot = pending_loot.duplicate(true)
	if host.temporary_loot.is_empty():
		host.complete_current_map_node()
	else:
		host.refresh_loot_ui()
		host.loot_panel.show()

func _defeat() -> void:
	_close()
	host.temporary_loot.clear()
	host.open_result_phase(host.ExpeditionEndReason.DEFEAT)

func _retreat() -> void:
	model.finished = true
	_close()
	# 방에서 아직 가방에 정리하지 않은 보상은 철수 전에 정리한다.
	if not pending_loot.is_empty():
		host.temporary_loot = pending_loot.duplicate(true)
		host.refresh_loot_ui()
		host.loot_panel.show()
		retreat_pending = true
	else:
		host.selected_map_node_id = ""
		host.open_result_phase(host.ExpeditionEndReason.RETREAT)

var retreat_pending: bool = false

func finish_retreat() -> bool:
	if not retreat_pending: return false
	retreat_pending = false
	host.selected_map_node_id = ""
	host.open_result_phase(host.ExpeditionEndReason.RETREAT)
	return true
