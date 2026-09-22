--[[ Azeroth Arcade — Tic-Tac-Toe vs an unbeatable AI.  You are X. ]]
local ADDON, ns = ...

local Logic = {}
ns.logic["tictactoe"] = Logic

local LINES = { { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 }, { 1, 4, 7 }, { 2, 5, 8 },
                { 3, 6, 9 }, { 1, 5, 9 }, { 3, 5, 7 } }

function Logic.winnerOf(b)          -- 0 none, 1 X, 2 O, 3 draw
  for _, l in ipairs(LINES) do
    local a = b[l[1]]
    if a ~= 0 and a == b[l[2]] and a == b[l[3]] then return a end
  end
  for i = 1, 9 do if b[i] == 0 then return 0 end end
  return 3
end

-- minimax: AI is player 2 (maximizing). returns score, move
function Logic.minimax(b, player)
  local w = Logic.winnerOf(b)
  if w == 2 then return 10, nil end
  if w == 1 then return -10, nil end
  if w == 3 then return 0, nil end
  local best, bestMove
  for i = 1, 9 do
    if b[i] == 0 then
      b[i] = player
      local score = Logic.minimax(b, player == 1 and 2 or 1)
      b[i] = 0
      if player == 2 then
        if not best or score > best then best, bestMove = score, i end
      else
        if not best or score < best then best, bestMove = score, i end
      end
    end
  end
  return best, bestMove
end

function Logic.aiMove(s)
  local _, m = Logic.minimax(s.board, 2)
  return m
end

function Logic.new()
  local b = {}
  for i = 1, 9 do b[i] = 0 end
  return { board = b, turn = 1, over = false, winner = 0 }
end

function Logic.move(s, i)
  if s.over or s.board[i] ~= 0 then return false end
  s.board[i] = s.turn
  s.winner = Logic.winnerOf(s.board)
  if s.winner ~= 0 then s.over = true else s.turn = (s.turn == 1) and 2 or 1 end
  return true
end

------------------------------------------------------------------------
-- View
------------------------------------------------------------------------
local SIZE, GAP = 122, 10
local frame, cells, state, overlay, overlayText, busy

local function render()
  for i = 1, 9 do
    local v = state.board[i]
    cells[i].fs:SetText(v == 1 and "X" or v == 2 and "O" or "")
    if v == 1 then cells[i].fs:SetTextColor(ns.C.accentLite[1], ns.C.accentLite[2], ns.C.accentLite[3])
    elseif v == 2 then cells[i].fs:SetTextColor(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3]) end
  end
end

local function finish()
  if state.winner == 1 then overlayText:SetText("|cff9be7a0You win!|r")
  elseif state.winner == 2 then overlayText:SetText("|cffff6677The AI wins|r")
  else overlayText:SetText("|cffe9d5a0Draw|r") end
  overlay:Show()
end

local function newGame() state = Logic.new(); busy = false; overlay:Hide(); render() end

local function onCell(i)
  if busy or not state or state.over then return end
  if not Logic.move(state, i) then return end
  render(); ns.Sound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION)
  if state.over then finish(); return end
  busy = true
  C_Timer.After(0.35, ns.Safe(function()
    local m = Logic.aiMove(state)
    if m then Logic.move(state, m) end
    render(); busy = false
    if state.over then finish() end
  end))
end

local function build(content)
  frame = CreateFrame("Frame", nil, content); frame:SetAllPoints()
  local board = CreateFrame("Frame", nil, frame)
  board:SetSize(3 * SIZE + 4 * GAP, 3 * SIZE + 4 * GAP); board:SetPoint("TOP", 0, -14)
  local bbg = board:CreateTexture(nil, "BACKGROUND"); bbg:SetAllPoints()
  bbg:SetColorTexture(ns.C.line[1], ns.C.line[2], ns.C.line[3], 0.55)   -- gaps read as bright grid lines
  cells = {}
  for i = 1, 9 do
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    local b = CreateFrame("Button", nil, board)
    b:SetSize(SIZE, SIZE)
    b:SetPoint("TOPLEFT", GAP + col * (SIZE + GAP), -(GAP + row * (SIZE + GAP)))
    local bgt = b:CreateTexture(nil, "BACKGROUND"); bgt:SetAllPoints()
    ns.Grad(bgt, "VERTICAL", ns.C.cell, ns.C.cellLo)
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont(ns.FONT_FANCY, 64); b.fs:SetPoint("CENTER")
    b.i = i
    b:SetScript("OnClick", function(self) onCell(self.i) end)
    cells[i] = b
  end
  local newBtn = ns.NewButton(frame, "New Game", 120, 26, function() newGame() end)
  newBtn:SetPoint("BOTTOM", 0, 8)

  overlay = CreateFrame("Frame", nil, frame); overlay:SetAllPoints(board)
  overlay:SetFrameLevel(board:GetFrameLevel() + 20)
  local obg = overlay:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints(); obg:SetColorTexture(0.05, 0.03, 0.09, 0.82)
  overlayText = ns.Header(overlay, "", 22); overlayText:SetPoint("CENTER", 0, 18)
  local again = ns.NewButton(overlay, "Play Again", 120, 26, function() newGame() end); again:SetPoint("CENTER", 0, -26)
  overlay:Hide()
end

local function start(content) if not frame then build(content) end frame:Show(); newGame() end
local function stop() if frame then frame:Hide() end end

ns.Register({ id = "tictactoe", name = "Tic-Tac-Toe", desc = "Beat the unbeatable AI.",
              category = "Vs AI", icon = "Interface\\Icons\\INV_Misc_Rune_01", start = start, stop = stop })
