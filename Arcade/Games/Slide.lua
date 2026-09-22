--[[ Azeroth Arcade — Sliding Puzzle.  Slide tiles into order; 0 is the gap. ]]
local ADDON, ns = ...

local Logic = {}
ns.logic["slide"] = Logic

local function findBlank(s)
  for r = 1, s.n do for c = 1, s.n do if s.grid[r][c] == 0 then return r, c end end end
end

function Logic.isSolved(s)
  local k = 1
  for r = 1, s.n do for c = 1, s.n do
    if r == s.n and c == s.n then return s.grid[r][c] == 0 end
    if s.grid[r][c] ~= k then return false end
    k = k + 1
  end end
  return true
end

-- try to slide the tile at (r,c) into an orthogonally-adjacent blank
function Logic.move(s, r, c)
  local br, bc = findBlank(s)
  if math.abs(br - r) + math.abs(bc - c) ~= 1 then return false end
  s.grid[br][bc], s.grid[r][c] = s.grid[r][c], s.grid[br][bc]
  s.moves = s.moves + 1
  s.solved = Logic.isSolved(s)
  return true
end

function Logic.new(n, rng)
  rng = rng or math.random
  n = n or 4
  local s = { n = n, grid = {}, moves = 0, solved = false }
  local k = 1
  for r = 1, n do s.grid[r] = {}; for c = 1, n do s.grid[r][c] = (r == n and c == n) and 0 or k; k = k + 1 end end
  -- shuffle by random legal slides (guarantees solvability); avoid trivial
  local br, bc = n, n
  for _ = 1, 200 do
    local opts = {}
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      local nr, nc = br + d[1], bc + d[2]
      if nr >= 1 and nr <= n and nc >= 1 and nc <= n then opts[#opts + 1] = { nr, nc } end
    end
    local pick = opts[rng(#opts)]
    s.grid[br][bc], s.grid[pick[1]][pick[2]] = s.grid[pick[1]][pick[2]], s.grid[br][bc]
    br, bc = pick[1], pick[2]
  end
  s.solved = Logic.isSolved(s)
  return s
end

------------------------------------------------------------------------
-- View
------------------------------------------------------------------------
local N, SIZE, GAP = 4, 96, 6
local frame, cells, state, overlay, overlayText

local function render()
  for r = 1, N do for c = 1, N do
    local v = state.grid[r][c]
    local b = cells[r][c]
    if v == 0 then b:Hide()
    else
      b:Show(); b.fs:SetText(tostring(v))
      ns.Grad(b.bg, "VERTICAL", { ns.C.accent[1] * 0.75, ns.C.accent[2] * 0.75, ns.C.accent[3] * 0.75 }, ns.C.accentLite)
    end
  end end
  ns.SetInfo("Moves  " .. state.moves)
end

local function newGame() state = Logic.new(N); overlay:Hide(); render() end

local function onCell(r, c)
  if not state or state.solved then return end
  if Logic.move(state, r, c) then
    render(); ns.Sound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION)
    if state.solved then
      ns.SubmitBest("slide", ns.Best("slide") + 1)
      overlayText:SetText("|cff9be7a0Solved!|r\n" .. state.moves .. " moves")
      overlay:Show(); ns.Sound(SOUNDKIT and SOUNDKIT.LEVELUP)
    end
  end
end

local function build(content)
  frame = CreateFrame("Frame", nil, content); frame:SetAllPoints()
  local board = CreateFrame("Frame", nil, frame)
  board:SetSize(N * SIZE + (N + 1) * GAP, N * SIZE + (N + 1) * GAP); board:SetPoint("TOP", 0, -14)
  cells = {}
  for r = 1, N do
    cells[r] = {}
    for c = 1, N do
      local b = CreateFrame("Button", nil, board)
      b:SetSize(SIZE, SIZE)
      b:SetPoint("TOPLEFT", GAP + (c - 1) * (SIZE + GAP), -(GAP + (r - 1) * (SIZE + GAP)))
      b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
      local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.10)
      b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont(ns.FONT_FANCY, 34)
      b.fs:SetTextColor(ns.C.text[1], ns.C.text[2], ns.C.text[3]); b.fs:SetPoint("CENTER")
      b.r, b.c = r, c
      b:SetScript("OnClick", function(self) onCell(self.r, self.c) end)
      cells[r][c] = b
    end
  end
  local newBtn = ns.NewButton(frame, "Shuffle", 120, 26, function() newGame() end)
  newBtn:SetPoint("BOTTOM", 0, 8)

  overlay = CreateFrame("Frame", nil, frame); overlay:SetAllPoints(board)
  overlay:SetFrameLevel(board:GetFrameLevel() + 20)
  local obg = overlay:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints(); obg:SetColorTexture(0.05, 0.03, 0.09, 0.82)
  overlayText = ns.Header(overlay, "", 20); overlayText:SetPoint("CENTER", 0, 16)
  local again = ns.NewButton(overlay, "Play Again", 120, 26, function() newGame() end); again:SetPoint("CENTER", 0, -30)
  overlay:Hide()
end

local function start(content) if not frame then build(content) end frame:Show(); newGame() end
local function stop() if frame then frame:Hide() end end

ns.Register({ id = "slide", name = "Sliding Puzzle", desc = "Slide the tiles into order.",
              category = "Puzzle", icon = "Interface\\Icons\\INV_Misc_Rune_06", start = start, stop = stop })
