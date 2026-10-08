extends Node
## 결투 정책 비교: 같은 상대에게 '생각하는 수(AI 계획) / 무작위 / 같은 버튼만' 각각 N판.
## 실행: godot --headless --path . res://tests/duel_sim.tscn

const N: int = 40


func _ready() -> void:
	RNG.reseed(777)
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	var me: String = GameState.player_id
	var p: Dictionary = GameState.player()
	for foe: String in ["gabriel", "isabelle"]:
		for policy: String in ["think", "random", "same"]:
			var wins: int = 0
			var draws: int = 0
			var turns: int = 0
			var t0: int = Time.get_ticks_msec()
			for i: int in N:
				var d: DuelState = Duel.start(me, foe)
				while not d.finished():
					match policy:
						"think":
							d.plan[me] = Duel.ai_plan(d, me)
						"random":
							d.plan[me] = RNG.pick(Duel._sequences(d, me))
						"same":
							d.plan[me] = ["guard", "guard", "guard"] if Duel.remaining(d, me, "slash") <= 0 else ["slash"] + (["slash"] if Duel.remaining(d, me, "slash") > 1 else ["guard"]) + ["guard"]
					Duel.resolve_turn(d)
				turns += d.turn
				if d.result == "a":
					wins += 1
				elif d.result == "draw":
					draws += 1
			var ms: float = float(Time.get_ticks_msec() - t0) / N
			print("주인공(무력 %d) vs %s(무력 %d) · %-6s: 승 %3d%%  무 %2d%%  평균 %.1f턴  (한 판 계산 %.0fms)" % [Officers.stat(me, "str"), foe,
				Officers.stat(foe, "str"), policy, wins * 100 / N, draws * 100 / N, float(turns) / N, ms])
	get_tree().quit()
