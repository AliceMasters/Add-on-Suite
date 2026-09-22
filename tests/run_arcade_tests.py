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
         "Games/LightsOut.lua", "Games/Memory.lua", "Games/Simon.lua",
         "Games/TicTacToe.lua", "Games/ConnectFour.lua", "Games/FloodIt.lua",
         "Games/Slide.lua", "Games/Mastermind.lua",
         "Games/Nim.lua", "Games/Hangman.lua", "Games/Reversi.lua", "Games/PegSolitaire.lua",
         "Games/Sudoku.lua"]

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


# ---------------------------------------------------------------- Tic-Tac-Toe
def test_tictactoe(lua, ns):
    G = ns.logic["tictactoe"]
    mkb = lua.eval("function(...) return {...} end")
    def winner(b): return int(G.winnerOf(mkb(*b)))
    def ai(b):
        _, m = G.minimax(mkb(*b), 2)
        return int(m) if m is not None else None

    # AI takes an immediate win
    b = [2, 2, 0,  0, 1, 0,  1, 0, 0]
    check("ttt AI takes the winning move", ai(b) == 3)
    # AI blocks an immediate threat
    b = [1, 1, 0,  0, 2, 0,  0, 0, 0]
    check("ttt AI blocks the opponent", ai(b) == 3)

    # exhaustive: opponent (X=1) plays every line, AI (O=2) plays minimax -> AI never loses
    import sys as _sys
    _sys.setrecursionlimit(10000)
    def search(b, turn):
        w = winner(b)
        if w == 1: return False        # AI lost -> fail
        if w != 0: return True         # AI win or draw
        if turn == 1:
            for i in range(9):
                if b[i] == 0:
                    nb = b[:]; nb[i] = 1
                    if not search(nb, 2): return False
            return True
        else:
            m = ai(b); nb = b[:]; nb[m - 1] = 2
            return search(nb, 1)
    check("ttt minimax NEVER loses (full game-tree search)", search([0] * 9, 1))


# ---------------------------------------------------------------- Connect Four
def test_connect4(lua, ns):
    G = ns.logic["connect4"]
    # AI takes a win: three of AI's discs on the bottom row, open 4th
    s = G.new()
    for c in (1, 2, 3): s.grid[6][c] = 2
    s.turn = 2
    check("c4 AI takes the win", int(G.aiMove(s)) == 4)
    # AI blocks opponent's three-in-a-row
    s = G.new()
    for c in (2, 3, 4): s.grid[6][c] = 1
    s.turn = 2
    check("c4 AI blocks the threat", int(G.aiMove(s)) in (1, 5))
    # drop lands at the bottom and stacks
    s = G.new()
    G.drop(s, 4)
    check("c4 disc lands on the floor", int(s.grid[6][4]) != 0 and int(s.grid[5][4]) == 0)
    # vertical win detected
    s = G.new()
    for r in (6, 5, 4, 3): s.grid[r][1] = 1
    check("c4 detects a vertical four", int(G.winnerAt(s.grid)) == 1)


# ---------------------------------------------------------------- Flood It
def test_floodit(lua, ns):
    G = ns.logic["floodit"]
    lua.execute("math.randomseed(4)")
    s = G.new(12, 6, 25)
    check("floodit region contains origin", len(list(G.region(s).values())) >= 1)
    check("floodit pick same colour is a no-op", not bool(G.pick(s, int(s.grid[1][1]))))
    other = 1 + (int(s.grid[1][1]) % 6) + 1
    other = other if other != int(s.grid[1][1]) and other <= 6 else (int(s.grid[1][1]) % 6) + 1
    m0 = int(s.moves)
    G.pick(s, other)
    check("floodit a real pick counts a move", int(s.moves) == m0 + 1)
    # uniform board => won
    s = G.new(12, 6, 25)
    for r in range(1, 13):
        for c in range(1, 13): s.grid[r][c] = 3
    check("floodit uniform board is won", bool(G.isWon(s)))


# ---------------------------------------------------------------- Sliding Puzzle
def test_slide(lua, ns):
    G = ns.logic["slide"]
    lua.execute("math.randomseed(5)")
    s = G.new(4)
    # exactly one blank, tiles 1..15 present
    vals = sorted(int(s.grid[r][c]) for r in range(1, 5) for c in range(1, 5))
    check("slide has 0..15 exactly once", vals == list(range(16)))
    # solved detection on an ordered board
    k = 1
    for r in range(1, 5):
        for c in range(1, 5):
            s.grid[r][c] = 0 if (r == 4 and c == 4) else k; k += 1
    s.solved = False
    check("slide detects solved", bool(G.isSolved(s)))
    # move: slide the tile left of the blank into it
    check("slide moves a tile into the gap", bool(G.move(s, 4, 3)) and int(s.grid[4][4]) == 15)
    check("slide non-adjacent move rejected", not bool(G.move(s, 1, 1)))


