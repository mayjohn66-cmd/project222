class_name ItemCatalog
extends RefCounted


const ITEMS: Dictionary = {
	"water": {
		"name": "물",
		"category": "food",
		"price": 50,
		"icon": preload("res://art/items/water.png"),
		"shelf_allowed": true,
		"sellable": true
	},

	"bread": {
		"name": "빵",
		"category": "food",
		"price": 80,
		"icon": preload("res://art/items/bread.png"),
		"shelf_allowed": true,
		"sellable": true
	},

	"potion": {
		"name": "포션",
		"category": "potion",
		"price": 120,
		"icon": preload("res://art/items/potion.png"),
		"shelf_allowed": true,
		"sellable": true
	}
}
