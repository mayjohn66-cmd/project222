class_name RegisterAreaProfile
extends Resource


@export_group("Rotation 0")

@export var worker_0: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, -1)
]

@export var checkout_0: Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(1, 1)
]


@export_group("Rotation 90")

@export var worker_90: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(-1, 1)
]

@export var checkout_90: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, 1)
]


@export_group("Rotation 180")

@export var worker_180: Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(1, 1)
]

@export var checkout_180: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, -1)
]


@export_group("Rotation 270")

@export var worker_270: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, 1)
]

@export var checkout_270: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(-1, 1)
]


func get_worker_offsets(
	rotation_index: int
) -> Array[Vector2i]:
	match posmod(rotation_index, 4):
		0:
			return worker_0.duplicate()
		1:
			return worker_90.duplicate()
		2:
			return worker_180.duplicate()
		3:
			return worker_270.duplicate()

	return []


func get_checkout_offsets(
	rotation_index: int
) -> Array[Vector2i]:
	match posmod(rotation_index, 4):
		0:
			return checkout_0.duplicate()
		1:
			return checkout_90.duplicate()
		2:
			return checkout_180.duplicate()
		3:
			return checkout_270.duplicate()

	return []
