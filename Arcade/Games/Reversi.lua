--[[ Azeroth Arcade — Reversi (Othello) vs AI.  You are dark; flank to flip. ]]
local ADDON, ns = ...

local N = 8
local Logic = {}
ns.logic["reversi"] = Logic

local DIRS = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

function Logic.new()
  local g = {}
  for r = 1, N do g[r] = {}; for c = 1, N do g[r][c] = 0 end end
  g[4][4], g[5][5] = 2, 2
  g[4][5], g[5][4] = 1, 1
  return { grid = g, turn = 1, over = false }
end

function Logic.flips(s, r, c, player)
  if s.grid[r][c] ~= 0 then return {} end
  local opp = (player == 1) and 2 or 1
  local out = {}
  for _, d in ipairs(DIRS) do
    local line = {}
    local nr, nc = r + d[1], c + d[2]
    while nr >= 1 and nr <= N and nc >= 1 and nc <= N and s.grid[nr][nc] == opp do
      line[#line + 1] = { nr, nc }; nr = nr + d[1]; nc = nc + d[2]
    end
    if #line > 0 and nr >= 1 and nr <= N and nc >= 1 and nc <= N and s.grid[nr][nc] == player then
      for _, cell in ipairs(line) do out[#out + 1] = cell end
    end
  end
  return out
end

function Logic.legalMoves(s, player)
  local out = {}
  for r = 1, N do for c = 1, N do
    if s.grid[r][c] == 0 and #Logic.flips(s, r, c, player) > 0 then out[#out + 1] = { r, c } end
  end end
  return out
end

function Logic.play(s, r, c)
  local player = s.turn
  local fl = Logic.flips(s, r, c, player)
  if #fl == 0 then return false end
  s.grid[r][c] = player
  for _, cell in ipairs(fl) do s.grid[cell[1]][cell[2]] = player end
  -- next turn (skip if opponent has no move; game over if neither can move)
  local opp = (player == 1) and 2 or 1
  if #Logic.legalMoves(s, opp) > 0 then s.turn = opp
  elseif #Logic.legalMoves(s, player) > 0 then s.turn = player
  else s.over = true end
  return true
end

function Logic.count(s)
  local a, b = 0, 0
  for r = 1, N do for c = 1, N do
    if s.grid[r][c] == 1 then a = a + 1 elseif s.grid[r][c] == 2 then b = b + 1 end
  end end
  return a, b
end

-- greedy AI: prefer corners, else the move flipping the most discs
function Logic.aiMove(s)
  local moves = Logic.legalMoves(s, 2)
  if #moves == 0 then return nil end
  local best, bestN = nil, -1
  for _, m in ipairs(moves) do
    local n = #Logic.flips(s, m[1], m[2], 2)
    local corner = ((m[1] == 1 or m[1] == N) and (m[2] == 1 or m[2] == N))
    if corner then n = n + 100 end
    if n > bestN then bestN, best = n, m end
  end
  return best
end

------------------------------------------------------------------------
-- View
------------------------------------------------------------------------
local SIZE, GAP = 48, 2
local frame, cells, state, overlay, overlayText, busy

local function render()
  local legal = {}
  if not state.over and state.turn == 1 then
    for _, m in ipairs(Logic.legalMoves(state, 1)) do legal[m[1] * 10 + m[2]] = true end
  end
  for r = 1, N do for c = 1, N do
    local v = state.grid[r][c]
    local cell = cells[r][c]
    if v == 1 then ns.Grad(cell.disc, "VERTICAL", { 0.20, 0.14, 0.28 }, { 0.42, 0.30, 0.58 }); cell.disc:Show()
    elseif v == 2 then ns.Grad(cell.disc, "VERTICAL", { 0.75, 0.62, 0.20 }, { 0.96, 0.86, 0.45 }); cell.disc:Show()
    else cell.disc:Hide() end
    cell.hint:SetShown(legal[r * 10 + c] and true or false)
  end end
  local a, b = Logic.count(state)
  ns.SetInfo("You " .. a .. "   AI " .. b)
end

local function finish()
  local a, b = Logic.count(state)
  overlayText:SetText(a > b and "|cff9be7a0You win!|r" or a < b and "|cffff6677The AI wins|r" or "|cffe9d5a0Draw|r")
  overlay:Show()
end

local function newGame() state = Logic.new(); busy = false; overlay:Hide(); render() end

local function aiTurn()
  busy = true
  C_Timer.After(0.4, ns.Safe(function()
    while not state.over and state.turn == 2 do
      local m = Logic.aiMove(state)
      if not m then break end
      Logic.play(state, m[1], m[2])
    end
    render(); busy = false
    if state.over then finish() end
  end))
end

local function onCell(r, c)
  if busy or state.over or state.turn ~= 1 then return end
  if not Logic.play(state, r, c) then return end
  render(); ns.Sound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION)
  if state.over then finish(); return end
  if state.turn == 2 then aiTurn() end
end

local function build(content)
  frame = CreateFrame("Frame", nil, content); frame:SetAllPoints()
  local board = ns.Panel(frame)
  board:SetSize(N * SIZE + (N + 1) * GAP, N * SIZE + (N + 1) * GAP); board:SetPoint("TOP", 0, -14)
  cells = {}
  for r = 1, N do
    cells[r] = {}
    for c = 1, N do
      local b = CreateFrame("Button", nil, board)
      b:SetSize(SIZE, SIZE)
      b:SetPoint("TOPLEFT", GAP + (c - 1) * (SIZE + GAP), -(GAP + (r - 1) * (SIZE + GAP)))
      local felt = b:CreateTexture(nil, "BACKGROUND"); felt:SetAllPoints()
      ns.Grad(felt, "VERTICAL", { 0.10, 0.16, 0.11 }, { 0.06, 0.11, 0.07 })
      b.hint = b:CreateTexture(nil, "ARTWORK"); b.hint:SetAllPoints(); b.hint:SetColorTexture(1, 1, 1, 0.08); b.hint:Hide()
      b.disc = b:CreateTexture(nil, "OVERLAY"); b.disc:SetPoint("TOPLEFT", 4, -4); b.disc:SetPoint("BOTTOMRIGHT", -4, 4)
      local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
      b.r, b.c = r, c
      b:SetScript("OnClick", function(self) onCell(self.r, self.c) end)
      cells[r][c] = b
    end
  end
  local newBtn = ns.NewButton(frame, "New Game", 120, 26, function() newGame() end)
  newBtn:SetPoint("BOTTOM", 0, 6)

  overlay = CreateFrame("Frame", nil, frame); overlay:SetAllPoints(board)
  overlay:SetFrameLevel(board:GetFrameLevel() + 20)
  local obg = overlay:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints(); obg:SetColorTexture(0.05, 0.03, 0.09, 0.82)
  overlayText = ns.Header(overlay, "", 22); overlayText:SetPoint("CENTER", 0, 16)
  local again = ns.NewButton(overlay, "Play Again", 120, 26, function() newGame() end); again:SetPoint("CENTER", 0, -28)
  overlay:Hide()
end

local function start(content) if not frame then build(content) end frame:Show(); newGame() end
local function stop() if frame then frame:Hide() end end

ns.Register({ category = "Vs AI", id = "reversi", name = "Reversi", desc = "Flank and flip vs the AI.",
              icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_05", start = start, stop = stop })
