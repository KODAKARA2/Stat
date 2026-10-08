extends Node
## 밸런스 시험: 출신 배경 × 의뢰 단계마다 자동 전투를 여러 번 돌려 승률·턴·손실률을 출력한다.
## 실행: godot --headless --path . res://tests/battle_sim.tscn

const RUNS: int = 40


func _ready() -> void:
	RNG.reseed(777)
	for bg: Dictionary in DataDB.get_rows("backgrounds"):
		for tier: int in [1, 2, 3]:
			var wins: int = 0
			var turns: int = 0
			var loss: float = 0.0
			for i: int in RUNS:
				WorldSetup.new_game({"name": "시험", "race": "human", "origin": "merka", "background": bg["id"], "bonus": {}})
				SaveManager.game_in_progress = false
				var quest: Dictionary = Guild.make_quest("salvia")
				while int(quest["tier"]) != tier:
					quest = Guild.make_quest("salvia")
				var state: BattleState = BattleSetup.from_quest(quest, GameState.player_id)
				var leader: BattleUnit = state.leader_of("ally")
				if BattleAI.run_to_end(state) == "win":
					wins += 1
				turns += state.turn
				loss += 1.0 - float(leader.troops) / leader.start_troops
			print("%-16s %d단계: 승률 %3d%%  평균 %4.1f턴  주인공 병력 손실 %3d%%" % [bg["id"], tier, 100 * wins / RUNS, float(turns) / RUNS, int(100 * loss / RUNS)])
	get_tree().quit()
