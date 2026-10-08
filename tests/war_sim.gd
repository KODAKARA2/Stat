extends Node
## 전쟁 시험: 주인공은 가만히 있고 20년(240개월)을 돌려 5개국 도시 수 변화를 본다.
## 실행: godot --headless --path . res://tests/war_sim.tscn
## M4 완료 기준: "방치해도 5개국이 싸우고 균형이 유지되는가"

const SEEDS: Array = [11, 22, 33, 44, 55]
const MONTHS: int = 240


func _ready() -> void:
	var nations: Array = []
	for row: Dictionary in DataDB.get_rows("nations"):
		nations.append(row["id"])
	for seed: int in SEEDS:
		RNG.reseed(seed)
		WorldSetup.new_game({"name": "시험", "race": "human", "origin": "merka", "background": "knight_bastard", "bonus": {}})
		SaveManager.game_in_progress = false
		var captures: int = 0
		var fallen: Array = []
		var line: String = "seed %d |" % seed
		for m: int in MONTHS:
			TimeManager.advance_month()
			var report: Dictionary = GameState.flags.get("report", {})
			for b: String in report.get("battles", []):
				if b.contains("점령"):
					captures += 1
			for d: String in report.get("diplomacy", []):
				if d.contains("멸망"):
					fallen.append("%s(%d년)" % [d.split(" ")[0], TimeManager.year])
			if (m + 1) % 48 == 0:
				var counts: PackedStringArray = []
				for n: String in nations:
					counts.append(str(Economy.cities_of(n).size()))
				line += " %d년:%s" % [TimeManager.year, "/".join(counts)]
		var deaths: int = 0
		for id: String in GameState.officers:
			if not GameState.officers[id]["alive"]:
				deaths += 1
		var staff: PackedStringArray = []
		for n: String in nations:
			staff.append(str(Personnel.officers_of(n).size()))
		var gold: PackedStringArray = []
		for n: String in nations:
			gold.append(Fmt.num(int(GameState.nations[n].get("gold", 0))))
		print(line, " | 점령 %d회 · 전사 %d명 · 멸망 %s · 무장 수 %s" % [captures, deaths, ", ".join(fallen) if not fallen.is_empty() else "없음", "/".join(staff)])
	print("(도시 수 순서: ", "/".join(nations), ")")
	get_tree().quit()
