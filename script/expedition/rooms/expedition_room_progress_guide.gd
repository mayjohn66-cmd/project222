class_name ExpeditionRoomProgressGuide
extends Node
## Runtime-only prerequisites and next action; no rolls, rewards or save fields.
const ENABLED := true
var controller: ExpeditionRoomController
var bound_model: ExpeditionRoomModel

func bind_model() -> void:
	clear_model()
	if not ENABLED: return
	bound_model = controller.model
	bound_model.interaction_guard = allows_interaction

func clear_model() -> void:
	if bound_model != null: bound_model.interaction_guard = Callable()
	bound_model = null

func missing_tool() -> String:
	var model := controller.model
	if model == null or model.finished or model.object_consumed or model.object_kind != "gather": return ""
	if model.extra_interaction_label.is_valid() and not str(model.extra_interaction_label.call()).is_empty(): return ""
	model.interaction_label() # Same nearest reachable site as the interaction button.
	if model.player_position.distance_to(model.object_position) > model.settings.interaction_reach or model._wall_between(model.player_position,model.object_position): return ""
	var table := model.selected_loot_table
	if table.is_empty(): table = str(controller.event.get("target_id",""))
	var rule := ExpeditionGatheringData.get_rule(table)
	if not bool(rule.get("tool_required",false)): return ""
	var effect := str(rule.get("tool_effect_id",""))
	if not controller.host.expedition_gathering_service._find_tool_placement(controller.host.expedition_bag,effect).is_empty(): return ""
	ExpeditionEquipmentData.ensure_loaded()
	for id in ExpeditionEquipmentData.equipment:
		if ExpeditionEquipmentData.get_equipment_type(id) == ExpeditionEquipmentData.TYPE_TOOL and ExpeditionEquipmentData.get_effect_id(id) == effect:
			return ItemData.get_item_name(id)
	return UiText.t("expedition.room.required_tool")

func allows_interaction() -> bool:
	if not ENABLED: return true
	return missing_tool().is_empty()

func hint(fallback: String) -> String:
	if not ENABLED or controller.model == null: return fallback
	var model := controller.model
	if model.finished: return fallback
	if model.interacting:
		return UiText.f("expedition.room.progress",[model.interaction_label(),roundi(100.0 * model.interaction_progress / model.interaction_seconds())])
	var missing := missing_tool()
	if not missing.is_empty():
		return UiText.f("expedition.room.missing_tool",[missing]) + "\n" + UiText.t("expedition.room.other_site" if model.gathering_sites.size() > 1 else "expedition.room.skip_gather")
	if model.extra_interaction_label.is_valid() and not str(model.extra_interaction_label.call()).is_empty():
		return UiText.t("expedition.room.contact")
	var exit_hint := UiText.t("expedition.room.exit")
	var caption := model.interaction_label()
	if model.object_consumed:
		return (controller.view.notice + "\n" if not controller.view.notice.is_empty() else "") + exit_hint
	if not caption.is_empty() and caption != "다음 방으로":
		return UiText.f("expedition.room.interact",[caption])
	if model.exit_open:
		if not controller.view.notice.is_empty(): return controller.view.notice + "\n" + exit_hint
		return exit_hint
	return fallback

func _exit_tree() -> void:
	clear_model()
