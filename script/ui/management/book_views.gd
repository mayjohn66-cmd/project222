class_name BookViews
extends RefCounted
## 관리 창을 "펼친 노트"로 보이게 하는 그리기 부품 세 가지.
##   Paper : 펼친 두 쪽(가운데 제본 홈과 그림자), 쌓인 쪽의 가장자리, 얇은 표지 두께, 포스트잇이 붙는 오른쪽 옆면
##   Hint  : 책 아래 "ESC 닫기" 안내(3D 책 쪽에서 화면 위에 얹는다)
##   (표지·책장 넘김은 3D 책 BookStage3D / BookFlip3D 가 맡는다. 3D 를 못 쓰는 헤드리스에서는 Paper 가 2D 로 책 모양을 그린다)
## 모든 그림은 MainPanel 전체 크기(= 쪽 영역 + 오른쪽 내비게이션 NAV_W) 기준이다.

const COVER_PAD := 6.0  # 표지가 쪽 둘레로 보이는 두께
const FORE_W := 10.0  # 오른쪽 쪽 옆면 폭
const BOTTOM_T := 6.0  # 아래쪽 쪽 옆면 두께
const NAV_W := 104.0  # 포스트잇 내비게이션 폭
const ONTO := 12.0  # 펼친 탭의 포스트잇이 쪽 안쪽 여백으로 붙는 길이(쪽 내용 여백 안이라 UI 를 가리지 않는다)
const FLAG_TEXT := Color("2b2f55")
const PAGE := Color("f5eddc")
const LEATHER := Color("70503b")
const LEATHER_DARK := Color("3d2a1d")
const GOLD := Color("d9a441")
const BRAND := Color("235740")
# 탭마다 쪽 종이 색이 조금씩 다르다(인벤토리·생산·직원·설계도·건설·일정·정보 순)
const TAB_PAPERS := ["f5eddc","f7eddf","f0f1e3","edf1ec","f4eddf","f3edf2","edf1ef"]


static func page_width(control_size: Vector2) -> float:
	return control_size.x - NAV_W

# 닫힌 책의 표지 한 면을 canvas 에 그린다(2D 표지 연출과 3D 책의 표지 질감이 같은 그림을 쓴다).
# x_spine = 제본선, x_end = 바깥 끝, k = 가로로 눌린 정도(1 = 활짝), lift = 자유 모서리가 들린 만큼, tint = 밝기 곱.
static func paint_cover(canvas: CanvasItem,font: Font,x_spine: float,x_end: float,y0: float,y1: float,k: float,lift: float,tint: Color,title_text: String,owner_text: String) -> void:
	var wc := (x_end - x_spine) * k
	var poly := PackedVector2Array([Vector2(x_spine,y0),Vector2(x_spine + wc,y0 - lift),Vector2(x_spine + wc,y1 + lift),Vector2(x_spine,y1)])
	canvas.draw_colored_polygon(poly,LEATHER * tint)
	# 아래쪽 두께와 왼쪽 제본(척추) 띠
	canvas.draw_rect(Rect2(x_spine,y1 - 4.0,wc,8.0),LEATHER_DARK * tint)
	canvas.draw_rect(Rect2(x_spine,y0,minf(14.0 * k,wc),y1 - y0),LEATHER_DARK * tint)
	canvas.draw_line(Vector2(x_spine + 14.0 * k,y0),Vector2(x_spine + 14.0 * k,y1),GOLD * tint,2.0)
	# 금박 테두리와 모서리 징
	var inset := 16.0
	var fx0 := x_spine + 26.0 * k
	var fx1 := x_spine + wc - inset * k
	if fx1 - fx0 > 12.0:
		canvas.draw_rect(Rect2(fx0,y0 + inset,fx1 - fx0,y1 - y0 - inset * 2.0),GOLD * tint,false,2.0)
		for c in [Vector2(fx0,y0 + inset),Vector2(fx1,y0 + inset),Vector2(fx0,y1 - inset),Vector2(fx1,y1 - inset)]:
			canvas.draw_circle(c,4.0 * k,GOLD * tint)
	# 제목 명패(위)와 점장 명패(아래)
	if k > 0.5:
		var cx := x_spine + wc * 0.5 + 6.0
		var alpha := clampf((k - 0.5) * 3.0,0.0,1.0)
		var plate_w := minf(wc * 0.62,240.0)
		var top := Rect2(cx - plate_w * 0.5,y0 + (y1 - y0) * 0.16,plate_w,74.0)
		canvas.draw_rect(top,BRAND * tint)
		canvas.draw_rect(top,GOLD * tint,false,3.0)
		var low := Rect2(cx - plate_w * 0.36,y1 - (y1 - y0) * 0.2,plate_w * 0.72,40.0)
		canvas.draw_rect(low,LEATHER_DARK * tint)
		canvas.draw_rect(low,GOLD * tint,false,2.0)
		if font != null:
			_centered(canvas,font,title_text,top,30,Color(1,1,1,alpha))
			_centered(canvas,font,owner_text,low,19,Color(0.98,0.92,0.75,alpha))
		# 초록 책갈피 끈
		canvas.draw_rect(Rect2(x_spine + wc * 0.82,y1 - 4.0,10.0,30.0),Color("2f7a58") * tint)


