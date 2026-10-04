class_name SeasonStockpileFlow
extends RefCounted
const SETTINGS = preload("res://scenes/shop/requests/default_season_stockpile.tres")

static func locked_reason(entry: Dictionary, started: bool) -> String:
	var season := str(entry.get("stockpile_season", ""))
	if season.is_empty() or started: return ""
	if CalendarData.get_season_id(GameState.total_day) == season: return ""
	return "%s에 보관한 재료를 찾는 부탁이 찾아옵니다. 맡으면 기한 없이 이어갈 수 있어요." % ExpeditionEnvironment.SEASONS.get(season, season)
