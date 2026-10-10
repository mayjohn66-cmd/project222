class_name ReceivedFurniturePreview
extends TextureRect
## 설계도의 외형 미리보기. 정렬본을 그대로 보여 주며 전용 그림이 없으면 기존 모델을 쓴다.

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	visible = false

func show_shape(build_id: String) -> bool:
	var path := ReceivedWorldArt.furniture_path(build_id,0) if ReceivedWorldArt.ENABLED else ""
	if ReceivedWorldArt.ENABLED:
		var frame := PixelShopArt.frame(build_id, 0)
		if not frame.is_empty(): path = PixelShopArt.storage_path(frame,0,false)
		if ContainerStockArt.COLD_UNITS.has(build_id):
			path = ContainerStockArt.cold_pair(build_id,0).empty
		if build_id in ["door", "production_door", "warehouse_door"]:
			path = PixelShopArt.door_path(build_id, 0, false)
	var source := ReceivedWorldArt.texture(path) if not path.is_empty() else null
	visible = source != null
	if source == null:
		texture = null
		return false
	var cropped := AtlasTexture.new()
	cropped.atlas = source
	cropped.region = Rect2(source.get_image().get_used_rect())
	texture = cropped
	return true
