extends Node2D
## Existing shop sprites stay at their native pixel density; no generated stand-ins.
const WALL = preload("res://script/world/shop/wood_walls.gd")
const TILE = preload("res://script/world/shop/world_tile_art.gd")
var kind := 0
var elapsed := 0.0

func prop(path: String, foot: Vector2) -> Sprite2D:
 var sprite := Sprite2D.new()
 sprite.texture = ArtLoader.load_texture("res://art/"+path)
 sprite.centered = false
 var factor := 0.5 if path.begins_with("items/") else 1.0
 sprite.scale = Vector2.ONE*factor
 if sprite.texture != null:
  sprite.position = foot-Vector2(sprite.texture.get_width()/2.0,sprite.texture.get_height())*factor
 add_child(sprite)
 return sprite

func wall(a: Vector2, b: Vector2, height: float, direction: int) -> void:
 var panel = WALL.TimberPanel.new()
 panel.start = a
 panel.end = b
 panel.wall_height = height
 panel.direction = direction
 add_child(panel)

func _ready() -> void:
 texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
 if kind == 3: return
 # Open-front timber workshops: all edges follow the shop's 2:1 floor axes.
 wall(Vector2(-126,-42),Vector2(-30,-90),86,3)
 wall(Vector2(-30,-90),Vector2(126,-12),86,0)
 if kind == 0:
  prop("world/cozy_v6/shelf_front.png",Vector2(-69,-24))
  prop("items/pixel_v1/rusty_sword.png",Vector2(-69,-79))
  prop("items/pixel_v1/leather_armor.png",Vector2(-48,-46))
  prop("world/cozy_v6/counter_front.png",Vector2(45,32))
  prop("items/pixel_v1/rusty_sword.png",Vector2(18,-29))
  prop("items/pixel_v1/sickle.png",Vector2(49,-14))
 else:
  prop("world/cozy_v6/rack_front.png",Vector2(35,-28))
  prop("world/cozy_v7/magic_oven_front.png",Vector2(-35,22))
  prop("items/pixel_v1/iron_ore.png",Vector2(75,20))
  prop("items/pixel_v1/iron_ore.png",Vector2(104,32))
  prop("items/pixel_v1/rusty_sword.png",Vector2(-34,-18))

func _process(delta: float) -> void:
 if kind != 1: return
 elapsed += delta
 queue_redraw()

func _draw() -> void:
 if kind == 3:
  gate()
  return
 for x in range(3):
  for y in range(2):
   var cell := Vector2((x-y)*48-24,(x+y)*24-48)
   TILE.draw_cell(self,cell,96,48,TILE.WOOD)
 if kind == 1:
  # Small warm hearth light on the floor, behind the actual forge sprite.
  draw_circle(Vector2(-38,4),23,Color(1.0,0.48,0.12,0.10+sin(elapsed*3)*0.025))

func stone(a: Vector2, b: Vector2, height: float, shade: Color) -> void:
 var rng := RandomNumberGenerator.new()
 rng.seed = int(abs(a.x*331+a.y*117+b.x*73))
 var length := a.distance_to(b)
 var rows := ceili(height/12.0)
 var columns := ceili(length/22.0)
 for row in range(rows):
  for col in range(columns+1):
   var start := clampf((col-0.5*(row%2))/columns,0,1)
   var end := clampf((col+1-0.5*(row%2))/columns,0,1)
   if end <= start: continue
   var p := a.lerp(b,start)+Vector2(0,-row*12)
   var q := a.lerp(b,end)+Vector2(0,-row*12)
   var rise := Vector2(0,-minf(12,height-row*12))
   var color := shade.lightened(rng.randf_range(-0.1,0.08))
   draw_colored_polygon(PackedVector2Array([p,q,q+rise,p+rise]),color)
   draw_polyline(PackedVector2Array([p,q,q+rise,p+rise,p]),Color("655a48"),1)
   draw_line(p+rise+Vector2(1,1),q+rise+Vector2(-1,1),color.lightened(0.22),1)
   var mid := p.lerp(q,0.3)+Vector2(0,-5)
   draw_line(mid,mid+Vector2(5,2),color.darkened(0.12),1)

func tower(base: Vector2, height: float) -> void:
 var left := base+Vector2(-32,-16)
 var back := base+Vector2(0,-32)
 var right := base+Vector2(32,-16)
 stone(left,base,height,Color("b3a082"))
 stone(base,right,height,Color("95836a"))
 var lift := Vector2(0,-height)
 draw_colored_polygon(PackedVector2Array([left+lift,back+lift,right+lift,base+lift]),Color("d5c3a0"))
 for top in [left,back,right,base]:
  stone(top+lift+Vector2(-7,-3.5),top+lift,13,Color("bfab89"))
  stone(top+lift,top+lift+Vector2(7,-3.5),13,Color("928069"))
 draw_line(base+Vector2(-14,-height+40),base+Vector2(-14,-height+61),Color("423c34"),5)

func gate() -> void:
 # A gate viewed on the same isometric axes as the village, with visible thickness.
 stone(Vector2(-225,-76),Vector2(-90,-8),112,Color("a99779"))
 stone(Vector2(38,56),Vector2(173,123),112,Color("a99779"))
 # The interior is dark; the pale path on the far side visually continues outdoors.
 draw_colored_polygon(PackedVector2Array([Vector2(-85,-10),Vector2(41,53),Vector2(41,-99),Vector2(-85,-162)]),Color("313a30"))
 draw_colored_polygon(PackedVector2Array([Vector2(-81,-10),Vector2(39,50),Vector2(63,20),Vector2(-57,-40)]),Color("9b9479"))
 stone(Vector2(-87,-155),Vector2(41,-91),31,Color("b9a584"))
 draw_line(Vector2(-85,-155),Vector2(41,-92),Color("d7c39b"),3)
 for i in range(8):
  var pos := Vector2(-85,-153)+Vector2(16*i,8*i)
  draw_line(pos,pos+Vector2(0,21),Color("514938"),3)
 tower(Vector2(-89,-5),166)
 tower(Vector2(43,61),166)
