extends "res://script/ui/shop_clock_hud.gd"
func _update_sky() -> void:
 var expedition = get_parent().get_parent()
 sky.texture = DAY
 period.text = "원정"
 $DayLabel.text = expedition.get_day_name()+" · 원정"
 $TimeLabel.text = "출발 준비" if expedition.current_expedition_phase == 0 else ("탐험 중" if expedition.current_expedition_phase == 1 else "원정 정산")
 $TimeLabel.add_theme_font_size_override("font_size",20)
