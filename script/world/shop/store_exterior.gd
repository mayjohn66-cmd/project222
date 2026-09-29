@tool
class_name StoreExterior
extends Node2D
const TILE_ART = preload("res://script/world/shop/world_tile_art.gd")
const TILE_GRID_OVERLAY = preload("res://script/world/shop/tile_grid_overlay.gd")
const VILLAGE_LAYOUT_PATH := "res://data/village_map_layout.json"
const VILLAGE_LAYOUT_FALLBACK := GameConfig.VILLAGE_LAYOUT_USER_PATH

var _layout_objects: Dictionary = {}
var _layout_tiles: Dictionary = {}
var _layout_added_cells: Dictionary = {}
var _layout_removed_cells: Dictionary = {}
var _layout_removed: Dictionary = {}
var _layout_added: Dictionary = {}
var _village_map_extent := Vector2i(30,30)

@export var show_tile_grid: bool = false:
	set(value):
		show_tile_grid = value
		if is_instance_valid(_tile_grid_overlay):
			_tile_grid_overlay.visible = value

var _tile_grid_overlay: Node2D



# 매장 외부 부지의 시작 좌표
# 내부 매장의 (0, 0)을 기준으로 바깥쪽 여유 공간을 만든다.
@export var exterior_origin: Vector2i = Vector2i(-4, -4):
	set(value):
		exterior_origin = value
		queue_redraw()


# 최대 16×14 크기의 매장과 주변 공간을 포함한다.
@export var exterior_columns: int = 24:
	set(value):
		exterior_columns = maxi(value, 1)
		queue_redraw()


@export var exterior_rows: int = 22:
	set(value):
		exterior_rows = maxi(value, 1)
		queue_redraw()


# 기존 매장 바닥과 동일한 아이소메트릭 타일 크기
@export var tile_width: float = 96.0:
	set(value):
		tile_width = maxf(value, 1.0)
		queue_redraw()


@export var tile_height: float = 48.0:
	set(value):
		tile_height = maxf(value, 1.0)
		queue_redraw()


# 외부 부지의 기본 색상
@export var ground_color: Color = Color(
	0.24,
	0.32,
	0.22
):
	set(value):
		ground_color = value
		queue_redraw()


# 외부 부지의 타일 경계선 색상
@export var grid_color: Color = Color(
	0.38,
	0.46,
	0.36
):
	set(value):
		grid_color = value
		queue_redraw()


func _ready() -> void:
	z_index = -20

	if Engine.is_editor_hint():
		queue_redraw()
		return

	load_village_map_layout()

	# 현재 확장 단계에 맞춰 외부 부지 크기를 계산한다.
	_apply_store_size_to_exterior()
	_tile_grid_overlay = TILE_GRID_OVERLAY.new()
	_tile_grid_overlay.name = "TileGridOverlay"
	_tile_grid_overlay.set("terrain", self)
	_tile_grid_overlay.z_as_relative = false
	_tile_grid_overlay.z_index = 90
	_tile_grid_overlay.visible = show_tile_grid
	add_child(_tile_grid_overlay)

	if not GameState.store_expansion_changed.is_connected(
		_on_store_expansion_changed
	):
		GameState.store_expansion_changed.connect(
			_on_store_expansion_changed
		)

	queue_redraw()

	# 계산된 외부 부지 가장자리에 충돌을 생성한다.
	_create_boundary_collision()


func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_F6:
		show_tile_grid = not show_tile_grid
		get_viewport().set_input_as_handled()


func _draw() -> void:
	for cell in get_connected_map_cells():
		_draw_ground_cell(cell,_get_cell_fill_color(cell))

# Keep the shop lot fixed and bring the dungeon approach inside a compact circle.
func get_route_rect() -> Rect2i:
	var lot := get_exterior_rect()
	return Rect2i(lot.end.x-8,lot.position.y-6,24,6)

func get_dungeon_entry_cell() -> Vector2i:
	var route := get_route_rect()
	return Vector2i(get_exterior_rect().end.x+4,route.position.y+3)

func get_expedition_departure_cell() -> Vector2i:
	# Center of the editable 5x5 departure area.
	return get_layout_cell("ExpeditionDeparture",Vector2i(13,-13))

func is_at_expedition_departure(world_position: Vector2) -> bool:
	var local_position := to_local(world_position)
	var tile_position := Vector2(
		local_position.x/tile_width+local_position.y/tile_height,
		local_position.y/tile_height-local_position.x/tile_width
	)
	var offset := tile_position-Vector2(get_expedition_departure_cell())
	return absf(offset.x) < 2.5 and absf(offset.y) < 2.5

func get_connected_map_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var center := get_village_map_center_local()
	var center_cell := Vector2i(roundi(center.x/tile_width+center.y/tile_height),roundi(center.y/tile_height-center.x/tile_width))
	var radius := get_village_map_radius()
	var cell_span := ceili(radius*sqrt(1.0/(tile_width*tile_width)+1.0/(tile_height*tile_height)))+2
	for y in range(center_cell.y-cell_span,center_cell.y+cell_span+1):
		for x in range(center_cell.x-cell_span,center_cell.x+cell_span+1):
			var cell := Vector2i(x,y)
			if _is_round_map_cell(cell,radius) and not _layout_removed_cells.has(_map_cell_key(cell)):
				cells.append(cell)
	for key in _layout_added_cells:
		var parts := str(key).split(",")
		if parts.size() != 2: continue
		var cell := Vector2i(int(parts[0]),int(parts[1]))
		if not _is_round_map_cell(cell,radius) and not _layout_removed_cells.has(key):
			cells.append(cell)
	return cells

