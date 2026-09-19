#!/usr/bin/env python3
"""
Integration tests that run the ACTUAL shipped Bejeweled/Bejeweled.lua.

An embedded Lua runtime (lupa) loads a mock WoW API (wow_mock.lua) and then the
real addon. We drive real swaps through the real TrySwap/ResolveStep/Collapse,
pump the real C_Timer-driven cascade to completion, and assert on the real board
state after every move:

  * no holes, no gems left flagged 'removed', gem.r/.c stays in sync
  * the board always settles (no leftover match) and a legal move always exists
  * input never stays locked after a cascade finishes
  * NO runtime Lua error reached the Safe() wrapper (captured via chat log)
  * ICON REGRESSION GUARD: every gem's icon vertex-tint matches its true colour
    (this is the check that fails on the old code and passes on the fix)

Run:  python tests/run_lua_tests.py [games] [moves]
Requires: pip install lupa
"""
import os, sys, random

try:
    from lupa import LuaRuntime
except ImportError:
    sys.exit("pip install lupa  (needed to run the Lua integration tests)")

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "..", "Bejeweled", "Bejeweled.lua")
MOCK = os.path.join(HERE, "wow_mock.lua")

EXPORT = """
BJW_TEST = {
  board = board, GEMS = GEMS, ROWS = ROWS, COLS = COLS, HYPER_TEX = HYPER_TEX,
  FindMove = FindMove, TrySwap = TrySwap, Toggle = Toggle, NewGame = NewGame,
  FindMatches = FindMatches, boot = boot,
  is_locked = function() return inputLocked end,
}
"""

TOL = 0.001

class TestFail(Exception):
    pass


def boot_addon():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(MOCK, encoding="utf-8").read())
    src = open(ADDON, encoding="utf-8").read() + "\n" + EXPORT
    loader = lua.eval('function(s) local f = assert(load(s, "Bejeweled")); f("Bejeweled") end')
    loader(src)
    # Lua-side identity check (Python object ids are unreliable for lupa proxies)
    lua.execute("""function DUP_CHECK(board, R, C)
      local seen = {}
      for r = 1, R do for c = 1, C do
        local gm = board[r][c]
        if gm then if seen[gm] then return r*100+c end; seen[gm] = true end
      end end
      return 0
    end""")
    g = lua.globals()
    T = g.BJW_TEST
    # fire ADDON_LOADED so SavedVariables + minimap init like in-game
    on_event = T.boot._scripts["OnEvent"]
    on_event(T.boot, "ADDON_LOADED", "Bejeweled")
    T.Toggle()          # build UI + start a game
    return lua, g, T


def lua_len(lua, t):
    return lua.eval("function(x) return #x end")(t)


def assert_board(lua, T, tag):
    ROWS, COLS = int(T.ROWS), int(T.COLS)
    board, GEMS = T.board, T.GEMS
    dup = int(lua.globals().DUP_CHECK(board, ROWS, COLS))
    if dup != 0:
        raise TestFail(f"[{tag}] same gem object in two cells at {dup//100},{dup%100}")
    for r in range(1, ROWS + 1):
        for c in range(1, COLS + 1):
            gem = board[r][c]
            if gem is None:
                raise TestFail(f"[{tag}] hole at {r},{c}")
            if gem.removed:
                raise TestFail(f"[{tag}] gem still flagged removed at {r},{c}")
            if int(gem.r) != r or int(gem.c) != c:
                raise TestFail(f"[{tag}] desync at {r},{c}: gem says {int(gem.r)},{int(gem.c)}")
            # ---- icon regression guard ----
            icon = gem.btn.icon
            vc = icon._vc
            if gem.special == "hyper":
                if icon._tex != T.HYPER_TEX:
                    raise TestFail(f"[{tag}] hyper at {r},{c} has wrong icon texture {icon._tex}")
            else:
                want = GEMS[gem.color].icon
                for i in (1, 2, 3):
                    if abs(vc[i] - want[i]) > TOL:
                        raise TestFail(
                            f"[{tag}] gem {r},{c} colour={int(gem.color)} has icon tint "
                            f"({vc[1]:.2f},{vc[2]:.2f},{vc[3]:.2f}) but expected "
                            f"({want[1]:.2f},{want[2]:.2f},{want[3]:.2f}) "
                            f"-- icon does not represent its colour")
    if lua_len(lua, T.FindMatches()) != 0:
        raise TestFail(f"[{tag}] board left with an unresolved match")
    if T.FindMove() is None:
        raise TestFail(f"[{tag}] no legal move exists (shuffle failed)")
    if T.is_locked():
        raise TestFail(f"[{tag}] input still locked after cascade settled")


def _count_table(t):
    n = 0
    while t[n + 1] is not None:
        n += 1
    return n


def play(lua, g, T, seed, moves):
    random.seed(seed)
    T.NewGame()
    assert_board(lua, T, f"seed{seed}:new")
    ROWS, COLS = int(T.ROWS), int(T.COLS)
    pump = g.PumpTimers
    specials = 0
    for m in range(moves):
        mv = T.FindMove()
        if mv is None:
            raise TestFail(f"seed{seed} move{m}: no move")
        r1, c1, r2, c2 = int(mv[1]), int(mv[2]), int(mv[3]), int(mv[4])
        if (r1, c1) == (r2, c2):
            hyper = T.board[r1][c1]
            neigh = None
            for dr, dc in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                nr, nc = r1 + dr, c1 + dc
                if 1 <= nr <= ROWS and 1 <= nc <= COLS and T.board[nr][nc] is not None:
                    neigh = T.board[nr][nc]
                    break
            T.TrySwap(hyper, neigh)
        else:
            T.TrySwap(T.board[r1][c1], T.board[r2][c2])
        pump()
        assert_board(lua, T, f"seed{seed}:move{m}")
        errs = [str(g.CHAT_LOG[i]) for i in range(1, _count_table(g.CHAT_LOG) + 1)
                if g.CHAT_LOG[i] and "ERROR" in str(g.CHAT_LOG[i])]
        if errs:
            raise TestFail(f"seed{seed} move{m}: runtime error surfaced: {errs[-1]}")
        for r in range(1, ROWS + 1):
            for c in range(1, COLS + 1):
                sp = T.board[r][c].special
                if sp:
                    specials += 1
    return specials


def main():
    games = int(sys.argv[1]) if len(sys.argv) > 1 else 40
    moves = int(sys.argv[2]) if len(sys.argv) > 2 else 100
    lua, g, T = boot_addon()
    print(f"Loaded real Bejeweled.lua into embedded {lua.eval('_VERSION')}")
    total_specials = 0
    fails = 0
    for s in range(games):
        try:
            total_specials += play(lua, g, T, s, moves)
        except TestFail as e:
            fails += 1
            print(f"  FAIL {e}")
            if fails >= 10:
                break
    tot = games * moves
    print("-" * 64)
    print(f"real-Lua integration: {games} games x {moves} moves = {tot} moves")
    print(f"special gems observed on-board across run: {total_specials}")
    print(f"result: {'ALL PASS' if fails == 0 else str(fails) + ' FAILURES'}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
