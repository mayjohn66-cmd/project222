class_name BookViews
extends RefCounted
## 관리 창을 "펼친 노트"로 보이게 하는 그리기 부품 세 가지.
##   Paper : 펼친 두 쪽(가운데 제본 홈과 그림자), 쌓인 쪽의 가장자리, 얇은 표지 두께, 포스트잇이 붙는 오른쪽 옆면
##   Cover : 닫힌 책의 세로형 표지(제목 명패·점장 명패·초록 책갈피 끈)와 표지가 제본선을 축으로 넘어가며 펼쳐지는 장면
##   Flip  : 탭을 옮길 때 책장이 넘어가는 장면. 옛 화면과 새 화면을 사진으로 떠서 한 장의 종이 앞뒤로 쓴다
## 모든 그림은 MainPanel 전체 크기(= 쪽 영역 + 오른쪽 내비게이션 NAV_W) 기준이다.

const COVER_PAD := 6.0  # 표지가 쪽 둘레로 보이는 두께
const FORE_W := 10.0  # 오른쪽 쪽 옆면 폭
const BOTTOM_T := 6.0  # 아래쪽 쪽 옆면 두께
const NAV_W := 104.0  # 포스트잇 내비게이션 폭
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
		# 가운데 제본 홈: 양쪽 쪽이 안쪽으로 휘며 어두워진다
		if left_visible:
			for i in range(20):
				var a := 0.20 * pow(1.0 - float(i) / 20.0,2.0)
				draw_rect(Rect2(mid - float(i) - 1.0,0,1,h - 3.0),Color(0.33,0.24,0.14,a))
				draw_rect(Rect2(mid + float(i),0,1,h - 3.0),Color(0.33,0.24,0.14,a))
			draw_line(Vector2(mid,0),Vector2(mid,h - 3.0),Color(0.33,0.24,0.14,0.45),2.0)


# ---------------------------------------------------------------- 표지와 펼침
class Cover extends Control:
	func _host_size() -> Vector2:
		var host := _ref()
		return host.size if host != null else size

	# 기준 노드 = MainPanel 의 첫 자식인 Paper(늘 보이므로 크기가 낡지 않는다). PanelContainer 는 둘레 여백만큼 안쪽으로 자식을 맞추므로 부모 크기를 그대로 쓰면 어긋난다.
	func _ref() -> Control:
		var host := get_parent()
		return host.get_child(0) as Control if host != null and host.get_child_count() > 0 else null

	## angle 0 = 닫힘, 1 = 표지가 세워짐(90도), 2 = 표지가 왼쪽으로 완전히 넘어가 왼쪽 쪽이 됨.
	## 닫힌 책은 오른쪽 쪽 자리(가운데 제본선에서 오른쪽)에 세로형 표지로 놓인다.
	var angle: float = 0.0
	var title_text: String = "영업 일지"
	var owner_text: String = "점장"

	func set_angle(value: float) -> void:
		angle = value
		queue_redraw()

	func _draw() -> void:
		var width := BookViews.page_width(_host_size())
		var mid := width * 0.5
		var h := _host_size().y
		var cp := BookViews.COVER_PAD
		var y0 := -cp
		var y1 := h + BookViews.BOTTOM_T + cp
		var theta := clampf(angle,0.0,2.0) * PI * 0.5
		var k := cos(theta)
		if absf(k) < 0.015 and angle > 0.0: return
		var lift := 12.0 * sin(theta)
		var shade := 1.0 - 0.38 * (1.0 - absf(k))
		var tint := Color(shade,shade,shade,1.0)
		if k >= 0.0:
			_draw_cover(mid,width + BookViews.FORE_W + cp,y0,y1,k,lift,tint)
		else:
			# 넘어간 표지의 안쪽(면지): 왼쪽 쪽 자리에 펼쳐지며 쪽 색에 가까워진다
			var w := (mid + cp) * absf(k)
			var poly := PackedVector2Array([Vector2(mid,y0),Vector2(mid - w,y0 - lift),Vector2(mid - w,y1 + lift),Vector2(mid,y1)])
			draw_colored_polygon(poly,Color("ece0c0").lerp(BookViews.PAGE,absf(k)))
			draw_polyline(PackedVector2Array([poly[1],poly[2]]),Color("9c8a68"),2.0)
			draw_line(poly[0],poly[3],Color(0.33,0.24,0.14,0.5),2.0)

	func _draw_cover(x_spine: float,x_end: float,y0: float,y1: float,k: float,lift: float,tint: Color) -> void:
		BookViews.paint_cover(self,get_theme_default_font(),x_spine,x_end,y0,y1,k,lift,tint,title_text,owner_text)


