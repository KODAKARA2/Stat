class_name BattleTiles
extends RefCounted
## 전투 지형 TileSet. terrain.json 순서대로 한 줄짜리 아틀라스(칸당 32px)를 쓴다.
## AssetRegistry에 "tileset_battle"이 등록돼 있으면 그 그림을, 없으면 색과 무늬로 임시 그림을 만든다.

const TILE: int = 32


static func atlas_index(terrain_id: String) -> int:
	var rows: Array = DataDB.get_rows("terrain")
	for i: int in rows.size():
		if rows[i]["id"] == terrain_id:
			return i
	return 0


static func make_tileset() -> TileSet:
	var tex: Texture2D
	if AssetRegistry.has_sprite("tileset_battle"):
		tex = AssetRegistry.get_texture("tileset_battle")
	else:
		tex = ImageTexture.create_from_image(_placeholder_atlas())
	var tileset: TileSet = TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = tex
	source.texture_region_size = Vector2i(TILE, TILE)
	for i: int in DataDB.get_rows("terrain").size():
		source.create_tile(Vector2i(i, 0))
	tileset.add_source(source, 0)
	return tileset


## 지형마다 바탕색 + 간단한 도트 무늬 (숲 = 나무, 언덕 = 봉우리, 강 = 물결, 성벽 = 벽돌)
static func _placeholder_atlas() -> Image:
	var rows: Array = DataDB.get_rows("terrain")
	var img: Image = Image.create(TILE * rows.size(), TILE, false, Image.FORMAT_RGBA8)
	for i: int in rows.size():
		var base: Color = Color.html(rows[i].get("color", "#808080"))
		var ox: int = i * TILE
		img.fill_rect(Rect2i(ox, 0, TILE, TILE), base)
		# 칸 경계선
		var edge: Color = base.darkened(0.25)
		for k: int in TILE:
			img.set_pixel(ox + k, TILE - 1, edge)
			img.set_pixel(ox + TILE - 1, k, edge)
		var mark: Color = base.darkened(0.35)
		var light: Color = base.lightened(0.25)
		match rows[i]["id"]:
			"forest":
				for p: Vector2i in [Vector2i(8, 10), Vector2i(22, 8), Vector2i(14, 22), Vector2i(25, 23)]:
					_tree(img, ox + p.x, p.y, mark, light)
			"hill":
				_hump(img, ox + 10, 22, 8, mark)
				_hump(img, ox + 22, 18, 7, light.darkened(0.1))
			"river":
				for y: int in [8, 16, 24]:
					for x: int in range(2, TILE - 3):
						img.set_pixel(ox + x, y + int(round(sin(x * 0.6) * 1.5)), light)
			"gate":
				for x: int in range(3, TILE - 3, 6):
					img.fill_rect(Rect2i(ox + x, 3, 2, TILE - 6), mark)
				img.fill_rect(Rect2i(ox + 3, 10, TILE - 6, 2), light)
				img.fill_rect(Rect2i(ox + 3, 21, TILE - 6, 2), light)
			"burnt", "rubble":
				for p: Vector2i in [Vector2i(6, 7), Vector2i(20, 12), Vector2i(12, 24), Vector2i(26, 26)]:
					img.fill_rect(Rect2i(ox + p.x, p.y, 3, 2), mark)
			"wall":
				for y: int in range(0, TILE, 8):
					for x: int in TILE:
						img.set_pixel(ox + x, y, mark)
					var shift: int = 0 if (y / 8) % 2 == 0 else 8
					for x: int in range(shift, TILE, 16):
						for yy: int in range(y, mini(y + 8, TILE)):
							img.set_pixel(ox + x, yy, mark)
			"plains":
				for p: Vector2i in [Vector2i(7, 9), Vector2i(21, 6), Vector2i(15, 19), Vector2i(26, 24), Vector2i(5, 26)]:
					img.set_pixel(ox + p.x, p.y, light)
					img.set_pixel(ox + p.x + 1, p.y - 1, light)
	return img


static func _tree(img: Image, cx: int, cy: int, dark: Color, light: Color) -> void:
	for dy: int in range(-4, 3):
		var half: int = (dy + 5) / 2
		for dx: int in range(-half, half + 1):
			img.set_pixel(cx + dx, cy + dy, dark)
	img.set_pixel(cx - 1, cy - 2, light)
	img.fill_rect(Rect2i(cx, cy + 3, 1, 2), dark.darkened(0.3))


static func _hump(img: Image, cx: int, base_y: int, half: int, color: Color) -> void:
	for dx: int in range(-half, half + 1):
		var h: int = int((half - absi(dx)) * 0.9)
		for dy: int in h:
			img.set_pixel(cx + dx, base_y - dy, color)
