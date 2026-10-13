extends Node
## 계산 손맛 검사: 스캔 판정·빗나감 한도·팁(5%), 손님 인내심, 간편 계산 옵션, 데이터 일관성.
var checks := 0
var failures := 0


class FakeRegister extends Node:
	var waiting = null
	var reserved_worker = null
	func get_waiting_customer():
		return waiting


class FakeCustomer extends Node:
	var purchase_completed := false
	var force_exit_requested := false
	var wanted_event_id := ""
	var target_register = null
	var register_wait := 0.0


class FakeGuide extends FakeCustomer:
	func can_be_checked_out_by(_actor: Node) -> bool:
		return true


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _ready() -> void:
	CheckoutData.reload_data()
	# 데이터
	check(is_equal_approx(CheckoutData.value("tip_rate"), 0.05), "팁 비율은 5%")
	check(CheckoutData.value("scan_perfect_half") < CheckoutData.value("scan_good_half"), "완벽 구간이 보통 구간보다 좁다")
	check(CheckoutData.value("patience_seconds") > 0.0, "인내심 시간이 있다")

	# 팁
	check(CheckoutScan.tip_for(100) == 5, "100G의 팁은 5G")
	check(CheckoutScan.tip_for(101) == 6, "팁은 올림")
	check(CheckoutScan.tip_for(3) == 1, "팁 최소 1G")

	# 판정
	var scan := CheckoutScan.new()
	scan.start(0.5)
	check(is_equal_approx(scan.center, 0.5), "roll 0.5 면 목표가 가운데")
	scan.cursor = scan.center
	check(scan.zone() == CheckoutScan.PERFECT, "목표 한가운데는 완벽")
	scan.cursor = scan.center + (scan.perfect_half + scan.good_half) * 0.5
	check(scan.zone() == CheckoutScan.GOOD, "완벽 밖·보통 안은 보통")
	scan.cursor = scan.center + scan.good_half + 0.05
	check(scan.zone() == CheckoutScan.MISS, "구간 밖은 빗나감")
	check(scan.press(0.5) == CheckoutScan.MISS and scan.misses == 1, "첫 빗나감은 다시 시도")
	scan.cursor = scan.center + scan.good_half + 0.05
	check(scan.press(0.5) == CheckoutScan.FAILED, "빗나감 한도에서 자동 계산")
	var edge := CheckoutScan.new()
	edge.start(0.0)
	check(edge.center - edge.good_half > 0.0, "목표가 막대 끝에 붙지 않는다(왼쪽)")
	edge.start(1.0)
	check(edge.center + edge.good_half < 1.0, "목표가 막대 끝에 붙지 않는다(오른쪽)")

	# 커서 왕복
	var sweep := CheckoutScan.new()
	sweep.start(0.5)
	var seen_high := false
	var seen_back := false
	for i in range(400):
		sweep.step(0.01)
		if sweep.cursor > 0.95:
			seen_high = true
		if seen_high and sweep.cursor < 0.5:
			seen_back = true
		if sweep.cursor < 0.0 or sweep.cursor > 1.0:
			check(false, "커서가 막대를 벗어남")
	check(seen_high and seen_back, "커서가 끝까지 갔다가 되돌아온다")

	# 인내심
	var register := FakeRegister.new()
	add_child(register)
	var customer := FakeCustomer.new()
	add_child(customer)
	customer.target_register = register
	register.waiting = customer
	check(CheckoutPatience.tick(customer, 1.0) == "" and customer.register_wait == 1.0, "기다리면 시간이 쌓인다")
	var limit: float = CheckoutData.value("patience_seconds")
	var warn_at: float = limit * (1.0 - CheckoutData.value("patience_warn_ratio"))
	customer.register_wait = warn_at - 0.5
	check(CheckoutPatience.tick(customer, 1.0) == "warn", "절반 지나면 한 번 재촉")
	check(CheckoutPatience.tick(customer, 1.0) == "", "재촉은 한 번만")
	customer.register_wait = limit - 0.5
	check(CheckoutPatience.tick(customer, 1.0) == "leave", "한도를 넘으면 떠난다")
	customer.register_wait = 0.0
	register.reserved_worker = self
	check(CheckoutPatience.tick(customer, 5.0) == "" and customer.register_wait == 0.0, "계산 중에는 인내심이 줄지 않는다")
	register.reserved_worker = null
	register.waiting = null
	check(CheckoutPatience.tick(customer, 5.0) == "", "계산대에 서지 않았으면 줄지 않는다")
	register.waiting = customer
	customer.wanted_event_id = "some_event"
	check(CheckoutPatience.tick(customer, 5.0) == "", "이벤트 손님은 기다려 준다")
	customer.wanted_event_id = ""
	customer.set_meta("regular_story_item", "water")
	check(CheckoutPatience.tick(customer, 5.0) == "", "이야기 손님은 기다려 준다")
	customer.remove_meta("regular_story_item")
	var guide := FakeGuide.new()
	add_child(guide)
	guide.target_register = register
	register.waiting = guide
	check(CheckoutPatience.tick(guide, 99.0) == "", "튜토리얼 손님은 기다려 준다")
	customer.purchase_completed = true
	register.waiting = customer
	check(CheckoutPatience.tick(customer, 99.0) == "", "결제된 손님은 줄지 않는다")

	# 간편 계산 옵션
	CheckoutOptions.set_simple(true)
	check(CheckoutOptions.simple(), "간편 계산 켬")
	CheckoutOptions.set_simple(false)
	check(not CheckoutOptions.simple(), "간편 계산 끔")
	var settings: Dictionary = GameSettingsService.new().load_settings()
	check(settings.has("simple_checkout"), "설정에 간편 계산 항목이 있다")

	print("CHECK_CHECKOUT_SCAN checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
