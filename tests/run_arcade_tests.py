#!/usr/bin/env python3
"""
Integration tests for the Azeroth Arcade addon — runs the ACTUAL shipped Lua.

Loads a mock WoW API (wow_mock.lua) then every real Arcade Lua file into one
embedded Lua runtime (lupa), sharing a single addon namespace exactly as WoW
does. Each game's logic is exercised through its real functions with invariant
checks, crafted scenarios, and fuzzing.

Run:  python tests/run_arcade_tests.py
Requires: pip install lupa
"""
import os, sys, glob

try:
    from lupa import LuaRuntime
except ImportError:
    sys.exit("pip install lupa")

HERE = os.path.dirname(os.path.abspath(__file__))
ARCADE = os.path.join(HERE, "..", "Arcade")
MOCK = os.path.join(HERE, "wow_mock.lua")

FILES = ["Core.lua", "Games/Nonogram.lua", "Games/Twenty48.lua",
         "Games/Minesweeper.lua", "Games/Snake.lua",
         "Games/LightsOut.lua", "Games/Memory.lua", "Games/Simon.lua"]

_passed = 0
_failed = 0


def check(name, cond, detail=""):
    global _passed, _failed
    if cond:
        _passed += 1
    else:
        _failed += 1
        print(f"  FAIL {name}" + (f"\n        {detail}" if detail else ""))


def boot():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(MOCK, encoding="utf-8").read())
    ns = lua.eval("{}")
    loadf = lua.eval('function(src, ns) local f = assert(load(src, "Arcade")); f("Arcade", ns) end')
    for rel in FILES:
        path = os.path.join(ARCADE, rel.replace("/", os.sep))
        loadf(open(path, encoding="utf-8").read(), ns)
    # fire ADDON_LOADED (Core's boot handler)
    boot_frame = ns.boot
    boot_frame._scripts["OnEvent"](boot_frame, "ADDON_LOADED", "Arcade")
    return lua, ns


def L(lua, *vals):
    """build a 1-indexed Lua array table from python values"""
    return lua.eval("function(...) return {...} end")(*vals)


# ---------------------------------------------------------------- 2048
def test_2048(lua, ns):
    G = ns.logic["2048"]

    def slide(vals):
        out, gained, moved = G.slideLine(L(lua, *vals), len(vals))
        return [int(out[i]) for i in range(1, len(vals) + 1)], int(gained), bool(moved)

    check("2048 [2,2,2,2]->[4,4]", slide([2, 2, 2, 2]) == ([4, 4, 0, 0], 8, True))
    check("2048 [2,2,4,0]->[4,4]", slide([2, 2, 4, 0]) == ([4, 4, 0, 0], 4, True))
    check("2048 [4,4,4,4]->[8,8]", slide([4, 4, 4, 4]) == ([8, 8, 0, 0], 16, True))
    check("2048 [2,0,2,0]->[4]", slide([2, 0, 2, 0]) == ([4, 0, 0, 0], 4, True))
    check("2048 no triple [2,2,2,0]->[4,2]", slide([2, 2, 2, 0]) == ([4, 2, 0, 0], 4, True))
    check("2048 no-move [2,4,2,4]", slide([2, 4, 2, 4]) == ([2, 4, 2, 4], 0, False))
    check("2048 slide [0,0,0,2]->[2]", slide([0, 0, 0, 2]) == ([2, 0, 0, 0], 0, True))

    # fuzz full games with invariants
    def is_pow2(v):
        return v == 0 or (v >= 2 and (v & (v - 1)) == 0)

    def grid_sum(s):
        return sum(int(s.grid[r][c]) for r in range(1, 5) for c in range(1, 5))

    bad = 0
    for seed in range(60):
        lua.execute(f"math.randomseed({seed})")
        s = G.new()
        for _ in range(400):
            if s.over:
                break
            before = grid_sum(s)
            moved = False
            for d in ("left", "right", "up", "down"):
                if G.move(s, d):
                    moved = True
                    break
            if not moved:
                break
            after = grid_sum(s)
            if after - before not in (2, 4):
                bad += 1
            for r in range(1, 5):
                for c in range(1, 5):
                    if not is_pow2(int(s.grid[r][c])):
                        bad += 1
    check("2048 fuzz: 60 games, tiles power-of-2 & sum grows by spawn", bad == 0, f"{bad} violations")


