extends RefCounted
## 인물 설정은 문서 한 곳에서 읽고 요청한 화자의 부분만 대사 문맥에 넣는다.

const PATH := "res://docs/drafts/story/character_profiles.md"
const ID_ALIASES := {"neighbor":"neighbor_bread", "peddler":"naru", "settle_naru":"naru", "gem_hunter":"doyun", "settle_doyun":"doyun", "relic_hunter":"sora", "settle_sora":"sora"}


static func load_profiles() -> Dictionary:
	return parse(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else {"guidance":"", "profiles":{}}


static func parse(text: String) -> Dictionary:
	var profiles: Dictionary = {}
	var guidance: PackedStringArray = []
	var current_id := ""
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("## "):
			current_id = ""
			var header := line.trim_prefix("## ").split(" — ", false, 1)
			if header.size() == 2:
				current_id = header[0].strip_edges()
				profiles[current_id] = {"name":header[1].strip_edges(), "lines":PackedStringArray()}
			continue
		if line.begins_with("#") or line.begins_with(">"):
			continue
		if current_id.is_empty():
			guidance.append(line)
		else:
			var body: PackedStringArray = profiles[current_id]["lines"]
			body.append(line)
			profiles[current_id]["lines"] = body
	return {"guidance":"\n".join(guidance).strip_edges(), "profiles":profiles}


static func for_speaker(data: Dictionary, speaker: String, source_id: String = "") -> String:
	var profiles: Dictionary = data.get("profiles", {})
	var selected := ""
	var label := speaker.strip_edges()
	# 역할 화자가 명시되어 있으면 손님 유형 ID로 이름 있는 주민을 추측하지 않는다.
	if not label.is_empty():
		for id in profiles:
			var name := str(profiles[id]["name"])
			if label == name or label.ends_with(" " + name):
				selected = str(id)
				break
	else:
		selected = str(ID_ALIASES.get(source_id, source_id))
	if not profiles.has(selected):
		return ""
	var profile: Dictionary = profiles[selected]
	return "[인물 설정 참고: %s]\n%s\n%s" % [profile["name"], data.get("guidance", ""), "\n".join(profile["lines"]).strip_edges()]