func _map_cell_key(cell: Vector2i) -> String:
	return str(cell.x)+","+str(cell.y)

func can_add_layout_cell(cell: Vector2i) -> bool:
	if is_exterior_cell(cell): return false
	for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		if is_exterior_cell(cell+offset): return true
	return false

func set_layout_cell_present(cell: Vector2i, present: bool) -> bool:
	var key := _map_cell_key(cell)
	if present:
		if not can_add_layout_cell(cell): return false
		_layout_removed_cells.erase(key)
		if not _is_round_map_cell(cell): _layout_added_cells[key] = true
	else:
		if not is_exterior_cell(cell): return false
		_layout_added_cells.erase(key)
		if _is_round_map_cell(cell): _layout_removed_cells[key] = true
		_layout_tiles.erase(key)
	queue_redraw()
	if is_instance_valid(_tile_grid_overlay): _tile_grid_overlay.queue_redraw()
	return true

func get_forecourt_rect() -> Rect2i:
	var lot := get_exterior_rect()
	return Rect2i(lot.end.x,lot.position.y,22,lot.size.y)

func get_village_map_center_local() -> Vector2:
	var lot := get_exterior_rect()
	var entry := get_dungeon_entry_cell()
	var shop_edge := grid_to_local(Vector2i(lot.position.x,lot.end.y-1))
	var dungeon_edge := grid_to_local(entry+Vector2i(5,1))
	return (shop_edge+dungeon_edge)*0.5

func get_village_map_radius() -> float:
	var center := get_village_map_center_local()
	var lot := get_exterior_rect()
	var entry := get_dungeon_entry_cell()
	var anchors := [
		lot.position,Vector2i(lot.end.x-1,lot.position.y),
		Vector2i(lot.position.x,lot.end.y-1),lot.end-Vector2i.ONE,
		entry+Vector2i(-5,1),entry+Vector2i(5,1),entry+Vector2i(1,-3),
		get_village_square_cell()
	]
	var base_radius := 0.0
	for cell in anchors:
		base_radius = maxf(base_radius,center.distance_to(grid_to_local(cell))+tile_height*0.5)
	return base_radius*float(_village_map_extent.x)/30.0

func _is_round_map_cell(cell: Vector2i, radius: float = -1.0) -> bool:
	if radius < 0.0: radius = get_village_map_radius()
	var point := grid_to_local(cell)-get_village_map_center_local()
	return point.length_squared() <= radius*radius

func get_village_map_extent() -> Vector2i:
	return _village_map_extent

func set_village_map_extent(extent: Vector2i) -> void:
	var size := clampi(maxi(extent.x,extent.y),30,60)
	_village_map_extent = Vector2i(size,size)
	refresh_village_layout()

func get_village_square_cell() -> Vector2i:
	var lot := get_exterior_rect()
	# The square begins beside the shop's front approach, rather than beyond
	# a separate strip of road.  The shop is one edge of the village core.
	return Vector2i(lot.end.x+3,lot.position.y+3)

func get_layout_cell(key: String, fallback: Vector2i) -> Vector2i:
	var saved: Variant = _layout_objects.get(key)
	if saved is Array and saved.size() == 2:
		return Vector2i(int(saved[0]),int(saved[1]))
	return fallback

func set_layout_cell(key: String, cell: Vector2i) -> void:
	if _layout_added.has(key):
		var record: Dictionary = _layout_added[key].duplicate(true)
		record["cell"] = [cell.x,cell.y]
		_layout_added[key] = record
	else:
		_layout_objects[key] = [cell.x,cell.y]

func clear_layout_cell(key: String) -> void:
	_layout_objects.erase(key)

func add_layout_object(source: String, cell: Vector2i, variant: String = "") -> String:
	if not is_exterior_cell(cell) or get_parent().get_node_or_null(source) == null:
		return ""
	var index := 1
	var key := source.get_base_dir()+"/EditorObject"+str(index)
	while _layout_added.has(key):
		index += 1
		key = source.get_base_dir()+"/EditorObject"+str(index)
	var record := {"source":source,"cell":[cell.x,cell.y]}
	if not variant.is_empty(): record["variant"] = variant
	_layout_added[key] = record
	refresh_village_layout()
	return key

func remove_layout_object(key: String) -> void:
	if _layout_added.has(key):
		_layout_added.erase(key)
	else:
		_layout_removed[key] = true
	refresh_village_layout()

func is_added_layout_object(key: String) -> bool:
	return _layout_added.has(key)

func get_layout_tile(cell: Vector2i) -> String:
	return str(_layout_tiles.get(str(cell.x)+","+str(cell.y),""))

func set_layout_tile(cell: Vector2i, kind: String) -> void:
	var key := str(cell.x)+","+str(cell.y)
	if kind == "road" or kind == "grass":
		_layout_tiles[key] = kind
	else:
		_layout_tiles.erase(key)
	queue_redraw()

func get_village_layout_snapshot() -> Dictionary:
	return {"objects":_layout_objects.duplicate(true),"tiles":_layout_tiles.duplicate(true),"removed":_layout_removed.duplicate(true),"added":_layout_added.duplicate(true),"added_cells":_layout_added_cells.duplicate(true),"removed_cells":_layout_removed_cells.duplicate(true),"extent":[_village_map_extent.x,_village_map_extent.y]}

