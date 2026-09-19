#!/usr/bin/env python3
"""
LAYER 1 — reference-model fuzzer.

A from-scratch Python reimplementation of the Bejeweled match-3 rules, used as an
independent oracle. A self-playing bot plays hundreds of full games and asserts
board invariants after every move; crafted boards verify special-gem semantics.

NOTE (honest QA caveat): this is a MODEL of the intended algorithm, not the
shipped Lua. During this project the model PASSED 60k moves while the real addon
still had a refill bug — because the model contained a line the Lua was missing.
That is exactly why `run_lua_tests.py` (Layer 2) exists: it drives the real
Bejeweled.lua and is authoritative for the shipped artifact. Keep both:
Layer 1 is a fast design oracle, Layer 2 is the integration truth.
"""
import math, random, sys

ROWS = COLS = 8
NCOLORS = 7


class Bug(Exception):
    pass


class Game:
    def __init__(self):
        self.board = [[None] * (COLS + 1) for _ in range(ROWS + 1)]
        self.comboLevel = 0
        self.score = 0
        self.level = 1
        self.levelScore = 0
        self.levelTarget = 1000
        self.lastSwap = None

    # ---- core ----
    def find_matches(self):
        b, groups = self.board, []
        for r in range(1, ROWS + 1):
            c = 1
            while c <= COLS:
                g = b[r][c]; col = g['color'] if g else None; run = 1
                if col and col > 0:
                    while c + run <= COLS and b[r][c + run] and b[r][c + run]['color'] == col:
                        run += 1
                if col and col > 0 and run >= 3:
                    groups.append({'len': run, 'cells': [(r, c + i) for i in range(run)]})
                c += run
        for c in range(1, COLS + 1):
            r = 1
            while r <= ROWS:
                g = b[r][c]; col = g['color'] if g else None; run = 1
                if col and col > 0:
                    while r + run <= ROWS and b[r + run][c] and b[r + run][c]['color'] == col:
                        run += 1
                if col and col > 0 and run >= 3:
                    groups.append({'len': run, 'cells': [(r + i, c) for i in range(run)]})
                r += run
        return groups

    def any_match(self):
        return len(self.find_matches()) > 0

    def add_score(self, pts):
        self.score += pts; self.levelScore += pts
        guard = 0
        while self.levelScore >= self.levelTarget:
            self.levelScore -= self.levelTarget
            self.level += 1
            self.levelTarget = math.floor(self.levelTarget * 1.4)
            guard += 1
            if guard > 100000:
                raise Bug("level loop runaway")

    def process_matches(self, groups):
        b = self.board
        clear, convert = {}, []
        key = lambda r, c: r * 100 + c
        for grp in groups:
            for (r, c) in grp['cells']:
                clear[key(r, c)] = True
            if grp['len'] >= 4:
                target = None
                if self.lastSwap:
                    for (r, c) in grp['cells']:
                        if (r, c) == self.lastSwap:
                            target = (r, c); break
                if target is None:
                    target = grp['cells'][math.ceil(grp['len'] / 2) - 1]
                convert.append((target[0], target[1], 'hyper' if grp['len'] >= 5 else 'flame'))
        queue = [(k // 100, k % 100) for k in list(clear) if b[k // 100][k % 100] and b[k // 100][k % 100]['special'] == 'flame']
        guard = 0
        while queue:
            cr, cc = queue.pop()
            for dr in (-1, 0, 1):
                for dc in (-1, 0, 1):
                    nr, nc = cr + dr, cc + dc
                    if 1 <= nr <= ROWS and 1 <= nc <= COLS:
                        k = key(nr, nc); g = b[nr][nc]
                        if g and not clear.get(k):
                            clear[k] = True
                            if g['special'] == 'flame':
                                queue.append((nr, nc))
            guard += 1
            if guard > 100000:
                raise Bug("flame runaway")
        for (r, c, kind) in convert:
            clear.pop(key(r, c), None)
        self.add_score(len(clear) * 40 * self.comboLevel)
        if convert:
            self.add_score(len(convert) * 120)
        for k in clear:
            g = b[k // 100][k % 100]
            if g:
                g['removed'] = True
        for (r, c, kind) in convert:
            g = b[r][c]
            if g:
                g['special'] = kind
                if kind == 'hyper':
                    g['color'] = 0

    def remove_faded(self):
        b = self.board
        for r in range(1, ROWS + 1):
            for c in range(1, COLS + 1):
                if b[r][c] and b[r][c]['removed']:
                    b[r][c] = None

    def collapse(self):
        b = self.board
        for c in range(1, COLS + 1):
            stack = []
            for r in range(ROWS, 0, -1):
                if b[r][c]:
                    stack.append(b[r][c]); b[r][c] = None
            row = ROWS
            for gem in stack:
                b[row][c] = gem; gem['r'], gem['c'] = row, c
                row -= 1
            for rr in range(1, row + 1):
                b[rr][c] = {'color': random.randint(1, NCOLORS), 'r': rr, 'c': c,
                            'special': None, 'removed': False}   # <-- board assignment the Lua was missing

    def resolve(self):
        guard = 0
        while True:
            groups = self.find_matches()
            if not groups:
                self.comboLevel = 0; self.lastSwap = None
                if not self.find_move():
                    self.shuffle()
                return
            self.comboLevel += 1
            self.process_matches(groups)
            self.remove_faded()
            self.collapse()
            self.lastSwap = None
            guard += 1
            if guard > 100000:
                raise Bug("cascade runaway")

    def find_move(self):
        b = self.board
        for r in range(1, ROWS + 1):
            for c in range(1, COLS + 1):
                g = b[r][c]
                if g and g['special'] == 'hyper':
                    return (r, c, r, c)
                if c < COLS and b[r][c + 1]:
                    b[r][c], b[r][c + 1] = b[r][c + 1], b[r][c]
                    ok = self.any_match()
                    b[r][c], b[r][c + 1] = b[r][c + 1], b[r][c]
                    if ok:
                        return (r, c, r, c + 1)
                if r < ROWS and b[r + 1][c]:
                    b[r][c], b[r + 1][c] = b[r + 1][c], b[r][c]
                    ok = self.any_match()
                    b[r][c], b[r + 1][c] = b[r + 1][c], b[r][c]
                    if ok:
                        return (r, c, r + 1, c)
        return None

    def shuffle(self):
        for _ in range(80):
            for r in range(1, ROWS + 1):
                for c in range(1, COLS + 1):
                    g = self.board[r][c]
                    if g:
                        g['special'] = None; g['color'] = random.randint(1, NCOLORS)
            if not self.any_match() and self.find_move():
                return

    def color_avoiding(self, r, c):
        b = self.board
        while True:
            col = random.randint(1, NCOLORS)
            if c >= 3 and b[r][c - 1] and b[r][c - 2] and b[r][c - 1]['color'] == col and b[r][c - 2]['color'] == col:
                continue
            if r >= 3 and b[r - 1][c] and b[r - 2][c] and b[r - 1][c]['color'] == col and b[r - 2][c]['color'] == col:
                continue
            return col

    def new_game(self):
        self.board = [[None] * (COLS + 1) for _ in range(ROWS + 1)]
        self.score = self.levelScore = 0; self.level = 1; self.levelTarget = 1000
        self.comboLevel = 0; self.lastSwap = None
        for r in range(1, ROWS + 1):
            for c in range(1, COLS + 1):
                self.board[r][c] = {'color': self.color_avoiding(r, c), 'r': r, 'c': c,
                                    'special': None, 'removed': False}
        if not self.find_move():
            self.shuffle()

    def activate_hyper(self, hyper, other):
        tc = other['color']
        hyper['removed'] = True
        for r in range(1, ROWS + 1):
            for c in range(1, COLS + 1):
                g = self.board[r][c]
                if g and tc and tc > 0 and g['color'] == tc:
                    g['removed'] = True
        if not (tc and tc > 0):
            other['removed'] = True
        self.comboLevel = 1
        self.add_score(60)
        self.remove_faded(); self.collapse(); self.resolve()

    # ---- invariants ----
    def check(self, tag):
        b = self.board
        seen = set()
        for r in range(1, ROWS + 1):
            for c in range(1, COLS + 1):
                g = b[r][c]
                if g is None:
                    raise Bug(f"[{tag}] hole at {r},{c}")
                if g['removed']:
                    raise Bug(f"[{tag}] removed gem left at {r},{c}")
                if g['r'] != r or g['c'] != c:
                    raise Bug(f"[{tag}] desync at {r},{c}")
                if id(g) in seen:
                    raise Bug(f"[{tag}] duplicate gem object")
                seen.add(id(g))
        if self.any_match():
            raise Bug(f"[{tag}] unresolved match on settled board")
        if not self.find_move():
            raise Bug(f"[{tag}] no legal move after resolve")


def play(seed, moves):
    random.seed(seed)
    g = Game(); g.new_game(); g.check(f"seed{seed}:new")
    for m in range(moves):
        mv = g.find_move()
        if mv is None:
            raise Bug(f"seed{seed} move{m}: no move")
        r1, c1, r2, c2 = mv
        if (r1, c1) == (r2, c2):
            hyper = g.board[r1][c1]; neigh = None
            for dr, dc in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                nr, nc = r1 + dr, c1 + dc
                if 1 <= nr <= ROWS and 1 <= nc <= COLS and g.board[nr][nc]:
                    neigh = g.board[nr][nc]; break
            g.activate_hyper(hyper, neigh)
        else:
            b = g.board
            b[r1][c1], b[r2][c2] = b[r2][c2], b[r1][c1]
            b[r1][c1]['r'], b[r1][c1]['c'] = r1, c1
            b[r2][c2]['r'], b[r2][c2]['c'] = r2, c2
            g.lastSwap = (r2, c2); g.comboLevel = 0
            g.resolve()
        g.check(f"seed{seed}:move{m}")


def scenarios():
    """Crafted boards for special-gem semantics."""
    out = []

    def T(name, cond):
        out.append((name, cond))

    def blank():
        g = Game()
        for r in range(1, ROWS + 1):
            for c in range(1, COLS + 1):
                g.board[r][c] = {'color': 1 + ((r * 2 + c * 3) % 7), 'r': r, 'c': c,
                                 'special': None, 'removed': False}
        return g

    # match-4 -> one flame
    g = blank()
    for c in range(1, COLS + 1):
        g.board[4][c]['color'] = 1 if c in (3, 4, 5, 6) else (2 if c % 2 else 5)
    for r in range(1, ROWS + 1):
        for c in (3, 4, 5, 6):
            if r != 4:
                g.board[r][c]['color'] = 3 if (r + c) % 2 else 6
    g.lastSwap = (4, 4); g.comboLevel = 1
    g.process_matches(g.find_matches())
    flames = [(r, c) for r in range(1, 9) for c in range(1, 9) if g.board[r][c] and g.board[r][c]['special'] == 'flame']
    T("match-4 -> exactly one flame at swapped cell", flames == [(4, 4)])

    # match-5 -> one hyper (color 0)
    g = blank()
    for c in range(1, COLS + 1):
        g.board[4][c]['color'] = 1 if 2 <= c <= 6 else 3
    for r in range(1, ROWS + 1):
        for c in range(2, 7):
            if r != 4:
                g.board[r][c]['color'] = 5 if (r + c) % 2 else 7
    g.lastSwap = (4, 4); g.comboLevel = 1
    g.process_matches(g.find_matches())
    hypers = [(r, c) for r in range(1, 9) for c in range(1, 9) if g.board[r][c] and g.board[r][c]['special'] == 'hyper']
    T("match-5 -> one hyper", len(hypers) == 1 and g.board[hypers[0][0]][hypers[0][1]]['color'] == 0)

    return out


def main():
    games = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    moves = int(sys.argv[2]) if len(sys.argv) > 2 else 200
    fails = 0
    for s in range(games):
        try:
            play(s, moves)
        except Bug as e:
            fails += 1; print(f"  FAIL {e}")
            if fails >= 10:
                break
    scen = scenarios()
    print("-" * 64)
    print(f"model fuzz: {games} games x {moves} moves = {games * moves} moves, "
          f"{fails} invariant failures")
    ok = 0
    for name, cond in scen:
        print(f"  [{'PASS' if cond else 'FAIL'}] {name}")
        ok += 1 if cond else 0
    print(f"scenarios: {ok}/{len(scen)} passed")
    bad = fails + (len(scen) - ok)
    print(f"result: {'ALL PASS' if bad == 0 else str(bad) + ' FAILURES'}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
