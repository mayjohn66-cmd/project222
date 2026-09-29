class_name ExpeditionData
extends RefCounted


const DAY_REWARDS: Dictionary = {
	6: [
		{
			"item_id": "iron_ore",
			"amount": 2
		}
	],

	7: [
		{
			"item_id": "iron_ore",
			"amount": 2
		}
	]
}


static func get_day_rewards(
	day: int
) -> Array:
	return DAY_REWARDS.get(
		day,
		[]
	)