func restore_village_layout_snapshot(snapshot: Dictionary) -> void:
	_layout_objects = snapshot.get("objects",{}).duplicate(true)
	_layout_tiles = snapshot.get("tiles",{}).duplicate(true)
	_layout_removed = snapshot.get("removed",{}).duplicate(true)
	_layout_added = snapshot.get("added",{}).duplicate(true)
	_layout_added_cells = snapshot.get("added_cells",{}).duplicate(true)
	_layout_removed_cells = snapshot.get("removed_cells",{}).duplicate(true)
	var extent: Array = snapshot.get("extent",[30,30])
	var size := clampi(maxi(int(extent[0]),int(extent[1])),30,60)
	_village_map_extent = Vector2i(size,size)
	refresh_village_layout()

func load_village_map_layout() -> void:
	var paths := [VILLAGE_LAYOUT_PATH,VILLAGE_LAYOUT_FALLBACK]
	if FileAccess.file_exists(VILLAGE_LAYOUT_FALLBACK) and (not FileAccess.file_exists(VILLAGE_LAYOUT_PATH) or FileAccess.get_modified_time(VILLAGE_LAYOUT_FALLBACK) > FileAccess.get_modified_time(VILLAGE_LAYOUT_PATH)):
		paths.reverse()
	for path in paths:
		if not FileAccess.file_exists(path): continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary: continue
		_layout_objects = parsed.get("objects",{}).duplicate(true)
		_layout_tiles = parsed.get("tiles",{}).duplicate(true)
		_layout_removed = parsed.get("removed",{}).duplicate(true)
		_layout_added_cells = parsed.get("added_cells",{}).duplicate(true)
		_layout_removed_cells = parsed.get("removed_cells",{}).duplicate(true)
		_layout_added.clear()
		var saved_added: Dictionary = parsed.get("added",{})
		for key in saved_added:
			var record: Dictionary = saved_added[key]
			var cell_data: Array = record.get("cell",[])
			if cell_data.size() != 2: continue
			var clean_record: Dictionary = record.duplicate(true)
			clean_record["source"] = str(record.get("source",""))
			clean_record["cell"] = [int(cell_data[0]),int(cell_data[1])]
			_layout_added[str(key)] = clean_record
		var extent: Array = parsed.get("extent",[30,30])
		var size := clampi(maxi(int(extent[0]),int(extent[1])),30,60)
		_village_map_extent = Vector2i(size,size)
		return

func save_village_map_layout() -> String:
	var payload := JSON.stringify({"version":3,"objects":_layout_objects,"tiles":_layout_tiles,"removed":_layout_removed,"added":_layout_added,"added_cells":_layout_added_cells,"removed_cells":_layout_removed_cells,"extent":[_village_map_extent.x,_village_map_extent.y]},"\t")
	for path in [VILLAGE_LAYOUT_PATH,VILLAGE_LAYOUT_FALLBACK]:
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file == null: continue
		file.store_string(payload+"\n")
		file.flush()
		return ProjectSettings.globalize_path(path)
	return ""

func refresh_village_layout() -> void:
	queue_redraw()
	_create_boundary_collision(false)
	_refresh_dungeon_wall()
	if is_instance_valid(_tile_grid_overlay):
		_tile_grid_overlay.queue_redraw()

func refresh_map_footprint() -> void:
	queue_redraw()
	_create_boundary_collision(false)
	if is_instance_valid(_tile_grid_overlay): _tile_grid_overlay.queue_redraw()

func get_village_square_rect() -> Rect2i:
	return Rect2i(get_village_square_cell()-Vector2i(4,4),Vector2i(9,9))

func get_house_cell() -> Vector2i:
	return get_layout_cell("NearbyHouses/RedRoofHouse",get_village_square_cell()+Vector2i(-5,-3))

func get_extra_house_cell(index: int) -> Vector2i:
	var fallback := get_village_square_cell()+(Vector2i(17,5) if index == 0 else Vector2i(14,-3))
	return get_layout_cell("VillageExtraHouses/"+("SouthTownhouse" if index == 0 else "EastCottage"),fallback)

func get_village_building_cell(index: int) -> Vector2i:
	# Keep the new buildings on two compact edges of the square instead of
	# stretching them across the outskirts.
	var offsets := [Vector2i(1,13),Vector2i(6,14),Vector2i(10,-2)]
	var names := ["VillageBakery","VillageGranary","VillageStable"]
	return get_layout_cell("VillageBuildings/"+names[index],get_village_square_cell()+offsets[index])

func get_village_building_entrance_cell(index: int) -> Vector2i:
	var approaches := [Vector2i(-4,-2),Vector2i(-1,-4),Vector2i(-4,2)]
	return get_village_building_cell(index)+approaches[index]

func get_extra_house_entrance_cell(index: int) -> Vector2i:
	# These rear-facing homes have their unseen doors on the inward side.
	return get_extra_house_cell(index)+(Vector2i(-8,-1) if index == 0 else Vector2i(-1,-4))

func get_blacksmith_cell() -> Vector2i:
	return get_layout_cell("VillageBlacksmith/Smithy",get_village_square_cell()+Vector2i(-14,-9))

func get_tool_shop_cell() -> Vector2i:
	return get_layout_cell("VillageToolShop/ToolShop",get_village_square_cell()+Vector2i(-7,-13))

func get_village_well_cell() -> Vector2i:
	return get_layout_cell("VillageDecor/VillageWell",get_village_square_cell()+Vector2i(-2,2))

