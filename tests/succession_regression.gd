extends Node
## Run with isolated HOME via tools/verify.sh. Save schema remains version 1.
var passes: int = 0
var fails: int = 0

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
		print("FAIL: ", label)

func _ready() -> void:
	for shape: String in ["missing", "empty", "existing"]:
		_test_assets(shape)
	_test_skills_and_repeat()
	_test_ruler_policy()
	print("SUCCESSION REGRESSION: %d passed, %d failed" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)

func _world() -> String:
	RNG.reseed(42)
	WorldSetup.new_game({"name": "Succession", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	var old: String = GameState.player_id
	for id: String in ["heir", "own", "inherited", "dead", "next"]:
		GameState.officers[id] = Officers.state_from_data({"id": id, "city": "leongarde", "stats": {"str": 90}, "skills": ["charge", "volley"]})
		GameState.officers[id]["name"] = id
	GameState.officers["heir"]["parents"] = [old]
	GameState.officers["dead"]["alive"] = false
	return old

func _test_assets(shape: String) -> void:
	var old: String = _world()
	var o: Dictionary = Officers.get_state(old)
	var h: Dictionary = Officers.get_state("heir")
	o["hired"] = [{"type": "archers", "troops": 123, "months": 3}]
	o["quests"] = [{"id": "inherited", "months": 2}]
	o["company"] = {"name": "Old company"}
	o["contract"] = {"id": "old_contract", "employer": "leonhart", "months": 3, "pay": 100}
	o["reputation"] = {"leonhart": 12, "merka": -4}
	Career.add_companion(old, "heir")
	Career.add_companion(old, "inherited")
	o["companions"].append("dead")
	if shape != "missing":
		for key: String in ["hired", "quests"]:
			h[key] = []
		for key: String in ["company", "contract", "reputation"]:
			h[key] = {}
	if shape == "existing":
		h["hired"] = [{"type": "archers", "troops": 123, "months": 3}]
		h["quests"] = [{"id": "own", "months": 4}]
		h["company"] = {"name": "Heir company"}
		h["contract"] = {"id": "own_contract", "employer": "merka", "months": 2, "pay": 50}
		h["reputation"] = {"leonhart": 7}
		Career.add_companion("heir", "own")
		# Shared ID must appear once; succession repairs its leader.
		h["companions"].append("inherited")
	var existing: bool = shape == "existing"
	Family.die(old, "old_age")
	check(GameState.player_id == "heir", shape + ": heir selected")
	check(h["hired"].size() == (2 if existing else 1), shape + ": every hired unit preserved, including identical units")
	check(h["quests"].size() == (2 if existing else 1), shape + ": active quests preserved")
	check(h.get("company", {}).get("name", "") == ("Heir company" if existing else "Old company"), shape + ": company retained or inherited")
	check(h.get("contract", {}).get("id", "") == ("own_contract" if existing else "old_contract"), shape + ": nonempty contract retained; empty inherits")
	check(h["reputation"] == {"leonhart": 7 if existing else 12, "merka": -4}, shape + ": reputation fills missing nations without overwriting heir")
	check(h["companions"] == (["own", "inherited"] if existing else ["inherited"]), shape + ": unique active companion union excludes self and dead")
	check(Officers.get_state("inherited").get("leader") == "heir" and not h.has("leader"), shape + ": leadership consistent")
	# Mutating inherited containers must not mutate the deceased officer's snapshot.
	if not h["hired"].is_empty():
		h["hired"][-1]["months"] = 1
	if not h["quests"].is_empty():
		h["quests"][-1]["months"] = 1
	check(o["hired"][0]["months"] == 3 and o["quests"][0]["months"] == 2, shape + ": inherited arrays are deep copies")
	if not existing and not h["contract"].is_empty():
		h["contract"]["months"] = 1
	check(existing or o["contract"]["months"] == 3, shape + ": inherited contract is a deep copy")
	var expected: Variant = JSON.parse_string(JSON.stringify(GameState.to_save()))
	check(SaveManager.save_game("succession") and SaveManager.load_game("succession"), shape + ": version 1 save round trip")
	check(JSON.parse_string(JSON.stringify(GameState.to_save())) == expected, shape + ": saved succession preserves full state")

func _test_skills_and_repeat() -> void:
	var old: String = _world()
	var h: Dictionary = Officers.get_state("heir")
	h["skill_levels"] = {"volley": 2}
	h["skill_uses"] = {"charge": 9, "volley": 5}
	check(SaveManager.save_game("succession") and SaveManager.load_game("succession"), "legacy NPC with missing skill level loads without migration")
	h = Officers.get_state("heir")
	var before: int = SkillLevels.level("heir", "charge")
	check(before == 3, "NPC implicit level fixture")
	Family.die(old, "old_age")
	check(SkillLevels.level("heir", "charge") == before, "implicit NPC level survives player ID change")
	check(SkillLevels.level("heir", "volley") == 2 and SkillLevels.uses("heir", "charge") == 9 and SkillLevels.uses("heir", "volley") == 5, "explicit skill level and uses preserved")
	check(SaveManager.save_game("succession") and SaveManager.load_game("succession") and SkillLevels.level("heir", "charge") == before, "materialized skill survives save/load")
	var next: Dictionary = Officers.get_state("next")
	next["parents"] = ["heir"]
	Career.add_companion("heir", "own")
	GameState.player()["contract"] = {"id": "continuing", "months_left": 3, "pay": 100, "employer": "leonhart"}
	Family.die("heir", "old_age")
	check(GameState.player_id == "next" and Career.companions("next") == ["own"] and Officers.get_state("own")["leader"] == "next", "second succession keeps companion membership")
	check(Career.contract("next")["id"] == "continuing" and SkillLevels.level("next", "charge") == 3, "second succession keeps contract and NPC level")
	Guild.tick_contracts("next")
	Career.tick_contract("next")
	check(Career.contract("next")["months_left"] == 2, "inherited contract continues monthly progression")

func _test_ruler_policy() -> void:
	var old: String = _world()
	var o: Dictionary = Officers.get_state(old)
	o["rank"] = "ruler"
	o["nation"] = "leonhart"
	o["governs"] = "leongarde"
	GameState.flags["player_founded"] = "leonhart"
	var nations: Dictionary = GameState.nations.duplicate(true)
	Family.die(old, "old_age")
	check(GameState.player()["rank"] == "merc_rookie" and GameState.player()["nation"] == "" and not GameState.player().has("governs"), "characterization: ruler office is not automatically inherited")
	check(GameState.nations == nations and GameState.flags["player_founded"] == "leonhart", "characterization: kingdom ownership and founded flag unchanged")
