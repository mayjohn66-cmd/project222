class_name SpriteNormalMaps
extends RefCounted
## 기존 *_n.png 우선. 없으면 원본 밝기 기울기로 만드는 보조 법선(형상 정답이 아닌 근사).
## 색상/알파/기준점은 수정하지 않는다. 텍스처/패딩별 캐시로 매 프레임 계산을 피한다.
static var _cache: Dictionary = {}
static var _padded: Dictionary = {}

static func texture(source: Texture2D) -> Texture2D:
	var key := source.resource_path if not source.resource_path.is_empty() else str(source.get_instance_id())
	if _cache.has(key): return _cache[key]
	var path := source.resource_path.get_basename() + "_n.png"
	if not source.resource_path.is_empty() and ResourceLoader.exists(path):
		var authored := load(path) as Texture2D
		if authored != null and authored.get_size() == source.get_size():
			_cache[key] = authored
			return authored
	var image := source.get_image()
	if image.is_compressed(): image.decompress()
	var normal := Image.create(image.get_width(),image.get_height(),false,Image.FORMAT_RGB8)
	normal.fill(Color(0.5,0.5,1.0))
	for y in image.get_height():
		for x in image.get_width():
			var center := image.get_pixel(x,y)
			if center.a < 0.5: continue
			var dx := sample(image,x+1,y,center)-sample(image,x-1,y,center)
			var dy := sample(image,x,y+1,center)-sample(image,x,y-1,center)
			var n := Vector3(-dx*1.5,dy*1.5,1.0).normalized()
			normal.set_pixel(x,y,Color(n.x*0.5+0.5,n.y*0.5+0.5,n.z*0.5+0.5))
	var result := ImageTexture.create_from_image(normal)
	_cache[key] = result
	return result

static func sample(image: Image, x: int, y: int, fallback: Color) -> float:
	var value := image.get_pixel(clampi(x,0,image.get_width()-1),clampi(y,0,image.get_height()-1))
	return (fallback if value.a < 0.5 else value).get_luminance()

static func top_padding(source: Texture2D, pixels: int) -> Texture2D:
	if pixels <= 0: return source
	var key := "%d:%d" % [source.get_instance_id(),pixels]
	if _padded.has(key): return _padded[key]
	var image := source.get_image()
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGB8)
	var padded := Image.create(image.get_width(),image.get_height()+pixels,false,Image.FORMAT_RGB8)
	padded.fill(Color(0.5,0.5,1.0))
	padded.blit_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),Vector2i(0,pixels))
	var result := ImageTexture.create_from_image(padded)
	_padded[key] = result
	return result