# ---------------------------------------------------------------- Minesweeper
def test_minesweeper(lua, ns):
    G = ns.logic["minesweeper"]

    # adjacency correctness vs brute force
    adj_bad = 0
    for seed in range(30):
        lua.execute(f"math.randomseed({seed})")
        s = G.new(9, 10)
        G.placeMines(s, 5, 5)
        # first click safe
        if s.mine[5][5]:
            check("minesweeper first-click safe", False, f"seed {seed} mine at first click")
            return
        for r in range(1, 10):
            for c in range(1, 10):
                if not s.mine[r][c]:
                    exp = 0
                    for dr in (-1, 0, 1):
                        for dc in (-1, 0, 1):
                            nr, nc = r + dr, c + dc
                            if (dr or dc) and 1 <= nr <= 9 and 1 <= nc <= 9 and s.mine[nr][nc]:
                                exp += 1
                    if int(s.adj[r][c]) != exp:
                        adj_bad += 1
    check("minesweeper adjacency counts correct", adj_bad == 0, f"{adj_bad} wrong")

    # reveal a mine loses
    lua.execute("math.randomseed(1)")
    s = G.new(9, 10)
    G.placeMines(s, 5, 5)
    mine = None
    for r in range(1, 10):
        for c in range(1, 10):
            if s.mine[r][c]:
                mine = (r, c)
                break
        if mine:
            break
    G.reveal(s, mine[0], mine[1])
    check("minesweeper revealing a mine -> loss", bool(s.over) and not bool(s.win))

    # flag blocks reveal (pick a cell still hidden after the first reveal)
    lua.execute("math.randomseed(2)")
    s = G.new(9, 10)
    G.reveal(s, 5, 5)  # places mines, safe
    hidden = None
    for r in range(1, 10):
        for c in range(1, 10):
            if not s.revealed[r][c] and not s.mine[r][c]:
                hidden = (r, c)
                break
        if hidden:
            break
    G.toggleFlag(s, hidden[0], hidden[1])
    G.reveal(s, hidden[0], hidden[1])
    check("minesweeper flagged cell cannot be revealed", not bool(s.revealed[hidden[0]][hidden[1]]))

    # fuzz: never reveal a mine unless lost; win => all non-mines revealed
    bad = 0
    for seed in range(40):
        lua.execute(f"math.randomseed({seed})")
        s = G.new(9, 10)
        G.reveal(s, 5, 5)
        import random as _r
        _r.seed(seed)
        guard = 0
        while not s.over and guard < 200:
            guard += 1
            hidden = [(r, c) for r in range(1, 10) for c in range(1, 10)
                      if not s.revealed[r][c] and not s.flagged[r][c]]
            if not hidden:
                break
            r, c = _r.choice(hidden)
            was_mine = bool(s.mine[r][c])
            G.reveal(s, r, c)
            if bool(s.revealed[r][c]) and bool(s.mine[r][c]) and not s.over:
                bad += 1  # revealed a mine without losing
        if bool(s.win):
            for r in range(1, 10):
                for c in range(1, 10):
                    if not s.mine[r][c] and not s.revealed[r][c]:
                        bad += 1
    check("minesweeper fuzz: mines safe, win reveals all non-mines", bad == 0, f"{bad} violations")


# ---------------------------------------------------------------- Snake
def test_snake(lua, ns):
    G = ns.logic["snake"]

    # reversal ignored
    s = G.new(17)
    G.setDir(s, "left")  # opposite of initial "right"
    check("snake cannot reverse", s.nextDir == "right")

    # fuzz
    import random as _r
    bad = 0
    for seed in range(60):
        lua.execute(f"math.randomseed({seed})")
        _r.seed(seed)
        s = G.new(17)
        guard = 0
        while not s.over and guard < 2000:
            guard += 1
            if _r.random() < 0.3:
                G.setDir(s, _r.choice(["up", "down", "left", "right"]))
            G.tick(s)
            n = int(s.n)
            # length == 3 + score
            if len(list(s.snake.values())) != 3 + int(s.score):
                bad += 1
            # no duplicate body cells while alive
            if not s.over:
                seen = set()
                dup = False
                for seg in s.snake.values():
                    k = (int(seg[1]), int(seg[2]))
                    if k in seen:
                        dup = True
                    seen.add(k)
                if dup:
                    bad += 1
                # food not on snake
                if s.food:
                    fk = (int(s.food[1]), int(s.food[2]))
                    if fk in seen:
                        bad += 1
    check("snake fuzz: length/score, no self-overlap, food off-snake", bad == 0, f"{bad} violations")


