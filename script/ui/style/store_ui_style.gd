class_name StoreUiStyle
extends RefCounted
## 새 UI 스타일 "이세계로 온 편의점". 값(색·굵기)은 한곳에 모아 두고, 위젯 모양은 StyleBoxFlat 으로 코드가 만든다(그림 파일 없이 바꿀 수 있다).
## 모티프: 편의점 간판의 초록 띠, 진열대 가격표, 영수증 종이. 모서리는 도트처럼 각지게, 그림자는 번지지 않고 한 칸 어긋나게.

# ---- 색 (매장 벽의 브랜드색 StoreShell.BRAND 와 같은 초록을 쓴다)
const BRAND := Color("235740")
const BRAND_DEEP := Color("163a2a")
const BRAND_SOFT := Color("d6e6db")
const PAPER := Color("f3f5f1")
const PAPER_ALT := Color("e4eae2")
const LINE := Color("b3c1b5")
const INK := Color("1f2b25")
const INK_DIM := Color("5f6e66")
const WHITE := Color("ffffff")
const ACCENT_GOLD := Color("e8a33d")  # 돈·강조
const ACCENT_RED := Color("c8553d")  # 경고·할인표
const ACCENT_BLUE := Color("4a86a8")  # 안내
const SHADOW := Color(0.05, 0.09, 0.07, 0.45)

# ---- 혼합형(판타지 재질 + 편의점 간판) 추가 색: 양피지·나무·황동
const PARCH := Color("f5eddc")
const PARCH_CELL := Color("e6d3ad")
const PARCH_LINE := Color("b9a582")
const WOOD := Color("70503b")
const WOOD_DARK := Color("3d2a1d")
const BRASS := Color("d9a441")
const INK_BROWN := Color("44392e")

# 관리 메뉴 7개 구역의 표식 색(탭 위쪽 가는 띠). 순서: 인벤토리 생산 직원 설계도 건설 일정 정보
const SECTION_COLORS: Array = [Color("e8a33d"), Color("d9735a"), Color("5f9f7a"), Color("4a86a8"), Color("b89a6a"), Color("8f78b0"), Color("4fa3a0")]

const BORDER: int = 2
const SHADOW_OFFSET := Vector2(3, 3)

static var _theme: Theme = null


static func box(fill: Color, border: Color = LINE, border_w: int = BORDER, pad: Vector4 = Vector4(14, 8, 14, 8), shadow: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(border_w)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w

	if shadow:
		s.shadow_color = SHADOW
		s.shadow_size = 0
		s.shadow_offset = SHADOW_OFFSET

	return s


# 큰 창: 흰 종이 + 짙은 초록 테두리 + 어긋난 그림자. 머리띠는 따로(header_bar).
static func window() -> StyleBoxFlat:
	return box(PAPER, BRAND_DEEP, 3, Vector4(0, 0, 0, 0), true)


# 창 머리띠: 편의점 간판처럼 초록 바탕에 흰 글씨.
static func header_bar() -> StyleBoxFlat:
	var s := box(BRAND, BRAND_DEEP, 0, Vector4(16, 8, 10, 8))
	return s


static func button(kind: String = "normal", primary: bool = false) -> StyleBoxFlat:
	var fill: Color = BRAND if primary else WHITE
	var edge: Color = BRAND_DEEP if primary else BRAND

	match kind:
		"hover":
			fill = BRAND.lightened(0.12) if primary else BRAND_SOFT
		"pressed":
			fill = BRAND_DEEP if primary else BRAND_SOFT.darkened(0.08)
		"disabled":
			fill = PAPER_ALT
			edge = LINE

	var s := box(fill, edge, 2, Vector4(16, 9, 16, 9))
	return s


# 진열대 가격표 모양 라벨(선택된 항목·가격).
static func tag(fill: Color = ACCENT_GOLD) -> StyleBoxFlat:
	return box(fill, fill.darkened(0.35), 2, Vector4(8, 3, 8, 3))


# 관리 메뉴 옆 탭: 평소엔 종이색, 위쪽에 구역 색 띠. 선택되면 초록 바탕.
static func section_tab(index: int, selected: bool) -> StyleBoxFlat:
	var c: Color = SECTION_COLORS[index % SECTION_COLORS.size()]
	var s := box(BRAND if selected else WHITE, BRAND_DEEP if selected else LINE, 2, Vector4(12, 10, 12, 8))
	s.border_width_left = 8
	s.border_color = c if not selected else c.lightened(0.1)
	s.border_blend = false
	return s


static func slot(selected: bool = false, hover: bool = false) -> StyleBoxFlat:
	var edge: Color = ACCENT_GOLD if selected else (BRAND if hover else LINE)
	return box(WHITE if not selected else Color("fff6e0"), edge, 3 if selected else 2, Vector4(2, 2, 2, 2))


# 프로젝트 전체에 쓸 테마. 기본 글자 크기·색, 버튼·패널·탭·스크롤·입력칸의 모양을 정한다.
static func theme() -> Theme:
	if _theme != null:
		return _theme

	var t := Theme.new()
	t.default_font_size = 18

	for type in ["Label", "RichTextLabel", "CheckBox", "OptionButton", "ItemList", "LineEdit"]:
		t.set_color("font_color", type, INK)

	t.set_color("default_color", "RichTextLabel", INK)

	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "Button", button(state.replace("hover_pressed", "pressed")))

	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), ACCENT_GOLD, 2, Vector4(16, 9, 16, 9)))
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", BRAND_DEEP)
	t.set_color("font_pressed_color", "Button", BRAND_DEEP)
	t.set_color("font_disabled_color", "Button", INK_DIM)
	t.set_stylebox("panel", "PanelContainer", box(PAPER, LINE, 2, Vector4(12, 10, 12, 10)))
	t.set_stylebox("panel", "Panel", box(PAPER, LINE, 2, Vector4(0, 0, 0, 0)))
	t.set_stylebox("panel", "TooltipPanel", box(BRAND_DEEP, BRAND, 2, Vector4(10, 6, 10, 6)))
	t.set_color("font_color", "TooltipLabel", WHITE)
	t.set_stylebox("panel", "AcceptDialog", box(PAPER, BRAND_DEEP, 3, Vector4(14, 12, 14, 12), true))
	t.set_stylebox("normal", "LineEdit", box(WHITE, LINE, 2, Vector4(8, 6, 8, 6)))
	t.set_stylebox("focus", "LineEdit", box(WHITE, BRAND, 2, Vector4(8, 6, 8, 6)))
	var grab := box(BRAND, BRAND_DEEP, 0, Vector4(0, 0, 0, 0))
	var track := box(PAPER_ALT, PAPER_ALT, 0, Vector4(0, 0, 0, 0))

	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, track)
		t.set_stylebox("grabber", type, grab)
		t.set_stylebox("grabber_highlight", type, box(BRAND.lightened(0.15), BRAND_DEEP, 0, Vector4(0, 0, 0, 0)))
		t.set_stylebox("grabber_pressed", type, box(BRAND_DEEP, BRAND_DEEP, 0, Vector4(0, 0, 0, 0)))

	_theme = t
	return t
