--[[ Azeroth Arcade — 2048.  Slide tiles; equal tiles merge; reach 2048. ]]
local ADDON, ns = ...

local N = 4

------------------------------------------------------------------------
-- Pure logic (no frames) — fully unit/integration tested in tests/
------------------------------------------------------------------------
local Logic = {}
ns.logic["2048"] = Logic

-- Slide one line of length n toward index 1, merging equal neighbours once.
-- Returns newLine, pointsGained, moved(bool).
function Logic.slideLine(line, n)
  local tiles = {}
  for i = 1, n do if line[i] ~= 0 then tiles[#tiles + 1] = line[i] end end
  local out, gained, i = {}, 0, 1
  while i <= #tiles do
    if tiles[i + 1] and tiles[i + 1] == tiles[i] then
      local m = tiles[i] * 2
      out[#out + 1] = m; gained = gained + m; i = i + 2
    else
      out[#out + 1] = tiles[i]; i = i + 1
    end
  end
  for j = #out + 1, n do out[j] = 0 end
  local moved = false
  for j = 1, n do if out[j] ~= line[j] then moved = true; break end end
  return out, gained, moved
end

local function getLine(grid, dir, idx, n)
  local line = {}
  for k = 1, n do
    if dir == "left" then line[k] = grid[idx][k]
    elseif dir == "right" then line[k] = grid[idx][n - k + 1]
    elseif dir == "up" then line[k] = grid[k][idx]
    else line[k] = grid[n - k + 1][idx] end   -- down
  end
  return line
end

local function setLine(grid, dir, idx, n, line)
  for k = 1, n do
    if dir == "left" then grid[idx][k] = line[k]
    elseif dir == "right" then grid[idx][n - k + 1] = line[k]
    elseif dir == "up" then grid[k][idx] = line[k]
    else grid[n - k + 1][idx] = line[k] end   -- down
  end
end

function Logic.spawn(s, rng)
  rng = rng or math.random
  local empties = {}
  for r = 1, s.n do for c = 1, s.n do
    if s.grid[r][c] == 0 then empties[#empties + 1] = { r, c } end
  end end
  if #empties == 0 then return false end
  local pick = empties[rng(#empties)]
  s.grid[pick[1]][pick[2]] = (rng(10) == 1) and 4 or 2
  return true
end

function Logic.canMove(s)
  local n, grid = s.n, s.grid
  for r = 1, n do for c = 1, n do
    if grid[r][c] == 0 then return true end
    if c < n and grid[r][c] == grid[r][c + 1] then return true end
    if r < n and grid[r][c] == grid[r + 1][c] then return true end
  end end
  return false
end

function Logic.hasWon(s)
  for r = 1, s.n do for c = 1, s.n do if s.grid[r][c] >= 2048 then return true end end end
  return false
end

function Logic.new(rng)
  local s = { grid = {}, score = 0, won = false, over = false, n = N }
  for r = 1, N do s.grid[r] = {}; for c = 1, N do s.grid[r][c] = 0 end end
  Logic.spawn(s, rng); Logic.spawn(s, rng)
  return s
end

-- Apply a move. dir in {left,right,up,down}. Spawns a tile if anything moved.
function Logic.move(s, dir, rng)
  if s.over then return false end
  local n, grid, moved, gained = s.n, s.grid, false, 0
  for idx = 1, n do
    local line = getLine(grid, dir, idx, n)
    local out, g, m = Logic.slideLine(line, n)
    gained = gained + g
    if m then moved = true; setLine(grid, dir, idx, n, out) end
  end
  if moved then
    s.score = s.score + gained
    if Logic.hasWon(s) then s.won = true end
    Logic.spawn(s, rng)
    if not Logic.canMove(s) then s.over = true end
  end
  return moved
end

------------------------------------------------------------------------
-- View
------------------------------------------------------------------------
local TILE_COLOR = {
  [0]    = { 0.16, 0.15, 0.14 }, [2] = { 0.78, 0.75, 0.70 }, [4] = { 0.80, 0.71, 0.52 },
  [8]    = { 0.90, 0.60, 0.35 }, [16] = { 0.92, 0.50, 0.30 }, [32] = { 0.93, 0.40, 0.30 },
  [64]   = { 0.93, 0.29, 0.20 }, [128] = { 0.90, 0.78, 0.36 }, [256] = { 0.90, 0.77, 0.30 },
  [512]  = { 0.91, 0.76, 0.24 }, [1024] = { 0.92, 0.75, 0.18 }, [2048] = { 0.94, 0.73, 0.10 },
}
local function tileColor(v)
  return TILE_COLOR[v] or { 0.20, 0.20, 0.28 }
end

local SIZE = 96
local GAP = 8
local frame, tiles, state, overlay, overlayText

local function render()
  for r = 1, N do
    for c = 1, N do
      local v = state.grid[r][c]
      local t = tiles[r][c]
      local col = tileColor(v)
      t.bg:SetColorTexture(col[1], col[2], col[3], 1)
      if v == 0 then
        t.fs:SetText("")
      else
        t.fs:SetText(tostring(v))
        if v <= 4 then t.fs:SetTextColor(0.20, 0.18, 0.15) else t.fs:SetTextColor(1, 1, 1) end
      end
    end
  end
end

local function newGame()
  state = Logic.new()
  overlay:Hide()
  render()
  ns.SetScore(0)
end

local function doMove(dir)
  if not state or state.over then return end
  if Logic.move(state, dir) then
    ns.Sound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION)
    render()
    ns.SetScore(state.score)
    ns.SubmitBest("2048", state.score)
    for r = 1, N do for c = 1, N do if state.grid[r][c] >= 512 then ns.Unlock("t512") end end end
    if state.over then
      overlayText:SetText("Game Over\n|cffffd200Score " .. state.score .. "|r")
      overlay:Show()
    end
  end
end

local KEYDIR = { LEFT = "left", A = "left", RIGHT = "right", D = "right",
                 UP = "up", W = "up", DOWN = "down", S = "down" }

local function build(content)
  frame = CreateFrame("Frame", nil, content)
  frame:SetAllPoints()

  local board = CreateFrame("Frame", nil, frame)
  local dim = N * SIZE + (N + 1) * GAP
  board:SetSize(dim, dim)
  board:SetPoint("TOP", 0, -4)
  local bbg = board:CreateTexture(nil, "BACKGROUND")
  bbg:SetAllPoints(); bbg:SetColorTexture(0, 0, 0, 0.5)

  tiles = {}
  for r = 1, N do
    tiles[r] = {}
    for c = 1, N do
      local t = CreateFrame("Frame", nil, board)
      t:SetSize(SIZE, SIZE)
      t:SetPoint("TOPLEFT", GAP + (c - 1) * (SIZE + GAP), -(GAP + (r - 1) * (SIZE + GAP)))
      t.bg = t:CreateTexture(nil, "BACKGROUND"); t.bg:SetAllPoints()
      t.fs = t:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
      t.fs:SetPoint("CENTER")
      tiles[r][c] = t
    end
  end

  -- controls
  local newBtn = ns.NewButton(frame, "New Game (N)", 120, 22, function() newGame() end)
  newBtn:SetPoint("BOTTOMLEFT", 4, 4)
  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMRIGHT", -6, 8)
  hint:SetText("Arrow keys / WASD")

  -- game-over overlay
  overlay = CreateFrame("Frame", nil, frame)
  overlay:SetAllPoints(board); overlay:SetFrameLevel(board:GetFrameLevel() + 10)
  local obg = overlay:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints()
  obg:SetColorTexture(0, 0, 0, 0.72)
  overlayText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  overlayText:SetPoint("CENTER", 0, 24)
  local again = ns.NewButton(overlay, "Play Again", 120, 26, function() newGame() end)
  again:SetPoint("CENTER", 0, -30)
  overlay:Hide()

  frame:EnableKeyboard(true)
  frame:SetScript("OnKeyDown", function(self, key)
    if key == "N" then newGame(); self:SetPropagateKeyboardInput(false); return end
    local dir = KEYDIR[key]
    if dir then self:SetPropagateKeyboardInput(false); doMove(dir)
    else self:SetPropagateKeyboardInput(true) end
  end)
end

local function start(content)
  if not frame then build(content) end
  frame:Show()
  frame:EnableKeyboard(true)
  newGame()
end

local function stop()
  if frame then frame:EnableKeyboard(false); frame:Hide() end
end

ns.Register({ category = "Arcade", id = "2048", name = "2048", desc = "Slide tiles, merge to 2048.",
              icon = "Interface\\Icons\\INV_Misc_Dice_02", start = start, stop = stop })
