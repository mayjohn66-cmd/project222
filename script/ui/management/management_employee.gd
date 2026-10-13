extends Control

enum EmployeeTab {
	SCHEDULE,
	EMPLOYMENT,
	TRAINING,
	INFO
}

var current_employee_tab: EmployeeTab = EmployeeTab.SCHEDULE
var employee_tab_buttons: Dictionary = {}

@onready var employee_scroll: ScrollContainer = (
	$MainVBox/EmployeeScroll
)

@onready var employee_list: GridContainer = (
	$MainVBox/EmployeeScroll/EmployeeList
)

@onready var message_label: Label = (
	$MainVBox/MessageLabel
)

@onready var dismiss_dialog: ConfirmationDialog = (
	$DismissDialog
)

@onready var schedule_button: Button = (
	$MainVBox/Tabs/ScheduleButton
)

@onready var employment_button: Button = (
	$MainVBox/Tabs/EmploymentButton
)

@onready var training_button: Button = (
	$MainVBox/Tabs/TrainingButton
)

@onready var info_button: Button = (
	$MainVBox/Tabs/InfoButton
)

var pending_dismiss_worker: Node = null
var employee_content: EmployeeContentController

func _ready() -> void:
	# 씬에 배치된 탭 버튼을 enum 값과 연결한다.
	employee_tab_buttons = {
		EmployeeTab.SCHEDULE: schedule_button,
		EmployeeTab.EMPLOYMENT: employment_button,
		EmployeeTab.TRAINING: training_button,
		EmployeeTab.INFO: info_button,
	}

	for raw_tab in employee_tab_buttons:
		var tab: int = int(raw_tab)
		var button: Button = employee_tab_buttons[raw_tab]

		button.pressed.connect(
			_select_employee_tab.bind(tab)
		)

	dismiss_dialog.confirmed.connect(_confirm_dismiss)
	dismiss_dialog.canceled.connect(_cancel_dismiss)
	employee_content = EmployeeContentController.new()
	add_child(employee_content)

	refresh_view()


func refresh_view() -> void:
	if not is_instance_valid(employee_list):
		return

	EmployeeProgressUI.refresh(self)
	employee_list.columns = 2
	# 기존 직원 카드 제거
	for child in employee_list.get_children():
		employee_list.remove_child(child)
		child.queue_free()

	# 현재 탭 버튼 비활성화
	for tab in employee_tab_buttons:
		var button: Button = employee_tab_buttons[tab]
		InteractionUiStyle.select_tab(button,int(tab) == int(current_employee_tab))

	# 탭 안내 문구
	match current_employee_tab:
		EmployeeTab.SCHEDULE:
			message_label.text = (
				"이어진 시간대를 최대 2타임까지 선택합니다(각 6시간, 심야와 저녁도 이어집니다)."
				+ "\n모두 해제하면 휴무입니다. 변경 후 적용을 눌러주세요."
			)

		EmployeeTab.EMPLOYMENT:
			message_label.text = (
				"직원을 고용하거나 해고합니다."
				+ "\n아침 6시 오픈 준비 중에 변경할 수 있습니다."
				+ "\n이야기와 고용 조건을 살핀 뒤, 고용한 직원의 근무표를 지정하세요."
			)

		EmployeeTab.TRAINING:
			message_label.text = (
				"교육할 능력을 선택합니다."
				+ "\n아침 6시 오픈 준비 중인 고용 직원만 교육할 수 있습니다."
			)

		EmployeeTab.INFO:
			message_label.text = (
				"직원별 능력치와 이번 급여 기간을 확인합니다."
				+ "\n전체 미지급 급여: %dG"
				% GameState.get_unpaid_employee_salary()
			)

	if current_employee_tab == EmployeeTab.EMPLOYMENT:
		message_label.text = EmployeeRecruitmentFlow.guide(get_tree().get_nodes_in_group("worker"))
		if EmployeeRecruitmentFlow.has_hired(get_tree().get_nodes_in_group("worker")):
			message_label.text += "\n고용·해고는 아침 6시 오픈 준비 중에 변경합니다."

	# worker 그룹에서 직원 노드 조회
	var workers: Array[Node] = (
		get_tree().get_nodes_in_group("worker")
	)

	if EmployeeNextStepGuide.ENABLED:
		message_label.text = EmployeeNextStepGuide.tab_message(self,workers)

	var visible_employee_count: int = 0

	for worker in workers:
		if not is_instance_valid(worker):
			continue

		if worker.is_queued_for_deletion():
			continue

		if not worker.has_method(
			"get_employee_display_name"
		):
			continue

		var hired: bool = bool(
			worker.get("is_hired")
		)

		# 근무표와 교육에는 고용된 직원만 표시
		if (
			current_employee_tab
			== EmployeeTab.SCHEDULE
			or current_employee_tab
			== EmployeeTab.TRAINING
		):
			if not hired:
				continue

		if not EmployeeProgressUI.show_worker(self, worker): continue
		_create_employee_entry(worker)
		visible_employee_count += 1

	# 표시할 직원이 없는 경우
	if visible_employee_count <= 0:
		match current_employee_tab:
			EmployeeTab.SCHEDULE:
				message_label.text += (
					"\n\n현재 고용된 직원이 없습니다."
				)

			EmployeeTab.EMPLOYMENT:
				if not EmployeeNextStepGuide.ENABLED:
					message_label.text += "\n\n아직 소개를 들은 지원자가 없습니다. 가게 앞에서 인사를 나눠 보세요."

			EmployeeTab.TRAINING:
				message_label.text += (
					"\n\n교육할 수 있는 고용 직원이 없습니다."
				)


