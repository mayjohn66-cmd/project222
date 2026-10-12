class_name UiTypography
extends RefCounted
## 기존 UI 글자 크기를 Silver의 실제 글자 높이에 맞춘다. 폰트 원본은 보존한다.
const FONT = preload("res://art/fonts/Silver_ui.tres")
const DEFAULT_SIZE := 28

static func size(legacy_size: int) -> int:
	return maxi(20, roundi(float(legacy_size) * 1.55 / 2.0) * 2)
