extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
var failures := 0

func check(ok: bool, label_text: String) -> void:
	if ok: print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)

func _ready() -> void:
	var rows := RequestTextData.read_file(RequestTextData.CSV_PATH)
	var sources := Tools.load_sources()
	var count := 0
	for kind in sources:
		for id in sources[kind]:
			count += 1
			check(rows.has(kind + ":" + id), "known content has CSV text: " + kind + "/" + id)
	check(rows.size() == count, "all content rows are known to writer tools")
	var validation := Tools.validate_file(RequestTextData.CSV_PATH,sources)
	check(validation["errors"].is_empty(), "all game prose passes writer rules: " + str(validation["errors"]))
	check(validation["warns"].is_empty(), "game prose avoids obsolete quantities and long completion text: " + str(validation["warns"]))
	var resident := RequestTextData.enrich(ResidentRequestFlow.SETTINGS.requests[0], "resident_request")
	check(resident["id"] == "neighbor_bread" and resident["item"] == "bread" and resident["amount"] == 2 and resident["money"] == 30, "enrichment preserves gameplay fields")
	var original: String = resident["title"]
	RequestTextData._rows["resident_request:neighbor_bread"]["title"] = "CSV에서 바꾼 제목"
	check(RequestTextData.enrich(ResidentRequestFlow.SETTINGS.requests[0], "resident_request")["title"] == "CSV에서 바꾼 제목", "runtime reads text by id without baking it into resource")
	RequestTextData.reload()
	check(RequestTextData.enrich(ResidentRequestFlow.SETTINGS.requests[0], "resident_request")["title"] == original, "reload restores source text")
	check(RequestTextData.enrich(ResidentStoryFlow.SETTINGS.settlement_requests[0], "resident_request")["lines"].size() == 3 and RequestTextData.enrich(ResidentStoryFlow.SETTINGS.introductions[0], "resident_introduction")["lines"].size() == 3, "settlement and introduction dialogue remain arrays")
	check(not ResidentRequestFlow.SETTINGS.requests[0].has("lines") and not ResidentRequestFlow.SETTINGS.requests[0].has("title"), "settings store gameplay only in editor and runtime")
	check(VillageLifeFlow.resident("naru")["greetings"].size() == 4, "all four time-of-day greetings are retained")
	var missing := RequestTextData.enrich({"id":"new_unwritten", "amount":9},"resident_greeting")
	check(missing["greetings"].size() == 4 and missing["amount"] == 9, "unwritten greeting is safe and preserves gameplay")
	var path := "user://request_text_csv_probe.csv"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_csv_line(RequestTextData.COLUMNS)
	file.store_csv_line(PackedStringArray(["same","service_text","쉼표, 따옴표 \"시험\"","여러\n줄","첫 줄|둘째 줄",""]))
	file.store_csv_line(PackedStringArray(["same","resident_greeting","","","다른 종류",""]))
	file.close()
	var probe := RequestTextData.read_file(path)
	check(probe.size() == 2 and probe["service_text:same"]["title"] == "쉼표, 따옴표 \"시험\"" and probe["service_text:same"]["summary"] == "여러\n줄", "CSV quoting newlines and kind/id namespaces round trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("CHECK_REQUEST_TEXT_RUNTIME failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
