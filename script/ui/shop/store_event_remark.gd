class_name StoreEventRemark
extends CanvasLayer
## 스쳐 들리는 손님 말. 결제/이동을 멈추지 않으며 현재 표시가 끝나야 다음 말을 받는다.
var card: PanelContainer
var caption: Label
var remaining := 0.0

static func tell(customer: Node, stage: String, item_id: String) -> void:
	if not is_instance_valid(customer.player): return
	var text := StoreEventStory.reaction(customer.wanted_event_id, customer.get_customer_type_id(), item_id, stage, GameState.total_day)
	if text.is_empty(): return
	var notice := customer.player.get_node_or_null("StoreEventRemark") as StoreEventRemark
	if notice == null:
		notice = StoreEventRemark.new()
		notice.name = "StoreEventRemark"
		customer.player.add_child(notice)
	notice.display(text)

# 가격 반응 같은 짧은 손님 말(이벤트 글이 아니라 정해진 문장).
static func say(customer: Node, text: String) -> void:
	if text.is_empty() or not is_instance_valid(customer.player): return
	var notice := customer.player.get_node_or_null("StoreEventRemark") as StoreEventRemark
	if notice == null:
		notice = StoreEventRemark.new()
		notice.name = "StoreEventRemark"
		customer.player.add_child(notice)
	notice.display(text)

func _ready() -> void:
	layer = 6
	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f1dfba")
	style.border_color = Color("90754b")
	style.set_border_width_all(2)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)
	caption = Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_color_override("font_color", Color("493826"))
	caption.add_theme_font_size_override("font_size", UiTypography.size(16))
	card.add_child(caption)
	get_viewport().size_changed.connect(_layout)
	card.hide()
	_layout()

func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var width := minf(StoreEventStory.SETTINGS.remark_width, maxf(viewport_size.x - 32, 0))
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -width - 16
	card.offset_right = -16
	card.offset_top = 170
	card.offset_bottom = 270

func display(text: String) -> bool:
	if remaining > 0: return false
	caption.text = "스쳐 들리는 손님 말\n“%s”" % text
	remaining = StoreEventStory.SETTINGS.remark_seconds
	card.show()
	return true

func _process(delta: float) -> void:
	remaining = maxf(remaining - delta, 0)
	if remaining == 0: card.hide()
