class_name FoodShelfLifeSettings
extends Resource

@export var ambient_age: int = 2
@export var fridge_age: int = 1
@export var freezer_age: int = 0
@export var markdown_days: int = 1
@export var markdown_percent: int = 30
@export var recycle_input: int = 2
@export var recycle_output: int = 1
@export var recycle_item: String = "food_compost"
@export var grace_steps: Array[String] = ["setup", "stock", "checkout", "barter", "expedition", "raw_sale"]