# ---------------------------------------------------------------- Nonogram
def test_nonogram(lua, ns):
    G = ns.logic["nonogram"]
    n_puzzles = int(lua.eval("function(t) return #t end")(G.puzzles))
    check("nonogram has puzzles", n_puzzles >= 4)

    for idx in range(1, n_puzzles + 1):
        name = G.puzzles[idx].name
        st = G.new(idx)
        rows, cols = int(st.rows), int(st.cols)
        # fill exactly the solution -> win, and every line satisfied
        result = None
        for r in range(1, rows + 1):
            for c in range(1, cols + 1):
                if st.p.sol[r][c]:
                    result = G.fill(st, r, c)
        check(f"nonogram '{name}' solved by filling solution", bool(st.won))
        # lives never dropped (all fills correct)
        check(f"nonogram '{name}' no lives lost on correct fills", int(st.lives) == int(st.maxLives))
        sat = all(bool(G.lineSatisfied(st, "row", r)) for r in range(1, rows + 1)) and \
              all(bool(G.lineSatisfied(st, "col", c)) for c in range(1, cols + 1))
        check(f"nonogram '{name}' all clues satisfied at solve", sat)

    # mistake + dead mechanics on a Hard puzzle (lives 3)
    hard = None
    for idx in range(1, n_puzzles + 1):
        if G.puzzles[idx].lives == 3:
            hard = idx
            break
    check("nonogram has a 3-life puzzle", hard is not None)
    if hard:
        st = G.new(hard)
        rows, cols = int(st.rows), int(st.cols)
        empties = [(r, c) for r in range(1, rows + 1) for c in range(1, cols + 1)
                   if not st.p.sol[r][c]]
        # wrong fill -> mistake, loses a life, becomes X
        r, c = empties[0]
        res = G.fill(st, r, c)
        check("nonogram wrong fill = mistake", res == "mistake" and int(st.lives) == 2 and int(st.fill[r][c]) == 2)
        # burn remaining lives -> dead
        res2 = G.fill(st, empties[1][0], empties[1][1])
        res3 = G.fill(st, empties[2][0], empties[2][1])
        check("nonogram lives to zero = dead", res3 == "dead" and bool(st.dead) and int(st.lives) == 0)
        # no actions after dead
        check("nonogram no fill after dead", G.fill(st, empties[3][0], empties[3][1]) == "none")

    # hint fills a correct cell and never a wrong one
    st = G.new(1)
    hint = G.hint(st)
    hr, hc = int(hint[1]), int(hint[2])
    check("nonogram hint fills a solution cell", bool(st.p.sol[hr][hc]) and int(st.fill[hr][hc]) == 1)


# ---------------------------------------------------------------- Lights Out
def test_lightsout(lua, ns):
    G = ns.logic["lightsout"]
    # flip is its own inverse
    s = G.new(5)
    snap = [[bool(s.grid[r][c]) for c in range(1, 6)] for r in range(1, 6)]
    G.flip(s, 3, 3); G.flip(s, 3, 3)
    same = all(bool(s.grid[r + 1][c + 1]) == snap[r][c] for r in range(5) for c in range(5))
    check("lightsout flip is an involution", same)
    # generated boards are not already solved
    unsolved = 0
    for seed in range(40):
        lua.execute(f"math.randomseed({seed})")
        if not bool(G.isSolved(G.new(5))):
            unsolved += 1
    check("lightsout new boards are unsolved", unsolved == 40, f"{40 - unsolved} were pre-solved")
    # press toggles + solve detection
    s = G.new(5)
    for r in range(1, 6):
        for c in range(1, 6):
            s.grid[r][c] = False
    s.solved = False
    G.press(s, 2, 2)
    check("lightsout press lights cells & isn't solved", not bool(s.solved) and int(s.moves) == 1)
    G.press(s, 2, 2)
    check("lightsout pressing back solves", bool(s.solved))


