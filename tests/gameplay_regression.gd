extends Node
## Focused state-invariant regressions; no user saves are written.

var passes: int = 0
var fails: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
		print("FAIL: ", label)


func _ready() -> void:
	_test_recruitment()
	_test_launch_fitness()
	_test_conquest_fitness()
	print("GAMEPLAY REGRESSION: %d passed, %d failed" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)


func _world() -> void:
	RNG.reseed(42)
	WorldSetup.new_game({"name": "Regression", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false


func _test_recruitment() -> void:
	_world()
	var me: String = GameState.player_id
	# Isolate one city and two candidates. Force hiring so the check is deterministic.
	GameState.officers = {me: GameState.player()}
	GameState.cities = {"leongarde": GameState.cities["leongarde"]}
	GameState.officers["companion"] = Officers.state_from_data({"id": "companion", "city": "leongarde"})
	GameState.officers["free"] = Officers.state_from_data({"id": "free", "city": "leongarde"})
	Career.add_companion(me, "companion")
	var recruit: Dictionary = DataDB.get_table("officer_gen")["recruit"]
	var base: float = recruit["base_chance"]
	var generic: float = recruit["generic_chance"]
	recruit["base_chance"] = 1.0
	recruit["generic_chance"] = 0.0
	Personnel.run_month("leonhart")
	check(Officers.get_state("companion")["nation"] == "", "AI cannot enlist a player's companion")
	check(Officers.get_state("companion").get("leader", "") == me and Career.companions(me).has("companion"), "companion membership remains consistent")
	check(Officers.get_state("free")["nation"] == "leonhart", "AI still recruits available free agents")
	recruit["base_chance"] = base
	recruit["generic_chance"] = generic


func _test_launch_fitness() -> void:
	_world()
	var me: String = GameState.player_id
	var p: Dictionary = GameState.player()
	var from: String = p["city"]
	var target: String = WorldMap.shared().neighbors(from)[0]
	p["nation"] = "leonhart"
	p["rank"] = "lord"
	p["governs"] = from
	p["ap"] = 5
	GameState.cities[from]["troops"] = 2000
	GameState.cities[target]["nation"] = "merka"
	Diplomacy.set_war("leonhart", "merka")
	GameState.flags["planned_attacks"] = []
	var params: Dictionary = {"target": target}
	check(Actions.can_execute("launch_war", me, params) == "", "healthy lord can launch war")
	p["injury"] = 2
	var result: Dictionary = Actions.execute("launch_war", me, params)
	check(not result["ok"], "injured lord cannot launch war")
	check(p["ap"] == 5 and WarSystem.plans().is_empty(), "rejected launch spends no AP and creates no plan")
	# Reset side effects from unfixed baseline so the zero-troop check stays independent.
	p["injury"] = 0
	p["ap"] = 5
	p["troops"] = 0
	GameState.flags["planned_attacks"] = []
	check(Actions.can_execute("launch_war", me, params) == "ACT_FAIL_NO_TROOPS", "lord without personal troops cannot launch war")
	p["troops"] = Officers.max_troops(me)
	check(Actions.execute("launch_war", me, params)["ok"] and p["ap"] == 3, "healthy launch still spends exactly two AP")


func _test_conquest_fitness() -> void:
	_world()
	var me: String = GameState.player_id
	var p: Dictionary = GameState.player()
	p["rank"] = "merc_captain"
	p["company"] = {"name": "Regression Company"}
	p["ap"] = 5
	GameState.flags["planned_attacks"] = []
	var target: String = WorldMap.shared().neighbors(p["city"])[0]
	var params: Dictionary = {"target": target}
	check(Actions.can_execute("conquest", me, params) == "", "healthy mercenary can launch conquest")
	p["injury"] = 2
	check(not Actions.execute("conquest", me, params)["ok"] and p["ap"] == 5, "injured conquest blocked without AP cost")
	p["injury"] = 0
	p["ap"] = 5
	p["troops"] = 0
	check(Actions.can_execute("conquest", me, params) == "ACT_FAIL_NO_TROOPS", "conquest requires personal troops")
