<div align="center">

# ✦ Add-on Suite ✦

### Arcade games that live *inside* your World of Warcraft window — no alt-tabbing.

[![tests](https://github.com/CallMeAlicex/Add-on-Suite/actions/workflows/tests.yml/badge.svg)](https://github.com/CallMeAlicex/Add-on-Suite/actions/workflows/tests.yml)
![WoW](https://img.shields.io/badge/WoW-Retail%20120100-6a3fb5)
![Lua](https://img.shields.io/badge/Lua-5.1-24136b)
![License](https://img.shields.io/badge/license-MIT-e9d5a0)

*Every game's logic is proven headlessly — the real shipped `.lua` is loaded into an*
*embedded Lua runtime and fuzzed on every push. Green badge = the cabinet still works.*

</div>

---

## 🎰 Azeroth Arcade

One addon, a whole cabinet — **12 games** and **100 nonogram puzzles**. A velvet
**amethyst** home screen with game cards, category tabs (Puzzle / Arcade / Vs AI),
a **daily streak**, **trophies/achievements**, per-game **best scores**, and a
**settings** panel with four theme accents. Open with `/arcade` (or the dice on
your minimap).

| Game | | What it is |
|---|---|---|
| 🖼️ **Nonogram** | *the star* | Solve row/column clues to reveal a hidden picture. Lives (a wrong fill costs a heart), bold 5×5 gridlines, hint stars, drag-to-mark, and **100 colour puzzles** (hand-drawn pictures, A–Z & 0–9, geometric patterns) across Easy → Hard. |
| 🎲 **2048** | | Slide with arrow keys / WASD; merge tiles up to 2048. |
| 💣 **Minesweeper** | | Left-click reveals, right-click flags. First-click safety + flood-fill. |
| 🐍 **Snake** | | Arrow keys / WASD; eat, grow, don't crash. |
| 💡 **Lights Out** | | Flip a tile and its neighbours; turn the whole board off. |
| 🃏 **Memory** | | Flip cards two at a time; find every matching pair. |
| 🔮 **Simon** | | Watch the sequence, then repeat it as it grows. |
| ⭕ **Tic-Tac-Toe** | *vs AI* | Try to beat a **minimax AI that never loses** (proven in tests). |
| 🔴 **Connect Four** | *vs AI* | Line up four; the AI takes wins and blocks your threats. |
| ❄️ **Flood It** | | Flood the board to one colour before your moves run out. |
| 🔢 **Sliding Puzzle** | | Slide the 15 tiles back into order. |
| 🎯 **Mastermind** | | Deduce the hidden four-colour code in ten guesses. |

### ✨ Arcade features

- **Daily streak** — comes back day after day, counts your run.
- **Trophies** — nine achievements to unlock, with a slide-in toast.
- **Best scores** kept per game, shown right on each card.
- **Themes** — Amethyst, Rose, Emerald, Sapphire, switchable live.
- Custom velvet UI, custom fonts, a movable window, and a minimap button.

## 💎 Bejeweled

The original match-3, in its own addon. Swap gems, trigger cascades, build a
**Flame** (match-4) or a **Hypercube** (match-5). `/bej` to play.

---

## 🧪 How it's tested

A WoW addon can't run in CI, so the suite is verified in two layers (see `tests/`,
run on every push):

1. **Reference-model fuzz** — an independent reimplementation plays 60,000 moves,
   asserting invariants after every one.
2. **Real-Lua integration** — the *actual* shipped `.lua` is loaded into an embedded
   Lua runtime behind a mock WoW API and driven for real: Bejeweled cascades, and
   every Arcade game's logic (merge rules, flood-fill, collisions, nonogram
   solve/lives/hint across all 100 puzzles, streaks, achievements, and a full
   game-tree proof that the Tic-Tac-Toe AI never loses). **365+ checks, all green.**

```bash
pip install -r tests/requirements.txt
python tests/run_arcade_tests.py     # the whole cabinet
```

## 🎮 Install

Copy the `Arcade` (and/or `Bejeweled`) folder into:

```
World of Warcraft\_retail_\Interface\AddOns\
```

Enable it on the character screen, then type `/arcade`.

## License

MIT — do whatever you like with it.
