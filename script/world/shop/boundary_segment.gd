class_name BoundarySegment
extends RefCounted


# 이동 경계용 StaticBody2D에 선분 충돌 모양을 추가한다.
static func add(
	boundary: StaticBody2D,
	point_a: Vector2,
	point_b: Vector2
) -> void:
	var segment := SegmentShape2D.new()
	segment.a = point_a
	segment.b = point_b

	var collision := CollisionShape2D.new()
	collision.shape = segment

	boundary.add_child(collision)