func _create_employee_entry(worker: Node) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	employee_list.add_child(panel)

	var margin := MarginContainer.new()

	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override(
			"margin_" + side,
			0
		)

	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	var identity_row := HBoxContainer.new()
	identity_row.add_theme_constant_override("separation",18)
	margin.add_child(content)
	content.add_child(identity_row)
	var portrait := TextureRect.new()
	var frames = load("res://art/characters/cozy_v1/"+str(worker.get("employee_id"))+"/frames.tres") as SpriteFrames
	if frames: portrait.texture = frames.get_frame_texture("idle_down",0)
	portrait.custom_minimum_size = Vector2(56,64)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	identity_row.add_child(portrait)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL


	var name_label := Label.new()
	name_label.text = str(worker.get_employee_display_name())
	name_label.add_theme_font_size_override("font_size", UiTypography.BOOK_HEADING_SIZE)
	identity_row.add_child(name_label)

	var hired: bool = bool(worker.get("is_hired"))
	var status: String = "비근무"

	if not hired:
		status = "재고용 후보" if PlayerProgress.story_beat_days.has(EmployeeStoryFlow.PREFIX + str(worker.get("employee_id")) + ":hire_count") else "지원자"
	elif bool(worker.get("shift_ending")):
		status = "퇴근 처리 중"
	elif bool(worker.get("on_duty")):
		status = "근무 중"

	var summary := Label.new()
	summary.text = (
		"상태: " + status
		+ "\n" + str(worker.get_preferred_period_text())
	)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(summary)
	if employee_content != null and current_employee_tab == EmployeeTab.EMPLOYMENT: employee_content.add_card(content, worker)

	match current_employee_tab:
		EmployeeTab.SCHEDULE:
			_create_schedule_controls(content, worker)

		EmployeeTab.EMPLOYMENT:
			_create_employment_controls(content, worker)

		EmployeeTab.TRAINING:
			var ability_label := Label.new()
			ability_label.autowrap_mode = (
				TextServer.AUTOWRAP_WORD_SMART
			)
			ability_label.text = (
				"현재 적용: 계산 %.2f초 · 진열 %.2f초"
				% [
					float(
						worker.get_effective_checkout_time()
					),
					float(
						worker.get_effective_restock_time()
					)
				]
				+ "\n이동 속도: %.1f"
				% float(
					worker.get_effective_move_speed()
				)
			)
			content.add_child(ability_label)

			_create_training_controls(
				content,
				worker
			)

		EmployeeTab.INFO:
			_create_employee_info(
				content,
				worker
			)


