class_name ExpeditionGatheringToolGuide
extends RefCounted

static func required_tool(table: String) -> String:
	var rule: Dictionary = ExpeditionGatheringData.get_rule(table)
	if not bool(rule.get("tool_required", false)): return ""
	var effect := str(rule.get("tool_effect_id", ""))
	var instruction := EarlyProgressionGuide.tool_instruction(effect)
	return instruction if not instruction.is_empty() else "이 채집물에는 도구가 필요합니다. 출발 전에 가방을 확인하세요."
