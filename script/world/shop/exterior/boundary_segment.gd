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


# 3D 벽의 두께만큼 바깥으로 두꺼운 충돌 모양(평행사변형)을 추가한다. outward = 벽 바깥쪽으로 가는 두께 벡터(화면 좌표).
# 선분만 있으면 바깥에서 벽에 붙을 때 몸 폭의 절반이 벽 상자 안으로 파고들기 때문에, 보이는 벽과 같은 두께로 막는다.
static func add_thick(
	boundary: StaticBody2D,
	point_a: Vector2,
	point_b: Vector2,
	outward: Vector2
) -> void:
	var shape := ConvexPolygonShape2D.new()
	shape.points = PackedVector2Array([point_a, point_b, point_b + outward, point_a + outward])

	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.set_meta("wall_thick", true)
	boundary.add_child(collision)
