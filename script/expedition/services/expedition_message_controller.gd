class_name ExpeditionMessageController
extends RefCounted


# 원정 진행 중 표시하는 안내 메시지 큐를 담당한다.
# 메시지를 모두 보여준 뒤에는 넘겨받은 finish_action을 한 번 호출한다.
# 큐와 finish_action은 체크포인트 저장 가능 여부 판단이 읽으므로 host(expedition.gd)가 가지고 있다.
# host는 씬 노드라서 타입을 붙이지 않는다.

var host


func setup(new_host) -> void:
	host = new_host


func show_messages(
	messages: Array[String],
	finish_action: Callable = Callable()
) -> void:
	host.run_message_queue.clear()

	for message in messages:
		host.run_message_queue.append(
			message
		)

	host.run_message_finish_action = (
		finish_action
	)

	host.message_panel.visible = true

	show_next()


func show_next() -> void:
	if host.run_message_queue.is_empty():
		host.message_panel.visible = false

		var finish_action := (
			host.run_message_finish_action
		)

		host.run_message_finish_action = (
			Callable()
		)

		if finish_action.is_valid():
			finish_action.call()

		return

	host.message_label.text = (
		host.run_message_queue.pop_front()
	)


func on_continue_pressed() -> void:
	if host.current_expedition_phase != host.ExpeditionPhase.RUN:
		return

	if not host.message_panel.visible:
		return

	show_next()

	# 종료 제한 안내를 원래 상태 문구로 복구
	if not host.message_panel.visible:
		host.update_ui()
