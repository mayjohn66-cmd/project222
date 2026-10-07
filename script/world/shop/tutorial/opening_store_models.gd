class_name OpeningStoreModels
extends RefCounted
## 프롤로그 가게 안 장식용 3D 모델(실제 편의점 내부 사진을 참고). 게임 집기 모델과 같은 방식(`FurnitureAssets.Frame`)으로
## 상자를 모아 **메시 하나**로 만든다. 상품 상자가 수백 개여도 깊이 정렬 항목은 하나라서 화면이 끊기지 않는다.
##   cooler  유리문 음료 냉장고(벽쪽 줄): 흰 몸통, 청록 윗띠, 층마다 알록달록한 음료
##   gondola 중앙 진열대: 흰 몸통, 층마다 과자·상품 상자, 청록 가격표 띠, 윗간판
##   chest   아이스크림 냉동 쇼케이스: 낮고 긴 흰 상자, 유리 뚜껑 아래 알록달록한 상품
##   rack    입구 쪽 작은 상품 걸이
##   table   취식 탁자와 초록 의자 두 개
##   cabinet 커피 기계가 올라간 흰 장
##   counter 계산대: 청록 상판·흰 몸통, 단말기(POS)·영수증 프린터·바구니
## 길이(L)·깊이(D)는 칸 단위. 앞면(손님 쪽)은 v = D.

# 차분한 상품 색. 진열대는 한 줄에 같은 색 상품을 묶음으로, 냉장고는 같은 색을 세로 한 줄로 놓아 정돈돼 보이게 한다.
const PALETTE := [
	Color(0.97, 0.72, 0.62), Color(0.99, 0.93, 0.7), Color(0.72, 0.85, 1.0), Color(0.78, 0.94, 0.8),
	Color(0.98, 0.98, 1.0), Color(0.98, 0.98, 1.0), Color(0.72, 0.85, 1.0), Color(0.99, 0.93, 0.7),
]
const RUN := 3          # 진열대 한 줄에서 같은 상품이 이어지는 칸 수
const TEAL := Color(0.1, 0.72, 0.72)
const WHITE := Color(0.93, 0.95, 0.97)
const GRAY := Color(0.7, 0.74, 0.8)
const DARK := Color(0.2, 0.22, 0.26)


static func build(kind: String, lo: Vector2, hi: Vector2, rot: int, pp: Dictionary) -> Dictionary:
	var f := FurnitureAssets.Frame.new(lo, hi, rot, pp)

	match kind:
		"cooler":
			return _cooler(f)
		"gondola":
			return _gondola(f)
		"chest":
			return _chest(f)
		"counter":
			return _counter(f)
		"table":
			return _table(f)
		"cabinet":
			return _cabinet(f)
		_:
			return _rack(f)


# 색 번호 i 의 상품 부품(색마다 면 하나로 모인다)
static func _goods(f: FurnitureAssets.Frame, i: int) -> Dictionary:
	var k: int = posmod(i, PALETTE.size())
	return f.flat(PALETTE[k], "pc%d" % k)


static func _cooler(f: FurnitureAssets.Frame) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var body: Dictionary = f.flat(WHITE, "co_body")
	var back: Dictionary = f.flat(Color(0.82, 0.9, 0.95), "co_back", 0.4)
	var shelf: Dictionary = f.flat(GRAY, "co_shelf")
	var teal: Dictionary = f.flat(TEAL, "co_teal", 0.5)
	var dark: Dictionary = f.flat(DARK, "co_dark")
	var glass: Dictionary = f.flat(Color(0.75, 0.92, 1.0), "co_glass", 0.3)
	var top: float = 1.78
	f.box(dark, 0.0, L, 0.0, D, 0.0, 0.14)                    # 받침
	f.box(body, 0.0, 0.06, 0.0, D, 0.14, top)                 # 왼쪽 옆판
	f.box(body, L - 0.06, L, 0.0, D, 0.14, top)               # 오른쪽 옆판
	f.box(back, 0.06, L - 0.06, 0.0, 0.08, 0.14, top - 0.12)  # 안쪽 뒷판(밝게)
	f.box(body, 0.0, L, 0.0, D, top - 0.12, top)              # 윗부분
	f.box(teal, 0.0, L, D - 0.05, D, top - 0.12, top - 0.02)  # 앞 청록 띠

	for r in range(5):
		var y0: float = 0.2 + float(r) * 0.3
		f.box(shelf, 0.06, L - 0.06, 0.1, D - 0.04, y0, y0 + 0.03)

		for j in range(6):
			var u0: float = 0.1 + float(j) * ((L - 0.2) / 6.0)
			f.box(_goods(f, 2 + j % 2), u0, u0 + (L - 0.2) / 6.0 - 0.025, D * 0.32, D - 0.1, y0 + 0.03, y0 + 0.26)

	# 앞 유리문 틀(가운데 세로 손잡이)과 반사
	f.box(dark, 0.06, L - 0.06, D - 0.03, D, 0.14, 0.2)
	f.box(dark, 0.06, 0.1, D - 0.03, D, 0.2, top - 0.12)
	f.box(dark, L - 0.1, L - 0.06, D - 0.03, D, 0.2, top - 0.12)
	f.box(dark, L * 0.5 - 0.015, L * 0.5 + 0.015, D - 0.04, D + 0.01, 0.35, 1.3)
	f.box(glass, 0.12, 0.2, D - 0.02, D, 0.3, top - 0.3)
	return f.finish(1.8)


