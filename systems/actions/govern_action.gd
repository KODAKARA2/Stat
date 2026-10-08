class_name GovernAction
extends GameAction
## 성주 통치 (행동력 1, 비용은 나라 국고): 다스리는 도시에 있을 때만.
## params = {"kind": "commerce" | "agriculture" | "defense" | "conscript"}


func _init() -> void:
	id = "govern"


func cost(actor: String, kind: String) -> int:
	match kind:
		"defense":
			return int(Career.cfg("govern", "defense_cost", 80))
		"conscript":
			return int(conscript_amount(actor) * float(Career.cfg("govern", "conscript_cost_per_troop", 1.0)))
	return int(Career.cfg("govern", "develop_cost", 50))


## 징병할 수 있는 병사 수: 한 번에 conscript_max, 도시 병력 상한(인구 비례)까지
func conscript_amount(actor: String) -> int:
	var city: String = Career.governs(actor)
	if city == "":
		return 0
	var c: Dictionary = GameState.cities[city]
	var cap: int = int(int(c["population"]) * float(DataDB.get_table("war").get("conscription", {}).get("max_pop_ratio", 0.12)))
	return clampi(cap - int(c["troops"]), 0, int(Career.cfg("govern", "conscript_max", 400)))


func check(actor: String, params: Dictionary) -> String:
	var city: String = Career.governs(actor)
	if city == "":
		return "GOVERN_FAIL_NO_CITY"
	if Officers.get_state(actor).get("city", "") != city:
		return "GOVERN_FAIL_NOT_HERE"
	var kind: String = params.get("kind", "")
	if not kind in ["commerce", "agriculture", "defense", "conscript"]:
		return "ACT_FAIL_UNKNOWN"
	if kind == "conscript" and conscript_amount(actor) <= 0:
		return "GOVERN_FAIL_FULL"
	if int(GameState.nations[GameState.city_owner(city)]["gold"]) < cost(actor, kind):
		return "GOVERN_FAIL_TREASURY"
	return ""


func run(actor: String, params: Dictionary) -> Dictionary:
	var city: String = Career.governs(actor)
	var kind: String = params["kind"]
	var c: Dictionary = GameState.cities[city]
	var n: String = GameState.city_owner(city)
	var spent: int = cost(actor, kind)
	var line: String
	match kind:
		"commerce", "agriculture":
			var gain: int = int(Career.cfg("govern", "develop_base", 1)) + int(Officers.stat(actor, "pol") * float(Career.cfg("govern", "develop_per_pol", 0.04)))
			c[kind] = mini(int(c[kind]) + gain, 100)
			line = msg("GOVERN_DEVELOPED", [TranslationServer.translate("STAT_" + kind.to_upper()), gain, int(c[kind])])
		"defense":
			c["defense"] = mini(int(c["defense"]) + int(Career.cfg("govern", "defense_gain", 4)), 100)
			line = msg("GOVERN_DEFENSE", [int(c["defense"])])
		"conscript":
			var amount: int = conscript_amount(actor)
			c["troops"] = int(c["troops"]) + amount
			line = msg("GOVERN_CONSCRIPT", [Fmt.num(amount), Fmt.num(int(c["troops"]))])
	GameState.nations[n]["gold"] = int(GameState.nations[n]["gold"]) - spent
	return {"kind": kind, "lines": [line, msg("GOVERN_SPENT", [Diplomacy.nation_name(n), Fmt.num(spent)])]}
