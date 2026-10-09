class_name ExpeditionShopReadinessGuide
extends ExpeditionLoadoutGuide
## 기존 장비 안내의 스크롤·고정 닫기·입력 차단·정리 동작을 재사용한다.
const SHOP_ENABLED := true

static func attach(target: Control) -> void:
	if not SHOP_ENABLED: return
	var guide := ExpeditionShopReadinessGuide.new()
	guide.name = "ShopReadinessGuide"
	guide.prep = target
	target.add_child(guide)

func _ready() -> void:
	super._ready()
	entry.name = "ShopReadinessButton"
	entry.text = "가게 운영 확인"
	entry.tooltip_text = "출발 전 영업 상태와 원정 중 직원의 근무 시간대를 확인합니다."
	entry.position.x = 190
	overlay.name = "ShopReadinessOverlay"
	root.get_child(0).get_child(0).text = "원정 동안의 가게"

func refresh() -> void:
	var next := ExpeditionShopReadinessData.snapshot()
	if next == current: return
	var old_scroll := scroll.scroll_vertical
	current = next
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	if current["valid"]:
		list.add_child(label("출발 전 가게 기록 · " + ExpeditionShopReadinessData.time_text(int(current["hour"]),int(current["minute"])),20))
		list.add_child(label("영업하며 나옴" if current["was_open"] else "닫고 나옴",19))
	list.add_child(label(ExpeditionShopReadinessData.guidance(current)))
	if current["valid"] and current["roster_valid"]:
		list.add_child(label("출발 시각부터 다음 정산까지의 근무표",19))
		list.add_child(label("아래는 담당 시간대입니다. 원정에서 얼마나 오래 머무를지는 플레이어가 정합니다."))
		for band in current["bands"]:
			var period: String = EmployeeData.PERIOD_NAMES.get(band["period"],"")
			var time := ExpeditionShopReadinessData.time_text(int(band["start"]),int(band["minute"])) + " ~ " + ExpeditionShopReadinessData.time_text(int(band["end"]),0,true)
			var names: Array = band["names"]
			list.add_child(label(period + " · " + time,18))
			list.add_child(label("근무자 없음" if names.is_empty() else "근무표 담당 · " + " · ".join(names)))
			if not current["was_open"]: list.add_child(label("가게를 닫고 나와 이 시간에도 손님은 받지 않습니다.",15))
		list.add_child(label("다음 정산 · %02d:00" % GameConfig.DAY_START_HOUR,19))
		list.add_child(label("원정 시간이 정산 시각을 넘기면 복귀 뒤 하루 정산이 이어집니다. 출발 준비와 이 안내를 읽는 시간은 원정 시간에 포함되지 않습니다."))
	list.add_child(label("가게를 정비하려면 이 안내를 닫고 원정 준비 오른쪽 위의 닫기 버튼으로 돌아가세요. 문을 닫거나 직원 근무표를 바꾸는 일은 가게에서 직접 합니다.\n근무표 변경은 아침 %02d:00에 문을 열기 전 정비 시간에 할 수 있습니다." % GameConfig.DAY_START_HOUR))
	scroll.set_deferred("scroll_vertical",old_scroll)
	call_deferred("fit")
