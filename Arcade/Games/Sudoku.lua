--[[ Azeroth Arcade — Sudoku.  Fill the grid so every row, column and box holds 1-9. ]]
local ADDON, ns = ...

-- puzzles generated + solution-verified offline (tests/gen_sudoku.py)
local PUZZLES = {
  { name = "Gentle", diff = "Easy", lives = 5, given = "200100009000000800708509206050306701087490603600871940040203008071904002326700500", solution = "263187459495632817718549236954326781187495623632871945549263178871954362326718594" },
  { name = "Steady", diff = "Easy", lives = 5, given = "470000203100023080000074001802700090607000300509208470960002000050307640003409510", solution = "478691253196523784325874961832746195647915328519238476964152837251387649783469512" },
  { name = "Tricky", diff = "Medium", lives = 4, given = "000010002023070900900006850060080000080090300000100528139050084056040003000901000", solution = "875419632623578941914326857361285479582794316497163528139652784256847193748931265" },
  { name = "Sharp", diff = "Medium", lives = 4, given = "008000205504000060000050381803769000960000000002000096000090450006005003045000600", solution = "138976245524831967679254381813769524967542138452318796381697452796425813245183679" },
  { name = "Fiendish", diff = "Hard", lives = 3, given = "000038700900100300003075000000082530000700060000000071000406000009007040400000057", solution = "146238795957164328283975614714682539395741862628359471571426983839517246462893157" },
}

local Logic = {}
ns.logic["sudoku"] = Logic
Logic.puzzles = PUZZLES

function Logic.new(index)
  local p = PUZZLES[index]
  local s = { grid = {}, fixed = {}, solution = {}, index = index, over = false, won = false }
  for r = 1, 9 do
    s.grid[r] = {}; s.fixed[r] = {}; s.solution[r] = {}
    for c = 1, 9 do
      local i = (r - 1) * 9 + c
      local g = tonumber(p.given:sub(i, i))
      s.grid[r][c] = g
      s.fixed[r][c] = (g ~= 0)
      s.solution[r][c] = tonumber(p.solution:sub(i, i))
    end
  end
  return s
end

function Logic.set(s, r, c, v)
  if s.over or s.fixed[r][c] then return false end
  s.grid[r][c] = v
  if Logic.isSolved(s) then s.won = true; s.over = true end
  return true
end

function Logic.conflict(s, r, c)
  local v = s.grid[r][c]
  if v == 0 then return false end
  for k = 1, 9 do
    if k ~= c and s.grid[r][k] == v then return true end
    if k ~= r and s.grid[k][c] == v then return true end
  end
  local br, bc = r - (r - 1) % 3, c - (c - 1) % 3
  for i = 0, 2 do for j = 0, 2 do
    local rr, cc = br + i, bc + j
    if (rr ~= r or cc ~= c) and s.grid[rr][cc] == v then return true end
  end end
  return false
end

function Logic.isSolved(s)
  for r = 1, 9 do for c = 1, 9 do
    if s.grid[r][c] == 0 or Logic.conflict(s, r, c) then return false end
  end end
  return true
end

------------------------------------------------------------------------
-- View
------------------------------------------------------------------------
local SIZE = 42
local frame, picker, cells, state, sel, overlay, overlayText

local function render()
  for r = 1, 9 do for c = 1, 9 do
    local cell = cells[r][c]
    local v = state.grid[r][c]
    cell.fs:SetText(v == 0 and "" or tostring(v))
    if state.fixed[r][c] then cell.fs:SetTextColor(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3])
    elseif v ~= 0 and Logic.conflict(state, r, c) then cell.fs:SetTextColor(0.95, 0.35, 0.4)
    else cell.fs:SetTextColor(ns.C.text[1], ns.C.text[2], ns.C.text[3]) end
    local shade = ((math.floor((r - 1) / 3) + math.floor((c - 1) / 3)) % 2 == 0) and 0.13 or 0.09
    cell.bg:SetColorTexture(shade, shade * 0.7, shade * 1.3, 1)
    cell.selg:SetShown(sel ~= nil and sel[1] == r and sel[2] == c)
  end end
end

local function newPuzzle(index)
  state = Logic.new(index); sel = nil; overlay:Hide()
  render(); ns.SetInfo(PUZZLES[index].diff .. "  \226\128\162  " .. PUZZLES[index].name)
  picker:Hide(); frame.play:Show()
end

