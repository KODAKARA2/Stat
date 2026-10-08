extends Node
## 코드와 데이터는 sprite_id만 쓰고, 실제 파일 경로는 assets/manifest.json에서 찾는다 (GDD §12.3-3).
## 아트 교체 = manifest 수정 + 파일 교체. 파일이 아직 없으면 색 사각형 임시 그림을 만들어 준다.

const MANIFEST_PATH: String = "res://assets/manifest.json"
const PLACEHOLDER_SIZE: int = 32

var _paths: Dictionary = {}       # sprite_id → 경로
var _cache: Dictionary = {}       # sprite_id → Texture2D


func _ready() -> void:
	reload()


func reload() -> void:
	_cache.clear()
	_paths.clear()
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(MANIFEST_PATH)) == OK and json.data is Dictionary:
		var sprites: Variant = json.data.get("sprites", {})
		if sprites is Dictionary:
			_paths = sprites
	else:
		push_warning("manifest.json을 읽지 못했습니다.")


func has_sprite(sprite_id: String) -> bool:
	var path: String = _paths.get(sprite_id, "")
	return path != "" and ResourceLoader.exists(path)


func get_texture(sprite_id: String) -> Texture2D:
	if _cache.has(sprite_id):
		return _cache[sprite_id]
	var tex: Texture2D = null
	if has_sprite(sprite_id):
		tex = load(_paths[sprite_id]) as Texture2D
	if tex == null:
		tex = _make_placeholder(sprite_id)
	_cache[sprite_id] = tex
	return tex


## sprite_id 글자로 색을 정해 늘 같은 색 사각형이 나오게 한다.
func _make_placeholder(sprite_id: String) -> Texture2D:
	var hue: float = float(sprite_id.hash() & 0xFFFF) / 65535.0
	var img: Image = Image.create(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.from_hsv(hue, 0.55, 0.85))
	var border: Color = Color.from_hsv(hue, 0.7, 0.4)
	for i: int in PLACEHOLDER_SIZE:
		img.set_pixel(i, 0, border)
		img.set_pixel(i, PLACEHOLDER_SIZE - 1, border)
		img.set_pixel(0, i, border)
		img.set_pixel(PLACEHOLDER_SIZE - 1, i, border)
	return ImageTexture.create_from_image(img)
