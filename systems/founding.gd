class_name Founding
extends RefCounted
## 건국 (GDD §4.2 "군주: 계승, 또는 독립(건국)"). 두 가지 길 (기획 확정 2026-10-08):
##  ① 독립 선언: 성주 이상이 다스리는 도시를 들고 독립 → 원 소속국과 전쟁
##  ② 용병단 점령: 용병대장이 용병단으로 이웃 도시를 공성해 빼앗으면 그 도시로 건국
## 새 나라는 GameState.nations[id]["custom"]에 이름·색 등을 갖고, 주인공은 군주가 된다.

const COLORS: Array = ["#e0563c", "#3cb6a8", "#d8b13a", "#8f5bd6", "#e07ab0", "#6f9e3a"]


static func cfg(key: String, default_value: Variant = null) -> Variant:
	return DataDB.get_table("career").get("founding", {}).get(key, default_value)


static func player_nation() -> String:
	var n: String = GameState.player().get("nation", "")
	return n if Nations.is_player_nation(n) else ""


## 독립 선언을 할 수 없으면 사유 키
static func independence_check(id: String) -> String:
	var s: Dictionary = Officers.get_state(id)
	if Officers.track(id) == "ruler":
		return "FOUND_FAIL_ALREADY_RULER"
	if Officers.rank_order(id) < int(DataDB.get_row("ranks", "lord").get("order", 11)):
		return "FOUND_FAIL_RANK"
	var city: String = Career.governs(id)
	if city == "" or s.get("city", "") != city:
		return "GOVERN_FAIL_NOT_HERE"
	return ""


## 용병단 점령전을 할 수 없으면 사유 키
static func conquest_check(id: String, target: String) -> String:
	var officer: Dictionary = Officers.get_state(id)
	if int(officer.get("injury", 0)) > 0:
		return "ACT_FAIL_INJURED"
	if int(officer.get("troops", 0)) <= 0:
		return "ACT_FAIL_NO_TROOPS"
	if Career.is_vassal(id):
		return "FOUND_FAIL_VASSAL"
	if not Officers.rank_row(id).get("can_form_company", false) or not Career.has_company(id):
		return "CONQUEST_FAIL_COMPANY"
	var here: String = Officers.get_state(id).get("city", "")
	if not WorldMap.shared().is_adjacent(here, target) or GameState.city_owner(target) == "":
		return "CONQUEST_FAIL_TARGET"
	for p: Dictionary in WarSystem.plans():
		if p["to"] == target:
			return "LAUNCH_FAIL_BUSY"
	return ""


## 새 나라 세우기. 돌려주는 값: 새 나라 id
static func found_nation(founder: String, city: String, nation_name: String, color: String, former: String) -> String:
	var n: int = int(GameState.flags.get("founded_count", 0)) + 1
	GameState.flags["founded_count"] = n
	var id: String = "player_nation_%d" % n
	var s: Dictionary = Officers.get_state(founder)
	var start_gold: int = int(cfg("start_gold", 500)) + int(int(s.get("gold", 0)) * float(cfg("gold_transfer", 0.5)))
	s["gold"] = int(int(s.get("gold", 0)) * (1.0 - float(cfg("gold_transfer", 0.5))))
	GameState.nations[id] = {
		"alive": true, "gold": start_gold, "food": int(cfg("start_food", 3000)), "player_founded": true,
		"custom": {"name": nation_name, "color": color, "main_units": [s.get("unit_type", "infantry")],
			"races": [s.get("race", "human")], "hire_rate": 0.5, "aggression": 0.0, "sprite_id": ""},
	}
	GameState.cities[city]["nation"] = id
	GameState.cities[city]["security"] = mini(int(GameState.cities[city]["security"]), int(cfg("start_security", 50)))
	s["nation"] = id
	s["rank"] = "ruler"
	s["governs"] = city
	s["city"] = city
	s["contract"] = {}
	s["mission"] = {}
	# 동료는 새 나라의 신하가 된다 (계속 따라다님)
	for c: String in Career.companions(founder):
		var cs: Dictionary = Officers.get_state(c)
		cs["nation"] = id
		cs["rank"] = "vassal_knight"
	# 그 도시에 있던 원 소속국 무장: 주인공과 친하면 합류, 아니면 퇴각
	var join_affinity: int = int(cfg("join_affinity", 50))
	for other: String in Officers.in_city(city, founder):
		var os: Dictionary = Officers.get_state(other)
		if os.get("nation", "") != former or former == "":
			continue
		if Relationship.affinity(founder, other) >= join_affinity and os.get("rank", "") != "ruler":
			os["nation"] = id
			Career.log_line(GameAction.msg("FOUND_JOINED", [Officers.display_name(other), nation_name]))
		else:
			var retreat: String = WarResolver._retreat_city(city, former)
			if retreat != "":
				os["city"] = retreat
	# 외교: 원 소속국과는 전쟁, 나머지와는 휴전
	for other: String in Diplomacy.alive_nations():
		if other == id:
			continue
		if other == former:
			Diplomacy.set_war(id, other)
		else:
			Diplomacy.set_truce(id, other, int(cfg("start_truce", 6)))
	Career.log_line(GameAction.msg("FOUND_DONE", [nation_name, WorldMap.city_name(city)]))
	return id


## 주인공 나라가 대륙을 모두 차지했는가
static func unified() -> bool:
	var n: String = player_nation()
	return n != "" and Economy.cities_of(n).size() == GameState.cities.size()