func _create_employee_info(
	parent: VBoxContainer,
	worker: Node
) -> void:
	var employee_id: String = str(
		worker.get("employee_id")
	)

	var employee: Dictionary = (
		EmployeeData.get_employee(employee_id)
	)

	if employee.is_empty():
		var error_label := Label.new()
		error_label.text = "직원 데이터를 찾을 수 없습니다."
		parent.add_child(error_label)
		return

	var salary_record: Dictionary = (
		GameState.get_employee_salary_record(
			employee_id
		)
	)

	var accrued_days: int = maxi(
		int(
			salary_record.get(
				"accrued_days",
				0
			)
		),
		0
	)

	var monthly_salary: int = (
		EmployeeData.get_monthly_salary(
			employee_id
		)
	)

	var accrued_salary: int = (
		GameState.get_employee_accrued_salary(
			employee_id
		)
	)

	var schedule_names := PackedStringArray()

	for period in worker.get_work_periods():
		schedule_names.append(
			EmployeeNextStepGuide.period_text(str(period)) if EmployeeNextStepGuide.ENABLED else EmployeeData.get_period_name(str(period))
		)

	var schedule_text: String = "휴무"

	if not schedule_names.is_empty():
		schedule_text = " · ".join(schedule_names)

	var info_label := Label.new()
	info_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)

	info_label.text = (
		"[근무 정보]"
		+ "\n근무표: " + schedule_text
		+ "\n" + str(
			worker.get_preferred_period_text()
		)

		+ "\n\n[능력치]"
		+ "\n계산: Lv.%d · %.2f초"
		% [
			worker.get_training_level(
				"checkout"
			),
			float(
				worker.get_effective_checkout_time()
			)
		]
		+ "\n진열: Lv.%d · %.2f초"
		% [
			worker.get_training_level(
				"restock"
			),
			float(
				worker.get_effective_restock_time()
			)
		]
		+ "\n이동: Lv.%d · 속도 %.1f"
		% [
			worker.get_training_level(
				"movement"
			),
			float(
				worker.get_effective_move_speed()
			)
		]
		+ "\n응대: Lv.%d · 추천 성공률 %.0f%%"
		% [
			worker.get_training_level(
				"service"
			),
			float(
				worker.get_customer_service_chance()
			) * 100.0
		]

		+ "\n\n[급여]"
		+ "\n%d일 기준 급여: %dG" % [CalendarData.DAYS_PER_SEASON,monthly_salary]
		+ "\n이번 기간 고용한 날: %d일" % accrued_days
		+ "\n현재 누적 급여: %dG" % accrued_salary
	)

	parent.add_child(info_label)


func _get_checked_periods(
	checks: Dictionary
) -> Array[String]:
	var result: Array[String] = []

	for period in ["morning", "day", "evening", "night"]:
		var check: CheckBox = checks[period]

		if check.button_pressed:
			result.append(period)

	return result


func _on_work_period_toggled(
	_pressed: bool,
	checks: Dictionary,
	editable: bool
) -> void:
	_refresh_period_checks(checks, editable)


func _refresh_period_checks(
	checks: Dictionary,
	editable: bool
) -> void:
	var selected: Array[String] = _get_checked_periods(checks)

	for period in ["morning", "day", "evening", "night"]:
		var check: CheckBox = checks[period]

		if not editable:
			check.disabled = true
			continue

		# 이미 선택된 항목은 항상 해제 가능
		if check.button_pressed:
			check.disabled = false
			continue

		# 이 항목을 추가했을 때 유효한 조합인지 검사
		var candidate: Array[String] = selected.duplicate()
		candidate.append(period)

		check.disabled = (
			not EmployeeData.is_work_periods_valid(candidate)
		)


