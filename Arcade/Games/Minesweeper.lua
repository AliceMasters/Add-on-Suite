--[[ Azeroth Arcade — Minesweeper.  Left-click reveal, right-click flag. ]]
local ADDON, ns = ...

------------------------------------------------------------------------
-- Pure logic
------------------------------------------------------------------------
local Logic = {}
ns.logic["minesweeper"] = Logic

function Logic.new(n, mines)
  n = n or 9; mines = mines or 10
  local s = { n = n, mines = mines, mine = {}, adj = {}, revealed = {}, flagged = {},
              over = false, win = false, placed = false, cellsLeft = n * n - mines }
  for r = 1, n do
    s.mine[r] = {}; s.adj[r] = {}; s.revealed[r] = {}; s.flagged[r] = {}
    for c = 1, n do
      s.mine[r][c] = false; s.adj[r][c] = 0
      s.revealed[r][c] = false; s.flagged[r][c] = false
    end
  end
  return s
end

function Logic.placeMines(s, sr, sc, rng)
  rng = rng or math.random
  local forbidden = {}
  for dr = -1, 1 do for dc = -1, 1 do
    local r, c = sr + dr, sc + dc
    if r >= 1 and r <= s.n and c >= 1 and c <= s.n then forbidden[r * 100 + c] = true end
  end end
  local cells = {}
  for r = 1, s.n do for c = 1, s.n do
    if not forbidden[r * 100 + c] then cells[#cells + 1] = { r, c } end
  end end
  local count = math.min(s.mines, #cells)
  for i = 1, count do
    local j = i - 1 + rng(#cells - i + 1)
    cells[i], cells[j] = cells[j], cells[i]
    s.mine[cells[i][1]][cells[i][2]] = true
  end
  s.mines = count
  for r = 1, s.n do for c = 1, s.n do
    if not s.mine[r][c] then
      local a = 0
      for dr = -1, 1 do for dc = -1, 1 do
        local nr, nc = r + dr, c + dc
        if (dr ~= 0 or dc ~= 0) and nr >= 1 and nr <= s.n and nc >= 1 and nc <= s.n and s.mine[nr][nc] then
          a = a + 1
        end
      end end
      s.adj[r][c] = a
    end
  end end
  s.placed = true
end

function Logic.reveal(s, r, c, rng)
  if s.over or s.revealed[r][c] or s.flagged[r][c] then return end
  if not s.placed then Logic.placeMines(s, r, c, rng) end
  if s.mine[r][c] then
    s.over = true; s.win = false
    for rr = 1, s.n do for cc = 1, s.n do if s.mine[rr][cc] then s.revealed[rr][cc] = true end end end
    return
  end
  local stack = { { r, c } }
  while #stack > 0 do
    local cell = table.remove(stack)
    local cr, cc = cell[1], cell[2]
    if not s.revealed[cr][cc] and not s.flagged[cr][cc] and not s.mine[cr][cc] then
      s.revealed[cr][cc] = true
      s.cellsLeft = s.cellsLeft - 1
      if s.adj[cr][cc] == 0 then
        for dr = -1, 1 do for dc = -1, 1 do
          local nr, nc = cr + dr, cc + dc
          if (dr ~= 0 or dc ~= 0) and nr >= 1 and nr <= s.n and nc >= 1 and nc <= s.n
             and not s.revealed[nr][nc] then
            stack[#stack + 1] = { nr, nc }
          end
        end end
      end
    end
  end
  if s.cellsLeft <= 0 then s.over = true; s.win = true end
end

function Logic.toggleFlag(s, r, c)
  if s.over or s.revealed[r][c] then return end
  s.flagged[r][c] = not s.flagged[r][c]
end

function Logic.flagsUsed(s)
  local n = 0
  for r = 1, s.n do for c = 1, s.n do if s.flagged[r][c] then n = n + 1 end end end
  return n
end

------------------------------------------------------------------------
-- View
------------------------------------------------------------------------
local NUMCOL = {
  [1] = { 0.35, 0.55, 1.0 }, [2] = { 0.25, 0.75, 0.3 }, [3] = { 0.95, 0.35, 0.35 },
  [4] = { 0.55, 0.4, 0.95 }, [5] = { 0.8, 0.35, 0.2 }, [6] = { 0.2, 0.8, 0.8 },
  [7] = { 0.9, 0.9, 0.9 }, [8] = { 0.7, 0.7, 0.7 },
}
local N, MINES, SIZE, GAP = 9, 10, 44, 2
local frame, cells, state, overlay, overlayText

local function renderCell(r, c)
  local cell = cells[r][c]
  local flagged, revealed, mine, adj = state.flagged[r][c], state.revealed[r][c], state.mine[r][c], state.adj[r][c]
  cell.mark:Hide(); cell.fs:SetText("")
  if flagged then
    cell.bg:SetColorTexture(0.34, 0.34, 0.38, 1)
    cell.mark:SetColorTexture(0.90, 0.15, 0.15); cell.mark:Show()
  elseif not revealed then
    cell.bg:SetColorTexture(0.34, 0.34, 0.38, 1)
  elseif mine then
    cell.bg:SetColorTexture(0.55, 0.10, 0.10, 1)
    cell.mark:SetColorTexture(0, 0, 0); cell.mark:Show()
  else
    cell.bg:SetColorTexture(0.13, 0.13, 0.15, 1)
    if adj > 0 then
      cell.fs:SetText(tostring(adj))
      local col = NUMCOL[adj]; cell.fs:SetTextColor(col[1], col[2], col[3])
    end
  end
end

local function render()
  for r = 1, N do for c = 1, N do renderCell(r, c) end end
  ns.SetInfo("Mines: " .. (state.mines - Logic.flagsUsed(state)))
end

local function newGame()
  state = Logic.new(N, MINES)
  overlay:Hide()
  render()
end

local function afterMove()
  render()
  if state.over then
    if state.win then
      overlayText:SetText("|cff40ff40Cleared!|r")
      ns.SubmitBest("minesweeper", ns.Best("minesweeper") + 1)  -- best = total clears
      ns.Unlock("sweep")
      ns.Sound(SOUNDKIT and SOUNDKIT.LEVELUP)
    else
      overlayText:SetText("|cffff4040Boom!|r")
      ns.Sound(SOUNDKIT and SOUNDKIT.IG_QUEST_FAILED)
    end
    overlay:Show()
  end
end

local function build(content)
  frame = CreateFrame("Frame", nil, content)
  frame:SetAllPoints()

  local board = CreateFrame("Frame", nil, frame)
  local dim = N * SIZE + (N + 1) * GAP
  board:SetSize(dim, dim)
  board:SetPoint("TOP", 0, -4)

  cells = {}
  for r = 1, N do
    cells[r] = {}
    for c = 1, N do
      local b = CreateFrame("Button", nil, board)
      b:SetSize(SIZE, SIZE)
      b:SetPoint("TOPLEFT", GAP + (c - 1) * (SIZE + GAP), -(GAP + (r - 1) * (SIZE + GAP)))
      b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
      b.mark = b:CreateTexture(nil, "ARTWORK"); b.mark:SetSize(16, 16); b.mark:SetPoint("CENTER"); b.mark:Hide()
      b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); b.fs:SetPoint("CENTER")
      local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.12)
      b.r, b.c = r, c
      b:SetScript("OnClick", function(self, button)
        if state.over then return end
        if button == "RightButton" then
          Logic.toggleFlag(state, self.r, self.c)
        else
          Logic.reveal(state, self.r, self.c)
        end
        afterMove()
      end)
      cells[r][c] = b
    end
  end

  local newBtn = ns.NewButton(frame, "New Game", 110, 22, function() newGame() end)
  newBtn:SetPoint("BOTTOMLEFT", 4, 4)
  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMRIGHT", -6, 8)
  hint:SetText("Left: reveal  •  Right: flag")

  overlay = CreateFrame("Frame", nil, frame)
  overlay:SetAllPoints(board); overlay:SetFrameLevel(board:GetFrameLevel() + 20)
  local obg = overlay:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints(); obg:SetColorTexture(0, 0, 0, 0.7)
  overlayText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge"); overlayText:SetPoint("CENTER", 0, 20)
  local again = ns.NewButton(overlay, "Play Again", 120, 26, function() newGame() end)
  again:SetPoint("CENTER", 0, -28)
  overlay:Hide()
end

local function start(content)
  if not frame then build(content) end
  frame:Show()
  newGame()
end

local function stop()
  if frame then frame:Hide() end
end

ns.Register({ category = "Puzzle", id = "minesweeper", name = "Minesweeper", desc = "Clear the field, flag the mines.",
              icon = "Interface\\Icons\\Spell_Fire_SelfDestruct", start = start, stop = stop })
