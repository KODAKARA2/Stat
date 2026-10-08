# 용병의 대륙

삼국지 10 스타일의 세로형 판타지 전략 RPG (Godot 4.7.2).
떠돌이 용병으로 시작해 의뢰·전쟁·출세·건국을 거쳐 대륙 통일 또는 은퇴까지.

- **브라우저에서 바로 해 보기**: https://kodakara2.github.io/Stat/ (GitHub Pages, `gh-pages` 브랜치)
- 기획서: [GDD.md](GDD.md)
- 사용한 외부 에셋과 라이선스: [assets/CREDITS.md](assets/CREDITS.md)

## 실행 (개발)
1. Godot 4.7.2로 이 폴더를 연다 (`project.godot`).
2. F5로 실행. 화면은 720×1280 세로.

## 자동 점검
```
godot --headless --path . res://tests/run_tests.tscn
```
시뮬레이션: `tests/battle_sim.tscn`, `tests/war_sim.tscn`, `tests/career_sim.tscn`, `tests/duel_sim.tscn`

## 저장소에 없는 것
- `assets/sprites/portraits/` (예전 임시 초상화, 재배포 금지 에셋). 지금 게임은 쓰지 않는다.
