class_name ArtLoader
extends RefCounted


# 이미지 파일이 없어도 스크립트 로드가 실패하지 않게 하는 텍스처 로더.
# preload는 파일이 없으면 스크립트 전체가 로드되지 않으므로,
# 아직 준비되지 않았거나 교체 중인 그림은 이 함수로 읽는다.
# 파일이 없으면 null을 돌려주므로 그리는 쪽에서 null을 처리해야 한다.
static func load_texture(
	path: String
) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null

	return load(path) as Texture2D
