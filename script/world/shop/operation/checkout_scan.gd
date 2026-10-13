class_name CheckoutScan
extends RefCounted
## 계산 스캔 타이밍 규칙. 막대 위를 오가는 커서가 목표 구간에 있을 때 누르면 성공이다.
## 화면 그리기는 CheckoutScanView, 수치는 CheckoutData(CSV)에 있다.

const PERFECT := "perfect"   # 완벽: 팁
const GOOD := "good"         # 보통: 성공, 팁 없음
const MISS := "miss"         # 빗나감: 다시 시도
const FAILED := "failed"     # 빗나감 한도: 자동 계산, 팁 없음

var cursor: float = 0.0
var center: float = 0.5
var direction: float = 1.0
var misses: int = 0
var perfect_half: float = 0.07
var good_half: float = 0.17
var sweep_seconds: float = 0.9
var miss_limit: int = 2


# center_roll: 0~1 난수. 시험에서 같은 값을 줄 수 있게 밖에서 받는다.
func start(center_roll: float) -> void:
	perfect_half = CheckoutData.value("scan_perfect_half")
	good_half = CheckoutData.value("scan_good_half")
	sweep_seconds = maxf(CheckoutData.value("scan_sweep_seconds"), 0.05)
	miss_limit = maxi(int(CheckoutData.value("scan_miss_limit")), 1)
	misses = 0
	cursor = 0.0
	direction = 1.0
	_roll_center(center_roll)


func _roll_center(roll: float) -> void:
	# 가장자리는 피한다(커서가 끝에서 되돌아오는 구간).
	var low: float = good_half + 0.08
	center = lerpf(low, 1.0 - low, clampf(roll, 0.0, 1.0))


func step(delta: float) -> void:
	cursor += direction * delta / sweep_seconds
	if cursor >= 1.0:
		cursor = 2.0 - cursor
		direction = -1.0
	elif cursor <= 0.0:
		cursor = -cursor
		direction = 1.0
	cursor = clampf(cursor, 0.0, 1.0)


func zone() -> String:
	var distance: float = absf(cursor - center)
	if distance <= perfect_half:
		return PERFECT
	if distance <= good_half:
		return GOOD
	return MISS


# 버튼을 눌렀을 때 판정. 빗나가면 목표 위치를 새로 굴린다.
func press(next_center_roll: float) -> String:
	var result: String = zone()
	if result != MISS:
		return result
	misses += 1
	if misses >= miss_limit:
		return FAILED
	_roll_center(next_center_roll)
	return MISS


static func tip_for(price: int) -> int:
	return maxi(int(ceil(float(price) * CheckoutData.value("tip_rate"))), int(CheckoutData.value("tip_min")))
