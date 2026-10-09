class_name StoreEventPreparationView
extends Node
var host: Control
var world: Node
var event: Dictionary
var card: PanelContainer
var body: VBoxContainer
var label: Label
var actions: VBoxContainer
var signature := ""
var elapsed := 0.0

static func attach(menu: Control, data: Dictionary) -> void:
	if not StoreEventPreparation.ENABLED or StoreEventPreparation.items(data).is_empty(): return
	var view := StoreEventPreparationView.new()
	view.host = menu
	view.event = data.duplicate(true)
	view.world = menu
	while view.world != null and view.world.get_node_or_null("DayManager") == null: view.world = view.world.get_parent()
	if view.world == null: view.free(); return
	var panel := PanelContainer.new()
	view.card = panel
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_" + side,16)
	panel.add_child(margin)
	view.body = VBoxContainer.new()
	view.body.add_theme_constant_override("separation",10)
	margin.add_child(view.body)
	view.label = Label.new()
	view.label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	view.label.add_theme_font_size_override("font_size",17)
	view.body.add_child(view.label)
	view.actions = VBoxContainer.new()
	view.body.add_child(view.actions)
	panel.add_child(view)
	menu.schedule_list.add_child(panel)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh()

func _process(delta: float) -> void:
	if not host.is_visible_in_tree() or not host.schedule_content.visible: return
	elapsed += delta
	if elapsed < 0.5: return
	elapsed = 0
	refresh()

func refresh() -> void:
	var text := StoreEventPreparation.summary(world,event)
	card.visible = not text.is_empty()
	var available := []
	if host.space_menu.tab_available(ManagementTabs.MenuTab.PRODUCTION) and is_instance_valid(host.management_production.preparation_book):
		for item in StoreEventPreparation.items(event):
			for recipe in StoreEventPreparation.recipes(item):
				available.append({"item":item,"recipe":str(recipe["recipe_id"])})
	var title := StoreEventStory.title(event,GameState.total_day)
	var state := JSON.stringify([title,text,available])
	if signature == state: return
	signature = state
	label.text = "상품 준비 · " + title + "\n\n" + text
	for child in actions.get_children(): actions.remove_child(child); child.queue_free()
	for entry in available:
		var button := Button.new()
		button.text = "상품 준비 · " + FishingData.recipe_name(ProductRecipeData.get_recipe(entry["recipe"]))
		button.custom_minimum_size.y = 42
		button.clip_text = true
		button.tooltip_text = button.text
		button.add_theme_font_size_override("font_size",17)
		actions.add_child(button)
		button.pressed.connect(open_recipe.bind(entry["item"],entry["recipe"]))

func open_recipe(item: String, id: String) -> void:
	if item not in StoreEventPreparation.items(event) or not StoreEventPreparation.recipes(item).any(func(recipe): return recipe["recipe_id"] == id): return
	if not host.space_menu.tab_available(ManagementTabs.MenuTab.PRODUCTION): return
	var book: ProductPreparationBook = host.management_production.preparation_book
	if not is_instance_valid(book): return
	host.select_tab(ManagementTabs.MenuTab.PRODUCTION)
	book.only_ready.set_pressed_no_signal(false)
	book.refresh()
	book.select_tab("learned")
	book.select_entry(id)
