class_name ProductPreparationBook
extends Control
const REFRESH_SECONDS := 1.0
var host
var world: Node
var mode := "today"
var selected := ""
var list: VBoxContainer
var detail: VBoxContainer
var list_scroll: ScrollContainer
var detail_scroll: ScrollContainer
var tabs := {}
var entries: Array[Dictionary] = []
var notes := {}
var only_ready: CheckBox
var summary: Label
var elapsed := 0.0
var signature := ""
var revision := 0
var viewed := false
func _ready() -> void:
	host = get_parent()
	world = host
	while world != null and world.get_node_or_null("DayManager") == null: world = world.get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.anchor_right = 0.5
	bar.offset_right = -BookLayout.GUTTER * 0.5
	bar.offset_bottom = 42
	bar.add_theme_constant_override("separation",6)
	add_child(bar)
	for entry in [["today","오늘의 준비"],["learned","배운 상품"],["facilities","설비 현황"]]:
		var button := Button.new()
		button.text = entry[1]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 42
		button.add_theme_font_size_override("font_size",UiTypography.size(16))
		button.clip_text = true
		bar.add_child(button)
		tabs[entry[0]] = button
		button.pressed.connect(select_tab.bind(entry[0]))
	var body := HBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_top = 56
	body.add_theme_constant_override("separation",int(BookLayout.GUTTER))
	add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1
	body.add_child(left)
	summary = text(left,"",17)
	only_ready = CheckBox.new()
	only_ready.text = "지금 만들 수 있는 상품만"
	only_ready.add_theme_font_size_override("font_size",UiTypography.size(16))
	left.add_child(only_ready)
	only_ready.toggled.connect(func(_value): selected = ""; refresh())
	list_scroll = ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(list_scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",10)
	list_scroll.add_child(list)
	detail_scroll = ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_stretch_ratio = 1
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(detail_scroll)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation",12)
	detail_scroll.add_child(detail)
	refresh()
func _process(delta: float) -> void:
	if not host.is_visible_in_tree(): return
	elapsed += delta
	if elapsed < REFRESH_SECONDS: return
	elapsed = 0
	refresh(false)
func select_tab(value: String) -> void:
	mode = value
	selected = ""
	list_scroll.scroll_vertical = 0
	detail_scroll.scroll_vertical = 0
	refresh()
func clear(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()
func text(parent: Node, value: String, font := 18) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",UiTypography.size(font))
	parent.add_child(label)
	return label
func refresh(force := true) -> void:
	if world == null: return
	if is_visible_in_tree() and not viewed:
		viewed = true
		mode = "today"
		selected = ""
	notes = ProductPreparationContext.notes()
	var recipes := ProductPreparationData.entries(world,notes)
	var machines := ProductPreparationData.facility_entries(world)
	# Default drying recipes are usable later, but do not lead the first store lesson.
	var first_steps := ProductNextStepGuidance.ENABLED and ProductNextStepGuidance.first_steps()
	if first_steps:
		recipes = []
		machines = []
	var state := str([GameState.inventory, GameState.preservation_state, PlayerProgress.learned_recipe_ids, PlayerProgress.story_beat_days, recipes, _machine_state(machines), ProductPreparationData.storage_state(world), mode, only_ready.button_pressed])
	if not force and state == signature: return
	signature = state
	var scroll := list_scroll.scroll_vertical
	var detail_position := detail_scroll.scroll_vertical
	revision += 1
	clear(list)
	for key in tabs: InteractionUiStyle.select_tab(tabs[key],key == mode)
	only_ready.visible = mode == "today" and not first_steps
	entries = machines if mode == "facilities" else recipes
	if mode == "learned": entries.sort_custom(func(a,b): return a["title"] < b["title"])
	if mode == "today" and only_ready.button_pressed: entries = entries.filter(func(entry): return entry["status"] == "지금 만들 수 있음")
	summary.text = "설치한 설비와 배운 상품에 필요한 설비를 살펴봅니다." if mode == "facilities" else ("들은 소문과 맡은 부탁을 먼저 살펴봅니다." if mode == "today" else "배운 제조법의 재료와 출처를 확인합니다.")
	if first_steps: summary.text = "첫 제작을 위한 준비"
	if not entries.any(func(entry): return str(entry["id"]) == selected): selected = "" if entries.is_empty() else str(entries[0]["id"])
	for entry in entries:
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 62
		button.add_theme_font_size_override("font_size",UiTypography.size(18))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.text = host.get_facility_display_name(entry["facility_id"]) + "\n" + ProductPreparationData.facility_summary(world,entry) if mode == "facilities" else str(entry["title"]) + "\n" + str(entry["status"]) + (" · 이야기 있음" if not entry["notes"].is_empty() else "")
		button.tooltip_text = button.text
		button.pressed.connect(select_entry.bind(str(entry["id"])))
		list.add_child(button)
		if entry["id"] == selected: button.disabled = true
	if entries.is_empty():
		text(list,("오른쪽에서 지금 할 일을 확인하세요." if first_steps else ProductNextStepGuidance.empty_message(mode,only_ready.button_pressed)) if ProductNextStepGuidance.ENABLED else ("조건에 맞는 상품이 없습니다. 필터를 바꾸거나 이웃과 제조법을 배워 보세요." if mode != "facilities" else "아직 필요한 설비가 없습니다. 먼저 배운 상품을 살펴보세요."))
	_render_detail()
	_restore_scroll.call_deferred(scroll,detail_position,revision)
func _restore_scroll(left: int, right: int, version: int) -> void:
	await get_tree().process_frame
	if version != revision: return
	list_scroll.scroll_vertical = left
	detail_scroll.scroll_vertical = right
func _machine_state(entries_: Array[Dictionary]) -> Array:
	var values := []
	for entry in entries_:
		var node = entry["node"]
		if is_instance_valid(node): values.append([node.get_instance_id(),node.production_state,node.remaining_seconds,node.pending_item_id,node.pending_amount])
	return values
func select_entry(id: String) -> void:
	selected = id
	detail_scroll.scroll_vertical = 0
	if mode != "facilities": host.selected_recipe_id = id
	refresh()
func _render_detail() -> void:
	clear(detail)
	for entry in entries:
		if str(entry["id"]) != selected: continue
		if mode == "facilities": _facility_detail(entry)
		else: _recipe_detail(entry)
		return
	text(detail,ProductNextStepGuidance.empty_title() if ProductNextStepGuidance.ENABLED else "오늘 필요한 것을 천천히 준비해 보세요.",22)
	text(detail,ProductNextStepGuidance.empty_message(mode,only_ready.button_pressed) if ProductNextStepGuidance.ENABLED else "제작과 완성품 수령은 현장 설비에서 진행합니다. 원정 재료를 그대로 진열해도 됩니다.")
func _recipe_detail(entry: Dictionary) -> void:
	var recipe: Dictionary = entry["recipe"]
	var item := str(recipe["result_item_id"])
	text(detail,str(entry["title"]) + " ×" + str(recipe["result_amount"]),22)
	text(detail,str(entry["status"]) + " · 1회 " + str(recipe["craft_time"]) + "초")
	text(detail,"필요 설비 · " + host.get_facility_display_name(str(recipe["facility_id"])))
	text(detail,ProductPreparationContext.source(recipe),16)
	for note in entry["notes"]: text(detail,str(note),17)
	text(detail,"1회분 재료",20)
	var ingredients := ProductionRecipeService.collect_required_ingredients(recipe,1)
	for id in ingredients:
		var need := int(ingredients[id])
		var owned := GameState.get_item_count(str(id))
		var stored := ProductPreparationData.shelf_count(world,str(id))
		var line := "%s · 소지 %d / 필요 %d" % [ItemData.get_item_name(str(id)),owned,need]
		if owned < need: line += " · %d개 부족" % (need-owned)
		if stored > 0: line += "\n창고 선반 %d개 · 꺼낸 뒤 사용할 수 있습니다." % stored
		var preserved := ProductPreparationData.preservation_note(str(id))
		if not preserved.is_empty(): line += "\n" + preserved
		text(detail,line)
		for note in notes.get(str(id),[]): text(detail,"이 재료를 사용하는 이야기 · " + str(note),16)
	var stock := GameState.get_item_count(item)
	text(detail,"완성품 소지 " + str(stock) + "개",17)
	var action := "설비에서 [E]로 제조법을 선택하세요."
	match str(entry["status"]):
		"생산실 마련": action = "생산실 문을 설치해 첫 공간을 마련하세요."
		"첫 상품 수령 먼저": action = "먼저 화덕에서 현지식 빵을 만들고 수령하세요."
		"설비 설치": action = "필요 설비를 현장에 설치하세요."
		"완성품 수령 먼저": action = "설비에서 [E]로 완성품을 수령하세요."
		"설비 사용 중": action = "가공이 끝나길 기다린 뒤 설비에서 [E]로 완성품을 수령하세요. 책을 열어 둔 동안 가공도 멈춥니다."
		"재료 준비": action = "부족한 재료를 소지품에 챙긴 뒤 설비에서 [E]로 제조법을 선택하세요."
	text(detail,"책을 닫고 " + action,17)
func _facility_detail(entry: Dictionary) -> void:
	var id := str(entry["facility_id"])
	text(detail,host.get_facility_display_name(id),22)
	var node = entry["node"]
	if is_instance_valid(node):
		text(detail,"위치 · " + ProductPreparationData.location(world,node))
		match node.production_state:
			ProductionFacility.ProductionState.IDLE: text(detail,"재료 준비 대기")
			ProductionFacility.ProductionState.PROCESSING: text(detail,"가공 중 · %s ×%d · %d초 남음" % [ItemData.get_item_name(node.pending_item_id),node.pending_amount,ceili(node.remaining_seconds)])
			ProductionFacility.ProductionState.READY: text(detail,"완성품 수령 대기 · %s ×%d" % [ItemData.get_item_name(node.pending_item_id),node.pending_amount])
	else: text(detail,"미설치 · 배운 상품에 필요한 설비입니다.")
	var products: Array[String] = []
	for recipe in ProductRecipeData.get_learned_recipes():
		var name := ItemData.get_item_name(str(recipe["result_item_id"]))
		if recipe["facility_id"] == id and name not in products: products.append(name)
	text(detail,"배운 상품에 사용하는 설비",20)
	text(detail," · ".join(products.slice(0,ProductPreparationData.MAX_EXAMPLES)) if not products.is_empty() else "이 설비에서 사용할 배운 제조법이 아직 없습니다.")
	text(detail,ProductNextStepGuidance.facility_action(world,entry) if ProductNextStepGuidance.ENABLED else "책을 닫고 현장에서 [E]로 재료를 가공하거나 완성품을 수령하세요.")
