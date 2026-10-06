class_name RequestPaymentText
extends RefCounted
## 표시만 구분한다. 소비·답례 지급·진행 기록은 기존 흐름에서 처리한다.

static func is_gift(entry: Dictionary) -> bool:
	return str(entry.get("payment_kind", "")) == "gift"

static func notice(entry: Dictionary) -> String:
	return "나눔 부탁 · 물품 대금은 별도로 받지 않습니다." if is_gift(entry) else ""

static func label(entry: Dictionary) -> String:
	return "답례" if is_gift(entry) else "보상"