# ---------------------------------------------------------------- 책장 넘기기(탭 이동)
class Flip extends Control:
	# 숨겨져 있는 동안은 컨테이너가 크기를 다시 맞춰 주지 않아 size 가 낡을 수 있으므로, 기준은 늘 부모(MainPanel)의 크기다.
	func _host_size() -> Vector2:
		var host := _ref()
		return host.size if host != null else size

	# 기준 노드 = MainPanel 의 첫 자식인 Paper(늘 보이므로 크기가 낡지 않는다). PanelContainer 는 둘레 여백만큼 안쪽으로 자식을 맞추므로 부모 크기를 그대로 쓰면 어긋난다.
	func _ref() -> Control:
		var host := get_parent()
		return host.get_child(0) as Control if host != null and host.get_child_count() > 0 else null

	## 뒤쪽 탭으로 가면 오른쪽 쪽이 왼쪽으로, 앞쪽 탭으로 가면 왼쪽 쪽이 오른쪽으로 넘어간다.
	## 넘어가는 한 장의 앞면 = 옛 화면의 그쪽 쪽, 뒷면 = 새 화면의 반대쪽 쪽. 바닥에는 옛/새 화면의 나머지 쪽이 보인다.
	const DURATION := 0.5
	var forward: bool = true
	var t: float = 0.0
	var active: bool = false
	var tex_old_left: Texture2D
	var tex_old_right: Texture2D
	var tex_new_left: Texture2D
	var tex_new_right: Texture2D
	var tween: Tween
	var last_tab: int = -1

	# 쪽 영역(= 이 컨트롤의 왼쪽 위에서 쪽 폭 × (높이-3))을 화면 사진으로 떠서 왼쪽/오른쪽 반으로 돌려준다. 헤드리스면 빈 배열.
	func capture_halves() -> Array:
		if DisplayServer.get_name() == "headless" or not ManagementMenu.PRESENTATION.animations_enabled: return []
		var shot := get_viewport().get_texture().get_image()
		if shot == null or shot.is_empty(): return []
		var ratio := Vector2(shot.get_size()) / get_viewport_rect().size
		var width := BookViews.page_width(_host_size())
		var origin := _ref().get_global_rect().position
		var left := Rect2i(origin * ratio,Vector2(width * 0.5,_host_size().y - 3.0) * ratio)
		var right := Rect2i((origin + Vector2(width * 0.5,0.0)) * ratio,Vector2(width * 0.5,_host_size().y - 3.0) * ratio)
		var bounds := Rect2i(Vector2i.ZERO,shot.get_size())
		left = left.intersection(bounds)
		right = right.intersection(bounds)
		if left.size.x <= 0 or left.size.y <= 0 or right.size.x <= 0 or right.size.y <= 0: return []
		return [ImageTexture.create_from_image(shot.get_region(left)),ImageTexture.create_from_image(shot.get_region(right))]

	# 탭을 옮기기 직전(옛 화면이 아직 보일 때) 부른다. 새 화면이 그려진 뒤 한 번 더 사진을 떠 책장 넘김을 시작한다.
	func begin(is_forward: bool) -> void:
		if tween and tween.is_valid(): tween.kill()
		var old := capture_halves()
		if old.is_empty():
			active = false
			hide()
			return
		forward = is_forward
		tex_old_left = old[0]
		tex_old_right = old[1]
		tex_new_left = null
		tex_new_right = null
		t = 0.0
		active = true
		show()
		queue_redraw()
		# 새 화면을 사진으로 뜨려면 덮개를 한 프레임 걷어야 한다: 걷은 프레임이 그려진 직후 사진을 뜨고 바로 덮개를 다시 씌운다(새 화면이 보이는 것은 한 프레임)
		hide()
		await RenderingServer.frame_post_draw
		var fresh := capture_halves()
		show()
		if fresh.is_empty():
			active = false
			hide()
			return
		tex_new_left = fresh[0]
		tex_new_right = fresh[1]
		tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_method(_set_t,0.0,1.0,DURATION)
		tween.tween_callback(func() -> void:
			active = false
			hide())

	func _set_t(value: float) -> void:
		t = value
		queue_redraw()

	func _draw() -> void:
		if not active or tex_old_left == null: return
		var width := BookViews.page_width(_host_size())
		var half := width * 0.5
		var ph := _host_size().y - 3.0
		var theta := clampf(t,0.0,1.0) * PI
		var k := cos(theta)
		var lift := 10.0 * sin(theta)
		var left_rect := Rect2(0,0,half,ph)
		var right_rect := Rect2(half,0,half,ph)
		if tex_new_left == null:
			# 새 화면을 아직 못 뜬 동안은 옛 화면을 그대로 보여 준다
			draw_texture_rect(tex_old_left,left_rect,false)
			draw_texture_rect(tex_old_right,right_rect,false)
			return
		if forward:
			draw_texture_rect(tex_old_left,left_rect,false)
			draw_texture_rect(tex_new_right,right_rect,false)
			if k >= 0.0:
				var w := half * k
				_shadow(half + w,half + w + 26.0 * sin(theta) + 4.0,0.28 * sin(theta))
				_leaf(tex_old_right,half,half + w,lift,1.0 - 0.3 * (1.0 - k),ph,false)
			else:
				var w2 := half * absf(k)
				_shadow(half - w2 - 26.0 * sin(theta) - 4.0,half - w2,0.28 * sin(theta),true)
				_leaf(tex_new_left,half - w2,half,lift,1.0 - 0.3 * (1.0 - absf(k)),ph,true)
		else:
			draw_texture_rect(tex_new_left,left_rect,false)
			draw_texture_rect(tex_old_right,right_rect,false)
			if k >= 0.0:
				var w3 := half * k
				_shadow(half - w3 - 26.0 * sin(theta) - 4.0,half - w3,0.28 * sin(theta),true)
				_leaf(tex_old_left,half - w3,half,lift,1.0 - 0.3 * (1.0 - k),ph,true)
			else:
				var w4 := half * absf(k)
				_shadow(half + w4,half + w4 + 26.0 * sin(theta) + 4.0,0.28 * sin(theta))
				_leaf(tex_new_right,half,half + w4,lift,1.0 - 0.3 * (1.0 - absf(k)),ph,false)

	# x0~x1 폭으로 눌린 한 장. 바깥(자유) 모서리가 눈앞으로 들려 위아래로 조금 커 보인다.
	func _leaf(tex: Texture2D,x0: float,x1: float,lift: float,shade: float,ph: float,free_left: bool) -> void:
		if x1 - x0 < 1.0: return
		var pts: PackedVector2Array
		if free_left:
			pts = PackedVector2Array([Vector2(x0,-lift),Vector2(x1,0),Vector2(x1,ph),Vector2(x0,ph + lift)])
		else:
			pts = PackedVector2Array([Vector2(x0,0),Vector2(x1,-lift),Vector2(x1,ph + lift),Vector2(x0,ph)])
		draw_polygon(pts,PackedColorArray([Color(shade,shade,shade,1.0)]),PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]),tex)
		draw_polyline(PackedVector2Array([pts[0],pts[3]]) if free_left else PackedVector2Array([pts[1],pts[2]]),Color(0.55,0.43,0.27,0.8),2.0)

	# 넘어가는 한 장의 자유 모서리 옆으로 번지는 그림자. reverse = false 면 x0 쪽이 짙고 오른쪽으로, true 면 x1 쪽이 짙고 왼쪽으로 옅어진다.
	func _shadow(x0: float,x1: float,alpha: float,reverse: bool = false) -> void:
		var steps := 10
		var seg := (x1 - x0) / float(steps)
		var ph := _host_size().y - 3.0
		for i in range(steps):
			var a := alpha * pow(1.0 - float(i) / float(steps),2.0)
			var xa := x0 + seg * float(i) if not reverse else x1 - seg * float(i + 1)
			draw_rect(Rect2(xa,0,seg + 1.0,ph),Color(0.2,0.14,0.08,a))