func get_village_tree_cells() -> Array[Vector2i]:
	var square := get_village_square_cell()
	var offsets := [Vector2i(-9,12),Vector2i(9,-11),Vector2i(-3,7),Vector2i(14,7)]
	var cells: Array[Vector2i] = []
	for index in range(offsets.size()):
		cells.append(get_layout_cell("VillageDecor/OrchardTree"+str(index+1),square+offsets[index]))
	return cells

func get_village_stall_cell() -> Vector2i:
	return get_layout_cell("VillageDecor/MarketStall",get_village_square_cell()+Vector2i(-2,7))

func get_village_herb_stall_cell() -> Vector2i:
	return get_layout_cell("VillageDecor/PlazaHerbStall",get_village_square_cell()+Vector2i(2,7))

func get_village_supply_cart_cell() -> Vector2i:
	return get_layout_cell("VillageDecor/PlazaSupplyCart",get_village_square_cell()+Vector2i(4,7))

func get_village_supply_crates_cell() -> Vector2i:
	return get_layout_cell("VillageDecor/PlazaCrates",get_village_square_cell()+Vector2i(5,7))

func get_village_wall_cells() -> Array[Vector2i]:
	var square := get_village_square_cell()
	return [get_layout_cell("VillageDecor/GardenWall1",square+Vector2i(10,7)),get_layout_cell("VillageDecor/GardenWall2",square+Vector2i(8,-6))]

# Shared paving connects the buildings into one hamlet, with clipped grassy corners.
func _is_village_courtyard(cell: Vector2i) -> bool:
	var delta := cell-get_village_square_cell()
	# A short paved apron groups the stalls and cart around the south edge of the square.
	if delta.y == 6 and delta.x >= 0 and delta.x <= 5: return true
	if delta.y == 7 and delta.x >= 1 and delta.x <= 5: return true
	if delta.x >= -7 and delta.x <= 11 and delta.y >= -6 and delta.y <= 5:
		if delta.x <= -6 and (delta.y <= -4 or delta.y >= 4): return false
		if delta.x >= 10 and (delta.y <= -4 or delta.y >= 4): return false
		return true
	return delta.x >= -4 and delta.x <= 7 and delta.y >= -9 and delta.y <= -7

# Walkable cells immediately outside the visible front steps.
func get_house_entrance_cell() -> Vector2i:
	return get_house_cell()+Vector2i(1,-3)

func get_blacksmith_entrance_cell() -> Vector2i:
	return get_blacksmith_cell()+Vector2i(3,1)

func get_tool_shop_entrance_cell() -> Vector2i:
	return get_tool_shop_cell()+Vector2i(-3,1)

func _on_path(cell: Vector2i, start: Vector2i, finish: Vector2i, half_width: int = 0) -> bool:
	if start.x == finish.x:
		return absi(cell.x-start.x) <= half_width and cell.y >= mini(start.y,finish.y) and cell.y <= maxi(start.y,finish.y)
	if start.y == finish.y:
		return absi(cell.y-start.y) <= half_width and cell.x >= mini(start.x,finish.x) and cell.x <= maxi(start.x,finish.x)
	return false

func _is_route_road(cell: Vector2i) -> bool:
	var painted := get_layout_tile(cell)
	if painted == "road": return true
	if painted == "grass": return false
	var lot := get_exterior_rect()
	var square := get_village_square_cell()
	var entry := get_dungeon_entry_cell()
	if get_village_square_rect().has_point(cell): return true
	# Main street runs from the shop forecourt through the square to the dungeon.
	var shop_junction := Vector2i(lot.end.x-2,square.y)
	if _on_path(cell,Vector2i(shop_junction.x,lot.end.y-2),shop_junction,1): return true
	if _on_path(cell,shop_junction,square,1): return true
	var north_turn := square+Vector2i(0,-7)
	if _on_path(cell,square,north_turn,1): return true
	if _on_path(cell,north_turn,Vector2i(entry.x,north_turn.y),1): return true
	# The townhouse now fronts the east side of the square.
	var town_door := get_extra_house_entrance_cell(0)
	if _on_path(cell,Vector2i(square.x,town_door.y),town_door): return true
	var bakery_door := get_village_building_entrance_cell(0)
	var bakery_lane := square+Vector2i(-5,4)
	if _on_path(cell,bakery_lane,Vector2i(bakery_lane.x,bakery_door.y)): return true
	if _on_path(cell,Vector2i(bakery_lane.x,bakery_door.y),bakery_door): return true
	var granary_door := get_village_building_entrance_cell(1)
	var granary_corner := square+Vector2i(6,4)
	if _on_path(cell,square+Vector2i(4,4),granary_corner): return true
	if _on_path(cell,granary_corner,Vector2i(granary_corner.x,granary_door.y)): return true
	if _on_path(cell,Vector2i(granary_corner.x,granary_door.y),granary_door): return true
	if _on_path(cell,square,get_village_building_entrance_cell(2)): return true
	var east_lane_start := square+Vector2i(0,-9)
	var east_back := square+Vector2i(13,-9)
	if _on_path(cell,east_lane_start,east_back): return true
	if _on_path(cell,east_back,get_extra_house_entrance_cell(1)): return true
	# Let the lane continue through the boundary so it reads as a way out of town.
	if _on_path(cell,Vector2i(entry.x,north_turn.y),Vector2i(entry.x,get_route_rect().position.y),1): return true
	# Each side lane finishes at its building's visible front steps.
	var red_door := get_house_entrance_cell()
	if _on_path(cell,red_door,Vector2i(square.x,red_door.y)): return true
	var smith_door := get_blacksmith_entrance_cell()
	var tools_door := get_tool_shop_entrance_cell()
	var smith_junction := Vector2i(smith_door.x,tools_door.y+2)
	if _on_path(cell,Vector2i(square.x,smith_junction.y),smith_junction): return true
	if _on_path(cell,smith_junction,smith_door): return true
	var tool_junction := Vector2i(square.x,tools_door.y+2)
	if _on_path(cell,north_turn,tool_junction): return true
	if _on_path(cell,tool_junction,Vector2i(tools_door.x,tool_junction.y)): return true
	if _on_path(cell,Vector2i(tools_door.x,tool_junction.y),tools_door): return true
	return get_forecourt_rect().has_point(cell) and cell.y >= lot.end.y-3