static func _centered(canvas: CanvasItem,font: Font,text: String,box: Rect2,font_size: int,color: Color) -> void:
	var sz := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	var asc := font.get_ascent(font_size)
	canvas.draw_string(font,Vector2(box.position.x + (box.size.x - sz.x) * 0.5,box.position.y + (box.size.y - sz.y) * 0.5 + asc),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)


# 포스트잇 한 장을 그린다(오른쪽 줄·왼쪽 줄·책장에 실려 넘어가는 3D 포스트잇이 모두 이 그림을 쓴다 → 어디서나 같은 모양).
# r = 포스트잇 전체 자리(쪽 위에 붙은 부분 포함), mirrored = 왼쪽 가장자리용(거울상), fold = 쪽 가장자리가 r 안쪽 어디에 있는지(r 의 붙은 쪽 끝에서부터의 거리, 쪽 위에 붙은 만큼).
static func paint_flag(c: CanvasItem,font: Font,r: Rect2,color: Color,label: String,mirrored: bool,fold: float,with_text: bool,with_shadow: bool = true) -> void:
	var dir := -1.0 if mirrored else 1.0
	var ax := r.end.x - fold if mirrored else r.position.x + fold  # 쪽 가장자리의 x
	var top := r.position.y
	var bottom := r.end.y
	if with_shadow:
		c.draw_rect(Rect2(r.position + Vector2(-3.0 if mirrored else 3.0,4.0),r.size),Color(0.16,0.11,0.06,0.28))
	# 본체: 한 장의 종이. 위가 밝고 아래가 살짝 짙다
	c.draw_polygon(PackedVector2Array([Vector2(r.position.x,top),Vector2(r.end.x,top),Vector2(r.end.x,bottom),Vector2(r.position.x,bottom)]),PackedColorArray([color.lightened(0.10),color.lightened(0.08),color.darkened(0.03),color.darkened(0.03)]))
	# 쪽 가장자리에서 꺾이는 곳: 바깥쪽으로 12px 가 어두워졌다가 풀린다
	var shade := Color(0.2,0.14,0.08,0.34)
	var clear := Color(0.2,0.14,0.08,0.0)
	c.draw_polygon(PackedVector2Array([Vector2(ax,top),Vector2(ax + dir * 12.0,top),Vector2(ax + dir * 12.0,bottom),Vector2(ax,bottom)]),PackedColorArray([shade,clear,clear,shade]))
	if fold > 0.5:
		c.draw_line(Vector2(ax,top),Vector2(ax,bottom),color.darkened(0.22),1.0)
	# 윤곽과 붙은 쪽 끝의 접착 자국
	c.draw_rect(r,color.darkened(0.25),false,1.5)
	var glue_x := r.end.x if mirrored else r.position.x
	c.draw_line(Vector2(glue_x,top),Vector2(glue_x,bottom),color.darkened(0.3),2.0)
	if with_text and font != null:
		var sz := font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,15)
		var ty := top + (bottom - top) * 0.5 + sz.y * 0.5 - font.get_descent(15)
		var tx := ax - 16.0 - sz.x if mirrored else ax + 16.0
		c.draw_string(font,Vector2(tx,ty),label,HORIZONTAL_ALIGNMENT_LEFT,-1,15,FLAG_TEXT)


# 책장에 실려 넘어가는 포스트잇의 질감용(3D): 자기 크기 전체에 포스트잇 한 장(그림자 없음). 2 배로 그려 또렷하게 한다.
class FlagFace extends Control:
	var color: Color = Color.WHITE
	var label: String = ""
	var mirrored: bool = false

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO,0.0,Vector2(2.0,2.0))
		BookViews.paint_flag(self,get_theme_default_font(),Rect2(0.0,0.0,size.x * 0.5,size.y * 0.5),color,label,mirrored,0.0,true,false)


