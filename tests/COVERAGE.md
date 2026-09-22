# Test coverage

Every feature is exercised in CI (`.github/workflows/tests.yml`, four gates).
The rule: **if it's a feature, it has a test here.** All tests drive the *real
shipped Lua* via an embedded runtime + a mock WoW API — never a re-description.

## Gates

| Script | What it proves |
|---|---|
| `syntax_check.py` | every `.lua` in `Bejeweled/` and `Arcade/` parses |
| `model_sim.py` | Bejeweled reference-model fuzz: 60k moves, invariants each move |
| `run_lua_tests.py` | the real `Bejeweled.lua`: 18k moves + builds the real UI |
| `run_arcade_tests.py` | the real Arcade addon: **439 checks** (below) |

## Arcade feature → test map (`run_arcade_tests.py`)

| Feature | Test |
|---|---|
| 2048 merge rules + fuzz | `test_2048` |
| Minesweeper adjacency / flood / first-click safety | `test_minesweeper` |
| Snake collision / growth / food / no-reverse | `test_snake` |
| Nonogram solve/lives/hint across **all 100 puzzles** | `test_nonogram` |
| Lights Out flip-involution / solve | `test_lightsout` |
| Memory match/mismatch/win | `test_memory` |
| Simon sequence / fail | `test_simon` |
| Tic-Tac-Toe AI **never loses** (full game-tree) | `test_tictactoe` |
| Connect Four AI takes wins / blocks | `test_connect4` |
| Flood It region / pick / win | `test_floodit` |
| Sliding Puzzle move / solve | `test_slide` |
| Mastermind scoring / win / lose | `test_mastermind` |
| Nim optimal AI (full search) | `test_nim` |
| Hangman hit/miss/win/lose | `test_hangman` |
| Reversi legal moves / flips / AI | `test_reversi` |
| Peg Solitaire jump rules | `test_pegs` |
| Sudoku validity + **save/resume round-trip** | `test_sudoku` |
| Daily streak (day rollover / gap reset) | `test_core` |
| Achievements (unlock idempotency, streak-3) | `test_core` |
| Best scores (max kept, per-id) | `test_submitbest` |
| **Share to chat** (channel, message, whisper target) | `test_share` |
| **Theme accents** (all four apply + persist) | `test_theme` |
| Minimap button created | `test_minimap` |
| Registry integrity (category/icon/start/stop/logic) | `test_registry` |
| **UI build**: window + open all 17 games without error | `test_ui_smoke` |

## How new features must be added

1. Put game/feature *logic* in a pure table (`ns.logic[id]` or a Core function) —
   no frame calls — so it's callable headlessly.
2. Add a test in `run_arcade_tests.py` and list it above.
3. `test_ui_smoke` auto-covers any new game's view (it opens every registered game).
4. The mock rejects nil/bad colour args, so view-layer arg bugs fail CI too.