static func _gondola(f: FurnitureAssets.Frame) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var body: Dictionary = f.flat(WHITE, "go_body")
	var board: Dictionary = f.flat(Color(0.86, 0.88, 0.92), "go_board")
	var teal: Dictionary = f.flat(TEAL, "go_teal", 0.4)
	var tag: Dictionary = f.flat(Color(1.0, 0.95, 0.5), "go_tag", 0.3)
	var dark: Dictionary = f.flat(DARK, "go_dark")
	var top: float = 1.5
	f.box(dark, 0.0, L, 0.0, D, 0.0, 0.1)
	f.box(body, 0.0, 0.07, 0.0, D, 0.1, top)
	f.box(body, L - 0.07, L, 0.0, D, 0.1, top)
	f.box(body, 0.07, L - 0.07, 0.0, 0.05, 0.1, top)          # 뒷판
	f.box(teal, 0.0, L, 0.0, D, top, top + 0.16)              # 윗간판
	var cols: int = maxi(3, int((L - 0.2) / 0.17))
	var cw: float = (L - 0.2) / float(cols)

	for r in range(4):
		var y0: float = 0.16 + float(r) * 0.31
		f.box(board, 0.07, L - 0.07, 0.04, D, y0, y0 + 0.03)
		f.box(tag, 0.09, L - 0.09, D - 0.02, D + 0.005, y0 + 0.005, y0 + 0.03)  # 가격표 띠

		for j in range(cols):
			var u0: float = 0.1 + float(j) * cw
			f.box(_goods(f, (r % 2) * 2 + (j / RUN) % 2), u0, u0 + cw - 0.02, 0.1, D - 0.06, y0 + 0.03, y0 + 0.03 + 0.22)

	return f.finish(1.66)


static func _chest(f: FurnitureAssets.Frame) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var body: Dictionary = f.flat(WHITE, "ch_body")
	var teal: Dictionary = f.flat(TEAL, "ch_teal", 0.4)
	var lid: Dictionary = f.flat(Color(0.8, 0.93, 1.0), "ch_lid", 0.45)
	var dark: Dictionary = f.flat(DARK, "ch_dark")
	f.box(dark, 0.0, L, 0.0, D, 0.0, 0.08)
	f.box(body, 0.0, L, 0.0, D, 0.08, 0.7)
	f.box(teal, 0.0, L, D - 0.04, D, 0.3, 0.44)
	var cols: int = maxi(3, int(L / 0.2))
	var cw: float = (L - 0.16) / float(cols)

	for j in range(cols):
		for k in range(3):
			var v0: float = 0.1 + float(k) * ((D - 0.2) / 3.0)
			f.box(_goods(f, 4 + (j / 2) % 2), 0.08 + float(j) * cw, 0.08 + float(j) * cw + cw - 0.03, v0, v0 + (D - 0.2) / 3.0 - 0.03, 0.7, 0.8)

	f.box(lid, 0.04, L - 0.04, 0.04, D - 0.04, 0.82, 0.86)
	return f.finish(0.9)


static func _rack(f: FurnitureAssets.Frame) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var body: Dictionary = f.flat(WHITE, "rk_body")
	var teal: Dictionary = f.flat(TEAL, "rk_teal", 0.4)
	f.box(body, 0.0, L, 0.0, D, 0.0, 0.08)
	f.box(body, 0.04, 0.1, 0.04, D - 0.04, 0.08, 1.2)
	f.box(body, L - 0.1, L - 0.04, 0.04, D - 0.04, 0.08, 1.2)
	f.box(teal, 0.0, L, 0.0, D, 1.2, 1.3)

	for r in range(3):
		var y0: float = 0.14 + float(r) * 0.36
		f.box(body, 0.04, L - 0.04, 0.04, D - 0.04, y0, y0 + 0.03)

		for j in range(3):
			var u0: float = 0.1 + float(j) * ((L - 0.2) / 3.0)
			f.box(_goods(f, r + 2), u0, u0 + (L - 0.2) / 3.0 - 0.03, 0.08, D - 0.08, y0 + 0.03, y0 + 0.3)

	return f.finish(1.3)