# 실행 중에는 GameState의 현재 부지 유형을 사용하고,
# 에디터에서는 기본 모서리형 부지를 미리 표시한다.
func _get_current_lot_type() -> String:
	if Engine.is_editor_hint():
		return StoreLotData.DEFAULT_LOT_TYPE

	return GameState.get_store_lot_type()


# 현재 셀이 도로에 포함되는지 확인한다.
func _is_road_cell(
	cell: Vector2i
) -> bool:
	var exterior_rect: Rect2i = (
		get_exterior_rect()
	)
	if not exterior_rect.has_point(cell): return false

	var lot_type: String = (
		_get_current_lot_type()
	)

	# 방향 1 바깥쪽 도로
	var is_right_road: bool = (
		cell.x
		>= exterior_rect.end.x - road_width
	)

	# 방향 2 바깥쪽 도로
	var is_bottom_road: bool = (
		cell.y
		>= exterior_rect.end.y - road_width
	)

	match lot_type:
		StoreLotData.LOT_TYPE_CORNER:
			# 모서리형은 전면 두 방향에 도로가 있다.
			return (
				is_right_road
				or is_bottom_road
			)

		StoreLotData.LOT_TYPE_ROADSIDE:
			# 도로변형은 방향 2에만 도로가 있다.
			return is_bottom_road

	return false


# 현재 셀이 보도에 포함되는지 확인한다.
func _is_sidewalk_cell(
	cell: Vector2i
) -> bool:
	if not get_exterior_rect().has_point(cell): return false
	# 도로 칸은 보도로 처리하지 않는다.
	if _is_road_cell(
		cell
	):
		return false

	var exterior_rect: Rect2i = (
		get_exterior_rect()
	)

	var lot_type: String = (
		_get_current_lot_type()
	)

	var right_sidewalk_start: int = (
		exterior_rect.end.x
		- road_width
		- sidewalk_width
	)

	var bottom_sidewalk_start: int = (
		exterior_rect.end.y
		- road_width
		- sidewalk_width
	)

	var is_right_sidewalk: bool = (
		cell.x >= right_sidewalk_start
		and cell.x
		< exterior_rect.end.x - road_width
	)

	var is_bottom_sidewalk: bool = (
		cell.y >= bottom_sidewalk_start
		and cell.y
		< exterior_rect.end.y - road_width
	)

	match lot_type:
		StoreLotData.LOT_TYPE_CORNER:
			return (
				is_right_sidewalk
				or is_bottom_sidewalk
			)

		StoreLotData.LOT_TYPE_ROADSIDE:
			return is_bottom_sidewalk

	return false


# 타일의 용도에 따라 표시 색상을 결정한다.
func _get_cell_fill_color(
	cell: Vector2i
) -> Color:
	if _is_road_cell(
		cell
	):
		return road_color

	if _is_sidewalk_cell(
		cell
	):
		return sidewalk_color

	return ground_color

# 외부 부지 타일 하나를 그린다.
func _draw_ground_cell(cell: Vector2i, _fill_color: Color) -> void:
	var painted := get_layout_tile(cell)
	if painted == "road" or painted == "grass":
		TILE_ART.draw_cell(self,grid_to_local(cell),tile_width,tile_height,TILE_ART.PAVING if painted == "road" else TILE_ART.GRASS)
		return
	var texture: Texture2D = TILE_ART.GRASS
	if _is_route_road(cell) or _is_road_cell(cell):
		texture = TILE_ART.ROAD
	elif _is_sidewalk_cell(cell):
		texture = TILE_ART.PAVING
	if get_route_rect().has_point(cell) or get_forecourt_rect().has_point(cell):
		texture = TILE_ART.PAVING if _is_route_road(cell) or _is_village_courtyard(cell) else TILE_ART.GRASS
		if get_village_square_rect().has_point(cell): texture = TILE_ART.ROAD
	TILE_ART.draw_cell(self, grid_to_local(cell), tile_width, tile_height, texture)


func grid_to_local(
	cell: Vector2i
) -> Vector2:
	return Vector2(
		(cell.x - cell.y)
		* tile_width
		* 0.5,

		(cell.x + cell.y)
		* tile_height
		* 0.5
	)


func get_exterior_rect() -> Rect2i:
	return Rect2i(
		exterior_origin,
		Vector2i(
			exterior_columns,
			exterior_rows
		)
	)


func is_exterior_cell(
	cell: Vector2i
) -> bool:
	var key := _map_cell_key(cell)
	if _layout_removed_cells.has(key): return false
	return _layout_added_cells.has(key) or _is_round_map_cell(cell)

