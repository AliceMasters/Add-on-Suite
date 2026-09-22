--[[ Azeroth Arcade — Connect Four vs AI.  Drop discs, line up four. You are purple. ]]
local ADDON, ns = ...

local COLS, ROWS = 7, 6
local Logic = {}
ns.logic["connect4"] = Logic

function Logic.new()
  local g = {}
  for r = 1, ROWS do g[r] = {}; for c = 1, COLS do g[r][c] = 0 end end
  return { grid = g, turn = 1, over = false, winner = 0 }
end

function Logic.canDrop(s, c) return c >= 1 and c <= COLS and s.grid[1][c] == 0 end

local function landingRow(s, c)
  for r = ROWS, 1, -1 do if s.grid[r][c] == 0 then return r end end
  return nil
end

function Logic.winnerAt(g)
  local dirs = { { 0, 1 }, { 1, 0 }, { 1, 1 }, { 1, -1 } }
  for r = 1, ROWS do for c = 1, COLS do
    local p = g[r][c]
    if p ~= 0 then
      for _, d in ipairs(dirs) do
        local n = 1
        while n < 4 do
          local nr, nc = r + d[1] * n, c + d[2] * n
          if nr < 1 or nr > ROWS or nc < 1 or nc > COLS or g[nr][nc] ~= p then break end
          n = n + 1
        end
        if n == 4 then return p end
      end
    end
  end end
  return 0
end

function Logic.boardFull(s)
  for c = 1, COLS do if s.grid[1][c] == 0 then return false end end
  return true
end

function Logic.drop(s, c)
  if s.over or not Logic.canDrop(s, c) then return false end
  local r = landingRow(s, c)
  s.grid[r][c] = s.turn
  local w = Logic.winnerAt(s.grid)
  if w ~= 0 then s.winner = w; s.over = true
  elseif Logic.boardFull(s) then s.winner = 3; s.over = true
  else s.turn = (s.turn == 1) and 2 or 1 end
  return true
end

local function wouldWin(s, c, player)
  if not Logic.canDrop(s, c) then return false end
  local r = landingRow(s, c)
  s.grid[r][c] = player
  local w = Logic.winnerAt(s.grid)
  s.grid[r][c] = 0
  return w == player
end

function Logic.aiMove(s)
  for c = 1, COLS do if wouldWin(s, c, 2) then return c end end   -- take the win
  for c = 1, COLS do if wouldWin(s, c, 1) then return c end end   -- block the threat
  for _, c in ipairs({ 4, 3, 5, 2, 6, 1, 7 }) do if Logic.canDrop(s, c) then return c end end
end

------------------------------------------------------------------------
-- View
------------------------------------------------------------------------
local SIZE, GAP = 54, 4
local DISC = { { 0, 0, 0, 0 }, { 0.68, 0.36, 0.88 }, { 0.95, 0.80, 0.22 } }  -- empty, you (purple), AI (gold)
local frame, cells, state, overlay, overlayText, busy

local function render()
  for r = 1, ROWS do for c = 1, COLS do
    local v = state.grid[r][c]
    if v == 0 then ns.Grad(cells[r][c].disc, "VERTICAL", ns.C.cell, ns.C.cellLo)
    else local d = DISC[v + 1]; ns.Grad(cells[r][c].disc, "VERTICAL", { d[1] * 0.75, d[2] * 0.75, d[3] * 0.75 }, d) end
  end end
end

local function finish()
  if state.winner == 1 then overlayText:SetText("|cff9be7a0You win!|r")
  elseif state.winner == 2 then overlayText:SetText("|cffff6677The AI wins|r")
  else overlayText:SetText("|cffe9d5a0Draw|r") end
  overlay:Show()
end

local function newGame() state = Logic.new(); busy = false; overlay:Hide(); render() end

local function onCol(c)
  if busy or not state or state.over then return end
  if not Logic.drop(state, c) then return end
  render(); ns.Sound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION)
  if state.over then finish(); return end
  busy = true
  C_Timer.After(0.35, ns.Safe(function()
    local m = Logic.aiMove(state); if m then Logic.drop(state, m) end
    render(); busy = false
    if state.over then finish() end
  end))
end

local function build(content)
  frame = CreateFrame("Frame", nil, content); frame:SetAllPoints()
  local boardBg = ns.Panel(frame)
  boardBg:SetSize(COLS * SIZE + (COLS + 1) * GAP, ROWS * SIZE + (ROWS + 1) * GAP)
  boardBg:SetPoint("TOP", 0, -20)
  cells = {}
  for r = 1, ROWS do
    cells[r] = {}
    for c = 1, COLS do
      local b = CreateFrame("Button", nil, boardBg)
      b:SetSize(SIZE, SIZE)
      b:SetPoint("TOPLEFT", GAP + (c - 1) * (SIZE + GAP), -(GAP + (r - 1) * (SIZE + GAP)))
      b.disc = b:CreateTexture(nil, "ARTWORK"); b.disc:SetPoint("TOPLEFT", 3, -3); b.disc:SetPoint("BOTTOMRIGHT", -3, 3)
      local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
      b.c = c
      b:SetScript("OnClick", function(self) onCol(self.c) end)
      cells[r][c] = b
    end
  end
  local newBtn = ns.NewButton(frame, "New Game", 120, 26, function() newGame() end)
  newBtn:SetPoint("BOTTOM", 0, 6)

  overlay = CreateFrame("Frame", nil, frame); overlay:SetAllPoints(boardBg)
  overlay:SetFrameLevel(boardBg:GetFrameLevel() + 20)
  local obg = overlay:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints(); obg:SetColorTexture(0.05, 0.03, 0.09, 0.82)
  overlayText = ns.Header(overlay, "", 22); overlayText:SetPoint("CENTER", 0, 18)
  local again = ns.NewButton(overlay, "Play Again", 120, 26, function() newGame() end); again:SetPoint("CENTER", 0, -26)
  overlay:Hide()
end

local function start(content) if not frame then build(content) end frame:Show(); newGame() end
local function stop() if frame then frame:Hide() end end

ns.Register({ id = "connect4", name = "Connect Four", desc = "Line up four vs the AI.",
              category = "Vs AI", icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_03", start = start, stop = stop })
