extends Control

const FRAME = preload("res://art/ui/reference_theme/wood.png")
const PAPER = preload("res://art/ui/reference_theme/normal.png")
const COIN = preload("res://art/ui/pixel_theme/icon_coin.png")
const DAY = preload("res://art/ui/clock_hud/day.png")
const NIGHT = preload("res://art/ui/clock_hud/night.png")
var sky: TextureRect
var weather_icon: TextureRect
var _weather_kind: String = "?"
var period: Label
var elapsed: float = 0.0
var money_digits: Control
var last_money: String = ""

func _ready() -> void:
	_panel("ClockFrame", FRAME, Rect2(-336,12,320,176), 8)
	_panel("DatePaper", PAPER, Rect2(-250,20,226,60), 10)
	_panel("TimePaper", PAPER, Rect2(-250,82,226,42), 10)
	_panel("MoneyPaper", PAPER, Rect2(-328,134,304,44), 10)
	sky = _icon("DayNight", DAY, Rect2(-326,28,72,72))
	_icon("Coin", COIN, Rect2(-314,143,24,24))
	weather_icon = _icon("WeatherIcon", null, Rect2(-290,26,40,40))
	weather_icon.visible = false
	period = Label.new()
	period.name = "PeriodCaption"
	add_child(period)
	_place(period, Rect2(-326,96,72,34))
	period.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	period.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	period.add_theme_color_override("font_color",Color("f9e6ae"))
	period.add_theme_font_size_override("font_size",UiTypography.size(14))
	_style_label($DayLabel,Rect2(-238,25,202,50),16)
	_style_label($TimeLabel,Rect2(-238,86,202,34),20)
	_style_label($MoneyLabel,Rect2(-286,140,248,32),22)
	$DayLabel.add_theme_constant_override("line_spacing",-4)
	$DayLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$TimeLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$MoneyLabel.hide()
	money_digits = Control.new()
	money_digits.name = "MoneyDigits"
	add_child(money_digits)
	_place(money_digits,Rect2(-284,141,246,32))
	_update_money_digits()
	_update_sky()

func _place(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _panel(node_name: String, texture: Texture2D, rect: Rect2, margin: int) -> void:
	var panel := Panel.new()
	panel.name = node_name
	var style := StyleBoxTexture.new()
	style.texture = texture
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_texture_margin(side,margin)
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	move_child(panel,0)
	panel.z_index = -1
	# Outer backing must be below the three paper compartments.
	if node_name == "ClockFrame": panel.z_index = -2
	_place(panel,rect)

func _icon(node_name: String, texture: Texture2D, rect: Rect2) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = node_name
	icon.texture = texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(icon)
	_place(icon,rect)
	return icon

func _style_label(label: Label, rect: Rect2, font_size: int) -> void:
	_place(label,rect)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",UiTypography.size(font_size))
	label.add_theme_color_override("font_color",Color("382314"))

func _process(delta: float) -> void:
	_update_money_digits()
	elapsed += delta
	if elapsed < 0.25: return
	elapsed = 0.0
	_update_sky()

func _update_sky() -> void:
	var manager = get_node_or_null("../../DayManager")
	if manager == null: return
	var hour: int = int(manager.current_hour)
	sky.texture = NIGHT if hour >= 18 or hour < 6 else DAY
	period.text = manager.get_period_name()
	_update_weather(manager)
	$TimeLabel.add_theme_font_size_override("font_size",UiTypography.size(16 if $TimeLabel.text.length() > 16 else 20))

func _update_money_digits() -> void:
	if money_digits == null: return
	var value := str(GameState.money)
	if value == last_money: return
	last_money = value
	for child in money_digits.get_children():
		money_digits.remove_child(child)
		child.queue_free()
	var count := maxi(9,value.length())
	var padded := " ".repeat(count-value.length()) + value
	var step := 246.0 / count
	for i in range(count):
		var card := Panel.new()
		card.position = Vector2(round(i*step),0)
		card.size = Vector2(floor(step)-2,32)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color("f2dbac")
		style.border_color = Color("936236")
		style.set_border_width_all(1)
		style.border_width_bottom = 2
		card.add_theme_stylebox_override("panel",style)
		money_digits.add_child(card)
		var highlight := ColorRect.new()
		highlight.color = Color("fff0cc")
		highlight.position = Vector2(1,1)
		highlight.size = Vector2(card.size.x-2,3)
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(highlight)
		var digit := Label.new()
		digit.text = padded[i]
		digit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		digit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		digit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		digit.add_theme_font_size_override("font_size",UiTypography.size(clampi(int(step)-4,11,22)))
		digit.add_theme_color_override("font_color",Color("77311e"))
		digit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(digit)


# 날씨(비·눈)를 하늘 그림 옆 작은 도트 아이콘과 시간대 글자 뒤에 보여 준다. 맑으면 아이콘은 숨긴다.
func _update_weather(manager) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	var total_day: int = int(gs.get("total_day")) if gs != null else 1
	var w: Dictionary = WeatherSystem.forecast(total_day, float(manager.current_hour))
	var kind: String = str(w["kind"])

	if kind != "clear":
		period.text += " · " + WeatherSystem.kind_name(kind)

	if kind == _weather_kind:
		return

	_weather_kind = kind
	weather_icon.visible = kind != "clear"
	weather_icon.texture = _weather_texture(kind) if kind != "clear" else null


# 16×16 도트 구름(비: 파란 빗방울, 눈: 흰 눈송이)
static func _weather_texture(kind: String) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var line := Color(0.2, 0.22, 0.3)
	var body := Color(0.8, 0.84, 0.92)
	var rows: Array = [[6, 10], [4, 12], [2, 13], [1, 14], [1, 14], [2, 13]]
	var mask: Dictionary = {}

	for i in range(rows.size()):
		for x in range(rows[i][0], rows[i][1] + 1):
			mask[Vector2i(x, 2 + i)] = true

	for c in mask.keys():
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d

			if not mask.has(n) and n.x >= 0 and n.x < 16 and n.y >= 0 and n.y < 16:
				img.set_pixelv(n, line)

	for c in mask.keys():
		img.set_pixelv(c, body)

	if kind == "rain":
		for p in [Vector2i(4, 10), Vector2i(8, 11), Vector2i(12, 10), Vector2i(6, 13), Vector2i(10, 13)]:
			img.set_pixel(p.x, p.y, Color(0.35, 0.6, 1.0))
			img.set_pixel(p.x, p.y + 1, Color(0.35, 0.6, 1.0))
	else:
		for p in [Vector2i(4, 10), Vector2i(8, 12), Vector2i(12, 10), Vector2i(6, 14), Vector2i(11, 14)]:
			img.set_pixel(p.x, p.y, Color.WHITE)

	return ImageTexture.create_from_image(img)
