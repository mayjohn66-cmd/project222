class_name ExpeditionRoomSettings
extends Resource

# 타일 단위의 잠정 조작 수치. 게임 밸런스(HP/공격/드롭)는 기존 CSV를 쓴다.
const GRID_SIZE: int = 8
@export var player_speed: float = 3.0
@export var actor_radius: float = 0.24
@export var enemy_speed: float = 0.85
@export var enemy_reach: float = 0.9
@export var boss_reach: float = 1.35
@export var enemy_windup: float = 0.65
@export var enemy_cooldown: float = 1.1
@export var hurt_grace: float = 0.6
@export var interaction_reach: float = 1.0
@export var gathering_seconds: float = 0.75
@export var ordinary_enemy_count: int = 2
@export var default_attack: ExpeditionAttackProfile
@export var equipment_attacks: Array[ExpeditionAttackProfile] = []

func attack_for(bag) -> ExpeditionAttackProfile:
	if bag != null:
		for placement in bag.placements:
			for profile in equipment_attacks:
				if str(placement.get("item_id", "")) == profile.equipment_id:
					return profile
	return default_attack

