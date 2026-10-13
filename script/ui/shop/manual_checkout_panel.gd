class_name ManualCheckoutPanel
extends CanvasLayer

signal checkout_requested
signal cancel_requested
var root: PanelContainer
var info: Label
var progress: ProgressBar
var action: Button
var cancel: Button
var scan_view: CheckoutScanView
var scan: CheckoutScan

func _ready() -> void:
	layer = 15
	root = PanelContainer.new()
	add_child(root)
	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.anchor_top = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = -230
	root.offset_right = 230
	root.offset_top = -164
	root.offset_bottom = -60
	var column := VBoxContainer.new()
	root.add_child(column)
	info = Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(info)
	progress = ProgressBar.new()
	progress.max_value = 1.0
	progress.show_percentage = false
	column.add_child(progress)
	scan_view = CheckoutScanView.new()
	scan_view.visible = false
	column.add_child(scan_view)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	action = Button.new()
	action.text = "결제 [E]"
	action.focus_mode = Control.FOCUS_NONE
	action.pressed.connect(func(): checkout_requested.emit())
	row.add_child(action)
	cancel = Button.new()
	cancel.text = "취소"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func(): cancel_requested.emit())
	row.add_child(cancel)
	root.hide()

func display(caption: String, value: float, busy: bool, enabled: bool, action_text: String = "결제 [E]") -> void:
	root.visible = not caption.is_empty()
	info.text = caption
	progress.visible = busy and scan == null
	scan_view.visible = busy and scan != null
	progress.value = value
	action.disabled = busy or not enabled
	action.text = action_text
	cancel.visible = busy


# 스캔 중이면 막대를 보이고, 없으면(간편 계산·튜토리얼) 진행 막대를 쓴다.
func set_scan(value: CheckoutScan) -> void:
	scan = value
	scan_view.scan = value
