class_name WarResolver
extends RefCounted
## 주인공이 직접 싸우지 않는 전투의 자동 판정 (월말). 주인공이 참전했으면 그 결과가 전력에 크게 반영된다.
## 돌려주는 값: {"lines": [보고 문장], "deaths": [전사 문장], "captured": 점령했는가}


static func cfg(key: String, default_value: Variant = null) -> Variant:
	return DataDB.get_table("war").get("resolve", {}).get(key, default_value)


static func resolve(plan: Dictionary, month: int) -> Dictionary:
	var out: Dictionary = {"lines": [], "deaths": [], "captured": false}
	var att: String = plan["attacker"]
	var def: String = plan["defender"]
	var from: Dictionary = GameState.cities[plan["from"]]
	var to: Dictionary = GameState.cities[plan["to"]]
	# 계획 뒤 상황이 바뀌었으면(이미 빼앗겼거나 휴전) 취소
	if GameState.city_owner(plan["from"]) != att or GameState.city_owner(plan["to"]) != def or not Diplomacy.at_war(att, def):
		return out
	var sent: int = mini(int(plan["sent"]), int(from["troops"]))
	if sent <= 0:
		return out
	from["troops"] = int(from["troops"]) - sent
	var army: int = sent + int(plan["mercs"])
	var garrison: int = int(to["troops"])

	var att_power: float = army * NationAI.commander_factor(_alive(plan["commander"]))
	# 이웃한 같은 나라 도시에서 지원군이 붙는다
	var reserves: float = 0.0
	for other: String in WorldMap.shared().neighbors(plan["to"]):
		if GameState.city_owner(other) == def:
			reserves += int(GameState.cities[other]["troops"]) * float(cfg("reserve_ratio", 0.25))
	var def_power: float = (garrison + reserves) * (1.0 + int(to["defense"]) * float(cfg("defense_bonus", 0.005))) * NationAI.commander_factor(_alive(plan["def_commander"]))
	if Economy.cities_of(def).size() <= int(cfg("desperate_cities", 2)):
		def_power *= float(cfg("desperate_bonus", 1.3))   # 필사적 저항
	if NationAI.is_winter(month):
		att_power *= float(DataDB.get_table("war").get("attack", {}).get("winter_power", 0.9))
	att_power *= RNG.randf_range(cfg("random_min", 0.8), cfg("random_max", 1.2))
	def_power *= RNG.randf_range(cfg("random_min", 0.8), cfg("random_max", 1.2))
	# 주인공 참전
	if plan.get("player_result", "") != "":
		var helped: String = plan["player_side"]
		var mult: float = float(cfg("player_win_bonus", 1.5)) if plan["player_result"] == "win" else float(cfg("player_lose_mult", 0.8))
		if helped == att:
			att_power *= mult
		else:
			def_power *= mult

	var att_won: bool = att_power > def_power
	var w_loss: float = RNG.randf_range(cfg("winner_loss_min", 0.12), cfg("winner_loss_max", 0.28))
	var l_loss: float = RNG.randf_range(cfg("loser_loss_min", 0.35), cfg("loser_loss_max", 0.55))
	var army_loss: int = int(army * (w_loss if att_won else l_loss))
	var gar_loss: int = int(garrison * (l_loss if att_won else w_loss))
	# 살아남은 병력 중 용병 몫은 계약이 끝나 떠나고, 정규군만 남는다
	var survivors: int = int((army - army_loss) * float(sent) / maxf(army, 1))
	var to_name: String = WorldMap.city_name(plan["to"])
	var loss_pct: int = int(round(100.0 * army_loss / maxf(army, 1)))
	var budget: String = TranslationServer.translate("REPORT_IN_BUDGET" if int(GameState.nations[att]["gold"]) > 0 else "REPORT_OVER_BUDGET")

	if att_won:
		var retreat: String = _retreat_city(plan["to"], def)
		var fled: int = garrison - gar_loss
		if retreat != "":
			GameState.cities[retreat]["troops"] = int(GameState.cities[retreat]["troops"]) + fled
		to["nation"] = att
		to["troops"] = survivors
		to["defense"] = maxi(10, int(to["defense"]) - int(cfg("captured_defense_loss", 10)))
		to["security"] = mini(int(to["security"]), int(cfg("captured_security", 40)))
		_move_officers(plan["to"], def, retreat)
		var cmd: String = plan["commander"]
		if cmd != "" and Officers.is_active(cmd) and cmd != GameState.player_id:
			Officers.get_state(cmd)["city"] = plan["to"]
		out["captured"] = true
		out["lines"].append(GameAction.msg("REPORT_CAPTURED", [Diplomacy.nation_name(att), to_name, Diplomacy.nation_name(def), loss_pct, budget]))
		_maybe_die(plan["def_commander"], out)
	else:
		to["troops"] = garrison - gar_loss
		from["troops"] = int(from["troops"]) + survivors
		out["lines"].append(GameAction.msg("REPORT_REPELLED", [Diplomacy.nation_name(att), to_name, Diplomacy.nation_name(def), loss_pct, budget]))
		_maybe_die(plan["commander"], out)
	if int(plan["mercs"]) > 0:
		out["lines"].append(GameAction.msg("REPORT_MERCS", [Diplomacy.nation_name(att), Fmt.num(int(plan["mercs"])), Fmt.num(int(plan["merc_cost"]))]))
	return out


static func _alive(id: String) -> String:
	return id if id != "" and Officers.is_active(id) else ""


## 진 쪽 지휘관은 낮은 확률로 전사 (GDD §5). 담담하게 한 줄.
static func _maybe_die(id: String, out: Dictionary) -> void:
	if id == "" or not Officers.is_active(id) or id == GameState.player_id:
		return
	if RNG.chance(float(cfg("commander_death_chance", 0.08))):
		Officers.get_state(id)["alive"] = false
		out["deaths"].append(GameAction.msg("REPORT_DIED", [Officers.display_name(id), Officers.nation_label(id)]))
	else:
		Officers.get_state(id)["injury"] = maxi(int(Officers.get_state(id).get("injury", 0)), 1)


## 빼앗긴 도시의 패잔병이 갈 곳: 이웃한 같은 나라 도시 중 병력이 가장 많은 곳 → 없으면 그 나라 아무 도시
static func _retreat_city(city: String, n: String) -> String:
	var best: String = ""
	for other: String in WorldMap.shared().neighbors(city):
		if GameState.city_owner(other) == n and (best == "" or int(GameState.cities[other]["troops"]) > int(GameState.cities[best]["troops"])):
			best = other
	if best == "":
		var cities: Array = Economy.cities_of(n)
		cities.erase(city)
		if not cities.is_empty():
			best = cities[0]
	return best


## 빼앗긴 도시에 있던 그 나라 무장은 퇴각. 갈 곳이 없으면 그 자리에서 재야가 된다.
static func _move_officers(city: String, n: String, retreat: String) -> void:
	for id: String in Officers.in_city(city):
		var s: Dictionary = Officers.get_state(id)
		if s.get("nation", "") != n or id == GameState.player_id:
			continue
		if retreat != "":
			s["city"] = retreat
		else:
			s["nation"] = ""
			s["rank"] = "none"