# ---------------------------------------------------------------- Mastermind
def test_mastermind(lua, ns):
    G = ns.logic["mastermind"]
    code = lua.eval("function(...) return {...} end")(1, 2, 3, 4)
    def score(guess):
        b, w = G.score(code, lua.eval("function(...) return {...} end")(*guess))
        return int(b), int(w)
    check("mm exact match = 4 black", score([1, 2, 3, 4]) == (4, 0))
    check("mm all wrong = 0/0", score([5, 5, 6, 6]) == (0, 0))
    check("mm swapped pair = 0 black 2 white", score([2, 1, 3, 4]) == (2, 2))  # 3,4 exact; 1,2 swapped
    check("mm duplicates counted once", score([1, 1, 1, 1]) == (1, 0))
    # win + lose flow
    s = G.new()
    code2 = [int(s.code[i]) for i in range(1, 5)]
    b, w = G.guess(s, lua.eval("function(...) return {...} end")(*code2))
    check("mm guessing the code wins", bool(s.won) and int(b) == 4)
    s = G.new()
    wrong = [1 + (int(s.code[1]) % 6), int(s.code[2]), int(s.code[3]), 1 + (int(s.code[4]) % 6)]
    for _ in range(10): G.guess(s, lua.eval("function(...) return {...} end")(*wrong))
    check("mm runs out of guesses", bool(s.over) and not bool(s.won))


# ---------------------------------------------------------------- Nim
def test_nim(lua, ns):
    G = ns.logic["nim"]
    def nimsum(h):
        x = 0
        for v in h: x ^= v
        return x
    def ai(heaps):
        s = lua.eval("function(a,b,c) return {heaps={a,b,c}} end")(*heaps)
        h, cnt = G.aiMove(s)
        return int(h), int(cnt)

    # AI zeroes the nim-sum from a winning position
    h, cnt = ai([3, 5, 7])
    nh = [3, 5, 7]; nh[h - 1] -= cnt
    check("nim AI moves to nim-sum 0", nimsum(nh) == 0)

    # taking the last piece wins
    s = lua.eval("function() return {heaps={0,0,1}, turn=1, over=false, winner=0} end")()
    G.take(s, 3, 1)
    check("nim last piece wins", bool(s.over) and int(s.winner) == 1)
    # can't overdraw
    s = G.new()
    check("nim rejects overdraw", not bool(G.take(s, 1, 99)))

    # full search: from a winning position AI never loses vs adversarial opponent
    import sys as _s; _s.setrecursionlimit(100000)
    def search(heaps, turn):
        if all(v == 0 for v in heaps):
            return 1 if turn == 2 else 2      # previous mover won
        if turn == 2:
            hh, cc = ai(heaps); nn = list(heaps); nn[hh - 1] -= cc
            return search(nn, 1)
        else:
            for hi in range(3):
                for take in range(1, heaps[hi] + 1):
                    nn = list(heaps); nn[hi] -= take
                    if search(nn, 2) == 1: return 1
            return 2
    check("nim AI wins from a winning position (full search)", search([3, 5, 7], 2) == 2)


# ---------------------------------------------------------------- Hangman
def test_hangman(lua, ns):
    G = ns.logic["hangman"]
    s = G.new()
    s.word = "CAT"; s.guessed = lua.eval("{}"); s.wrong = 0; s.over = False; s.won = False
    check("hangman hit reveals", G.guess(s, "C") == "hit" and "C" in G.masked(s))
    check("hangman miss counts", G.guess(s, "Z") == "miss" and int(s.wrong) == 1)
    G.guess(s, "A")
    check("hangman completing word wins", G.guess(s, "T") == "win" and bool(s.won))
    # lose after max wrong
    s = G.new()
    s.word = "CAT"; s.guessed = lua.eval("{}"); s.wrong = 0; s.over = False; s.won = False
    res = None
    for ch in "BDEFGH":
        res = G.guess(s, ch)
    check("hangman loses after 6 wrong", res == "lose" and bool(s.over) and not bool(s.won))


# ---------------------------------------------------------------- Reversi
def test_reversi(lua, ns):
    G = ns.logic["reversi"]
    s = G.new()
    a, b = G.count(s)
    check("reversi starts 2-2", int(a) == 2 and int(b) == 2)
    lm = G.legalMoves(s, 1)
    check("reversi black has 4 opening moves", len(list(lm.values())) == 4)
    m = lm[1]
    fl = G.flips(s, int(m[1]), int(m[2]), 1)
    check("reversi a legal move flips >=1", len(list(fl.values())) >= 1)
    G.play(s, int(m[1]), int(m[2]))
    a2, b2 = G.count(s)
    check("reversi play increases disc count", int(a2) + int(b2) == 5)
    check("reversi AI returns a legal move", G.aiMove(s) is not None)


