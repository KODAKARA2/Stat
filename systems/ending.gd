class_name Ending
extends RefCounted
## 엔딩 (기획 확정 2026-10-08): 대륙 통일, 은퇴 두 가지.
## GameState.flags["ending"]에 요약을 남기면 지도 화면이 엔딩 화면으로 넘어간다.


## 월말: 주인공의 나라가 모든 도시를 가졌으면 통일 엔딩
static func check_unification() -> void:
	if GameState.flags.has("ending") or GameState.player_id == "":
		return
	if Founding.unified():
		finish("unify")


## 은퇴: 언제든 스스로 칼을 내려놓는다
static func retire() -> void:
	finish("retire")


static func finish(kind: String) -> void:
	GameState.flags["ending"] = summary(kind)
	SaveManager.game_in_progress = false


static func summary(kind: String) -> Dictionary:
	var id: String = GameState.player_id
	var s: Dictionary = Officers.get_state(id)
	var n: String = s.get("nation", "")
	return {
		"kind": kind, "name": Officers.display_name(id), "rank_key": Officers.rank_row(id).get("name_key", ""),
		"track": Officers.track(id), "year": TimeManager.year, "month": TimeManager.month,
		"months": int(GameState.flags.get("months_played", 0)), "fame": int(s.get("fame", 0)), "gold": int(s.get("gold", 0)),
		"age": int(s.get("age", 0)), "nation": Diplomacy.nation_name(n) if n != "" else "",
		"cities": Economy.cities_of(n).size() if n != "" else 0, "companions": Career.companions(id).size(),
		"children": Family.children(id).size(), "married": Family.spouse(id) != "",
		"epilogue": epilogue(kind, id),
	}


## 맺음말 몇 줄. 신분과 처지에 따라 고른다. 담담하고 조금 비뚤게.
static func epilogue(kind: String, id: String) -> Array:
	var lines: Array = []
	var s: Dictionary = Officers.get_state(id)
	if kind == "unify":
		lines.append("ENDING_UNIFY_1")
		lines.append("ENDING_UNIFY_2")
		lines.append("ENDING_UNIFY_3" if Career.companions(id).size() > 0 else "ENDING_UNIFY_ALONE")
		return lines
	match Officers.track(id):
		"ruler":
			lines.append("ENDING_RETIRE_RULER")
		"vassal":
			lines.append("ENDING_RETIRE_VASSAL")
		"merc":
			lines.append("ENDING_RETIRE_MERC")
		_:
			lines.append("ENDING_RETIRE_FREE")
	if int(s.get("gold", 0)) >= 5000:
		lines.append("ENDING_RICH")
	elif int(s.get("gold", 0)) < 100:
		lines.append("ENDING_POOR")
	if Family.spouse(id) != "":
		lines.append("ENDING_MARRIED" if Family.children(id).is_empty() else "ENDING_FAMILY")
	else:
		lines.append("ENDING_SINGLE")
	if int(s.get("fame", 0)) >= 200:
		lines.append("ENDING_FAMOUS")
	else:
		lines.append("ENDING_FORGOTTEN")
	return lines
