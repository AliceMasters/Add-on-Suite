--[[ Azeroth Arcade — Lights Out.  Tap a tile to flip it and its neighbours;
     turn the whole board off. ]]
local ADDON, ns = ...

------------------------------------------------------------------------
-- Pure logic
------------------------------------------------------------------------
local Logic = {}
ns.logic["lightsout"] = Logic

function Logic.flip(s, r, c)   -- toggle a cell + orthogonal neighbours (no move count)
  local n = s.n
  local function tog(rr, cc) if rr >= 1 and rr <= n and cc >= 1 and cc <= n then s.grid[rr][cc] = not s.grid[rr][cc] end end
  tog(r, c); tog(r - 1, c); tog(r + 1, c); tog(r, c - 1); tog(r, c + 1)
end

function Logic.isSolved(s)
  for r = 1, s.n do for c = 1, s.n do if s.grid[r][c] then return false end end end
  return true
end

function Logic.press(s, r, c)
  if s.solved then return false end
  Logic.flip(s, r, c)
  s.moves = s.moves + 1
  s.solved = Logic.isSolved(s)
  return true
end

function Logic.new(n, rng)
  rng = rng or math.random
  n = n or 5
  local s = { n = n, grid = {}, moves = 0, solved = false }
  local tries = 0
  repeat
    for r = 1, n do s.grid[r] = s.grid[r] or {}; for c = 1, n do s.grid[r][c] = false end end
    for _ = 1, 6 + rng(8) do Logic.flip(s, rng(n), rng(n)) end  -- random presses => always solvable
    tries = tries + 1
  until (not Logic.isSolved(s)) or tries > 25
  return s
end

------------------------------------------------------------------------
-- View
------------------------------------------------------------------------
local N, SIZE, GAP = 5, 74, 8
local frame, cells, state, overlay, overlayText

local function renderCell(r, c)
  local b = cells[r][c]
  if state.grid[r][c] then
    ns.Grad(b.bg, "VERTICAL", { ns.C.accent[1] * 0.8, ns.C.accent[2] * 0.8, ns.C.accent[3] * 0.8 }, ns.C.accentLite)
    b.glow:Show()
  else
    ns.Grad(b.bg, "VERTICAL", ns.C.panel, ns.C.panelLo)
    b.glow:Hide()
  end
end

local function render()
  for r = 1, N do for c = 1, N do renderCell(r, c) end end
  ns.SetInfo("Moves  " .. state.moves)
end

local function newGame()
  state = Logic.new(N)
  overlay:Hide()
  render()
end

local function onPress(r, c)
  if not state or state.solved then return end
  Logic.press(state, r, c)
  ns.Sound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION)
  render()
  if state.solved then
    ns.Unlock("lights")
    ns.SubmitBest("lightsout", ns.Best("lightsout") + 1)
    overlayText:SetText("|cffe9d5a0Enlightened|r\nSolved in " .. state.moves .. " moves")
    overlay:Show()
    ns.Sound(SOUNDKIT and SOUNDKIT.LEVELUP)
  end
end

local function build(content)
  frame = CreateFrame("Frame", nil, content); frame:SetAllPoints()
  local board = CreateFrame("Frame", nil, frame)
  local dim = N * SIZE + (N + 1) * GAP
  board:SetSize(dim, dim); board:SetPoint("TOP", 0, -20)

  cells = {}
  for r = 1, N do
    cells[r] = {}
    for c = 1, N do
      local b = CreateFrame("Button", nil, board)
      b:SetSize(SIZE, SIZE)
      b:SetPoint("TOPLEFT", GAP + (c - 1) * (SIZE + GAP), -(GAP + (r - 1) * (SIZE + GAP)))
      b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
      b.glow = b:CreateTexture(nil, "ARTWORK"); b.glow:SetAllPoints()
      b.glow:SetColorTexture(1, 1, 1, 0.10); b.glow:Hide()
      local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.10)
      b.r, b.c = r, c
      b:SetScript("OnClick", function(self) onPress(self.r, self.c) end)
      cells[r][c] = b
    end
  end

  local newBtn = ns.NewButton(frame, "New Puzzle", 120, 26, function() newGame() end)
  newBtn:SetPoint("BOTTOM", 0, 8)

  overlay = CreateFrame("Frame", nil, frame); overlay:SetAllPoints(board)
  overlay:SetFrameLevel(board:GetFrameLevel() + 20)
  local obg = overlay:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints(); obg:SetColorTexture(0.05, 0.03, 0.09, 0.82)
  overlayText = ns.Header(overlay, "", 20); overlayText:SetPoint("CENTER", 0, 20)
  local again = ns.NewButton(overlay, "Play Again", 120, 26, function() newGame() end)
  again:SetPoint("CENTER", 0, -28)
  overlay:Hide()
end

local function start(content) if not frame then build(content) end frame:Show(); newGame() end
local function stop() if frame then frame:Hide() end end

ns.Register({ id = "lightsout", name = "Lights Out", desc = "Turn every tile off.",
              icon = "Interface\\Icons\\Spell_Nature_Lightning", start = start, stop = stop })
