class_name DaySummaryPreparation
extends CenterContainer
## Keep the original summary label and button paths as DayManager's contract.
const ENABLED := true
var source: Label
var result_text: Label
var guidance: Label
var scroll: ScrollContainer
var panel: PanelContainer
var confirm: Button
var world: Node
var manager: Node
var interaction_hint: Control
var hint_was_visible := false
var owns_hint := false

func _ready() -> void:
	if ENABLED: call_deferred("_setup")

func _setup() -> void:
	world = InventoryItemGuide.world(self)
	if world == null: return
	manager = world.get_node("DayManager")
	z_index = 100
	interaction_hint = world.get_node_or_null("UI/WorldInteractionHint")
	panel = $DaySummaryPanel
	var column: VBoxContainer = $DaySummaryPanel/VBoxContainer
	source = column.get_node("SummaryText")
	confirm = column.get_node("NextDayButton")
	scroll = ScrollContainer.new()
	scroll.name = "PreparationScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	column.move_child(scroll, source.get_index())
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	scroll.add_child(body)
	result_text = _label(body)
	guidance = _label(body)
	source.hide()
	confirm.custom_minimum_size.y = 44
	column.add_theme_constant_override("separation", 12)
	visibility_changed.connect(_opened)
	resized.connect(_fit)
	_fit()
	_opened()

func _label(parent: Node) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("51382d"))
	parent.add_child(label)
	return label

func _fit() -> void:
	if panel == null: return
	var bounds := get_viewport_rect().size
	panel.custom_minimum_size = Vector2(minf(720, bounds.x - 48), minf(560, bounds.y - 48))

func _opened() -> void:
	if result_text == null: return
	if not is_visible_in_tree():
		if owns_hint and is_instance_valid(interaction_hint): interaction_hint.visible = hint_was_visible
		owns_hint = false
		return
	if is_instance_valid(interaction_hint) and not owns_hint:
		hint_was_visible = interaction_hint.visible
		interaction_hint.hide()
		owns_hint = true
	result_text.text = source.text
	guidance.text = "\n\n".join(notes(world, manager))
	confirm.text = UiText.f("day.preparation.confirm", ["%02d:00" % GameConfig.DAY_START_HOUR])
	scroll.scroll_vertical = 0

func _process(_delta: float) -> void:
	if result_text != null and is_visible_in_tree() and result_text.text != source.text:
		result_text.text = source.text

static func notes(shop: Node, day_manager: Node) -> Array[String]:
	var result: Array[String] = []
	if not ENABLED: return result
	result.append(UiText.f("day.preparation.transition", ["%02d:00" % GameConfig.DAY_START_HOUR]))
	if not OpeningJourneyFlow.core_finished():
		result.append(UiText.t("day.preparation.tutorial"))
		return result
	result.append(UiText.t("day.preparation.food"))
	for unit in shop.get_tree().get_nodes_in_group("preservation_unit"):
		if shop.is_ancestor_of(unit) and not unit.is_queued_for_deletion() and not unit.get_meta("is_build_preview", false):
			result.append(UiText.t("day.preparation.cold"))
			break
	var hired := false
	var accrued := false
	for id in EmployeeData.get_all_employee_ids():
		hired = hired or bool(GameState.get_employee_state(id).get("is_hired", false))
		accrued = accrued or int(GameState.employee_salary_records.get(id, {}).get("accrued_days", 0)) > 0
	if hired: result.append(UiText.t("day.preparation.staff"))
	if CalendarData.get_day_of_season(GameState.total_day) == CalendarData.DAYS_PER_SEASON and (hired or accrued):
		result.append(UiText.t("day.preparation.salary_period"))
	var debt := GameState.get_unpaid_employee_salary()
	if debt > 0: result.append(UiText.f("day.preparation.salary_debt", [debt]))
	result.append(UiText.t("day.preparation.open") if day_manager.can_open_shop() else UiText.t("day.preparation.furniture"))
	return result