# 외부 부지의 가장자리에만 충돌을 생성한다.
func _create_boundary_collision(schedule_visual_refresh: bool = true) -> void:
	var old_boundary := get_node_or_null("ExteriorBoundary")
	if old_boundary:
		remove_child(old_boundary)
		old_boundary.queue_free()
	var boundary := StaticBody2D.new()

	boundary.name = "ExteriorBoundary"
	boundary.collision_layer = 1
	boundary.collision_mask = 0

	add_child(
		boundary
	)

	for cell in get_connected_map_cells():
		_add_cell_boundary(boundary,cell)
	if schedule_visual_refresh:
		call_deferred("_refresh_dungeon_wall")


func _add_cell_boundary(
	boundary: StaticBody2D,
	cell: Vector2i
) -> void:
	var center: Vector2 = grid_to_local(
		cell
	)

	var top: Vector2 = center + Vector2(
		0,
		-tile_height * 0.5
	)

	var right: Vector2 = center + Vector2(
		tile_width * 0.5,
		0
	)

	var bottom: Vector2 = center + Vector2(
		0,
		tile_height * 0.5
	)

	var left: Vector2 = center + Vector2(
		-tile_width * 0.5,
		0
	)

	# 이웃 외부 타일이 없는 변에만 충돌을 만든다.
	if not is_exterior_cell(
		cell + Vector2i(1, 0)
	):
		BoundarySegment.add(
			boundary,
			right,
			bottom
		)

	if not is_exterior_cell(
		cell + Vector2i(-1, 0)
	):
		BoundarySegment.add(
			boundary,
			left,
			top
		)

	if not is_exterior_cell(
		cell + Vector2i(0, 1)
	):
		BoundarySegment.add(
			boundary,
			bottom,
			left
		)

	if not is_exterior_cell(
		cell + Vector2i(0, -1)
	):
		BoundarySegment.add(
			boundary,
			top,
			right
		)


# =========================
# 도로와 보도 설정
# =========================

# 도로가 차지하는 타일 너비
@export var road_width: int = 2:
	set(value):
		road_width = maxi(
			value,
			1
		)

		queue_redraw()


# 도로와 매장 부지 사이의 보도 너비
@export var sidewalk_width: int = 1:
	set(value):
		sidewalk_width = maxi(
			value,
			1
		)

		queue_redraw()


@export var road_color: Color = Color(
	0.16,
	0.17,
	0.18
):
	set(value):
		road_color = value
		queue_redraw()


@export var sidewalk_color: Color = Color(
	0.48,
	0.48,
	0.45
):
	set(value):
		sidewalk_color = value
		queue_redraw()

# 매장 뒤쪽과 측면에 남겨둘 최소 여백
@export var back_margin: int = 2:
	set(value):
		back_margin = maxi(
			value,
			0
		)

		queue_redraw()


# 매장 전면과 보도 사이의 잔디 공간
@export var front_yard_width: int = 1:
	set(value):
		front_yard_width = maxi(
			value,
			0
		)

		queue_redraw()

# 현재 매장 크기를 기준으로 외부 부지 크기를 계산한다.
#
# 뒤쪽 여백 + 매장 + 앞마당 + 보도 + 도로 순서로 구성한다.
func _apply_store_size_to_exterior() -> void:
	var store_size: Vector2i = (
		GameState.get_store_size()
	)

	var front_space: int = (
		front_yard_width
		+ sidewalk_width
		+ road_width
	)

	exterior_origin = Vector2i(
		-back_margin,
		-back_margin
	)

	exterior_columns = (
		back_margin
		+ store_size.x
		+ front_space
	)

	exterior_rows = (
		back_margin
		+ store_size.y
		+ front_space
	)

	DebugLog.write(
		"[외부 부지] 매장 크기: ",
		store_size,
		" / 외부 크기: ",
		Vector2i(
			exterior_columns,
			exterior_rows
		)
	)

# 보도의 오른쪽 방향 중심 x 좌표
func _get_right_sidewalk_x() -> int:
	var exterior_rect: Rect2i = (
		get_exterior_rect()
	)

	var sidewalk_start: int = (
		exterior_rect.end.x
		- road_width
		- sidewalk_width
	)

	return (
		sidewalk_start
		+ floori(
			float(sidewalk_width - 1) / 2.0
		)
	)


# 보도의 아래쪽 방향 중심 y 좌표
func _get_bottom_sidewalk_y() -> int:
	var exterior_rect: Rect2i = (
		get_exterior_rect()
	)

	var sidewalk_start: int = (
		exterior_rect.end.y
		- road_width
		- sidewalk_width
	)

	return (
		sidewalk_start
		+ floori(
			float(sidewalk_width - 1) / 2.0
		)
	)


