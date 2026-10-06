class_name VillageRestSettings
extends Resource

@export var preparation := "trail_rest_corner"
@export var site_path := "VillageGathering/TrailRestBench"
@export var afterglow_requests: Array[String] = ["naru_market_juice", "doyun_market_soup", "sora_market_drink"]
@export var participants: Array[String] = ["naru", "doyun", "sora"]
@export var days_after := 1
@export var opening_days_after := 1
@export var start_hour := 14
@export var end_hour := 19
@export var interaction_distance := 180.0
@export var arrival_distance := 220.0
@export var opening_reputation := 1
@export var quiet_id := "trail_rest_quiet"
@export var moments: Array[Dictionary] = []