# ---------------------------------------------------------------- Memory
def test_memory(lua, ns):
    G = ns.logic["memory"]
    lua.execute("math.randomseed(3)")
    s = G.new(8)
    check("memory has 16 cards", int(s.n) == 16)
    counts = {}
    for i in range(1, 17):
        f = int(s.cards[i].face); counts[f] = counts.get(f, 0) + 1
    check("memory every face appears exactly twice", all(v == 2 for v in counts.values()) and len(counts) == 8)

    # find a matching pair and a mismatching pair
    byface = {}
    for i in range(1, 17):
        byface.setdefault(int(s.cards[i].face), []).append(i)
    a, b = byface[1]
    check("memory matching pair -> match", G.flip(s, a) == "flip" and G.flip(s, b) == "match")
    check("memory pairsFound incremented", int(s.pairsFound) == 1 and bool(s.cards[a].matched))
    # mismatch
    x = byface[2][0]; y = byface[3][0]
    G.flip(s, x)
    check("memory mismatch -> mismatch", G.flip(s, y) == "mismatch")
    check("memory two cards shown after mismatch", len(list(s.up.values())) == 2)
    G.resolve(s)
    check("memory resolve hides mismatch", len(list(s.up.values())) == 0)

    # full win
    lua.execute("math.randomseed(9)")
    s = G.new(8)
    byface = {}
    for i in range(1, 17):
        byface.setdefault(int(s.cards[i].face), []).append(i)
    for f, (i, j) in byface.items():
        G.flip(s, i); G.flip(s, j)
    check("memory win when all pairs found", bool(s.over) and int(s.pairsFound) == 8)


# ---------------------------------------------------------------- Simon
def test_simon(lua, ns):
    G = ns.logic["simon"]
    lua.execute("math.randomseed(1)")
    s = G.new(); G.extend(s)
    check("simon starts at round 1", int(G.round(s)) == 1)
    # correct input completes the round
    res = G.input(s, int(s.seq[1]))
    check("simon correct single -> round", res == "round")
    G.extend(s)
    check("simon extend -> round 2", int(G.round(s)) == 2)
    # correct then wrong
    r1 = G.input(s, int(s.seq[1]))
    wrong = 1 + (int(s.seq[2]) % 4) + 1
    wrong = wrong if wrong != int(s.seq[2]) else (int(s.seq[2]) % 4) + 1
    res2 = G.input(s, wrong)
    check("simon wrong input -> fail", r1 == "ok" and res2 == "fail" and bool(s.over))


# ---------------------------------------------------------------- Core features
def test_core(lua, ns):
    g = lua.globals()
    # achievements idempotent
    lua.execute("ArcadeDB.ach = {}")
    check("achievement unlock returns true once", bool(ns.Unlock("first")) and not bool(ns.Unlock("first")))
    check("achievement recorded", bool(g.ArcadeDB.ach["first"]))

    # streak logic across days
    base = 20000
    lua.execute("ArcadeDB.stats = { plays = {}, total = 0 }")
    g.MOCK_TIME = base * 86400
    check("streak starts at 1", int(ns.RecordPlay("x")) == 1)
    check("same day keeps streak", int(ns.RecordPlay("x")) == 1)
    g.MOCK_TIME = (base + 1) * 86400
    check("next day increments streak", int(ns.RecordPlay("x")) == 2)
    g.MOCK_TIME = (base + 3) * 86400
    check("gap resets streak", int(ns.RecordPlay("x")) == 1)
    check("streak3 achievement respects real streak", not bool(g.ArcadeDB.ach["streak3"]))
    # build a 3-streak
    lua.execute("ArcadeDB.stats = { plays = {}, total = 0 }")
    for k in range(3):
        g.MOCK_TIME = (base + 10 + k) * 86400
        ns.RecordPlay("x")
    check("streak3 unlocks at 3-day streak", bool(g.ArcadeDB.ach["streak3"]))


def main():
    lua, ns = boot()
    print(f"Loaded real Arcade addon ({len(FILES)} files) into embedded {lua.eval('_VERSION')}")
    print(f"Registered games: " + ", ".join(
        ns.games[i].name for i in range(1, int(lua.eval('function(t) return #t end')(ns.games)) + 1)))
    test_2048(lua, ns)
    test_minesweeper(lua, ns)
    test_snake(lua, ns)
    test_nonogram(lua, ns)
    test_lightsout(lua, ns)
    test_memory(lua, ns)
    test_simon(lua, ns)
    test_core(lua, ns)
    print("-" * 64)
    print(f"arcade integration: {_passed} passed, {_failed} failed")
    sys.exit(1 if _failed else 0)


if __name__ == "__main__":
    main()