func _apply_period_schedule(
	worker: Node,
	checks: Dictionary
) -> void:
	if not is_instance_valid(worker):
		refresh_view()
		return

	if worker.is_queued_for_deletion():
		refresh_view()
		return

	var selected: Array[String] = _get_checked_periods(checks)
	var employee_name: String = str(
		worker.get_employee_display_name()
	)

	var success: bool = worker.set_work_periods(selected)

	refresh_view()

	if success:
		message_label.text = (
			employee_name + "의 근무표를 적용했습니다." + ("\n" + EmployeeNextStepGuide.first_shift(worker,EmployeeNextStepGuide.manager_for(self)) if EmployeeNextStepGuide.ENABLED else "")
		)
	else:
		message_label.text = (
			"근무표를 적용하지 못했습니다. 변경 가능 시간을 확인해주세요."
		)

func _hire_worker(worker: Node) -> void:
	if not is_instance_valid(worker):
		refresh_view()
		return

	if worker.is_queued_for_deletion():
		refresh_view()
		return

	var worker_name: String = worker.get_employee_display_name()
	var success: bool = worker.hire_employee()

	refresh_view()
	_refresh_money_displays()

	if success:
		employee_content.after_action(str(worker.get("employee_id")), "hired")
		message_label.text = (
			worker_name + "을 고용했습니다. 근무표를 지정해주세요."
		)
	else:
		message_label.text = (
			"고용하지 못했습니다. 소지금과 변경 가능 시간을 확인해주세요."
		)


func _request_dismiss(worker: Node) -> void:
	if not is_instance_valid(worker):
		return

	if worker.is_queued_for_deletion():
		return

	if not worker.can_change_employment():
		return

	pending_dismiss_worker = worker

	dismiss_dialog.dialog_text = EmployeeStoryFlow.terms(worker, true)

	dismiss_dialog.popup_centered()


func _confirm_dismiss() -> void:
	var worker: Node = pending_dismiss_worker
	pending_dismiss_worker = null

	if not is_instance_valid(worker):
		refresh_view()
		return

	if worker.is_queued_for_deletion():
		refresh_view()
		return

	var worker_name: String = worker.get_employee_display_name()
	var success: bool = worker.dismiss_employee()

	refresh_view()

	if success:
		employee_content.after_action(str(worker.get("employee_id")), "dismissed")
		message_label.text = worker_name + "을 해고했습니다."
	else:
		message_label.text = "현재는 해고할 수 없습니다."


func _cancel_dismiss() -> void:
	pending_dismiss_worker = null


func _refresh_money_displays() -> void:
	# 관리 메뉴 하단 소지금 갱신
	var ancestor: Node = get_parent()

	while ancestor != null:
		if ancestor.has_method("refresh_common_info"):
			ancestor.call("refresh_common_info")
			break

		ancestor = ancestor.get_parent()

	# 게임 화면의 소지금 갱신
	var scene: Node = get_tree().current_scene

	if scene == null:
		return

	var player_node: Node = scene.get_node_or_null("Actors/Player")

	if player_node != null:
		if player_node.has_method("update_money_ui"):
			player_node.call("update_money_ui")

func _create_training_controls(
	parent: VBoxContainer,
	worker: Node
) -> void:
	if not EmployeeRecruitmentFlow.training_available(str(worker.get("employee_id"))): return
	var title := Label.new()
	title.text = "직원 교육"
	title.add_theme_font_size_override("font_size", UiTypography.BOOK_HEADING_SIZE)
	parent.add_child(title)

	var stat_names: Dictionary = {
		"checkout": "계산",
		"restock": "진열",
		"movement": "이동",
		"service": "응대"
	}

	for stat_id in EmployeeTrainingData.STAT_IDS:
		var level: int = worker.get_training_level(stat_id)

		var current_data: Dictionary = (
			EmployeeTrainingData.get_level_data(
				stat_id,
				level
			)
		)

		var next_data: Dictionary = (
			EmployeeTrainingData.get_level_data(
				stat_id,
				level + 1
			)
		)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		parent.add_child(row)

		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)

		var button := Button.new()
		button.custom_minimum_size = Vector2(130, 42)
		row.add_child(button)

		if current_data.is_empty():
			label.text = str(stat_names[stat_id]) + ": 데이터 없음"
			button.text = "교육 불가"
			button.disabled = true
			continue

		label.text = "%s Lv.%d\n%s" % [
			str(stat_names[stat_id]),
			level,
			_format_training_effect(
				stat_id,
				float(current_data["value"])
			)
		]

		if stat_id == "service":
			label.text += "\n응대 성공 시 손님에게 상품을 추천합니다."

		if next_data.is_empty():
			button.text = "최대 단계"
			button.disabled = true
			continue

		label.text += (
			" → "
			+ _format_training_effect(
				stat_id,
				float(next_data["value"])
			)
		)

		var cost: int = int(current_data["upgrade_cost"])

		button.text = "교육 · %dG" % cost
		button.disabled = (
			not worker.can_edit_work_schedule()
			or not GameState.can_afford(cost)
		)

		button.pressed.connect(
			_train_employee.bind(worker, stat_id)
		)