# 문을 향해 방향을 바꾸는 보도 위 접근 셀을 반환한다.
func get_sidewalk_approach_cell_for_door(
	door: Node
) -> Vector2i:
	if not is_instance_valid(door):
		return Vector2i.ZERO

	var exterior_rect: Rect2i = (
		get_exterior_rect()
	)

	var anchor: Vector2i = (
		door.get_meta(
			"anchor",
			Vector2i.ZERO
		)
	)

	var rotation_index: int = int(
		door.get_meta(
			"rotation_index",
			-1
		)
	)

	match rotation_index:
		1:
			# 오른쪽 아래 벽의 문:
			# 오른쪽 보도에서 문의 y좌표와 맞춘다.
			return Vector2i(
				_get_right_sidewalk_x(),
				clampi(
					anchor.y,
					exterior_rect.position.y,
					_get_bottom_sidewalk_y()
				)
			)

		2:
			# 왼쪽 아래 벽의 문:
			# 아래쪽 보도에서 문의 x좌표와 맞춘다.
			var maximum_x: int = (
				exterior_rect.end.x - 1
			)

			if (
				_get_current_lot_type()
				== StoreLotData.LOT_TYPE_CORNER
			):
				maximum_x = (
					_get_right_sidewalk_x()
				)

			return Vector2i(
				clampi(
					anchor.x,
					exterior_rect.position.x,
					maximum_x
				),
				_get_bottom_sidewalk_y()
			)

	return Vector2i.ZERO


# 손님과 직원이 보도에서 등장할 셀을 반환한다.
func get_sidewalk_spawn_cell_for_door(
	door: Node
) -> Vector2i:
	if not is_instance_valid(door):
		return Vector2i.ZERO

	var exterior_rect: Rect2i = (
		get_exterior_rect()
	)

	var approach_cell: Vector2i = (
		get_sidewalk_approach_cell_for_door(
			door
		)
	)

	var rotation_index: int = int(
		door.get_meta(
			"rotation_index",
			-1
		)
	)

	match rotation_index:
		1:
			var first_cell := Vector2i(
				_get_right_sidewalk_x(),
				exterior_rect.position.y
			)

			var last_cell := Vector2i(
				_get_right_sidewalk_x(),
				_get_bottom_sidewalk_y()
			)

			# 접근 지점에서 더 먼 보도 끝을 사용한다.
			if (
				approach_cell.distance_squared_to(
					first_cell
				)
				>= approach_cell.distance_squared_to(
					last_cell
				)
			):
				return first_cell

			return last_cell

		2:
			var maximum_x: int = (
				exterior_rect.end.x - 1
			)

			if (
				_get_current_lot_type()
				== StoreLotData.LOT_TYPE_CORNER
			):
				maximum_x = (
					_get_right_sidewalk_x()
				)

			var first_cell := Vector2i(
				exterior_rect.position.x,
				_get_bottom_sidewalk_y()
			)

			var last_cell := Vector2i(
				maximum_x,
				_get_bottom_sidewalk_y()
			)

			if (
				approach_cell.distance_squared_to(
					first_cell
				)
				>= approach_cell.distance_squared_to(
					last_cell
				)
			):
				return first_cell

			return last_cell

	return approach_cell


func get_sidewalk_approach_position_for_door(
	door: Node
) -> Vector2:
	return to_global(
		grid_to_local(
			get_sidewalk_approach_cell_for_door(
				door
			)
		)
	)


func get_sidewalk_spawn_position_for_door(
	door: Node
) -> Vector2:
	return to_global(
		grid_to_local(
			get_sidewalk_spawn_cell_for_door(
				door
			)
		)
	)

# 손님이 생성되거나 사라지는 보도의 양쪽 끝을 반환한다.
# 문 위치와 관계없이 도로의 가장 먼 양 끝만 사용한다.
func get_sidewalk_end_cells_for_door(
	_door: Node
) -> Array[Vector2i]:
	var exterior_rect: Rect2i = (
		get_exterior_rect()
	)

	# 화면 왼쪽에 보이는 도로의 끝
	var left_end_cell := Vector2i(
		exterior_rect.position.x,
		_get_bottom_sidewalk_y()
	)

	# 화면 오른쪽 위에 보이는 도로의 끝
	var right_end_cell := Vector2i(
		_get_right_sidewalk_x(),
		exterior_rect.position.y
	)

	return [
		left_end_cell,
		right_end_cell
	]

# 양쪽 도로 끝 중 하나를 출발점으로 정하고,
# 문과 출발 방향에 맞는 보행 경로를 만든다.
func get_random_sidewalk_route_for_door(
	door: Node
) -> Dictionary:
	var end_cells: Array[Vector2i] = (
		get_sidewalk_end_cells_for_door(
			door
		)
	)

	if end_cells.size() < 2:
		return {}

	var start_index: int = randi_range(0, 1)
	var finish_index: int = 1 - start_index

	var start_cell: Vector2i = (
		end_cells[start_index]
	)

	var finish_cell: Vector2i = (
		end_cells[finish_index]
	)

	var decision_cell: Vector2i = (
		get_sidewalk_approach_cell_for_door(
			door
		)
	)

	# 두 보도가 만나는 모서리
	var corner_cell := Vector2i(
		_get_right_sidewalk_x(),
		_get_bottom_sidewalk_y()
	)

	var door_rotation: int = int(
		door.get_meta(
			"rotation_index",
			-1
		)
	)

	var approach_positions: Array[Vector2] = []
	var pass_positions: Array[Vector2] = []

	# 오른쪽 보도에서 출발해서 아래쪽 문으로 가거나,
	# 아래쪽 보도에서 출발해서 오른쪽 문으로 갈 때는
	# 반드시 도로 모서리를 경유한다.
	var approach_needs_corner: bool = (
		door_rotation == 2
		and start_index == 1
	) or (
		door_rotation == 1
		and start_index == 0
	)

	if approach_needs_corner:
		approach_positions.append(
			to_global(
				grid_to_local(
					corner_cell
				)
			)
		)

	approach_positions.append(
		to_global(
			grid_to_local(
				decision_cell
			)
		)
	)

	# 매장에 들어가지 않고 반대편으로 지나가는 경로
	var pass_needs_corner: bool = (
		door_rotation == 2
		and finish_index == 1
	) or (
		door_rotation == 1
		and finish_index == 0
	)

	if pass_needs_corner:
		pass_positions.append(
			to_global(
				grid_to_local(
					corner_cell
				)
			)
		)

	pass_positions.append(
		to_global(
			grid_to_local(
				finish_cell
			)
		)
	)

	return {
		"start_position": to_global(
			grid_to_local(
				start_cell
			)
		),
		"decision_position": to_global(
			grid_to_local(
				decision_cell
			)
		),
		"finish_position": to_global(
			grid_to_local(
				finish_cell
			)
		),
		"approach_positions": approach_positions,
		"pass_positions": pass_positions
	}

