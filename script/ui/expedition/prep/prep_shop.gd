extends PanelContainer


@onready var weapon_button: Button = (
	$ShopHBox/ShopItemArea/ShopCategoryTabs/WeaponButton
)

@onready var armor_button: Button = (
	$ShopHBox/ShopItemArea/ShopCategoryTabs/ArmorButton
)

@onready var tool_button: Button = (
	$ShopHBox/ShopItemArea/ShopCategoryTabs/ToolButton
)

@onready var etc_button: Button = (
	$ShopHBox/ShopItemArea/ShopCategoryTabs/EtcButton
)

@onready var shop_item_list: VBoxContainer = (
	$ShopHBox/ShopItemArea/ShopItemList
)

@onready var detail_overlay: Control = (
	$ShopDetailOverlay
)

@onready var item_name_label: Label = (
	$ShopDetailOverlay/CenterContainer/DetailPanel/VBoxContainer/ItemNameLabel
)

@onready var item_type_label: Label = (
	$ShopDetailOverlay/CenterContainer/DetailPanel/VBoxContainer/ItemTypeLabel
)

@onready var item_size_label: Label = (
	$ShopDetailOverlay/CenterContainer/DetailPanel/VBoxContainer/ItemSizeLabel
)

@onready var item_price_label: Label = (
	$ShopDetailOverlay/CenterContainer/DetailPanel/VBoxContainer/ItemPriceLabel
)

@onready var item_description_label: Label = (
	$ShopDetailOverlay/CenterContainer/DetailPanel/VBoxContainer/ItemDescriptionLabel
)

@onready var buy_button: Button = (
	$ShopDetailOverlay/CenterContainer/DetailPanel/VBoxContainer/ButtonRow/BuyButton
)

@onready var close_button: Button = (
	$ShopDetailOverlay/CenterContainer/DetailPanel/VBoxContainer/ButtonRow/CloseButton
)

@onready var money_label: Label = (
	$ShopDetailOverlay/CenterContainer/DetailPanel/VBoxContainer/MoneyLabel
)

@onready var purchase_status_label: Label = (
	$ShopDetailOverlay/CenterContainer/DetailPanel/VBoxContainer/PurchaseStatusLabel
)

@onready var bag_content: Control = (
	$"../BagContent"
)



var selected_item_id: String = ""
var purchase_processing: bool = false



func _ready() -> void:
	weapon_button.pressed.connect(
		_show_category.bind(
			ExpeditionShopData.CATEGORY_WEAPON
		)
	)

	armor_button.pressed.connect(
		_show_category.bind(
			ExpeditionShopData.CATEGORY_ARMOR
		)
	)

	tool_button.pressed.connect(
		_show_category.bind(
			ExpeditionShopData.CATEGORY_TOOL
		)
	)

	etc_button.pressed.connect(
		_show_category.bind(
			ExpeditionShopData.CATEGORY_ETC
		)
	)

	# 처음 상점을 열었을 때 무기 탭 표시
	_show_category(
		ExpeditionShopData.CATEGORY_WEAPON
	)

	close_button.pressed.connect(
		_close_detail_popup
	)

	buy_button.pressed.connect(
		_on_buy_pressed
	)

	detail_overlay.visible = false


func _show_category(category: String) -> void:
	_clear_item_list()

	var item_ids := (
		ExpeditionShopData.get_items_by_category(category)
	)

	if item_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "판매 중인 상품이 없습니다."
		shop_item_list.add_child(empty_label)
		return

	for item_id in item_ids:
		_create_item_button(item_id)


func _create_item_button(
	item_id: String
) -> void:
	if not ItemCatalog.ITEMS.has(item_id):
		push_warning(
			"상점 상품이 items.csv에 없음: "
			+ item_id
		)
		return

	var item: Dictionary = (
		ItemCatalog.ITEMS[item_id]
	)

	var item_name: String = str(
		item.get(
			"name",
			item_id
		)
	)

	var price: int = (
		ExpeditionShopData.get_price(
			item_id
		)
	)

	var button := Button.new()

	if _is_unique_tool_owned(item_id):
		button.text = (
			"%s    보유 중"
			% item_name
		)
	else:
		button.text = (
			"%s    %d G"
			% [
				item_name,
				price
			]
		)

	button.custom_minimum_size.y = 48

	button.pressed.connect(
		_on_item_pressed.bind(
			item_id
		)
	)

	shop_item_list.add_child(
		button
	)


