class_name SaveSlotSummary
extends RefCounted
## Describe the selected file without applying it or reading current play progress.
const ENABLED := true

static func describe(data: Dictionary, modified_time: int) -> String:
	var day := int(data.get("total_day", data.get("current_day", 1)))
	var place := UiText.f("save.slot.store", ["%02d:00" % GameConfig.DAY_START_HOUR])
	var checkpoint: Variant = data.get("expedition_checkpoint", {})
	if str(data.get("resume_scene_id", "")) == GameState.RESUME_SCENE_EXPEDITION and checkpoint is Dictionary and not checkpoint.is_empty():
		place = UiText.t("save.slot.expedition")
	var progress: Variant = data.get("progress", {})
	var name := PlayerProgress.clean_player_name(str(progress.get("player_name", ""))) if progress is Dictionary else ""
	if name.is_empty(): name = PlayerProgress.DEFAULT_PLAYER_NAME
	return UiText.f("save.slot.summary", [CalendarData.get_display_date(day), place, name, int(data.get("money", 0)), datetime(modified_time)])

static func datetime(unix_time: int) -> String:
	if unix_time <= 0: return UiText.t("save.slot.unknown_time")
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var value := Time.get_datetime_dict_from_unix_time(unix_time + bias * 60)
	return "%04d-%02d-%02d %02d:%02d" % [value["year"], value["month"], value["day"], value["hour"], value["minute"]]
