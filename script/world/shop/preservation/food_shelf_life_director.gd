class_name FoodShelfLifeDirector
extends Node
## One consolidated, non-modal morning notice. Reopening menus never repeats it.
var elapsed: float = 0.0

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 1.0: return
	elapsed = 0.0
	var world := get_parent().get_parent()
	var guide := world.get_node_or_null("TutorialDirector")
	var manager := world.get_node_or_null("DayManager")
	var interactions := world.get_node_or_null("WorldInteractions")
	if manager == null or interactions == null or manager.summary_open: return
	if manager.current_hour != GameConfig.DAY_START_HOUR: return
	if guide != null and guide.talking: return
	if get_tree().paused or interactions.blocked(): return
	var notice := FoodShelfLife.claim_morning_notice()
	if not notice.is_empty(): interactions.show_message(notice + "\n메뉴 → 운영 → 인벤토리 → 식품 관리")
