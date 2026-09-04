extends PanelContainer

const ITEM_CARD_SCENE: PackedScene = preload(
	"res://scenes/ui/item_card.tscn"
)

@onready var close_button: Button = (
	$VBoxContainer/TitleHBox/CloseButton
)

@onready var item_grid: GridContainer = (
	$VBoxContainer/ItemGrid
)

@onready var food_tab_button: Button = (
	$VBoxContainer/CategoryTabs/FoodTabButton
)

@onready var potion_tab_button: Button = (
	$VBoxContainer/CategoryTabs/PotionTabButton
)

@onready var tool_tab_button: Button = (
	$VBoxContainer/CategoryTabs/ToolTabButton
)

@onready var etc_tab_button: Button = (
	$VBoxContainer/CategoryTabs/EtcTabButton
)


var selected_category: String = (
	ItemData.CATEGORY_FOOD
)


func _ready():
	visible = false

	close_button.pressed.connect(
		close_inventory
	)

	food_tab_button.pressed.connect(
		select_category.bind(
			ItemData.CATEGORY_FOOD
		)
	)

	potion_tab_button.pressed.connect(
		select_category.bind(
			ItemData.CATEGORY_POTION
		)
	)

	tool_tab_button.pressed.connect(
		select_category.bind(
			ItemData.CATEGORY_TOOL
		)
	)

	etc_tab_button.pressed.connect(
		select_category.bind(
			ItemData.CATEGORY_ETC
		)
	)

	print("[인벤토리 UI] 준비 완료")


func _input(event):
	if not event is InputEventKey:
		return

	if not event.pressed:
		return

	if event.echo:
		return

	if event.keycode == KEY_I:
		toggle_inventory()

		get_viewport().set_input_as_handled()


func toggle_inventory():
	visible = not visible

	print(
		"[인벤토리] ",
		"OPEN" if visible else "CLOSE"
	)

	if visible:
		selected_category = "food"
		refresh_inventory()

		await get_tree().process_frame
		center_inventory_panel()


func close_inventory():
	visible = false


func refresh_inventory():
	clear_item_grid()

	var item_ids: Array[String] = (
		ItemData.get_items_by_category(
			selected_category
		)
	)

	for item_id in item_ids:
		var count: int = (
			GameState.get_item_count(
				item_id
			)
		)

		if count <= 0:
			continue

		create_item_card(
			item_id,
			count
		)


func create_item_card(
	item_id: String,
	count: int
):
	var card = (
		ITEM_CARD_SCENE.instantiate()
	)

	item_grid.add_child(
		card
	)

	card.setup(
		item_id,
		count
	)


func clear_item_grid():
	for child in item_grid.get_children():
		item_grid.remove_child(child)
		child.queue_free()

func center_inventory_panel():
	var viewport_size: Vector2 = (
		get_viewport_rect().size
	)

	position = (
		viewport_size - size
	) * 0.5

	z_index = 200

func select_category(category: String):
	selected_category = category

	print(
		"[인벤토리] 카테고리 변경: ",
		selected_category
	)

	refresh_inventory()
