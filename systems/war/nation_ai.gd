class_name NationAI
extends RefCounted
## 국가 AI (GDD §7.3): 매월 초 공격 계획, 매월 말 세력균형 개입.
## 공격 계획 = {"id", "attacker", "defender", "from", "to", "sent", "mercs", "merc_cost", "commander", "def_commander",
##              "player_side": 주인공이 편든 나라, "player_result": "win"/"lose"/""}


static func cfg(section: String, key: String, default_value: Variant = null) -> Variant:
	return DataDB.get_table("war").get(section, {}).get(key, default_value)


static func is_winter(month: int) -> bool:
	return month == 12 or month <= 2


## 지휘관 후보 전투력: (통솔 + 무력)
static func commander_score(id: String) -> int:
	return Officers.stat(id, "lead") + Officers.stat(id, "str")


## 그 나라 무장 중 지휘관: 그 도시에 있는 사람 우선, 없으면 나라 전체에서 가장 강한 사람. 부상자 제외.
static func pick_commander(n: String, city_id: String, exclude: Array = []) -> String:
	var best: String = ""
	var best_here: bool = false
	for id: String in GameState.officers:
		var s: Dictionary = GameState.officers[id]
		if id == GameState.player_id or exclude.has(id) or not Officers.is_active(id) or s.get("nation", "") != n or int(s.get("injury", 0)) > 0:
			continue
		var here: bool = s.get("city", "") == city_id
		if best == "" or (here and not best_here) or (here == best_here and commander_score(id) > commander_score(best)):
			best = id
			best_here = here
	return best


static func commander_factor(id: String) -> float:
	return 1.0 if id == "" else 1.0 + commander_score(id) / 400.0


## 매월 초: 나라마다 aggression 확률로 공격 한 곳을 정한다.
static func plan_attacks(month: int) -> Array:
	var plans: Array = []
	var used_commanders: Array = []
	var world: WorldMap = WorldMap.shared()
	var send_ratio: float = cfg("attack", "send_ratio", 0.6)
	var strong_line: float = _average_power() * float(DataDB.balance("balance_of_power.strong_ratio", 1.8))
	var strong_bonus: float = cfg("attack", "strong_target_bonus", 1.3)
	for n: String in Diplomacy.alive_nations():
		var chance: float = float(Nations.row(n).get("aggression", 0.3))
		if is_winter(month):
			chance *= float(cfg("attack", "winter_factor", 0.4))
		if not RNG.chance(chance):
			continue
		var best: Dictionary = {}
		var best_ratio: float = 0.0
		for from: String in Economy.cities_of(n):
			var available: int = int(int(GameState.cities[from]["troops"]) * send_ratio)
			if int(GameState.cities[from]["troops"]) - available < int(cfg("attack", "keep_min", 400)):
				continue
			for to: String in world.neighbors(from):
				var enemy: String = GameState.city_owner(to)
				if not Diplomacy.at_war(n, enemy) or _targeted(plans, to):
					continue
				var c: Dictionary = GameState.cities[to]
				var defense: float = int(c["troops"]) * (1.0 + int(c["defense"]) * float(cfg("resolve", "defense_bonus", 0.005)))
				var ratio: float = available / maxf(defense, 1.0)
				if power_index(enemy) > strong_line:
					ratio *= strong_bonus   # 너무 강한 나라는 다 같이 노린다
				if ratio > best_ratio:
					best_ratio = ratio
					best = {"from": from, "to": to, "enemy": enemy, "sent": available}
		if best.is_empty():
			continue
		# 돈 많은 나라는 용병으로 모자란 전력을 채운다 (hire_rate)
		var mercs: int = 0
		var merc_cost: int = 0
		var nation: Dictionary = GameState.nations[n]
		if RNG.chance(float(Nations.row(n).get("hire_rate", 0.5))):
			var per: float = float(cfg("attack", "merc_cost_per_troop", 1.5)) * (1.0 + Economy.cities_of(n).size() * float(cfg("attack", "merc_size_premium", 0.1)))
			mercs = mini(int(int(nation["gold"]) * float(cfg("attack", "merc_gold_ratio", 0.3)) / per),
				int(best["sent"] * float(cfg("attack", "merc_max_ratio", 0.5))))
			merc_cost = int(mercs * per)
		var total_ratio: float = best_ratio * (best["sent"] + mercs) / maxf(best["sent"], 1)
		if total_ratio < float(cfg("attack", "min_ratio", 1.15)):
			continue
		var commander: String = pick_commander(n, best["from"], used_commanders)
		if commander != "":
			used_commanders.append(commander)
		var def_commander: String = pick_commander(best["enemy"], best["to"], used_commanders)
		# 방어 지휘관은 그 도시에 있을 때만
		if def_commander != "" and Officers.get_state(def_commander).get("city", "") != best["to"]:
			def_commander = ""
		nation["gold"] = int(nation["gold"]) - merc_cost
		plans.append({
			"id": "w%d_%s" % [TimeManager.month_index(), n],
			"attacker": n, "defender": best["enemy"], "from": best["from"], "to": best["to"],
			"sent": best["sent"], "mercs": mercs, "merc_cost": merc_cost,
			"commander": commander, "def_commander": def_commander,
			"player_side": "", "player_result": "",
		})
	return plans