# 포스트잇 질감 한 장을 SubViewport 로 한 번 그려 돌려준다(parent 의 자식으로 붙는다. 다 쓰면 parent 쪽에서 free).
static func make_flag_art(parent: Node,color: Color,label: String,mirrored: bool,flag_px: Vector2) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(flag_px * 2.0)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var face := FlagFace.new()
	face.color = color
	face.label = label
	face.mirrored = mirrored
	face.size = Vector2(vp.size)
	vp.add_child(face)
	parent.add_child(vp)
	return vp


# 3D 책의 표지 질감 그리기용: 자기 크기 전체에 표지 한 면(제본선이 왼쪽)을 그린다.
class CoverFace extends Control:
	var title_text: String = "영업 일지"
	var owner_text: String = "점장"

	func _draw() -> void:
		BookViews.paint_cover(self,get_theme_default_font(),0.0,size.x,0.0,size.y,1.0,0.0,Color.WHITE,title_text,owner_text)



# ---------------------------------------------------------------- 펼친 두 쪽
class Paper extends Control:
	var mode: int = 0  # 현재 탭: 종이 색과 바탕무늬(설계도 모눈, 건설 모눈, 일정 왼쪽 띠)를 정한다
	var left_visible: bool = true  # false 면 닫히는 중·열리기 전이라 오른쪽 반만 그린다(왼쪽 쪽은 표지가 넘어와 덮은 뒤 나타난다)
	var pages_only: bool = false  # true 면 두 쪽의 종이면(색·무늬·제본 홈)만 그린다. 표지·쪽 옆면·그림자는 3D 책이 맡는다

	# 책 오른쪽 아래, 표지 바깥에 키캡 모양 "ESC" 와 "닫기"를 적는다(바닥 어두운 곳에 밝게).
	func _draw_hint(width: float,h: float) -> void:
		var font := get_theme_default_font()
		if font == null: return
		var y := h + BookViews.BOTTOM_T + BookViews.COVER_PAD + 8.0
		var key := Rect2(width - 112.0,y,46.0,22.0)
		draw_rect(key,Color("f5eddc"))
		draw_rect(key,Color("b9a582"),false,2.0)
		draw_string(font,Vector2(key.position.x + 7.0,key.position.y + 16.0),"ESC",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("44392e"))
		draw_string(font,Vector2(key.end.x + 8.0,key.position.y + 17.0),"닫기",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("f5eddc"))

	func set_mode(value: int) -> void:
		mode = clampi(value,0,BookViews.TAB_PAPERS.size() - 1)
		queue_redraw()

	func set_left_visible(value: bool) -> void:
		left_visible = value
		queue_redraw()

	func _draw() -> void:
		var width := BookViews.page_width(size)
		var h := size.y
		var mid := width * 0.5
		var cp := BookViews.COVER_PAD
		var fw := BookViews.FORE_W
		var bt := BookViews.BOTTOM_T
		var x_left := -cp if left_visible else mid - 2.0
		if pages_only:
			_draw_surfaces(width,h,mid)
			return
		# 바닥 그림자와 표지(뒷면 두께 → 앞면 → 안쪽 단)
		draw_rect(Rect2(x_left + 2.0,-cp + 2.0,width + fw + cp - x_left + 2.0,h + bt + cp * 2.0 + 4.0),Color("1d141055"))
		draw_rect(Rect2(x_left,-cp,width + fw + cp + 4.0 - x_left,h + bt + cp + 4.0),Color("4a3223"))
		draw_rect(Rect2(x_left,-cp,width + fw + cp + 4.0 - x_left,h + bt + cp + 1.0),BookViews.LEATHER)
		draw_rect(Rect2(x_left + 3.0,-cp + 3.0,width + fw + cp - 2.0 - x_left,h + bt + cp - 5.0),Color("5c4130"))
		# 쪽 더미: 맨 위 쪽 아래로 두세 장이 살짝 겹쳐 보인다
		for e in [3,2,1]:
			if left_visible:
				draw_rect(Rect2(-e,e,mid + e,h),Color("e4d7bb"))
				draw_rect(Rect2(-e,e,mid + e,h),Color("b9a582"),false,1)
			draw_rect(Rect2(mid,e,width - mid + e,h),Color("e4d7bb"))
			draw_rect(Rect2(mid,e,width - mid + e,h),Color("b9a582"),false,1)
		_draw_page_faces(width,h,mid)
		# 오른쪽 옆면: 쪽이 쌓인 가는 줄무늬. 포스트잇이 이 위에 붙는다
		var fore_x := width - 2.0
		draw_rect(Rect2(fore_x,2,fw,h - 4.0),Color("efe3c7"))
		var y := 3.0
		var toggle := false
		while y < h - 3.0:
			draw_line(Vector2(fore_x,y),Vector2(fore_x + fw,y),Color("b9a582") if toggle else Color("fffaf0"),1)
			toggle = not toggle
			y += 2.0
		draw_line(Vector2(fore_x + fw,2),Vector2(fore_x + fw,h - 2.0),Color("9c8a68"),1)
		# 왼쪽 옆면(표지 두께 안쪽의 얇은 줄무늬)
		if left_visible:
			draw_rect(Rect2(-4,3,4,h - 6.0),Color("efe3c7"))
			for ly in range(4,int(h) - 4,2):
				draw_line(Vector2(-4,ly),Vector2(0,ly),Color("b9a582"),1)
		# 아래쪽 쪽 옆면
		draw_rect(Rect2(2 if left_visible else mid,h - 3.0,width + fw - (2.0 if left_visible else mid),bt),Color("efe3c7"))
		for k in range(1,3):
			draw_line(Vector2(2 if left_visible else mid,h - 3.0 + k * 2.0),Vector2(width + fw,h - 3.0 + k * 2.0),Color("b9a582"),1)
		# 책 아래의 조작 안내: 닫기 버튼 대신 키 표기로 알린다
		_draw_hint(width,h)
		_draw_gutter(h,mid)

	func _draw_surfaces(width: float,h: float,mid: float) -> void:
		_draw_page_faces(width,h,mid)
		_draw_gutter(h,mid)

	func _draw_page_faces(width: float,h: float,mid: float) -> void:
		var page := Color(BookViews.TAB_PAPERS[mode])
		if left_visible:
			draw_rect(Rect2(0,0,mid,h - 3.0),page)
		draw_rect(Rect2(mid,0,width - mid,h - 3.0),page)
		# 탭별 바탕무늬: 쪽 전체에 깔린다(안쪽 사각형 없이 종이 자체의 무늬)
		if mode == 3 or mode == 4:
			var line := Color(0.3,0.5,0.6,0.07) if mode == 3 else Color(0.5,0.4,0.2,0.06)
			for gx in range(0,int(width),24):
				if left_visible or float(gx) >= mid: draw_line(Vector2(gx,0),Vector2(gx,h - 3.0),line)
			for gy in range(0,int(h - 3.0),24):
				draw_line(Vector2(0.0 if left_visible else mid,gy),Vector2(width,gy),line)
		elif mode == 5 and left_visible:
			draw_rect(Rect2(0,0,8,h - 3.0),Color("897299"))

	func _draw_gutter(h: float,mid: float) -> void:
		# 가운데 제본 홈: 양쪽 쪽이 안쪽으로 휘며 어두워진다
		if left_visible:
			for i in range(20):
				var a := 0.20 * pow(1.0 - float(i) / 20.0,2.0)
				draw_rect(Rect2(mid - float(i) - 1.0,0,1,h - 3.0),Color(0.33,0.24,0.14,a))
				draw_rect(Rect2(mid + float(i),0,1,h - 3.0),Color(0.33,0.24,0.14,a))
			draw_line(Vector2(mid,0),Vector2(mid,h - 3.0),Color(0.33,0.24,0.14,0.45),2.0)