func _on_item_pressed(
	item_id: String
) -> void:
	var item: Dictionary = (
		ItemCatalog.ITEMS.get(
			item_id,
			{}
		)
	)

	if item.is_empty():
		return

	selected_item_id = item_id

	var item_type: String = str(
		item.get(
			"item_type",
			""
		)
	)

	var bag_size: Vector2i = (
		item.get(
			"bag_size",
			Vector2i.ZERO
		)
	)

	var price: int = (
		ExpeditionShopData.get_price(
			item_id
		)
	)

	item_name_label.text = str(
		item.get(
			"name",
			item_id
		)
	)

	item_type_label.text = (
		"종류: %s"
		% _get_item_type_text(
			item_id,
			item_type
		)
	)

	item_size_label.text = (
		"크기: %d × %d"
		% [
			bag_size.x,
			bag_size.y
		]
	)

	item_price_label.text = (
		"가격: %d G"
		% price
	)

	var description: String = str(
		item.get(
			"description",
			"설명이 없습니다."
		)
	)

	if ExpeditionEquipmentData.has_equipment(item_id):
		var effect_id: String = (
			ExpeditionEquipmentData.get_effect_id(item_id)
		)

		var base_power: int = int(
			ExpeditionEquipmentData.get_base_value(item_id)
		)

		var max_level: int = (
			ExpeditionEquipmentData.get_max_enhancement_level(item_id)
		)

		match effect_id:
			"attack":
				# 공격력 숫자는 보이지 않고 공격 방식만 보인다.
				description += (
					"\n\n[공격 방식]\n"
					+ ExpeditionWeaponLoadout.get_style_text(item_id)
				)

			"defense":
				description += (
					"\n\n[방어]\n방어력 +"
					+ str(base_power)
				)

			_:
				description += "\n\n[도구 효과]"

				description += (
					"\n"
					+ _get_tool_effect_text(
						effect_id,
						base_power
					)
				)

		description += (
			"\n최대 강화: +"
			+ str(max_level)
		)

	elif item_type == "equipment":
		var attack_bonus: int = int(
			item.get(
				"attack",
				0
			)
		)

		var defense_bonus: int = int(
			item.get(
				"defense",
				0
			)
		)

		if (
			attack_bonus != 0
			or defense_bonus != 0
		):
			description += "\n"

		if attack_bonus != 0:
			# 공격력 숫자는 보이지 않고 공격 방식만 보인다.
			description += (
				"\n공격 방식: "
				+ ExpeditionWeaponLoadout.get_style_text(item_id)
			)

		if defense_bonus != 0:
			description += (
				"\n방어력 %+d"
				% defense_bonus
			)

	item_description_label.text = description

	_update_money_display()

	var already_owned: bool = (
		_is_unique_tool_owned(
			item_id
		)
	)

	buy_button.disabled = (
		price <= 0
		or not ItemData.has_item(item_id)
		or not GameState.can_afford(price)
		or _is_unique_tool_owned(item_id)
		or already_owned
	)

	if _is_unique_tool_owned(item_id):
		purchase_status_label.text = (
			"같은 용도의 도구를 이미 보유하고 있습니다."
		)

	if already_owned:
		purchase_status_label.text = (
			"이미 보유한 도구입니다."
		)
	else:
		purchase_status_label.text = ""

	detail_overlay.visible = true


func _clear_item_list() -> void:
	for child in shop_item_list.get_children():
		child.queue_free()


func _get_item_type_text(
	item_id: String,
	item_type: String
) -> String:
	if ExpeditionEquipmentData.has_equipment(item_id):
		return "도구"

	match item_type:
		"equipment":
			return "장비"

		"material":
			return "재료"

		"expedition_consumable":
			return "원정 소비품"

		"special":
			return "특수"

		_:
			return item_type

func _close_detail_popup() -> void:
	detail_overlay.visible = false
	selected_item_id = ""

