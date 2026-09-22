--[[ Azeroth Arcade — Flood It.  Flood the board to a single colour before moves run out. ]]
local ADDON, ns = ...

local Logic = {}
ns.logic["floodit"] = Logic

local NBR = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }

function Logic.new(n, k, moves, rng)
  rng = rng or math.random
  n = n or 12; k = k or 6
  local g = {}
  for r = 1, n do g[r] = {}; for c = 1, n do g[r][c] = rng(k) end end
  return { n = n, k = k, grid = g, moves = 0, maxMoves = moves or 25, over = false, won = false }
end

function Logic.region(s)          -- cells connected to (1,1) sharing its colour
  local cur = s.grid[1][1]
  local seen = { [101] = true }
  local stack, out = { { 1, 1 } }, {}
  while #stack > 0 do
    local cell = table.remove(stack); out[#out + 1] = cell
    for _, d in ipairs(NBR) do
      local nr, nc = cell[1] + d[1], cell[2] + d[2]
      if nr >= 1 and nr <= s.n and nc >= 1 and nc <= s.n
         and not seen[nr * 100 + nc] and s.grid[nr][nc] == cur then
        seen[nr * 100 + nc] = true; stack[#stack + 1] = { nr, nc }
      end
    end
  end
  return out
end

function Logic.isWon(s)
  local first = s.grid[1][1]
  for r = 1, s.n do for c = 1, s.n do if s.grid[r][c] ~= first then return false end end end
  return true
end

function Logic.pick(s, color)
  if s.over or color == s.grid[1][1] then return false end
  for _, cell in ipairs(Logic.region(s)) do s.grid[cell[1]][cell[2]] = color end
  s.moves = s.moves + 1
  s.won = Logic.isWon(s)
  if s.won or s.moves >= s.maxMoves then s.over = true end
  return true
end

------------------------------------------------------------------------
-- View
------------------------------------------------------------------------
local N, K, SIZE = 12, 6, 30
local PAL = {
  { 0.90, 0.25, 0.28 }, { 0.35, 0.62, 0.98 }, { 0.35, 0.80, 0.42 },
  { 0.95, 0.80, 0.22 }, { 0.70, 0.40, 0.92 }, { 0.30, 0.82, 0.82 },
}
local frame, cells, pickers, state, overlay, overlayText

local function render()
  for r = 1, N do for c = 1, N do
    local col = PAL[state.grid[r][c]]
    cells[r][c]:SetColorTexture(col[1], col[2], col[3], 1)
  end end
  ns.SetInfo("Moves  " .. state.moves .. " / " .. state.maxMoves)
end

local function finish()
  overlayText:SetText(state.won and ("|cff9be7a0Flooded!|r\n" .. state.moves .. " moves")
    or "|cffff6677Out of moves|r")
  overlay:Show()
end

local function newGame() state = Logic.new(N, K, 25); overlay:Hide(); render() end

local function onPick(color)
  if not state or state.over then return end
  if not Logic.pick(state, color) then return end
  render(); ns.Sound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION)
  if state.over then
    if state.won then ns.SubmitBest("floodit", ns.Best("floodit") + 1) end
    finish()
  end
end

local function build(content)
  frame = CreateFrame("Frame", nil, content); frame:SetAllPoints()
  local board = CreateFrame("Frame", nil, frame)
  board:SetSize(N * SIZE, N * SIZE); board:SetPoint("TOP", 0, -8)
  cells = {}
  for r = 1, N do
    cells[r] = {}
    for c = 1, N do
      local t = board:CreateTexture(nil, "ARTWORK")
      t:SetSize(SIZE - 1, SIZE - 1)
      t:SetPoint("TOPLEFT", (c - 1) * SIZE, -(r - 1) * SIZE)
      cells[r][c] = t
    end
  end
  pickers = {}
  local pw = 56
  for i = 1, K do
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(pw, 30)
    b:SetPoint("BOTTOM", frame, "BOTTOM", (i - (K + 1) / 2) * (pw + 6), 8)
    local t = b:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints()
    t:SetColorTexture(PAL[i][1], PAL[i][2], PAL[i][3], 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
    b.color = i
    b:SetScript("OnClick", function(self) onPick(self.color) end)
    pickers[i] = b
  end

  overlay = CreateFrame("Frame", nil, frame); overlay:SetAllPoints(board)
  overlay:SetFrameLevel(board:GetFrameLevel() + 20)
  local obg = overlay:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints(); obg:SetColorTexture(0.05, 0.03, 0.09, 0.82)
  overlayText = ns.Header(overlay, "", 20); overlayText:SetPoint("CENTER", 0, 16)
  local again = ns.NewButton(overlay, "Play Again", 120, 26, function() newGame() end); again:SetPoint("CENTER", 0, -30)
  overlay:Hide()
end

local function start(content) if not frame then build(content) end frame:Show(); newGame() end
local function stop() if frame then frame:Hide() end end

ns.Register({ id = "floodit", name = "Flood It", desc = "One colour, before moves run out.",
              category = "Puzzle", icon = "Interface\\Icons\\Spell_Frost_Glacier", start = start, stop = stop })