# 계산대: 흰 몸통에 청록 상판, 한쪽에 단말기와 영수증 프린터, 다른 쪽에 상품 바구니. 앞면(손님 쪽)이 v = D.
static func _counter(f: FurnitureAssets.Frame) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var body: Dictionary = f.flat(WHITE, "cn_body")
	var teal: Dictionary = f.flat(TEAL, "cn_teal", 0.4)
	var gray: Dictionary = f.flat(Color(0.74, 0.77, 0.82), "cn_gray")
	var dark: Dictionary = f.flat(DARK, "cn_dark")
	var screen: Dictionary = f.flat(Color(0.55, 0.85, 1.0), "cn_screen", 0.9)
	var top: float = 0.92
	f.box(dark, 0.0, L, 0.0, D, 0.0, 0.08)
	f.box(body, 0.02, L - 0.02, 0.02, D - 0.02, 0.08, top)
	f.box(teal, 0.0, L, 0.0, D, top, top + 0.07)              # 청록 상판
	f.box(teal, 0.02, L - 0.02, D - 0.04, D, 0.2, 0.5)        # 앞면 청록 띠
	# 단말기(POS): 받침 + 화면 + 영수증 프린터
	f.box(gray, 0.25, 0.95, 0.18, 0.55, top + 0.07, top + 0.2)
	f.box(dark, 0.4, 0.8, 0.22, 0.3, top + 0.2, top + 0.58)
	f.box(screen, 0.43, 0.77, 0.3, 0.33, top + 0.24, top + 0.54)
	f.box(gray, 1.05, 1.4, 0.2, 0.5, top + 0.07, top + 0.22)
	# 상품 바구니와 담긴 상품
	f.box(dark, 1.9, L - 0.2, 0.18, 0.62, top + 0.07, top + 0.2)

	for j in range(4):
		var u0: float = 1.95 + float(j) * 0.2
		f.box(_goods(f, j * 3 + 1), u0, u0 + 0.16, 0.22, 0.58, top + 0.2, top + 0.34)

	return f.finish(1.6)


# 취식 탁자: 작은 탁자 하나와 초록 의자 두 개(탁자 양옆). L·D 안에 맞춘다.
static func _table(f: FurnitureAssets.Frame) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var wood: Dictionary = f.flat(Color(0.86, 0.72, 0.52), "tb_wood")
	var green: Dictionary = f.flat(Color(0.2, 0.62, 0.38), "tb_green")
	var dark: Dictionary = f.flat(DARK, "tb_dark")
	var cx: float = L * 0.5
	var cz: float = D * 0.5
	f.box(dark, cx - 0.04, cx + 0.04, cz - 0.04, cz + 0.04, 0.0, 0.5)
	f.box(wood, cx - 0.3, cx + 0.3, cz - 0.3, cz + 0.3, 0.5, 0.56)

	for side in [-1.0, 1.0]:
		var u0: float = cx + side * 0.4 - 0.1
		f.box(dark, u0 + 0.07, u0 + 0.13, cz - 0.04, cz + 0.04, 0.0, 0.28)
		f.box(green, u0, u0 + 0.2, cz - 0.12, cz + 0.12, 0.28, 0.34)
		f.box(green, u0 + (0.16 if side < 0.0 else 0.0), u0 + (0.2 if side < 0.0 else 0.04), cz - 0.12, cz + 0.12, 0.34, 0.62)

	return f.finish(0.65)


# 커피 기계 장: 흰 장 위에 커피 기계와 컵 더미
static func _cabinet(f: FurnitureAssets.Frame) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var body: Dictionary = f.flat(WHITE, "cb_body")
	var teal: Dictionary = f.flat(TEAL, "cb_teal", 0.4)
	var dark: Dictionary = f.flat(DARK, "cb_dark")
	var gray: Dictionary = f.flat(Color(0.78, 0.8, 0.84), "cb_gray")
	f.box(dark, 0.0, L, 0.0, D, 0.0, 0.08)
	f.box(body, 0.02, L - 0.02, 0.02, D - 0.02, 0.08, 0.9)
	f.box(teal, 0.0, L, 0.0, D, 0.9, 0.95)
	f.box(gray, 0.2, 0.7, 0.15, D - 0.15, 0.95, 1.45)          # 커피 기계 몸통
	f.box(dark, 0.28, 0.62, D - 0.18, D - 0.12, 1.05, 1.35)    # 기계 앞 패널
	f.box(_goods(f, 1), L - 0.5, L - 0.34, 0.2, 0.36, 0.95, 1.1)  # 컵 더미
	f.box(_goods(f, 5), L - 0.5, L - 0.34, 0.4, 0.56, 0.95, 1.1)
	return f.finish(1.5)
