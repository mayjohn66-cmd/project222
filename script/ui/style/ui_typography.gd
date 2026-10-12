class_name UiTypography
extends RefCounted
## Silver 원본의 19px 도트 격자를 유지한다. 기본 본문은 2배, 보조 글씨는 1배.
const FONT = preload("res://art/fonts/Silver_ui.tres")
const DESIGN_SIZE := 19
const SMALL_SIZE := DESIGN_SIZE
const DEFAULT_SIZE := DESIGN_SIZE * 2

static func size(legacy_size: int) -> int:
	if legacy_size < 18:
		return SMALL_SIZE
	# 18~24px였던 본문·버튼을 19px로 축소하지 않는다. 큰 제목도 정수 배수만 사용한다.
	return maxi(DEFAULT_SIZE, roundi(float(legacy_size) * 1.55 / DESIGN_SIZE) * DESIGN_SIZE)
