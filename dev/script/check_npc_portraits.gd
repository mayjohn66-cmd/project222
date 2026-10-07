extends Node
# 대화 화자 이름 → NPC 초상화 연결 검사(data/story/npc_portraits.csv, NpcPortraits, StoryDialoguePanel).
var checks := 0
var failures := 0

func check(ok: bool, label_text: String) -> void:
	checks += 1
	if ok: print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)

func _ready() -> void:
	var names := ["타블렌", "코르빈", "이세르", "이웃 오렐", "이웃 피니아", "라슈", "엘미", "광부 바르크", "세이나", "델빈", "행상인 타블렌"]
	for n in names:
		var tex: Texture2D = NpcPortraits.find(n)
		check(tex != null, "초상화 찾음: " + n)
		if tex: check(tex.get_width() == 160 and tex.get_height() == 192, "초상화 크기 160x192: " + n)
	check(NpcPortraits.find("순회 기술자") == null, "초상화 없는 역할명은 null")
	check(NpcPortraits.find("나") == null, "플레이어는 초상화 없음")
	var placeholder: Texture2D = load(NpcPortraits.PLACEHOLDER_PATH)
	check(NpcPortraits.resolve("이웃 오렐", placeholder).resource_path == "res://art/npc/neighbor_bread.png", "임시 그림은 인물 초상화로 교체")
	check(NpcPortraits.resolve("순회 기술자", placeholder) == placeholder, "못 찾으면 넘겨받은 그림 유지")
	var other: Texture2D = load("res://art/npc/doyun.png")
	check(NpcPortraits.resolve("타블렌", other) == other, "직접 넘긴 초상화는 그대로")
	var panel := StoryDialoguePanel.new()
	add_child(panel)
	await get_tree().process_frame
	var lines: Array[String] = ["안녕."]
	panel.start("코르빈", null, lines)
	check(panel.portrait.visible and panel.portrait.texture != null and panel.portrait.texture.resource_path == "res://art/npc/doyun.png", "대화창이 null 대신 코르빈 초상화 표시")
	print("checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
