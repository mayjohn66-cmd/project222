class_name BookFlowVBox
extends VBoxContainer
## 두 쪽에 걸쳐 흐르는 세로 목록. 자식들을 왼쪽 쪽에 위에서부터 채우다가 절반을 넘으면 오른쪽 쪽으로 넘긴다(자식 하나는 쪼개지 않는다).
## 기존 VBoxContainer 노드에 set_script 로 씌워 쓰므로, 그 노드에 자식을 더하는 기존 코드는 바꾸지 않아도 된다.
## 두 쪽 사이 간격은 BookLayout.GUTTER. 필요한 높이(_min_h)는 두 단 중 긴 쪽이라서, 글이 길면 감싼 ScrollContainer 가 한꺼번에 스크롤한다.

var _min_h: float = 0.0


func _get_minimum_size() -> Vector2:
	return Vector2(0.0,_min_h)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_flow()


func _flow() -> void:
	var gap: float = BookLayout.GUTTER
	var col_w := maxf((size.x - gap) * 0.5,1.0)
	var sep := float(get_theme_constant("separation"))
	var items: Array[Control] = []
	for c in get_children():
		if c is Control and (c as Control).visible and not (c as Control).top_level:
			items.append(c)
	# 단 폭에 맞춘 뒤의 높이(줄바꿈하는 글은 폭이 정해져야 높이가 정해진다)
	var heights: Array[float] = []
	var total := 0.0
	for c in items:
		fit_child_in_rect(c,Rect2(0.0,0.0,col_w,c.get_combined_minimum_size().y))
		var h := c.get_combined_minimum_size().y
		heights.append(h)
		total += h + sep
	var half := total * 0.5
	var col := 0
	var y := 0.0
	var left_h := 0.0
	var right_h := 0.0
	for i in range(items.size()):
		if col == 0 and y > 0.0 and y + heights[i] * 0.5 > half:
			left_h = y - sep
			col = 1
			y = 0.0
		fit_child_in_rect(items[i],Rect2(float(col) * (col_w + gap),y,col_w,heights[i]))
		y += heights[i] + sep
	if col == 0: left_h = y - sep
	else: right_h = y - sep
	var need := maxf(maxf(left_h,right_h),0.0)
	if not is_equal_approx(need,_min_h):
		_min_h = need
		update_minimum_size()
