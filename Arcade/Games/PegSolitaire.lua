--[[ Azeroth Arcade — Peg Solitaire.  Jump pegs over pegs; finish with one. ]]
local ADDON, ns = ...

local Logic = {}
ns.logic["pegs"] = Logic

function Logic.valid(r, c)
  if r < 1 or r > 7 or c < 1 or c > 7 then return false end
  return not ((r <= 2 or r >= 6) and (c <= 2 or c >= 6))
end

function Logic.new()
  local g = {}
  for r = 1, 7 do
    g[r] = {}
    for c = 1, 7 do
      if not Logic.valid(r, c) then g[r][c] = -1
      elseif r == 4 and c == 4 then g[r][c] = 0
      else g[r][c] = 1 end
    end
  end
  return { grid = g, moves = 0, solved = false }
end

function Logic.pegs(s)
  local n = 0
  for r = 1, 7 do for c = 1, 7 do if s.grid[r][c] == 1 then n = n + 1 end end end
  return n
end

function Logic.canMove(s, r, c, tr, tc)
  if not Logic.valid(r, c) or not Logic.valid(tr, tc) then return false end
  if s.grid[r][c] ~= 1 or s.grid[tr][tc] ~= 0 then return false end
  local dr, dc = tr - r, tc - c
  if not ((math.abs(dr) == 2 and dc == 0) or (math.abs(dc) == 2 and dr == 0)) then return false end
  local mr, mc = (r + tr) / 2, (c + tc) / 2
  return s.grid[mr][mc] == 1
end

function Logic.move(s, r, c, tr, tc)
  if not Logic.canMove(s, r, c, tr, tc) then return false end
  s.grid[r][c] = 0
  s.grid[(r + tr) / 2][(c + tc) / 2] = 0
  s.grid[tr][tc] = 1
  s.moves = s.moves + 1
  s.solved = (Logic.pegs(s) == 1)
  return true
end

function Logic.hasMoves(s)
  for r = 1, 7 do for c = 1, 7 do
    if s.grid[r][c] == 1 then
      for _, d in ipairs({ { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }) do
        if Logic.canMove(s, r, c, r + d[1], c + d[2]) then return true end
      end
    end
  end end
  return false
end

------------------------------------------------------------------------
-- View
------------------------------------------------------------------------
local SIZE, GAP = 50, 4
local frame, cells, state, sel, overlay, overlayText

local function render()
  for r = 1, 7 do for c = 1, 7 do
    local v = state.grid[r][c]
    local cell = cells[r][c]
    if v == -1 then cell:Hide()
    else
      cell:Show()
      if v == 1 then
        ns.Grad(cell.disc, "VERTICAL", { ns.C.accent[1] * 0.8, ns.C.accent[2] * 0.8, ns.C.accent[3] * 0.8 }, ns.C.accentLite)
        cell.disc:Show()
      else cell.disc:Hide() end
      cell.selg:SetShown(sel ~= nil and sel[1] == r and sel[2] == c)
    end
  end end
  ns.SetInfo("Pegs  " .. Logic.pegs(state))
end

local function finish()
  overlayText:SetText(state.solved and "|cff9be7a0Perfect! One peg left.|r"
    or ("|cffff9955Stuck |r|cffe9d5a0" .. Logic.pegs(state) .. " pegs left|r"))
  overlay:Show()
end

local function newGame() state = Logic.new(); sel = nil; overlay:Hide(); render() end

local function onCell(r, c)
  if state.solved then return end
  if state.grid[r][c] == 1 then
    sel = { r, c }; render()
  elseif state.grid[r][c] == 0 and sel then
    if Logic.move(state, sel[1], sel[2], r, c) then
      sel = nil; render(); ns.Sound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION)
      if state.solved then ns.SubmitBest("pegs", ns.Best("pegs") + 1); finish()
      elseif not Logic.hasMoves(state) then finish() end
    end
  end
end

local function build(content)
  frame = CreateFrame("Frame", nil, content); frame:SetAllPoints()
  local board = CreateFrame("Frame", nil, frame)
  board:SetSize(7 * SIZE + 8 * GAP, 7 * SIZE + 8 * GAP); board:SetPoint("TOP", 0, -12)
  cells = {}
  for r = 1, 7 do
    cells[r] = {}
    for c = 1, 7 do
      local b = CreateFrame("Button", nil, board)
      b:SetSize(SIZE, SIZE)
      b:SetPoint("TOPLEFT", GAP + (c - 1) * (SIZE + GAP), -(GAP + (r - 1) * (SIZE + GAP)))
      local hole = b:CreateTexture(nil, "BACKGROUND"); hole:SetAllPoints()
      ns.Grad(hole, "VERTICAL", ns.C.panelLo, ns.C.bg2)
      b.selg = b:CreateTexture(nil, "BORDER"); b.selg:SetAllPoints(); b.selg:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], 0.35); b.selg:Hide()
      b.disc = b:CreateTexture(nil, "ARTWORK"); b.disc:SetPoint("TOPLEFT", 6, -6); b.disc:SetPoint("BOTTOMRIGHT", -6, 6)
      local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
      b.r, b.c = r, c
      b:SetScript("OnClick", function(self) onCell(self.r, self.c) end)
      cells[r][c] = b
    end
  end
  local newBtn = ns.NewButton(frame, "New Game", 120, 26, function() newGame() end)
  newBtn:SetPoint("BOTTOM", 0, 8)

  overlay = CreateFrame("Frame", nil, frame); overlay:SetAllPoints(board)
  overlay:SetFrameLevel(board:GetFrameLevel() + 20)
  local obg = overlay:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints(); obg:SetColorTexture(0.05, 0.03, 0.09, 0.82)
  overlayText = ns.Header(overlay, "", 18); overlayText:SetPoint("CENTER", 0, 16)
  local again = ns.NewButton(overlay, "Play Again", 120, 26, function() newGame() end); again:SetPoint("CENTER", 0, -28)
  overlay:Hide()
end

local function start(content) if not frame then build(content) end frame:Show(); newGame() end
local function stop() if frame then frame:Hide() end end

ns.Register({ category = "Puzzle", id = "pegs", name = "Peg Solitaire", desc = "Jump to a single peg.",
              icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_04", start = start, stop = stop })
