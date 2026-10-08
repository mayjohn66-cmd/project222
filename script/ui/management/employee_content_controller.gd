class_name EmployeeContentController
extends Node
var host
var hire_dialog: ConfirmationDialog
var dialogue: StoryDialoguePanel
var pending_hire: Node
var pending_story := ""
var current_story := ""
var elapsed := 0.0

func _ready() -> void:
	host = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	hire_dialog = ConfirmationDialog.new()
	hire_dialog.title = "고용 조건 확인"
	hire_dialog.ok_button_text = "고용하기"
	hire_dialog.cancel_button_text = "돌아가기"
	add_child(hire_dialog)
	_style_confirmation(hire_dialog)
	_style_confirmation(host.dismiss_dialog)
	hire_dialog.confirmed.connect(_confirm_hire)
	hire_dialog.canceled.connect(func(): pending_hire = null)
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_end_story)
	host.visibility_changed.connect(_host_visibility_changed)

func _style_confirmation(window: ConfirmationDialog) -> void:
	# 책 위 제목, 어두운 본문, 밝은 버튼에 맞춰 각각의 글자색을 지정한다.
	window.add_theme_color_override("title_color", Color("332619"))
	window.get_label().add_theme_color_override("font_color", Color("f9edda"))
	for button in [window.get_ok_button(), window.get_cancel_button()]:
		for color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(color, Color("332619"))

func request_hire(worker: Node) -> void:
	var reason := EmployeeStoryFlow.hire_reason(worker)
	if not reason.is_empty():
		host.message_label.text = reason
		return
	if dialogue.open or hire_dialog.visible: return
	pending_hire = worker
	hire_dialog.dialog_text = EmployeeStoryFlow.terms(worker)
	hire_dialog.popup_centered(Vector2i(580, 310))

func _confirm_hire() -> void:
	var worker := pending_hire
	pending_hire = null
	var reason := EmployeeStoryFlow.hire_reason(worker)
	if not reason.is_empty():
		host.message_label.text = reason
		return
	host._hire_worker(worker)

func add_card(parent: VBoxContainer, worker: Node) -> void:
	var id := str(worker.get("employee_id"))
	var entry := EmployeeStoryFlow.profile(id)
	if entry.is_empty(): return
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = str(entry["role"])
	label.text += "\n고용 비용 %d G · %d일 기준 급여 %d G" % [worker.get_hire_cost(), CalendarData.DAYS_PER_SEASON, EmployeeData.get_monthly_salary(id)]
	parent.add_child(label)
	var button := Button.new()
	button.custom_minimum_size.y = 42
	button.text = "직원의 이야기 듣기" if not EmployeeStoryFlow.unread(id).is_empty() else "함께한 기억 다시 읽기"
	button.pressed.connect(func(): open_story(id))
	parent.add_child(button)
	# 새 행동이 발생하면 카드의 버튼 문구를 다음 갱신에서 바꾼다.

func open_story(id: String) -> void:
	if not EmployeeRecruitmentFlow.met(id): return
	if dialogue.open or hire_dialog.visible: return
	var entry := EmployeeStoryFlow.unread(id)
	pending_story = str(entry.get("id", ""))
	current_story = pending_story
	var lines: Array[String] = []
	if entry.is_empty(): lines.append(EmployeeStoryFlow.memory(id))
	else: lines = RequestTextData.lines("service_text", pending_story)
	dialogue.start(str(EmployeeData.get_employee(id).get("display_name", "직원")), null, lines)

func _end_story() -> void:
	if not pending_story.is_empty() and dialogue.line_index >= dialogue.lines.size(): EmployeeStoryFlow.finish(pending_story)
	pending_story = ""
	current_story = ""
	if is_instance_valid(host): host.refresh_view()

func after_action(id: String, event: String) -> void:
	EmployeeStoryFlow.record(id, event)
	host.refresh_view()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 1.0: return
	elapsed = 0.0
	for worker in get_tree().get_nodes_in_group("worker"):
		var id := str(worker.get("employee_id"))
		if bool(worker.get("is_hired")):
			EmployeeStoryFlow.observe_existing(id)
			if bool(worker.get("on_duty")) and worker.visible and not EmployeeStoryFlow.available(id, "first_shift"):
				EmployeeStoryFlow.record(id, "first_shift")
				host.refresh_view()
				if host.is_visible_in_tree(): host.message_label.text = "첫 근무를 시작했습니다. 다음 아침 오픈 준비 중에 교육 탭을 살펴보세요."

func _host_visibility_changed() -> void:
	if host.is_visible_in_tree(): return
	pending_hire = null
	hire_dialog.hide()
	host._cancel_dismiss()
	host.dismiss_dialog.hide()
	if dialogue.open: dialogue.close()

func _input(event: InputEvent) -> void:
	if dialogue.open and not event.is_echo() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		dialogue.close()