func _format_training_effect(
	stat_id: String,
	value: float
) -> String:
	if stat_id == "service":
		return "추천 성공률 %.0f%%" % (value * 100.0)

	return "속도 ×%.2f" % value


func _train_employee(
	worker: Node,
	stat_id: String
) -> void:
	if not is_instance_valid(worker):
		refresh_view()
		return

	if worker.is_queued_for_deletion():
		refresh_view()
		return

	var worker_name: String = worker.get_employee_display_name()
	var success: bool = worker.train_stat(stat_id)

	refresh_view()
	_refresh_money_displays()

	if success:
		employee_content.after_action(str(worker.get("employee_id")), "trained")
		message_label.text = (
			worker_name + "의 교육을 완료했습니다."
		)
	else:
		message_label.text = (
			"교육하지 못했습니다. 소지금·교육 단계·변경 가능 시간을 확인해주세요."
		)


func _select_employee_tab(tab: int) -> void:
	current_employee_tab = tab as EmployeeTab
	refresh_view()

	if is_instance_valid(employee_scroll):
		employee_scroll.scroll_vertical = 0

func _create_schedule_controls(
	parent: VBoxContainer,
	worker: Node
) -> void:
	var row := GridContainer.new()
	row.columns = 2
	row.add_theme_constant_override("h_separation", 6)
	parent.add_child(row)

	var checks: Dictionary = {}
	var current_periods: Array[String] = worker.get_work_periods()

	var period_ids: Array[String] = [
		"morning",
		"day",
		"evening",
		"night"
	]

	for period in period_ids:
		var check := CheckBox.new()
		check.text = EmployeeNextStepGuide.period_text(period) if EmployeeNextStepGuide.ENABLED else EmployeeData.get_period_name(period)
		check.button_pressed = current_periods.has(period)
		row.add_child(check)
		checks[period] = check

	var editable: bool = worker.can_edit_work_schedule()

	for period in period_ids:
		var check: CheckBox = checks[period]
		check.toggled.connect(
			_on_work_period_toggled.bind(checks, editable)
		)

	_refresh_period_checks(checks, editable)

	var apply_button := Button.new()
	apply_button.text = "근무표 적용"
	apply_button.custom_minimum_size.y = 42
	apply_button.disabled = not editable
	parent.add_child(apply_button)

	apply_button.pressed.connect(
		_apply_period_schedule.bind(worker, checks)
	)


func _create_employment_controls(
	parent: VBoxContainer,
	worker: Node
) -> void:
	var button := Button.new()
	button.custom_minimum_size.y = 42
	parent.add_child(button)

	var hired: bool = bool(worker.get("is_hired"))
	var can_change: bool = worker.can_change_employment()

	if hired:
		button.text = "해고"
		button.disabled = not can_change
		button.pressed.connect(
			_request_dismiss.bind(worker)
		)
	else:
		var cost: int = worker.get_hire_cost()
		button.text = "고용 · %dG" % cost
		button.disabled = (
			not can_change
			or not GameState.can_afford(cost)
		)
		button.pressed.connect(
			_request_hire.bind(worker)
		)

func _request_hire(worker: Node) -> void:
	employee_content.request_hire(worker)
