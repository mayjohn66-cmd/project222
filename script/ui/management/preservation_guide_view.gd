class_name PreservationGuideView
extends Node
var host: PreservationPanel
var signature := ""
var elapsed := 0.0
const REFRESH_SECONDS := 0.5

func _ready() -> void:
	host = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS

func current_state() -> String:
	var records := {}
	for key in PlayerProgress.story_beat_days:
		if str(key).begins_with(PreservationLessonFlow.PREFIX) or str(key).begins_with(FishingRecords.PREFIX + "caught:"):
			records[key] = PlayerProgress.story_beat_days[key]
	var residents: Array[bool] = []
	for entry in VillageLifeFlow.SETTINGS.residents: residents.append(VillageLifeFlow.available(entry))
	return str([GameState.total_day,GameState.money,GameState.inventory,GameState.preservation_state,PlayerProgress.learned_recipe_ids,records,CommunityRequestFlow.board_available(),residents,host.unit_filter])

func remember_state() -> void:
	signature = current_state()

func _process(delta: float) -> void:
	if not PreservationGuide.ENABLED or not host.visible: return
	elapsed += delta
	if elapsed < REFRESH_SECONDS: return
	elapsed = 0
	PreservationService.settle()
	var state := current_state()
	if state == signature or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): return
	host.refresh()
	remember_state()
