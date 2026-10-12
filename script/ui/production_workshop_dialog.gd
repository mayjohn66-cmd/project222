extends AcceptDialog

var hero_title: Label
var hero_icon: TextureRect
var subtitle: Label
var ingredients: HBoxContainer
var result_box: VBoxContainer
var notice: Label
var progress: ProgressBar
var timing: Label
var current_recipe: Dictionary = {}
var batch: int = 1
var total_seconds: float = 1.0

func paper(color: String, padding: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color)
	style.set_content_margin_all(padding)
	return style

func label(text_value: String, font_size: int = 16) -> Label:
	var text_label := Label.new()
	text_label.text = text_value
	text_label.add_theme_font_size_override("font_size",UiTypography.size(font_size))
	text_label.add_theme_color_override("font_color",Color("51382d"))
	return text_label

func icon(texture: Texture2D, pixels: int = 48) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.custom_minimum_size = Vector2(pixels,pixels)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return image

func _ready() -> void:
	about_to_popup.connect(_fit_workshop)
	get_ok_button().add_theme_color_override("font_color",Color("51382d"))
	add_theme_stylebox_override("panel",paper("f5e5c9",18))
	var backdrop := KitchenBackdrop.new()
	backdrop.dialog = self
	add_child(backdrop)
	move_child(backdrop,0)
	size_changed.connect(backdrop.queue_redraw)
	var content: VBoxContainer = $Content
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation",16)
	hero_icon = icon(null,56)
	hero.add_child(hero_icon)
	var words := VBoxContainer.new()
	hero_title = label("조리 작업대",24)
	subtitle = label("재료를 준비하고, 정성껏 완성하세요.",14)
	words.add_child(hero_title)
	words.add_child(subtitle)
	hero.add_child(words)
	content.add_child(hero)
	content.move_child(hero,0)
	var flow := HBoxContainer.new()
	flow.name = "RecipeFlow"
	flow.add_theme_constant_override("separation",12)
	var input_paper := PanelContainer.new()
	input_paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_paper.add_theme_stylebox_override("panel",paper("e8d4af"))
	var input_column := VBoxContainer.new()
	input_column.add_child(label("재료 준비",16))
	ingredients = HBoxContainer.new()
	ingredients.add_theme_constant_override("separation",12)
	input_column.add_child(ingredients)
	input_paper.add_child(input_column)
	flow.add_child(input_paper)
	var arrow := label("→",28)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	flow.add_child(arrow)
	var output_paper := PanelContainer.new()
	output_paper.custom_minimum_size = Vector2(160,0)
	output_paper.add_theme_stylebox_override("panel",paper("dce6ce"))
	result_box = VBoxContainer.new()
	output_paper.add_child(result_box)
	flow.add_child(output_paper)
	content.add_child(flow)
	content.move_child(flow,2)
	timing = label("",15)
	content.add_child(timing)
	content.move_child(timing,4)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 14
	progress.show_percentage = false
	progress.add_theme_stylebox_override("background",paper("deceb0",0))
	progress.add_theme_stylebox_override("fill",paper("b87145",0))
	content.add_child(progress)
	content.move_child(progress,5)
	notice = label("레시피를 선택하세요.",15)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(notice)
	content.move_child(notice,6)
	$Content/DetailLabel.add_theme_color_override("font_color",Color("51382d"))
	$Content/ProductionCountRow/ProductionCountLabel.text = "만들 횟수"
	for button_name in ["StartButton","CollectButton"]:
		var button: Button = content.get_node(button_name)
		button.add_theme_stylebox_override("normal",paper("567d69",10))
		button.add_theme_stylebox_override("hover",paper("688f7b",10))
		button.add_theme_stylebox_override("pressed",paper("42624f",10))
		button.add_theme_stylebox_override("disabled",paper("d3c5aa",10))
		button.add_theme_color_override("font_color",Color("fff4df"))
		button.add_theme_color_override("font_disabled_color",Color("82725b"))

func clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func show_recipe(recipe: Dictionary, count: int, facility: ProductionFacility) -> void:
	current_recipe = recipe
	batch = count
	total_seconds = maxf(1,float(recipe.get("craft_time",0))*count)
	clear(ingredients)
	clear(result_box)
	var required := ProductionRecipeService.collect_required_ingredients(recipe,count)
	var missing := false
	for raw_id in required:
		var id := str(raw_id)
		var needed := int(required[id])
		var owned := GameState.get_item_count(id)
		var card := VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(icon(ItemData.get_item_icon(id)))
		card.add_child(label(ItemData.get_item_name(id),14))
		var quantity := label("%d / %d" % [owned,needed],15)
		if owned<needed:
			missing = true
			quantity.add_theme_color_override("font_color",Color("ad4736"))
		card.add_child(quantity)
		ingredients.add_child(card)
	var output_id := str(recipe.get("result_item_id",""))
	result_box.add_child(label("완성품",16))
	result_box.add_child(icon(ItemData.get_item_icon(output_id),56))
	result_box.add_child(label("%s  %d개" % [ItemData.get_item_name(output_id),int(recipe.get("result_amount",1))*count],15))
	timing.text = "%d회 만들기  ·  총 %d초" % [count,ceili(total_seconds)]
	notice.text = "재료가 부족합니다. 빨간 수량을 확인해주세요." if missing else "재료 준비 완료 · 가공을 시작할 수 있습니다."
	notice.add_theme_color_override("font_color",Color("ad4736") if missing else Color("426650"))
	$Content/DetailLabel.hide()
	refresh_state(facility)

func refresh_state(facility: ProductionFacility) -> void:
	if not is_instance_valid(facility): return
	hero_icon.texture = FurnitureData.get_furniture_icon(facility.facility_id)
	hero_title.text = "베이킹 작업대" if facility.facility_id=="magic_oven" else "음료 공방"
	subtitle.text = "반죽 준비  →  굽기  →  완성" if facility.facility_id=="magic_oven" else "재료 준비  →  혼합  →  병에 담기"
	if facility.production_state!=ProductionFacility.ProductionState.IDLE and str(current_recipe.get("recipe_id",""))!=facility.active_recipe_id:
		var recipe := ProductRecipeData.get_recipe(facility.active_recipe_id)
		if not recipe.is_empty():
			show_recipe(recipe,maxi(1,facility.pending_amount/maxi(1,int(recipe.get("result_amount",1)))),facility)
	$Content/DetailLabel.visible = current_recipe.is_empty()
	progress.visible = facility.production_state!=ProductionFacility.ProductionState.IDLE
	if facility.production_state==ProductionFacility.ProductionState.PROCESSING:
		progress.value = 100*(1-facility.remaining_seconds/total_seconds)
		notice.text = "가공 중 · %d초 남음 · 창을 닫아도 계속됩니다." % ceili(facility.remaining_seconds)
		notice.add_theme_color_override("font_color",Color("885235"))
	elif facility.production_state==ProductionFacility.ProductionState.READY:
		progress.value = 100
		notice.text = "완성되었습니다! 완성품을 인벤토리로 가져가세요."
		notice.add_theme_color_override("font_color",Color("426650"))

class KitchenBackdrop extends Node2D:
	var dialog: Window
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,Vector2(dialog.size)),Color("a6734e"))
		draw_rect(Rect2(Vector2(4,4),Vector2(dialog.size)-Vector2(8,8)),Color("f5e5c9"))

func _fit_workshop() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	reset_size()
	size = Vector2i(632,552)
	position = (get_parent().get_viewport().get_visible_rect().size-Vector2(size))/2
