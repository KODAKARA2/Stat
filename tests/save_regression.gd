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
	check(JSON.parse_string(JSON.stringify(GameState.to_save())) == JSON.parse_string(next_state), "autosave captures refreshed AP, quests and world state")
	SaveManager.game_in_progress = false
	var before: String = JSON.stringify(GameState.to_save())
	var f: FileAccess = FileAccess.open(SaveManager.slot_path("regression_bad"), FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	check(not SaveManager.load_game("regression_bad"), "empty JSON rejected")
	check(JSON.stringify(GameState.to_save()) == before, "failed load leaves current game untouched")
	# Two successful writes retain the previous known-good save.
	SaveManager.save_game("regression_backup")
	var old_gold: int = int(GameState.player()["gold"])
	GameState.player()["gold"] = old_gold + 17
	check(SaveManager.save_game("regression_backup"), "overwrite creates backup")
	f = FileAccess.open(SaveManager.slot_path("regression_backup"), FileAccess.WRITE)
	f.store_string("{truncated")
	f.close()
	check(SaveManager.load_game("regression_backup") and SaveManager.recovered_backup, "truncated primary recovers backup")
	check(int(GameState.player()["gold"]) == old_gold, "backup restores previous valid state")
	check(SaveManager.peek("regression_backup").get("backup", false), "preview identifies recovered backup")
	var good: Dictionary = {"version": 1, "rng": RNG.to_save(), "time": TimeManager.to_save(), "state": GameState.to_save().duplicate(true)}
	for kind: String in ["future", "month", "year", "shape", "player", "city", "nation"]:
		var bad: Dictionary = good.duplicate(true)
		match kind:
			"future": bad["version"] = 999
			"month": bad["time"]["month"] = 13
			"year": bad["time"]["year"] = 1.5
			"nation": bad["state"]["nations"]["leonhart"] = {}
			"shape": bad["state"]["officers"] = []
			"player": bad["state"]["player_id"] = "missing"
			"city": bad["state"]["officers"][GameState.player_id]["city"] = "missing"
		f = FileAccess.open(SaveManager.slot_path("regression_bad"), FileAccess.WRITE)
		f.store_string(JSON.stringify(bad))
		f.close()
		before = JSON.stringify(GameState.to_save())
		check(not SaveManager.load_game("regression_bad") and JSON.stringify(GameState.to_save()) == before, "reject malformed " + kind + " without mutation")
	check(not SaveManager.save_game("../escape"), "reject slot path traversal")
	# A directory at destination simulates replacement failure without disk-full setup.
	DirAccess.make_dir_absolute(SaveManager.slot_path("regression_blocked"))
	check(not SaveManager.save_game("regression_blocked"), "replacement failure is not reported as success")
	DirAccess.remove_absolute(SaveManager.slot_path("regression_blocked"))
	for slot: String in ["regression_rng", "regression_bad", "regression_backup", "regression_blocked"]:
		for suffix: String in ["", ".bak", ".tmp"]:
			DirAccess.remove_absolute(SaveManager.slot_path(slot) + suffix)
	SaveManager.game_in_progress = false
	print("SAVE REGRESSION failures=", failures)
	get_tree().quit(1 if failures else 0)
