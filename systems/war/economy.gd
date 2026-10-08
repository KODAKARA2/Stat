class_name Economy
extends RefCounted
## 국가 경제 (GDD §7.2): 세수·가을 수확·병력 유지비·징병·내정. 나라 금고는 GameState.nations[n]["gold"/"food"].


static func cfg(section: String, key: String, default_value: Variant = null) -> Variant:
	return DataDB.get_table("war").get(section, {}).get(key, default_value)


static func city_income(city_id: String) -> int:
	var c: Dictionary = GameState.cities[city_id]
	var base: float = int(c["commerce"]) * int(c["population"]) / 1000.0 * float(cfg("economy", "income_factor", 0.03))
	return int(base * (0.5 + int(c.get("security", 80)) / 200.0))


static func city_harvest(city_id: String) -> int:
	var c: Dictionary = GameState.cities[city_id]
	return int(int(c["agriculture"]) * int(c["population"]) / 1000.0 * float(cfg("economy", "harvest_factor", 0.4)))


static func cities_of(n: String) -> Array:
	var list: Array = []
	for city: String in GameState.cities:
		if GameState.city_owner(city) == n:
			list.append(city)
	return list


static func total_troops(n: String) -> int:
	var total: int = 0
	for city: String in cities_of(n):
		total += int(GameState.cities[city]["troops"])
	return total


static func monthly_income(n: String) -> int:
	var total: int = 0
	for city: String in cities_of(n):
		total += city_income(city)
	return total


static func upkeep(n: String) -> int:
	var extra_cities: int = maxi(0, cities_of(n).size() - int(cfg("economy", "admin_free_cities", 5)))
	return int(total_troops(n) * float(cfg("economy", "gold_upkeep", 0.01))) + extra_cities * int(cfg("economy", "admin_cost_per_city", 60))


## 매월 말 한 나라의 수입·지출. 모자라면 탈영. 바뀐 내용을 문장으로 돌려준다.
static func run_month(n: String, month: int) -> Array:
	var lines: Array = []
	var nation: Dictionary = GameState.nations[n]
	nation["gold"] = int(nation["gold"]) + monthly_income(n) - upkeep(n)
	if month == int(cfg("economy", "harvest_month", 9)):
		var harvest: int = 0
		for city: String in cities_of(n):
			harvest += city_harvest(city)
		nation["food"] = int(nation["food"]) + harvest
	nation["food"] = int(nation["food"]) - int(total_troops(n) * float(cfg("economy", "food_per_troop", 0.02)))
	if int(nation["gold"]) < 0 or int(nation["food"]) < 0:
		var ratio: float = cfg("economy", "desert_ratio", 0.05)
		var lost: int = 0
		for city: String in cities_of(n):
			var c: Dictionary = GameState.cities[city]
			var d: int = int(int(c["troops"]) * ratio)
			c["troops"] = int(c["troops"]) - d
			lost += d
		nation["gold"] = maxi(0, int(nation["gold"]))
		nation["food"] = maxi(0, int(nation["food"]))
		if lost > 0:
			lines.append(GameAction.msg("ECON_DESERTION", [Diplomacy.nation_name(n), Fmt.num(lost)]))
	return lines


## 성주: 그 도시에 있는 그 나라 무장 중 정치가 가장 높은 사람
static func governor(city_id: String) -> String:
	var owner: String = GameState.city_owner(city_id)
	var best: String = ""
	for id: String in Officers.in_city(city_id):
		if Officers.get_state(id).get("nation", "") == owner and (best == "" or Officers.stat(id, "pol") > Officers.stat(best, "pol")):
			best = id
	return best


static func develop(n: String) -> void:
	var per_pol: float = cfg("development", "chance_per_pol", 0.005)
	var cap: int = cfg("development", "max", 100)
	for city: String in cities_of(n):
		var gov: String = governor(city)
		if gov != "" and RNG.chance(Officers.stat(gov, "pol") * per_pol):
			var key: String = "commerce" if RNG.chance(0.5) else "agriculture"
			GameState.cities[city][key] = mini(int(GameState.cities[city][key]) + 1, cap)


## 남는 금으로 징병. 전쟁 중인 나라와 맞닿은 도시 중 병력이 가장 적은 곳부터 채운다.
static func conscript(n: String) -> void:
	var nation: Dictionary = GameState.nations[n]
	var reserve: int = upkeep(n) * int(cfg("conscription", "reserve_months", 3))
	var budget: int = int((int(nation["gold"]) - reserve) * float(cfg("conscription", "spend_ratio", 0.5)))
	if budget <= 0:
		return
	var per: float = cfg("conscription", "gold_per_troop", 1.0)
	var cities: Array = cities_of(n)
	cities.sort_custom(func(a: String, b: String) -> bool:
		var ta: bool = is_front(a)
		var tb: bool = is_front(b)
		if ta != tb:
			return ta
		return int(GameState.cities[a]["troops"]) < int(GameState.cities[b]["troops"]))
	for city: String in cities:
		var c: Dictionary = GameState.cities[city]
		var room: int = int(int(c["population"]) * float(cfg("conscription", "max_pop_ratio", 0.12))) - int(c["troops"])
		var add: int = mini(room, int(budget / per))
		if add <= 0:
			continue
		c["troops"] = int(c["troops"]) + add
		budget -= int(add * per)
		nation["gold"] = int(nation["gold"]) - int(add * per)
		if budget <= 0:
			break


## 전쟁 중인 나라와 맞닿은 도시
static func is_front(city_id: String) -> bool:
	var owner: String = GameState.city_owner(city_id)
	for other: String in WorldMap.shared().neighbors(city_id):
		if Diplomacy.at_war(owner, GameState.city_owner(other)):
			return true
	return false


## 치안 회복: 매월 security_regen씩 목표치까지 (성주가 있으면 2배)
static func recover_security(n: String) -> void:
	var target: int = cfg("economy", "security_target", 80)
	var regen: int = cfg("economy", "security_regen", 1)
	for city: String in cities_of(n):
		var c: Dictionary = GameState.cities[city]
		var step: int = regen * (2 if governor(city) != "" else 1)
		if int(c["security"]) < target:
			c["security"] = mini(int(c["security"]) + step, target)
