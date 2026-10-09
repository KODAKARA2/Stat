# Succession preservation — 2026-10-09

Base: `946be59306f0d8803930ca4376760e480f1fbe2e` (merged PR #1).
Engine: **4.7.2.stable.official.ed1daf0bf**.

## Reproduction and changes

Identical 46-check succession suite: original **32 passed / 14 failed**, fixed **46 passed / 0 failed**. Neither run has script errors. Raw evidence: `succession-baseline.log`, `succession-final.log`.

- Merge heir and deceased hired-unit/quest arrays using deep copies. Identical hired units are separate units and must not be deduplicated.
- Empty or missing company/contract inherits a deep copy. Preserve a nonempty heir company/contract as before; do not combine incompatible single-record contracts or company identities.
- Reputation retains existing heir entries and fills missing nation entries from the deceased, without summing or overwriting conflicting values.
- Merge active companion lists, remove duplicate IDs/self/deceased leader, and update leader references. Succession does not dismiss inherited companions to enforce recruitment slot limits (same behavior as prior inheritance).
- Before switching player ID, materialize the heir's effective battle skill levels using the existing SkillLevels API. Explicit levels and use counts survive; legacy missing levels retain NPC stat-derived proficiency. Do not inherit the deceased's personal skills.

Tests cover missing/empty/preexisting asset containers, independent nested values, existing and inherited companions, self/dead exclusion, duplicate companion ID, identical hired units, legacy version-1 save load, complete state round trips, partial explicit skill maps, repeated succession and monthly contract continuation.

## Regression validation

`GODOT=/tmp/godot-runtime/Godot_v4.7.2-stable_linux.x86_64 bash tools/verify.sh`

Runs in a temporary HOME/cache, with import and error-log checks:

| Suite | Passed | Failed |
| --- | ---: | ---: |
| Existing automatic tests | 986 | 0 |
| Save regression | 19 | 0 |
| Gameplay regression | 11 | 0 |
| Succession regression | 46 | 0 |
| Total | **1,062** | **0** |

`git diff --check` passed. No save schema/version, data tables, balance constants or global skill fallback changed. Existing optional containers remain supported. New focused suite is included in `tools/verify.sh`. Long seeded battle/war/career simulations and export builds were not rerun for this scoped change; prior PR evidence is not counted as new validation.

## Design decisions intentionally deferred

Ruler rank, nation affiliation, governed city, nation records and `player_founded` behavior are untouched. Characterization tests lock the existing behavior, **not an endorsement of its correctness**. GDD appendix G lists inherited assets but does not specify office or kingdom sovereignty inheritance. Decide separately whether the heir inherits office/control, how existing affiliations interact, and whether `player_founded` remains applicable after succession.

Two nonempty companies/contracts cannot both be represented by the current single-record schema. This change keeps the existing heir-wins behavior; deciding cancellation, penalty, transfer or multi-contract support requires separate game-rule design. Conflicting reputation entries likewise keep heir values rather than inventing a new arithmetic rule.
