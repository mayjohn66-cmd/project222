class_name VillageJournalPanel
extends CommunityBoardPanel

var world: Node
var tracked_id := ""

func entries() -> Array[Dictionary]: return VillageJournalFlow.entries()
func panel_title() -> String: return "마을 수첩"
func introduction() -> String: return "이웃과 함께한 날을 확인하세요. 목적지를 표시한 뒤 수첩을 닫고 직접 걸어가세요."

func refresh() -> void:
	count_label.text = "%s · 마을 평판 %d" % [ResidentStoryFlow.place_name(),ResidentRequestFlow.reputation()]
	for entry in entries():
		var id := str(entry["id"])
		var card: Dictionary = cards[id]
		card["info"].text = VillageJournalFlow.information(id)
		if id.begins_with("resident:"):
			var resident = VillageJournalFlow.destination(world,id)
			if resident != null: card["info"].text += "\n현재: " + resident.routine_status()
		var target := VillageJournalFlow.destination(world,id)
		card["action"].text = "목적지 표시 해제" if tracked_id == id else "목적지 표시"
		card["action"].disabled = target == null and tracked_id != id
