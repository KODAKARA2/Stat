extends Node

var failures: int = 0

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _ready() -> void:
	WorldSetup.new_game({"name": "저장 회귀", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	RNG.reseed(12345)
	RNG.randf()
	SaveManager.save_game("regression_rng")
	var expected: Array = []
	for i: int in 20:
		expected.append(RNG.randi_range(0, 1000000))
	SaveManager.load_game("regression_rng")
	var actual: Array = []
	for i: int in 20:
		actual.append(RNG.randi_range(0, 1000000))
	check(actual == expected, "JSON round trip preserves RNG stream")
	SaveManager.game_in_progress = true
	TimeManager.advance_month()
	var next_date: Dictionary = TimeManager.to_save().duplicate(true)
	var next_state: String = JSON.stringify(GameState.to_save())
	check(SaveManager.load_game("auto"), "automatic save loads")
	check(TimeManager.to_save() == next_date, "autosave uses new month, not settled old month")
	check(JSON.stringify(GameState.to_save()) == next_state, "autosave captures refreshed AP, quests and world state")
	SaveManager.game_in_progress = false
	var before: String = JSON.stringify(GameState.to_save())
	var f: FileAccess = FileAccess.open(SaveManager.slot_path("regression_bad"), FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	check(not SaveManager.load_game("regression_bad"), "empty JSON rejected")
	check(JSON.stringify(GameState.to_save()) == before, "failed load leaves current game untouched")
	for slot: String in ["regression_rng", "regression_bad"]:
		for suffix: String in ["", ".bak", ".tmp"]:
			DirAccess.remove_absolute(SaveManager.slot_path(slot) + suffix)
	SaveManager.game_in_progress = false
	print("SAVE REGRESSION failures=", failures)
	get_tree().quit(1 if failures else 0)
