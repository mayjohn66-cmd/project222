class_name PixelProductionArt
extends RefCounted
## 설비 원본을 유지하고 실제 작업/완료 상태를 작은 도트 표지로 덧붙인다.
const BADGE_HEIGHT := 24
const PROGRESS_STEPS := 12

static func progress_step(node: ProductionFacility) -> int:
	var recipe := ProductRecipeData.get_recipe(node.active_recipe_id)
	var batches := float(node.pending_amount) / maxi(1, int(recipe.get("result_amount",1)))
	var total := float(recipe.get("craft_time",0)) * batches
	if total <= 0.0: return 0
	return clampi(floori((1.0 - node.remaining_seconds / total) * PROGRESS_STEPS), 0, PROGRESS_STEPS)

static func signature(node: Node) -> String:
	if not node is ProductionFacility: return ""
	return "%d:%s:%d:%d" % [node.production_state, node.pending_item_id, node.pending_amount, progress_step(node)]

static func compose(source: Image, node: ProductionFacility) -> Image:
	if node.production_state == ProductionFacility.ProductionState.IDLE: return source
	var image := Image.create(source.get_width(),source.get_height()+BADGE_HEIGHT,false,Image.FORMAT_RGBA8)
	image.blit_rect(source,Rect2i(Vector2i.ZERO,source.get_size()),Vector2i(0,BADGE_HEIGHT))
	var x := source.get_width()/2 - 12
	var top := source.get_used_rect().position.y
	image.fill_rect(Rect2i(x,top+1,24,21),Color("543d2a"))
	image.fill_rect(Rect2i(x+1,top+2,22,19),Color("fff0c9"))
	PixelShopArt.prepare()
	var icon := PixelShopArt.glyph(node.pending_item_id)
	if icon != null:
		image.blend_rect(icon,Rect2i(Vector2i.ZERO,icon.get_size()),Vector2i(x+12-icon.get_width()/2,top+3))
	var ready := node.production_state == ProductionFacility.ProductionState.READY
	var width := PROGRESS_STEPS if ready else progress_step(node)
	image.fill_rect(Rect2i(x+6,top+17,PROGRESS_STEPS,2),Color("80664c"))
	image.fill_rect(Rect2i(x+6,top+17,width,2),Color("58a65c") if ready else Color("df9a36"))
	if ready:
		# 완료는 색뿐 아니라 체크 모양으로도 구분한다.
		for point in [Vector2i(0,2),Vector2i(1,3),Vector2i(2,4),Vector2i(3,3),Vector2i(4,2),Vector2i(5,1),Vector2i(6,0)]:
			image.set_pixelv(Vector2i(x+16,top+5)+point,Color("317844"))
	return image

static func furniture(view: StoreView3D, key: String, node: Node, build_id: String,
		rotation: int, lo: Vector2, hi: Vector2, base: Vector2, sig: String, preview: bool) -> bool:
	if preview or not node is ProductionFacility: return false
	var path := ReceivedWorldArt.furniture_path(build_id,rotation)
	var tex := ReceivedWorldArt.texture(path)
	if tex == null: return false
	var source := tex.get_image()
	if source.is_compressed(): source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	var image := compose(source,node)
	var anchor := Vector2(source.get_width()*0.5,152.0 if build_id == "magic_oven" else source.get_height()-24.0)
	if node.production_state != ProductionFacility.ProductionState.IDLE: anchor.y += BADGE_HEIGHT
	ReceivedWorldArt.billboard(view,key,ImageTexture.create_from_image(image),anchor,lo,hi,base,sig,Color.WHITE,1.0,path)
	view._items[key]["received_art"] = path
	view._items[key]["production_state"] = int(node.production_state)
	return true