# ---------------------------------------------------------------- 포스트잇 책갈피
# 진짜 포스트잇처럼: 책 밖으로 나온 부분은 살짝 기울고 쪽 가장자리에서 꺾이는 그림자가 있으며, 쪽 위로 넘어온 부분(펼친 탭)은 반투명 필름이라 쪽의 글이 비친다.
class Strip extends Control:
	## 책 밖으로 튀어나온 포스트잇들(내비게이션 버튼 아래에 깔리는 그림). items = [{rect: Rect2(이 컨트롤 기준 버튼 자리), color: Color}]
	var items: Array = []
	var hover: int = -1

	func set_items(list: Array) -> void:
		items = list
		queue_redraw()

	func set_hover(i: int) -> void:
		hover = i
		queue_redraw()

	func _draw() -> void:
		for i in range(items.size()):
			if bool(items[i].get("hidden",false)): continue  # 왼쪽 가장자리로 옮겨 갔거나 책장에 실려 가는 중
			var r: Rect2 = items[i]["rect"]
			var fold := 0.0
			if bool(items[i].get("current",false)):
				# 펼친 탭: 한 장의 포스트잇이 쪽 가장자리를 감싸 안쪽 여백(ONTO)까지 붙는다
				r = Rect2(r.position - Vector2(BookViews.ONTO,0.0),r.size + Vector2(BookViews.ONTO,0.0))
				fold = BookViews.ONTO
			if i == hover: r.size.x += 6.0
			BookViews.paint_flag(self,null,r,items[i]["color"],"",false,fold,false)  # 글자는 내비게이션 버튼이 쓴다