# ---------------------------------------------------------------- Peg Solitaire
def test_pegs(lua, ns):
    G = ns.logic["pegs"]
    s = G.new()
    check("pegs starts with 32", int(G.pegs(s)) == 32)
    check("pegs center empty", int(s.grid[4][4]) == 0)
    check("pegs corner invalid", not bool(G.valid(1, 1)) and bool(G.valid(4, 1)))
    check("pegs a valid jump exists", bool(G.canMove(s, 4, 2, 4, 4)))
    G.move(s, 4, 2, 4, 4)
    check("pegs jump removes two, adds one", int(G.pegs(s)) == 31 and int(s.grid[4][4]) == 1
          and int(s.grid[4][3]) == 0 and int(s.grid[4][2]) == 0)
    check("pegs rejects non-jump", not bool(G.move(s, 4, 4, 4, 5)))
    check("pegs has moves at start", bool(G.hasMoves(G.new())))


# ---------------------------------------------------------------- Sudoku
def test_sudoku(lua, ns):
    G = ns.logic["sudoku"]
    n = int(lua.eval("function(t) return #t end")(G.puzzles))
    check("sudoku has puzzles", n >= 4)

    def box_ok(sol_grid):
        def ok(cells): return sorted(cells) == list(range(1, 10))
        for r in range(9):
            if not ok(sol_grid[r]): return False
        for c in range(9):
            if not ok([sol_grid[r][c] for r in range(9)]): return False
        for br in range(0, 9, 3):
            for bc in range(0, 9, 3):
                if not ok([sol_grid[br + i][bc + j] for i in range(3) for j in range(3)]): return False
        return True

    for idx in range(1, n + 1):
        p = G.puzzles[idx]
        sol = str(p.solution)
        grid = [[int(sol[r * 9 + c]) for c in range(9)] for r in range(9)]
        check(f"sudoku '{p.name}' solution is valid", box_ok(grid))
        given = str(p.given)
        check(f"sudoku '{p.name}' givens agree with solution",
              all(given[i] == "0" or given[i] == sol[i] for i in range(81)))

    # new(): fixed flags match givens
    s = G.new(1)
    given = str(G.puzzles[1].given)
    ok = True
    for r in range(1, 10):
        for c in range(1, 10):
            g = int(given[(r - 1) * 9 + (c - 1)])
            if bool(s.fixed[r][c]) != (g != 0): ok = False
    check("sudoku fixed flags match givens", ok)

    # can't overwrite a given; can fill an empty
    fr = fc = None
    for r in range(1, 10):
        for c in range(1, 10):
            if not s.fixed[r][c]: fr, fc = r, c; break
        if fr: break
    ffr = ffc = None
    for r in range(1, 10):
        for c in range(1, 10):
            if s.fixed[r][c]: ffr, ffc = r, c; break
        if ffr: break
    check("sudoku rejects editing a given", not bool(G.set(s, ffr, ffc, 5)))
    check("sudoku allows editing a blank", bool(G.set(s, fr, fc, 1)))

    # conflict detection: duplicate in a row
    s = G.new(1)
    # find an empty cell and set it to a value already present in its row
    for r in range(1, 10):
        rowvals = [int(s.grid[r][c]) for c in range(1, 10) if s.grid[r][c] != 0]
        empty = [c for c in range(1, 10) if s.grid[r][c] == 0]
        if rowvals and empty:
            G.set(s, r, empty[0], rowvals[0])
            check("sudoku detects a row conflict", bool(G.conflict(s, r, empty[0])))
            break

    # solving from the solution wins
    s = G.new(2)
    sol = str(G.puzzles[2].solution)
    for r in range(1, 10):
        for c in range(1, 10):
            if not s.fixed[r][c]:
                G.set(s, r, c, int(sol[(r - 1) * 9 + (c - 1)]))
    check("sudoku is solved when filled correctly", bool(s.won) and bool(G.isSolved(s)))

    # save/resume round-trips the in-progress grid
    s = G.new(1)
    n = 0
    for r in range(1, 10):
        for c in range(1, 10):
            if not s.fixed[r][c] and n < 6:
                G.set(s, r, c, 3); n += 1
    blob = str(G.serialize(s))
    s2 = G.load(1, blob)
    same = all(int(s2.grid[r][c]) == int(s.grid[r][c]) for r in range(1, 10) for c in range(1, 10))
    check("sudoku save/resume round-trips", len(blob) == 81 and same)


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
    test_tictactoe(lua, ns)
    test_connect4(lua, ns)
    test_floodit(lua, ns)
    test_slide(lua, ns)
    test_mastermind(lua, ns)
    test_nim(lua, ns)
    test_hangman(lua, ns)
    test_reversi(lua, ns)
    test_pegs(lua, ns)
    test_sudoku(lua, ns)
    test_core(lua, ns)
    print("-" * 64)
    print(f"arcade integration: {_passed} passed, {_failed} failed")
    sys.exit(1 if _failed else 0)


if __name__ == "__main__":
    main()
