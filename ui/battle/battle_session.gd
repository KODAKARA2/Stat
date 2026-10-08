class_name BattleSession
extends RefCounted
## 지도 화면 → 전투 화면으로 넘길 전투 한 판. 장면이 바뀌어도 남도록 static에 둔다.

static var state: BattleState


static func start(quest: Dictionary, tree: SceneTree) -> void:
	if quest.get("type", "monster") in ["war", "conquest"]:
		state = BattleSetup.from_war_quest(quest, GameState.player_id)
	else:
		state = BattleSetup.from_quest(quest, GameState.player_id)
	tree.change_scene_to_file("res://ui/battle/battle_screen.tscn")
