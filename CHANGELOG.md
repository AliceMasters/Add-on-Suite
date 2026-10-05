# 📜 Patch Notes: Add-on Suite

Each patch below covers one release day. Hashes link to the commits.

---

## Patch 4.2: *"Show Your Work"*
**October 5, 2026**

**📖 Docs**
- **Fixed:** the CI badge pointed at the old `CallMeAlicex` username. ([`6bb97c6`](https://github.com/AliceMasters/Add-on-Suite/commit/6bb97c6))
- **New:** a QA-at-a-glance summary at the top of the README: 4 CI gates, 60,000 fuzzed moves, 18,000 moves through the real addon code, 439 arcade checks, and game-tree proofs that the AIs play perfectly.
- **New:** *"The bug the fuzzer missed"* is now told up front. 60,000 simulated moves passed while the real addon was broken, and the tests that load the real code caught it on move 0.
- **Fixed:** the test docs said there were three CI gates (there are four) and described only 4 of the 17 games.

---

## Patch 4.1.1: *"Housekeeping"*
**October 3, 2026**
- Added `.editorconfig` so formatting stays consistent. ([`778b360`](https://github.com/AliceMasters/Add-on-Suite/commit/778b360))

---

## Patch 4.1: *"The Full Cabinet"*
**September 22, 2026**

**✨ New games: 17 in the cabinet**
- **Arcade v3:** 5 new games, including 2 with AI opponents, **100 nonogram puzzles**, and category tabs. ([`8291b66`](https://github.com/AliceMasters/Add-on-Suite/commit/8291b66))
- **Arcade v4:** 5 more games, bringing the cabinet to 17: Nim, Hangman, Reversi, Peg Solitaire and Sudoku. ([`beeb6c4`](https://github.com/AliceMasters/Add-on-Suite/commit/beeb6c4))

**✨ New features**
- **Share Score** to chat: Say, Party, Guild, Raid, Instance, or a whisper to your target. ([`dc63fd5`](https://github.com/AliceMasters/Add-on-Suite/commit/dc63fd5))
- **Sudoku save and resume:** your puzzle survives logging out. ([`1c6a1a3`](https://github.com/AliceMasters/Add-on-Suite/commit/1c6a1a3))
- **Classic Era support** (1.60.1, Forever) alongside Retail. ([`d533504`](https://github.com/AliceMasters/Add-on-Suite/commit/d533504))

**🎨 UI**
- Overhaul: rounded 9-slice panels, metallic themed borders, and a soft pop effect. ([`1792d69`](https://github.com/AliceMasters/Add-on-Suite/commit/1792d69))
- A contrast overhaul and a richer velvet palette. ([`e494823`](https://github.com/AliceMasters/Add-on-Suite/commit/e494823), [`9bd8212`](https://github.com/AliceMasters/Add-on-Suite/commit/9bd8212))

**🐛 Fixes**
- The UI was transparent and the top-bar buttons couldn't be clicked. ([`b4fd8c3`](https://github.com/AliceMasters/Add-on-Suite/commit/b4fd8c3))
- The window didn't open at all: bad `SetVertexColor` arguments in the rounded panels. ([`9b17a07`](https://github.com/AliceMasters/Add-on-Suite/commit/9b17a07))
- Title clipping and a missing Snake icon. ([`9bd8212`](https://github.com/AliceMasters/Add-on-Suite/commit/9bd8212))

**🛡️ Quality**
- **Full coverage:** every feature now has a test that runs in CI, mapped feature by feature in `tests/COVERAGE.md`. ([`d584f6e`](https://github.com/AliceMasters/Add-on-Suite/commit/d584f6e))

---

## Patch 3.0: *"Velvet"*
**September 21, 2026**
- **Azeroth Arcade v2:** the velvet/amethyst redesign, 3 new games, daily streaks, trophies, best scores and themes. ([`7aab0b2`](https://github.com/AliceMasters/Add-on-Suite/commit/7aab0b2))

---

## Patch 2.0: *"Insert Coin"*
**September 19, 2026**

**✨ New**
- **Bejeweled**, a single-player match-3 addon: swaps, cascades, Flame gems (match-4) and Hypercubes (match-5). ([`deea412`](https://github.com/AliceMasters/Add-on-Suite/commit/deea412))
- **Azeroth Arcade:** one addon, four games: Nonogram, 2048, Minesweeper and Snake. ([`c69e5dd`](https://github.com/AliceMasters/Add-on-Suite/commit/c69e5dd))
- Nonogram: 27 colour puzzles and a scrollable picker. ([`500319e`](https://github.com/AliceMasters/Add-on-Suite/commit/500319e))

**🐛 Fixes and 🛡️ Quality**
- **Cascade refill bug:** new gems were created but never written back into the board. The 60,000-move model fuzz missed it, and the new test that loads the real Lua code caught it on move 0. Gem colours were also fixed: every icon had been tinted white. The two-layer automated QA was introduced in the same commit. ([`0718e40`](https://github.com/AliceMasters/Add-on-Suite/commit/0718e40))
