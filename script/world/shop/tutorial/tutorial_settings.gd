class_name TutorialSettings
extends Resource
@export var guide_name: String = "델빈"
@export var merchant_name: String = "행상인 타블렌"
@export var opening_layout: Array[Dictionary] = []
# 새 게임에서 건져 보관함에 남는 가구 개수(나머지 시작 가구는 부서져 없어졌다). 키는 가구 id.
@export var salvaged_furniture: Dictionary = {}
@export var barter_requirements: Array[Dictionary] = []
@export var barter_gifts: Array[Dictionary] = []
@export var steps: Array[Dictionary] = []
