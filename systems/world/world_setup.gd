class_name WorldSetup
extends RefCounted
## 새 게임 시작 시 data/의 초기값을 GameState로 복사하고 주인공을 만든다.
## 데이터 파일은 그대로 두고, 판이 진행되며 바뀌는 값만 GameState에 둔다.

const CITY_STATE_KEYS: PackedStringArray = [
	"nation", "population", "troops",
	"security", "commerce", "agriculture", "defense",
]


## player: 캐릭터 생성 결과 {name, race, variant, gender, origin, background, bonus: {stat: 점수}}
static func new_game(player: Dictionary) -> void:
	GameState.reset()
	for row: Dictionary in DataDB.get_rows("cities"):
		var state: Dictionary = {}
		for key: String in CITY_STATE_KEYS:
			state[key] = row.get(key)
		GameState.cities[row["id"]] = state
	WarSystem.setup()   # 나라 금고(도시 금·식량 합계), 외교 관계
	for row: Dictionary in DataDB.get_rows("officers"):
		GameState.officers[row["id"]] = Officers.state_from_data(row)
	_create_player(player)
	TimeManager.start_new(DataDB.balance("time.start_year", 1), DataDB.balance("time.start_month", 1))
	SaveManager.game_in_progress = true


## 캐릭터 생성 화면 미리보기와 실제 생성이 같은 계산을 쓴다.
## 최종 능력 = 출신 배경 기본치 + 보너스 포인트 + 종족 보정 (1~100)
static func compute_stats(race_id: String, background_id: String, bonus: Dictionary) -> Dictionary:
	var bg: Dictionary = DataDB.get_row("backgrounds", background_id)
	var mods: Dictionary = DataDB.get_row("races", race_id).get("stat_mod", {})
	var stats: Dictionary = {}
	for key: String in Officers.stat_keys():
		var value: int = int(bg.get("stats", {}).get(key, 30)) + int(bonus.get(key, 0)) + int(mods.get(key, 0))
		stats[key] = Officers.clamp_stat(value)
	return stats


## 출신 국가의 수도에서 시작한다.
static func start_city(nation_id: String) -> String:
	for row: Dictionary in DataDB.get_rows("cities"):
		if row["nation"] == nation_id and row.get("capital", false):
			return row["id"]
	return DataDB.get_rows("cities")[0]["id"]


static func _create_player(p: Dictionary) -> void:
	var race: Dictionary = DataDB.get_row("races", p.get("race", "human"))
	var bg: Dictionary = DataDB.get_row("backgrounds", p.get("background", ""))
	var stats: Dictionary = compute_stats(race.get("id", "human"), bg.get("id", ""), p.get("bonus", {}))
	var headroom: int = DataDB.balance("create.potential_headroom", 25)
	var pot: Dictionary = {}
	for key: String in stats:
		pot[key] = Officers.clamp_stat(stats[key] + headroom)
	var id: String = GameState.PLAYER_ID
	GameState.officers[id] = {
		"name": p.get("name", "?"),
		"race": race.get("id", "human"),
		"variant": p.get("variant", ""),
		"gender": p.get("gender", ""),
		"age": int(race.get("start_age", 18)),
		"nation": "",                       # 떠돌이 용병은 소속 국가 없음
		"origin": p.get("origin", "leonhart"),
		"city": start_city(p.get("origin", "leonhart")),
		"rank": DataDB.balance("create.start_rank", "merc_rookie"),
		"background": bg.get("id", ""),
		"stats": stats,
		"potential": pot,
		"exp": {},
		"skills": bg.get("skills", []).duplicate(),
		"skill_levels": SkillLevels.starting_levels(bg.get("skills", [])),   # 주인공 전법은 1레벨에서 시작
		"personality": {},
		"ap": 0,
		"energy": int(DataDB.balance("energy.start", 100)),
		"injury": 0,
		"gold": int(bg.get("gold", 0)),
		"fame": 0,
		"alive": true,
		"sprite_id": p.get("portrait", ""),
		"unit_type": bg.get("unit_type", "infantry"),
		"troops": Officers.troops_for_lead(int(stats["lead"])),
		"quests": [],
		"hired": [],
		"perks": bg.get("perks", []).duplicate(),
		"reputation": {},
	}
	GameState.player_id = id
	if String(GameState.officers[id]["sprite_id"]) == "":
		GameState.officers[id]["sprite_id"] = Portraits.pick(race.get("id", "human"), p.get("variant", ""), p.get("gender", "m"))
	if bg.get("perks", []).has("start_hired"):
		Guild.add_hired(id, "helper_spear")
	for link: Dictionary in bg.get("connections", []):
		if GameState.officers.has(link["officer"]):
			Relationship.mark_met(id, link["officer"])
			Relationship.add(id, link["officer"], int(link["affinity"]))
