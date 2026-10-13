class_name UiTypography
extends RefCounted
## Silver 원본의 19px 도트 격자를 유지한다. 기본 본문은 2배, 보조 글씨는 1배.
const FONT = preload("res://art/fonts/Silver_ui.tres")
const DESIGN_SIZE := 19
const SMALL_SIZE := DESIGN_SIZE
const DEFAULT_SIZE := DESIGN_SIZE * 2
# 펼친 수첩은 목록과 설명을 같은 배율로 읽고, 제목만 한 단계 크게 쓴다.
const BOOK_BODY_SIZE := SMALL_SIZE
const BOOK_CONTROL_SIZE := SMALL_SIZE
const BOOK_HEADING_SIZE := DEFAULT_SIZE

static func size(legacy_size: int) -> int:
	if legacy_size < 18:
		return SMALL_SIZE
	# 18~24px였던 본문·버튼을 19px로 축소하지 않는다. 큰 제목도 정수 배수만 사용한다.
	return maxi(DEFAULT_SIZE, roundi(float(legacy_size) * 1.55 / DESIGN_SIZE) * DESIGN_SIZE)
