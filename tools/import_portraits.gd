extends SceneTree
## 새 초상화 가져오기 (ChatGPT·Grok 등으로 그린 그림)
## 실행: godot --headless --path . -s res://tools/import_portraits.gd
##
## 1) C:/1/참고그림/대륙_초상화_의뢰/받은그림 (와 그 안의 portraits/) 의 named_<장수id>.* / gen_<묶음>_<번호>.* 를 읽는다 (png/jpg/webp)
##    "이름 (2).png" 같은 내려받기 사본과 깨진(덜 받아진) 그림은 건너뛴다
## 2) 정사각형으로 자르고(세로로 길면 위쪽 = 얼굴 쪽) 256px로 줄여 assets/sprites/portraits_ai/ 에 png로 저장
## 3) assets/manifest.json 에 "ai_<파일이름>" 항목을 넣고, named_ 그림은 "portrait_<장수id>" 를 새 그림으로 바꾼다
## 4) data/portraits.json 의 묶음(pools)은 새 그림이 한 장이라도 있으면 새 그림만으로 바꾼다 (그림체 섞임 방지)

const SRC_DIR: String = "C:/1/참고그림/대륙_초상화_의뢰/받은그림/"
const DST_DIR: String = "res://assets/sprites/portraits_ai/"
const SIZE: int = 256


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DST_DIR))
	if DirAccess.open(SRC_DIR) == null:
		print("받은그림 폴더가 없습니다: ", SRC_DIR)
		quit()
		return
	var named: Dictionary = {}     # 장수 id → sprite id
	var pools: Dictionary = {}     # 묶음 → [sprite id]
	var count: int = 0
	var done: PackedStringArray = []   # 가져온 파일 이름(확장자 없이)
	var paths: Dictionary = {}         # 파일 이름 → 전체 경로 (같은 이름이면 위 폴더 우선)
	for sub: String in ["portraits/", ""]:
		var dir: DirAccess = DirAccess.open(SRC_DIR + sub)
		if dir == null:
			continue
		for file: String in dir.get_files():
			if " (" in file:
				continue   # 내려받기 사본
			paths[file.get_basename()] = SRC_DIR + sub + file
	var bases: Array = paths.keys()
	bases.sort()
	for base: String in bases:
		var full: String = paths[base]
		var ext: String = full.get_extension().to_lower()
		if not ext in ["png", "jpg", "jpeg", "webp"] or not (base.begins_with("named_") or base.begins_with("gen_")):
			continue
		var img: Image = Image.new()
		if img.load(full) != OK or img.is_empty():
			print("읽기 실패 (깨진 파일?): ", full.get_file())
			continue
		var s: int = mini(img.get_width(), img.get_height())
		var x: int = (img.get_width() - s) / 2
		var y: int = 0 if img.get_height() > img.get_width() else (img.get_height() - s) / 2
		var sq: Image = img.get_region(Rect2i(x, y, s, s))
		sq.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		sq.save_png(ProjectSettings.globalize_path(DST_DIR + base + ".png"))
		var sprite: String = "ai_" + base
		if base.begins_with("named_"):
			named[base.trim_prefix("named_")] = sprite
		elif base.begins_with("gen_"):
			var key: String = base.trim_prefix("gen_")
			key = key.substr(0, key.rfind("_"))   # gen_dark_elf_f_03 → dark_elf_f
			pools.get_or_add(key, []).append(sprite)
		count += 1
		done.append(base)
	_update_manifest(named, done)
	_update_pools(pools)
	print("가져온 그림: %d장 (이름 있는 장수 %d명, 범용 묶음 %d개)" % [count, named.size(), pools.size()])
	quit()


func _read_json(path: String) -> Dictionary:
	var json: JSON = JSON.new()
	json.parse(FileAccess.get_file_as_string(path))
	return json.data if json.data is Dictionary else {}


func _write_json(path: String, data: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  ", false))
	f.close()


func _update_manifest(named: Dictionary, done: PackedStringArray) -> void:
	var path: String = "res://assets/manifest.json"
	var m: Dictionary = _read_json(path)
	var sprites: Dictionary = m.get("sprites", {})
	for base: String in done:
		sprites["ai_" + base] = DST_DIR + base + ".png"
	for officer: String in named:
		sprites["portrait_" + officer] = DST_DIR + "named_" + officer + ".png"
	m["sprites"] = sprites
	_write_json(path, m)


func _update_pools(pools: Dictionary) -> void:
	var path: String = "res://data/portraits.json"
	var p: Dictionary = _read_json(path)
	var current: Dictionary = p.get("pools", {})
	for key: String in pools:
		current[key] = pools[key]
	p["pools"] = current
	var old: PackedStringArray = []
	for key: String in current:
		for v: Variant in current[key]:
			if not str(v).begins_with("ai_"):
				old.append(key)
				break
	_write_json(path, p)
	if not old.is_empty():
		print("아직 예전 그림을 쓰는 묶음: ", ", ".join(old))
