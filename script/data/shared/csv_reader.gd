class_name CsvReader
extends RefCounted


# CSV 데이터 로더들이 공유하는 셀 읽기 도구.

# 헤더 이름에 해당하는 열의 값을 앞뒤 공백 없이 돌려준다.
# 열이 없거나 행이 짧으면 빈 문자열을 돌려준다.
static func get_cell(
	row: PackedStringArray,
	indexes: Dictionary,
	column_name: String
) -> String:
	if not indexes.has(column_name):
		return ""

	var index: int = int(
		indexes[column_name]
	)

	if index < 0 or index >= row.size():
		return ""

	return row[index].strip_edges()
