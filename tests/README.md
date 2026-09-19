# Bejeweled — automated QA

A WoW addon can't be unit-tested in the game client, so this suite verifies the
match-3 engine headlessly, in two complementary layers.

```
pip install -r tests/requirements.txt
python tests/syntax_check.py          # 1. does the Lua parse?
python tests/model_sim.py 300 200     # 2. reference-model fuzz (60k moves)
python tests/run_lua_tests.py 120 150 # 3. the REAL Bejeweled.lua (18k moves)
python tests/run_arcade_tests.py      # 4. the REAL Arcade addon (2048/Mines/Snake/Nonogram)
```

`run_arcade_tests.py` loads every Arcade Lua file into one shared namespace
(exactly as WoW does) and exercises each game's logic through its real functions
— 2048 merge scenarios + fuzz, Minesweeper adjacency/flood/first-click-safety
fuzz, Snake collision/growth fuzz, and Nonogram solve/lives/hint mechanics
across every built-in puzzle.

CI runs all three on every push (`.github/workflows/tests.yml`).

## Layer 1 — reference-model fuzz (`model_sim.py`)

An independent Python reimplementation of the rules acts as an oracle. A bot plays
hundreds of full games, choosing a legal move each turn, and after **every move**
asserts a set of invariants:

- no holes; no gem left flagged `removed`; every gem's stored `(r,c)` matches its
  cell; no gem object occupies two cells;
- the board always settles (no leftover match) and a legal move always exists;
- crafted boards confirm special-gem semantics (match-4 → Flame, match-5 → Hyper).

Fast, deterministic (seeded), good for exercising the algorithm design.

## Layer 2 — real-Lua integration (`run_lua_tests.py`)

Loads a mock WoW API (`wow_mock.lua`) and then **the actual shipped
`Bejeweled/Bejeweled.lua`** into an embedded Lua runtime (lupa). It drives real
swaps through the real `TrySwap` / `ResolveStep` / `Collapse`, pumps the real
`C_Timer`-driven cascade to completion, and asserts on the real board after every
move — including:

- all Layer-1 invariants, on the real data structures;
- **input never stays locked** after a cascade settles;
- **no runtime Lua error** reached the `Safe()` wrapper (captured via a mock chat frame);
- **icon regression guard** — every gem's icon vertex-tint matches its true colour.
  This is the check that fails on the pre-fix code (which tinted every icon white)
  and passes on the fix.

### Why both layers exist (a real lesson from this project)

The model fuzz passed **60,000 moves** while the shipped addon still had a refill
bug: `Collapse()` spawned new gems but never wrote them back into the `board`
grid. The model didn't catch it because the model contained the line the Lua was
missing — **it tested intent, not the artifact.** The Layer-2 integration test,
running the real `.lua`, caught it on move 0 (a hole in the top row).

Takeaway: keep the model as a fast design oracle, but trust the integration layer
for the shipped code.

## Files

| File | Role |
|---|---|
| `syntax_check.py` | parses `Bejeweled.lua` with luaparser |
| `model_sim.py` | Layer 1 — reference-model fuzzer + scenarios |
| `wow_mock.lua` | headless WoW API (frames, textures, C_Timer, clock) |
| `run_lua_tests.py` | Layer 2 — drives the real addon via lupa |
| `requirements.txt` | `lupa`, `luaparser` |
