extends Node
## 실제 GPU 글리프: 38px 출력이 19px 출력의 정확한 최근접 2배인지 검사한다.
var checks := 0
var failures := 0

class FontSample extends Node2D:
	var sample: String
	var factor: int
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,Vector2(256,32)*factor),InteractionUiStyle.PAPER)
		draw_string(UiTypography.FONT,Vector2(2,23)*factor,sample,HORIZONTAL_ALIGNMENT_LEFT,-1,19*factor,InteractionUiStyle.INK)

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	run.call_deferred()

func render_sample(text: String,factor: int) -> Image:
	var view := SubViewport.new()
	view.size = Vector2i(256,32)*factor
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(view)
	var sample := FontSample.new()
	sample.sample = text
	sample.factor = factor
	sample.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.add_child(sample)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	view.queue_free()
	return image

func run() -> void:
	var font: FontFile = UiTypography.FONT.base_font
	check(FileAccess.get_sha256("res://art/fonts/Silver.ttf") == "5bbbcd90b9f3ed71f8e15816fc114cbfefe9dfa29e5aacab31fe3f49fe1d1c89","font original unchanged")
	check(font.antialiasing == TextServer.FONT_ANTIALIASING_NONE,"pixel font has no smoothing")
	check(font.subpixel_positioning == TextServer.SUBPIXEL_POSITIONING_DISABLED,"subpixel positioning disabled")
	check(font.hinting == TextServer.HINTING_NONE and is_equal_approx(font.oversampling,1.0),"glyph raster scale unchanged")
	check(UiTypography.DEFAULT_SIZE == 38 and UiTypography.size(16) == 19,"38px body and 19px supporting text")
	for legacy in range(8,65):
		check(UiTypography.size(legacy)%19 == 0,"pixel grid for legacy %d"%legacy)
	for text in ["편의점 생산 직원", "원정 준비 물품", "0123456789 ABC xyz", "[]() / + - : ! ?"]:
		for character in text:
			check(font.has_char(character.unicode_at(0)),"Silver glyph exists: "+character)
		var native: Image = await render_sample(text,1)
		var doubled: Image = await render_sample(text,2)
		var marked := 0
		var background := native.get_pixel(0,0)
		for y in native.get_height():
			for x in native.get_width():
				if native.get_pixel(x,y) != background: marked += 1
		check(marked > 20,"glyphs actually rendered: "+text)
		native.resize(512,64,Image.INTERPOLATE_NEAREST)
		check(native.get_data() == doubled.get_data(),"38px is exact 2x raster: "+text)
	print("SILVER_PIXEL_GRID checks=%d failures=%d" % [checks,failures])
	get_tree().quit(1 if failures else 0)
