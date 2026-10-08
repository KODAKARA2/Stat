# Gameplay audit — 2026-10-08

Source baseline: `c0aae42c9fe01438567a7fcd2c878f8a3669ea1c`; existing world, officers and art preserved. Reviewed GDD, time/month updates, career, family, events, growth, economics, nation AI, tactical AI and battle outcome. No AGENTS.md found in repository/workspace search. No balance constants changed.

## Implemented, with failing baseline evidence

1. **P1 — AI recruits the player's companions without release.** `systems/war/personnel.gd` considered every nationless active officer eligible. A companion could simultaneously retain their leader, follow the player, draw companion wages and become an AI country's knight/commander. Use the existing `Career.is_free_agent()` predicate. Regression isolates a companion and a free agent and forces a hire; companion stays, free agent is hired.
2. **P1 — injured or troopless character can launch a battle through alternate paths.** `systems/actions/launch_war_action.gd` and `systems/founding.gd` checked city/rank/company requirements without the fitness checks used by `SubjugateAction`. Both now reject injury or zero personal troops before AP is spent. Healthy launch remains available and costs two AP.

`tests/gameplay_regression.tscn`: final identical 11-check suite on original source with Godot 4.7.2 produced **4 passed / 7 failed**, versus **11 passed / 0 failed** after fixes. Earlier staged evidence: initial two-fix baseline 3 passed / 5 failed (Godot 4.6.3); conquest extension before its fix 9 passed / 2 failed (4.7.2); all implemented fixes 11 passed / 0 failed (4.7.2). The original full suite after first two fixes passed 986 / 0 on 4.6.3. These results are separate from parent integration validation.

## Remaining priorities, not silently changed

- **P1 — succession consistency and kingdom control.** `Family.succeed()` only copies hired/company/contract/reputation/quests when the heir lacks each key entirely. Existing empty arrays/dictionaries suppress inheritance; companion lists are replaced instead of merged. Ruler rank/nation/governs are not transferred, while `player_founded` survives and affects diplomatic autonomy. GDD appendix G explicitly lists assets but not office inheritance, so kingdom policy needs an explicit design decision before modifying it. Add empty/preexisting heir inventory and ruler-heir tests. Also snapshot existing NPC effective skill levels before switching `player_id`: `SkillLevels.level()` otherwise changes missing-level fallback from NPC stat-derived level to player level 1.
- **P2 — unreachable monthly war orders.** `Career.assign_mission()` chooses the first national war regardless of player distance and `_give_war_order()` requires reaching its source city, while `SubjugateAction.check()` requires being there. With limited AP, distant commands may be impossible; failed missions deduct merit. Measure shortest-path move cost plus battle AP before assigning and provide a local alternative when impossible. No current test covers a distant lord ordered into an unreachable battle.
- **P2 — strategic attack evaluation differs from resolution.** `NationAI.plan_attacks()` scores local garrison/defense while `WarResolver.resolve()` also accounts for adjacent reserves, commander power, winter strength and last-city resistance. Therefore optimistic attacks can be predictably poor. Share a deterministic power estimate only after comparing seeded outcomes; do not merely raise aggression/min_ratio.
- **P2 — economy observability.** `Career.tick_contract()` creates player pay independently of employer treasury and mission participation. This may be intended abstraction, but should be explicit before claiming a closed national economy. `Economy.conscript()` reserves gold but does not consider food runway, so food shortages can coexist with new hiring. Existing war simulation gathers gold without printing it, never reports food, and uses localized report substrings to count captures. Add numeric economy telemetry and state-invariant assertions before changing costs or income.
- **P2 — retirement/event/long-run tests.** Battle, career and war simulations print results but do not enforce outcome thresholds. Event choices have guards and effects, but no exhaustive availability/one-time-resume tests. Family tests cover basic heir/gold/notification, not repeated successions or effective skill preservation.
- **P3 — configurable January start.** `MonthlyUpdate.start_month()` increments age during the first January before the `months_played` new-year guard. Current configuration starts in March, so this is not an existing new-game bug. Leave current time behavior unchanged; cover it if January starts become supported.

The economy, growth and battle code already clamps key stats, development, energy and troops in their intended scopes. Five seeded 240-month economy probes produced identical before/after metrics: peak nation gold 5,674, food 131,576, city troops 12,607, and zero negative gold/food/troop states. Food stockpiles accumulate significantly; this is an observed balancing question, not proof of overflow. These finite runs do not establish a bound for arbitrary campaigns.

## Re-run

Use the project version, Godot 4.7.2:

```sh
godot --headless --path . res://tests/gameplay_regression.tscn
godot --headless --path . res://tests/run_tests.tscn
godot --headless --path . res://tests/battle_sim.tscn
godot --headless --path . res://tests/war_sim.tscn
godot --headless --path . res://tests/career_sim.tscn
godot --headless --path . res://tests/duel_sim.tscn
```

Parent owns the final integrated report/build and final exact-version checks. No remote push, merge or deployment performed.


## Seeded simulation evidence

Matching Godot 4.7.2, original detached checkout and working tree, isolated HOME per process:

- Battle: 4 backgrounds × 3 tiers × 40 battles = 480 encounters per revision; before/after output identical.
- War: 5 seeds × 240 months per revision; all five nations survive every run, with 26–45 captures depending on seed; before/after output identical.
- Duel: before/after win/draw/turn metrics identical (wall-clock timings intentionally differ).
- Economy: 5 seeds × 240 months per revision, identical numeric metrics and no negative gold/food/troop states. Re-run `godot --headless --path . res://verification/gameplay/stat-economy-probe.tscn`.
- Raw logs and economy probe are in `verification/gameplay/`.

Implementation checkpoint: `d6b2473`. Original automatic tests remain the integration owner's responsibility after all concurrent edits.


## Career simulation completed

All eight seeded 240-month campaigns completed before and after with exit code 0: six vassal-route runs and two mercenary-only runs. All vassal runs reached chancellor and both mercenary runs reached captain; no game-over output appeared. Before: lord year 3 month 3–year 4 month 9; chancellor year 12 month 3–year 14 month 12; mercenary captain year 5 month 9/year 6 month 3. After: lord year 3 month 2–year 4 month 9; chancellor year 11 month 3–year 14 month 11; mercenary captain year 6 month 5/year 7 month 2. Outcomes diverge because companion recruitment eligibility and RNG consumption changed; this is not evidence that all progression became faster. No balance values were retuned.

The first concurrent harness used a 180-second subprocess timeout and interrupted career near completion. That infrastructure limit was resolved by rerunning the two full career simulations with a 600-second allowance; both completed normally. Only complete career logs are retained here.

## Integration save review (read-only)

The new core-shape validator accepted all five 20-year simulation end states, including dead and generated officers, on Godot 4.7.2 (`stat-save-compat.log`). Current gameplay sources retain an officer's valid city after death and always keep city ownership assigned to an existing nation; custom kingdoms are in the nation table. No valid late-game rejection was observed. New string RNG state preserves int64 precision; older numeric saves are readable but lost JSON precision cannot be retroactively restored.

Review findings communicated to the integration owner: nation entries also need required `gold`/`food`/`alive` checks; optional gameplay containers need further validation if comprehensive corruption hardening is claimed; the year should be integral like the month. Moving autosave after all `month_started` subscribers includes the UI's report erasure, so reloading while the report is displayed may no longer restore that report. These are separate from the three gameplay fixes above and are owned by the integration work.
