class_name CheckoutPatience
extends RefCounted
## 계산대 앞 손님의 인내심. 시간이 다 되면 물건을 두고 나간다.
## 수치는 CheckoutData(CSV). 튜토리얼·이야기·이벤트 손님은 기다려 준다.


static func exempt(customer: Node) -> bool:
	return customer.has_method("can_be_checked_out_by") \
		or customer.has_meta("regular_story_item") \
		or not str(customer.wanted_event_id).is_empty()


# 기다리는 중이면 true (인내심이 줄어드는 상황).
static func ticking(customer: Node) -> bool:
	if customer.purchase_completed or customer.force_exit_requested or exempt(customer):
		return false
	var register = customer.target_register
	if not is_instance_valid(register) or register.get_waiting_customer() != customer:
		return false
	return not is_instance_valid(register.reserved_worker)


# 한 걸음. "" / "warn" / "leave" 중 하나를 돌려준다.
static func tick(customer: Node, delta: float) -> String:
	if not ticking(customer):
		return ""
	var limit: float = maxf(CheckoutData.value("patience_seconds"), 1.0)
	var before: float = customer.register_wait
	customer.register_wait = before + delta
	if customer.register_wait >= limit:
		return "leave"
	var warn_at: float = limit * (1.0 - CheckoutData.value("patience_warn_ratio"))
	if before < warn_at and customer.register_wait >= warn_at:
		return "warn"
	return ""


static func ratio_left(customer: Node) -> float:
	return clampf(1.0 - customer.register_wait / maxf(CheckoutData.value("patience_seconds"), 1.0), 0.0, 1.0)
