class_name RegisterDashboardPanel
extends FoodShelfLifePanel
## Idle register: product overview first, food cleanup on a separate page.
var cleanup_page := false
var cleanup_seen := false
var products: Array[Dictionary] = []
var product_table: Tree
var detail: Label

func _ready() -> void:
	super._ready()
	title = "계산대"

func _fit() -> void:
	super._fit()
	var bounds := get_parent().get_viewport().get_visible_rect().size
	scroll.custom_minimum_size.y = minf(420, bounds.y - 150)
	size.y = mini(540, int(bounds.y - 40))

func open() -> void:
	if visible: return
	cleanup_page = false
	cleanup_seen = false
	super.open()

func show_page(cleanup: bool) -> void:
	cleanup_page = cleanup
	if cleanup: cleanup_seen = true
	refresh()
	scroll.set_deferred("scroll_vertical", 0)

func refresh() -> void:
	if cleanup_page:
		super.refresh()
	else:
		for child in rows.get_children():
			rows.remove_child(child)
			child.queue_free()
		products = RegisterProductOverview.entries(get_parent().get_parent())
		_label("진열 상품 %d종 · 같은 상품은 모아서 표시합니다." % products.size())
		if products.is_empty():
			_label("아직 진열대에 등록된 상품이 없습니다. 진열대에서 상품을 등록하면 여기에 표시됩니다.")
		else:
			_product_list()
	var tabs := HBoxContainer.new()
	rows.add_child(tabs)
	rows.move_child(tabs, 0)
	for cleanup in [false, true]:
		var button := Button.new()
		button.name = "CleanupTab" if cleanup else "ProductsTab"
		button.text = "마감 정리" if cleanup else "상품 조회"
		button.disabled = cleanup_page == cleanup
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(show_page.bind(cleanup))
		tabs.add_child(button)

func _product_list() -> void:
	product_table = Tree.new()
	product_table.name = "ProductTable"
	product_table.columns = 4
	product_table.column_titles_visible = true
	product_table.hide_root = true
	product_table.select_mode = Tree.SELECT_ROW
	product_table.custom_minimum_size.y = 200
	for i in range(4):
		product_table.set_column_title(i, ["상품", "진열", "판매가", "상태"][i])
		product_table.set_column_custom_minimum_width(i, [125, 60, 95, 135][i])
		product_table.set_column_expand(i, i == 0 or i == 3)
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("f9efd9")
	paper.set_content_margin_all(6)
	product_table.add_theme_stylebox_override("panel", paper)
	product_table.add_theme_color_override("font_color", Color("51382d"))
	rows.add_child(product_table)
	var root := product_table.create_item()
	for product in products:
		var row := product_table.create_item(root)
		row.set_metadata(0, product)
		row.set_text(0, product["name"])
		row.set_text(1, "%d/%d" % [product["stock"], product["capacity"]])
		row.set_text(2, RegisterProductOverview.price_text(product))
		row.set_text(3, RegisterProductOverview.status_text(product))
		for column in range(4):
			row.set_tooltip_text(column, _details(product))
			if int(product["stock"]) == 0: row.set_custom_color(column, Color("776b60"))
	_label("상품을 선택하면 설명과 진열 상태를 확인할 수 있습니다.")
	detail = rows.get_child(rows.get_child_count() - 1)
	product_table.item_selected.connect(func() -> void:
		var selected := product_table.get_selected()
		if selected != null: detail.text = _details(selected.get_metadata(0)))

func _details(product: Dictionary) -> String:
	var status := RegisterProductOverview.status_text(product)
	if int(product["days_left"]) >= 0: status = "가장 빠른 " + status
	if product["min_price"] != product["max_price"]: status += " · 날짜별 재고에 따라 가격이 다릅니다."
	return "%s · 진열 %d/%d개 · %s\n%s\n%s" % [product["name"], product["stock"], product["capacity"], RegisterProductOverview.price_text(product), status, product["description"]]

func _acknowledge() -> void:
	if cleanup_seen: FoodShelfLife.state()["learned"] = true
	hide()