local function place(v)
  if not sel or not state or state.over then return end
  if Logic.set(state, sel[1], sel[2], v) then
    render(); ns.Sound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION)
    if state.won then
      ns.SubmitBest("sudoku", ns.Best("sudoku") + 1)
      overlayText:SetText("|cff9be7a0Solved!|r\n" .. PUZZLES[state.index].name)
      overlay:Show(); ns.Sound(SOUNDKIT and SOUNDKIT.LEVELUP)
    end
  end
end

local function showPicker()
  if frame.play then frame.play:Hide() end
  picker:Show(); ns.SetInfo("")
end

local function buildPlay()
  local play = CreateFrame("Frame", nil, frame); play:SetAllPoints(); play:Hide()
  frame.play = play
  local board = CreateFrame("Frame", nil, play)
  board:SetSize(9 * SIZE + 10, 9 * SIZE + 10); board:SetPoint("TOP", 0, -6)
  cells = {}
  for r = 1, 9 do
    cells[r] = {}
    for c = 1, 9 do
      local b = CreateFrame("Button", nil, board)
      b:SetSize(SIZE - 1, SIZE - 1)
      b:SetPoint("TOPLEFT", 5 + (c - 1) * SIZE, -(5 + (r - 1) * SIZE))
      b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
      b.selg = b:CreateTexture(nil, "BORDER"); b.selg:SetAllPoints(); b.selg:SetColorTexture(ns.C.accentLite[1], ns.C.accentLite[2], ns.C.accentLite[3], 0.4); b.selg:Hide()
      b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont(ns.FONT, 20); b.fs:SetPoint("CENTER")
      local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
      b.r, b.c = r, c
      b:SetScript("OnClick", function(self)
        if not state.fixed[self.r][self.c] then sel = { self.r, self.c }; render() end
      end)
      cells[r][c] = b
    end
  end
  -- bold 3x3 lines
  for i = 0, 9, 3 do
    local v = board:CreateTexture(nil, "OVERLAY"); v:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], 0.5)
    v:SetSize(2, 9 * SIZE + 2); v:SetPoint("TOPLEFT", 5 + i * SIZE - 1, -4)
    local h = board:CreateTexture(nil, "OVERLAY"); h:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], 0.5)
    h:SetSize(9 * SIZE + 2, 2); h:SetPoint("TOPLEFT", 4, -(5 + i * SIZE - 1))
  end
  -- number pad
  for v = 1, 9 do
    local b = ns.NewButton(play, tostring(v), 36, 28, function() place(v) end)
    b:SetPoint("BOTTOMLEFT", 6 + (v - 1) * 40, 34)
  end
  local erase = ns.NewButton(play, "Erase", 80, 26, function() place(0) end); erase:SetPoint("BOTTOMLEFT", 6, 4)
  local pk = ns.NewButton(play, "Puzzles", 90, 26, function() showPicker() end); pk:SetPoint("BOTTOMRIGHT", -6, 4)

  overlay = CreateFrame("Frame", nil, play); overlay:SetAllPoints(board)
  overlay:SetFrameLevel(board:GetFrameLevel() + 20)
  local obg = overlay:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints(); obg:SetColorTexture(0.05, 0.03, 0.09, 0.82)
  overlayText = ns.Header(overlay, "", 20); overlayText:SetPoint("CENTER", 0, 16)
  local again = ns.NewButton(overlay, "More Puzzles", 130, 26, function() showPicker() end); again:SetPoint("CENTER", 0, -30)
  overlay:Hide()
end

local function buildPicker()
  picker = CreateFrame("Frame", nil, frame); picker:SetAllPoints()
  local head = ns.Header(picker, "Choose a puzzle", 18); head:SetPoint("TOP", 0, -8)
  for i, p in ipairs(PUZZLES) do
    local b = ns.NewButton(picker, "", ns.CONTENT_W - 60, 40, function() newPuzzle(i) end)
    b:SetPoint("TOP", 0, -44 - (i - 1) * 48)
    local nm = ns.Header(b, p.name, 14); nm:SetPoint("LEFT", 14, 0)
    local sub = ns.Label(b, p.diff, 11, ns.C.sub); sub:SetPoint("RIGHT", -14, 0)
  end
end

local function build(content)
  frame = CreateFrame("Frame", nil, content); frame:SetAllPoints()
  buildPlay(); buildPicker()
end

local function start(content) if not frame then build(content) end frame:Show(); showPicker() end
local function stop() if frame then frame:Hide() end end

ns.Register({ category = "Puzzle", id = "sudoku", name = "Sudoku", desc = "Fill the classic 9x9 grid.",
              icon = "Interface\\Icons\\INV_Misc_Note_02", start = start, stop = stop })