func _on_buy_pressed() -> void:
	if purchase_processing:
		return

	if not is_visible_in_tree():
		return

	if not detail_overlay.visible:
		return

	if selected_item_id.is_empty():
		return

	var item_id: String = selected_item_id

	if (
		not ItemCatalog.ITEMS.has(item_id)
		or not ItemData.has_item(item_id)
	):
		purchase_status_label.text = (
			"상품 정보를 확인할 수 없습니다."
		)

		buy_button.disabled = true

		push_warning(
			"[원정 상점] 상품 데이터 등록 불일치: "
			+ item_id
		)
		return

	var item: Dictionary = (
		ItemCatalog.ITEMS[item_id]
	)

	var item_name: String = str(
		item.get(
			"name",
			item_id
		)
	)

	var price: int = (
		ExpeditionShopData.get_price(
			item_id
		)
	)

	if price <= 0:
		purchase_status_label.text = (
			"구매할 수 없는 상품입니다."
		)

		buy_button.disabled = true
		return

	# 결제 직전에도 도구 용도 중복을 다시 검사한다.
	if _is_unique_tool_owned(item_id):
		purchase_status_label.text = (
			"같은 용도의 도구를 이미 보유하고 있습니다."
		)

		buy_button.disabled = true
		return

	purchase_processing = true
	buy_button.disabled = true

	if not GameState.spend_money(price):
		purchase_processing = false

		_update_money_display()

		purchase_status_label.text = (
			"소지금이 부족합니다."
		)
		return

	var purchase_success: bool = false

	# 무기·방어구·도구는 개별 장비로 생성
	if ExpeditionEquipmentData.has_equipment(
		item_id
	):
		var instance_id: int = (
			GameState.create_owned_equipment_instance(
				item_id,
				0
			)
		)

		purchase_success = (
			instance_id > 0
		)

	# 일반 아이템은 기존 수량 인벤토리에 추가
	else:
		GameState.add_item(
			item_id,
			1
		)

		purchase_success = (
			GameState.get_item_count(
				item_id
			) > 0
		)

	# 지급 실패 시 결제 금액 반환
	if not purchase_success:
		GameState.add_money(price)

		purchase_processing = false
		_update_money_display()

		purchase_status_label.text = (
			"상품을 지급하지 못해 결제를 취소했습니다."
		)

		push_error(
			"[원정 상점] 구매 지급 실패: "
			+ item_id
		)
		return

	purchase_processing = false

	_update_money_display()

	if (
		is_instance_valid(bag_content)
		and bag_content.has_method(
			"refresh_all"
		)
	):
		bag_content.call(
			"refresh_all"
		)

	var owned_count: int

	if ExpeditionEquipmentData.has_equipment(
		item_id
	):
		owned_count = (
			_get_total_equipment_count(
				item_id
			)
		)
	else:
		owned_count = (
			GameState.get_item_count(
				item_id
			)
		)

	purchase_status_label.text = (
		"%s 구매 완료! (보유 %d개)"
		% [
			item_name,
			owned_count
		]
	)

	buy_button.disabled = (
		not GameState.can_afford(price)
		or _is_unique_tool_owned(item_id)
	)

	DebugLog.write(
		"[원정 상점] 구매 완료 / ",
		item_name,
		" / 가격: ",
		price,
		" / 남은 돈: ",
		GameState.get_money(),
		" / 보유 수량: ",
		owned_count
	)

func _update_money_display() -> void:
	money_label.text = (
		"보유금: %d G"
		% GameState.get_money()
	)

func refresh_all() -> void:
	_close_detail_popup()

	purchase_status_label.text = ""
	buy_button.disabled = true

	_update_money_display()

func _get_tool_effect_text(
	effect_id: String,
	power: int
) -> String:
	match effect_id:
		"harvest_wheat":
			return (
				"밀 채집 성공률 100%"
				+ "\n밀 추가 획득 +"
				+ str(power)
				+ "개"
			)

		"collect_water":
			return (
				"호수에서 물 채집 가능"
				+ "\n물 추가 획득 +"
				+ str(power)
				+ "개"
			)

	return "등록되지 않은 도구 효과"

func _is_unique_tool_owned(
	item_id: String
) -> bool:
	if not ExpeditionEquipmentData.has_equipment(
		item_id
	):
		return false

	if (
		ExpeditionEquipmentData.get_equipment_type(
			item_id
		)
		!= ExpeditionEquipmentData.TYPE_TOOL
	):
		return false

	var wanted_effect_id: String = (
		ExpeditionEquipmentData.get_effect_id(
			item_id
		)
	)

	if wanted_effect_id.is_empty():
		return false

	# 보유 장비 검사
	for instance_data in (
		GameState.get_owned_equipment_instances()
	):
		var owned_item_id: String = str(
			instance_data.get(
				"item_id",
				""
			)
		)

		if not ExpeditionEquipmentData.has_equipment(
			owned_item_id
		):
			continue

		if (
			ExpeditionEquipmentData.get_equipment_type(
				owned_item_id
			)
			!= ExpeditionEquipmentData.TYPE_TOOL
		):
			continue

		var owned_effect_id: String = (
			ExpeditionEquipmentData.get_effect_id(
				owned_item_id
			)
		)

		if owned_effect_id == wanted_effect_id:
			return true

	# 원정 가방 검사
	var bag_model = _get_prepared_bag_model()

	if bag_model != null:
		for placement in bag_model.placements:
			var bag_item_id: String = str(
				placement.get(
					"item_id",
					""
				)
			)

			if not ExpeditionEquipmentData.has_equipment(
				bag_item_id
			):
				continue

			if (
				ExpeditionEquipmentData.get_equipment_type(
					bag_item_id
				)
				!= ExpeditionEquipmentData.TYPE_TOOL
			):
				continue

			var bag_effect_id: String = (
				ExpeditionEquipmentData.get_effect_id(
					bag_item_id
				)
			)

			if bag_effect_id == wanted_effect_id:
				return true

	return false

func _get_prepared_bag_model():
	if not is_instance_valid(bag_content):
		return null

	if not bag_content.has_method(
		"get_prepared_bag_model"
	):
		return null

	return bag_content.call(
		"get_prepared_bag_model"
	)

func _get_total_equipment_count(
	item_id: String
) -> int:
	var count: int = (
		GameState.get_owned_equipment_count(
			item_id
		)
	)

	var bag_model = _get_prepared_bag_model()

	if bag_model == null:
		return count

	for placement in bag_model.placements:
		if str(
			placement.get(
				"item_id",
				""
			)
		) == item_id:
			count += 1

	return count
