class_name Nations
extends RefCounted
## 나라 정보 조회: 처음부터 있는 5개국은 data/nations.json, 주인공이 세운 나라는 GameState.nations[n]["custom"].
## 나라 정보는 반드시 여기를 거쳐 읽는다 (DataDB를 직접 읽으면 새로 생긴 나라를 모른다).


static func row(n: String) -> Dictionary:
	var data: Dictionary = DataDB.get_row("nations", n)
	if not data.is_empty():
		return data
	return GameState.nations.get(n, {}).get("custom", {})


static func display_name(n: String) -> String:
	var r: Dictionary = row(n)
	if r.has("name"):
		return r["name"]
	return TranslationServer.translate(r.get("name_key", n))


static func color(n: String) -> Color:
	return Color.html(row(n).get("color", "#888888"))


static func is_player_nation(n: String) -> bool:
	return n != "" and GameState.nations.get(n, {}).get("player_founded", false)