# 내부 매장 크기가 바뀌면 외부 부지와 도로 범위도 다시 계산한다.
func _on_store_expansion_changed(
	_previous_level: int,
	new_level: int,
	_new_store_size: Vector2i
) -> void:
	_apply_store_size_to_exterior()

	queue_redraw()
	if is_instance_valid(_tile_grid_overlay):
		_tile_grid_overlay.queue_redraw()

	# 외부 부지 크기를 기준으로 충돌 경계를 다시 만든다.
	call_deferred(
		"_create_boundary_collision"
	)

	DebugLog.write(
		"[매장 외부] 확장 적용 / 단계: ",
		new_level,
		" / 외부 크기: ",
		Vector2i(
			exterior_columns,
			exterior_rows
		)
	)

func _refresh_dungeon_wall() -> void:
	if not is_inside_tree() or Engine.is_editor_hint(): return
	var world := get_parent()
	var wall = world.get_node_or_null("DungeonWall")
	if wall == null:
		wall = preload("res://script/world/shop/dungeon_wall.gd").new()
		wall.name = "DungeonWall"
		world.add_child(wall)
	wall.rebuild(self)
	var roadside = world.get_node_or_null("DungeonRoadside")
	if roadside == null:
		roadside = preload("res://script/world/shop/dungeon_roadside.gd").new()
		roadside.name = "DungeonRoadside"
		world.add_child(roadside)
	roadside.rebuild(self)
	var houses = world.get_node_or_null("NearbyHouses")
	if houses == null:
		houses = preload("res://script/world/shop/nearby_houses.gd").new()
		houses.name = "NearbyHouses"
		world.add_child(houses)
	houses.rebuild(self)
	var extra_houses = world.get_node_or_null("VillageExtraHouses")
	if extra_houses == null:
		extra_houses = preload("res://script/world/shop/village_extra_houses.gd").new()
		extra_houses.name = "VillageExtraHouses"
		world.add_child(extra_houses)
	extra_houses.rebuild(self)
	var smithy = world.get_node_or_null("VillageBlacksmith")
	if smithy == null:
		smithy = preload("res://script/world/shop/village_blacksmith.gd").new()
		smithy.name = "VillageBlacksmith"
		world.add_child(smithy)
	smithy.rebuild(self)
	var tool_shop = world.get_node_or_null("VillageToolShop")
	if tool_shop == null:
		tool_shop = preload("res://script/world/shop/village_tool_shop.gd").new()
		tool_shop.name = "VillageToolShop"
		world.add_child(tool_shop)
	tool_shop.rebuild(self)
	var buildings = world.get_node_or_null("VillageBuildings")
	if buildings == null:
		buildings = preload("res://script/world/shop/village_buildings.gd").new()
		buildings.name = "VillageBuildings"
		world.add_child(buildings)
	buildings.rebuild(self)
	var decor = world.get_node_or_null("VillageDecor")
	if decor == null:
		decor = preload("res://script/world/shop/village_decor.gd").new()
		decor.name = "VillageDecor"
		world.add_child(decor)
	decor.rebuild(self)
	var gathering = world.get_node_or_null("VillageGathering")
	if gathering == null:
		gathering = preload("res://script/world/shop/village_gathering.gd").new()
		gathering.name = "VillageGathering"
		world.add_child(gathering)
	gathering.rebuild(self)
	_apply_editor_objects(world)

func _apply_editor_objects(world: Node) -> void:
	for key in _layout_added:
		var record: Dictionary = _layout_added[key]
		var source := world.get_node_or_null(str(record.get("source",""))) as StaticBody2D
		var cell_data: Array = record.get("cell",[])
		if source == null or cell_data.size() != 2: continue
		var cell := Vector2i(int(cell_data[0]),int(cell_data[1]))
		var group := source.get_parent() as Node2D
		var copy := source.duplicate() as StaticBody2D
		copy.name = str(key).get_file()
		group.add_child(copy)
		copy.position = group.to_local(to_global(grid_to_local(cell)))
		copy.set_meta("tile_cell",cell)
		if group.has_method("apply_house_variant"):
			group.apply_house_variant(copy,str(record.get("source","")),str(record.get("variant","")))
		if group.has_method("apply_cottage_roof_variant"):
			group.apply_cottage_roof_variant(copy,str(record.get("variant","")))
		if group.has_method("apply_market_stall_variant"):
			group.apply_market_stall_variant(copy,str(record.get("variant","")))
	for key in _layout_removed:
		var removed := world.get_node_or_null(str(key)) as StaticBody2D
		if removed == null: continue
		removed.visible = false
		removed.collision_layer = 0