static func _targeted(plans: Array, city: String) -> bool:
	for p: Dictionary in plans:
		if p["to"] == city:
			return true
	return false


## 국력 = 도시 수 × 가중치 + 총 병력 + 금
static func power_index(n: String) -> float:
	return Economy.cities_of(n).size() * float(cfg("intervention", "city_weight", 3000)) + Economy.total_troops(n) + int(GameState.nations[n]["gold"])


## 세력균형 개입 (GDD §7.3): 약한 나라는 이웃이 돕고, 너무 강한 나라에는 나머지가 손잡는다.
static func intervene() -> Array:
	var lines: Array = []
	var alive: Array = Diplomacy.alive_nations()
	if alive.size() < 3:
		return lines
	var total: float = 0.0
	for n: String in alive:
		total += power_index(n)
	var avg: float = total / alive.size()
	var weak: float = DataDB.balance("balance_of_power.weak_ratio", 0.5)
	var strong: float = DataDB.balance("balance_of_power.strong_ratio", 1.8)
	var truce_chance: float = cfg("intervention", "truce_chance", 0.5)
	for n: String in alive:
		var p: float = power_index(n)
		if p < avg * weak:
			for other: String in Diplomacy.neighbor_nations(n):
				# 주인공 나라의 외교·국고는 주인공이 정한다 (도움을 받을 수는 있다)
				if Nations.is_player_nation(other):
					continue
				if Diplomacy.at_war(n, other):
					if Nations.is_player_nation(n):
						continue
					if RNG.chance(truce_chance):
						Diplomacy.set_truce(n, other)
						lines.append(GameAction.msg("DIPLO_BALANCE_TRUCE", [Diplomacy.nation_name(other), Diplomacy.nation_name(n)]))
				else:
					var aid: int = int(int(GameState.nations[other]["gold"]) * float(cfg("intervention", "aid_ratio", 0.15)))
					if aid > 0:
						GameState.nations[other]["gold"] = int(GameState.nations[other]["gold"]) - aid
						GameState.nations[n]["gold"] = int(GameState.nations[n]["gold"]) + aid
						lines.append(GameAction.msg("DIPLO_BALANCE_AID", [Diplomacy.nation_name(other), Diplomacy.nation_name(n), Fmt.num(aid)]))
		elif p > avg * strong:
			lines.append(GameAction.msg("DIPLO_BALANCE_STRONG", [Diplomacy.nation_name(n)]))
			for a: String in alive:
				if a == n:
					continue
				for b: String in alive:
					if b <= a or b == n:
						continue
					if Nations.is_player_nation(a) or Nations.is_player_nation(b):
						continue
					if Diplomacy.at_war(a, b) and RNG.chance(truce_chance):
						Diplomacy.set_truce(a, b)
						lines.append(GameAction.msg("DIPLO_TRUCE_AGAINST", [Diplomacy.nation_name(a), Diplomacy.nation_name(b), Diplomacy.nation_name(n)]))
				if not Nations.is_player_nation(a) and Diplomacy.neighbor_nations(n).has(a) and not Diplomacy.at_war(a, n) and RNG.chance(float(cfg("intervention", "war_on_strong_chance", 0.5))):
					Diplomacy.set_war(a, n)
					lines.append(GameAction.msg("DIPLO_WAR_ON_STRONG", [Diplomacy.nation_name(a), Diplomacy.nation_name(n)]))
	return lines


static func _average_power() -> float:
	var alive: Array = Diplomacy.alive_nations()
	var total: float = 0.0
	for n: String in alive:
		total += power_index(n)
	return total / maxf(alive.size(), 1)
