class_name ResidentFollowthroughGuide
extends RefCounted
## Keep a delivered request's follow-up focused; no acceptance, consumption or rewards.
const ENABLED := true

static func personal_lines(resident_id: String, afterglow: String) -> Array[String]:
	var lines: Array[String] = []
	if ENABLED and not afterglow.is_empty(): return lines
	for request in PersonalRequestFlow.entries():
		if request["resident"] != resident_id or PersonalRequestFlow.done(str(request["id"])) or not PersonalRequestFlow.locked_reason(request).is_empty(): continue
		lines.append_array(RequestTextData.lines("personal_request",str(request["id"])))
		lines.append(UiText.t("request.followthrough.personal_hint"))
	return lines

static func story_button(is_accepted: bool, is_done: bool, repeats: bool, reason: String, active_caption: String) -> String:
	if is_accepted: return active_caption
	if ENABLED and is_done:
		if not repeats: return UiText.t("request.followthrough.finished")
		if not reason.is_empty(): return UiText.t("request.followthrough.repeat_wait")
	return "이야기 맡기" if reason.is_empty() else "다음 소식을 기다리는 중"