class Note extends Control:
	## 펼친 탭의 포스트잇이 쪽 위로 넘어온 부분: 반투명 필름(쪽의 글이 비침) + 쪽 가장자리에서 꺾이는 그림자 + 끝의 접착 자국.
	var rect: Rect2 = Rect2()
	var color: Color = Color.WHITE

	func set_note(r: Rect2,c: Color) -> void:
		rect = r
		color = c
		queue_redraw()

	func _draw() -> void:
		if rect.size.x <= 0.0: return
		# 필름 아래 쪽에 드리우는 그림자
		draw_rect(Rect2(rect.position + Vector2(1.5,3.0),rect.size),Color(0.2,0.14,0.08,0.20))
		# 반투명 필름
		var film := color.lerp(Color.WHITE,0.30)
		draw_rect(rect,Color(film.r,film.g,film.b,0.50))
		# 쪽 가장자리(오른쪽 끝) 꺾임: 오른쪽으로 갈수록 어두워짐
		var steps := 10
		for k in range(steps):
			var f := float(k) / float(steps)
			draw_rect(Rect2(rect.end.x - rect.size.x * 0.28 * (1.0 - f) - 1.0,rect.position.y,rect.size.x * 0.28 / float(steps) + 1.0,rect.size.y),Color(0.2,0.14,0.08,0.22 * f))
		# 윤곽과 끝(접착) 자국
		draw_rect(rect,Color(color.r * 0.7,color.g * 0.7,color.b * 0.7,0.85),false,1.5)
		draw_rect(Rect2(rect.position,Vector2(5.0,rect.size.y)),Color(color.r * 0.85,color.g * 0.85,color.b * 0.85,0.75))


# 책 아래 "ESC 닫기" 안내: 키캡 모양 "ESC" 와 "닫기"(바닥 어두운 곳에 밝게)
class Hint extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(112.0,24.0)
		size = custom_minimum_size

	func _draw() -> void:
		var font := get_theme_default_font()
		if font == null: return
		var key := Rect2(0.0,0.0,46.0,22.0)
		draw_rect(key,Color("f5eddc"))
		draw_rect(key,Color("b9a582"),false,2.0)
		draw_string(font,Vector2(7.0,16.0),"ESC",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("44392e"))
		draw_string(font,Vector2(key.end.x + 8.0,17.0),"닫기",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("f5eddc"))


# 현재 탭보다 앞 탭의 포스트잇: 넘어간 종이에 붙은 채 책의 왼쪽 가장자리에 모인다(오른쪽 Strip 의 거울상). 누르면 그 탭으로 돌아간다.
class LeftFlags extends Control:
	signal picked(tab: int)
	## items = [{tab: int, rect: Rect2(이 컨트롤 기준, 쪽 가장자리에서 왼쪽으로 뻗는 자리), color: Color, label: String}]
	var items: Array = []
	var hover: int = -1
	var enabled: bool = true

	func set_items(list: Array) -> void:
		items = list
		queue_redraw()

	func _item_at(p: Vector2) -> int:
		for i in range(items.size()):
			if (items[i]["rect"] as Rect2).grow(2.0).has_point(p): return i
		return -1

	func _has_point(point: Vector2) -> bool:
		return enabled and _item_at(point) >= 0

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var h := _item_at((event as InputEventMouseMotion).position)
			if h != hover:
				hover = h
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var i := _item_at((event as InputEventMouseButton).position)
			if i >= 0:
				accept_event()
				picked.emit(int(items[i]["tab"]))

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT and hover != -1:
			hover = -1
			queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		for i in range(items.size()):
			var r: Rect2 = items[i]["rect"]
			if i == hover: r = Rect2(r.position - Vector2(6.0,0.0),r.size + Vector2(6.0,0.0))
			BookViews.paint_flag(self,font,r,items[i]["color"],items[i]["label"],true,0.0,true)
