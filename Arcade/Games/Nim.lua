--[[ Azeroth Arcade — Nim.  Take any number from one row; take the last to win.
     The AI plays the perfect nim-sum strategy. ]]
local ADDON, ns = ...

local Logic = {}
ns.logic["nim"] = Logic

local function xor(a, b)
  local r, p = 0, 1
  while a > 0 or b > 0 do
    if (a % 2) ~= (b % 2) then r = r + p end
    a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
  end
  return r
end

function Logic.nimsum(s)
  local x = 0
  for _, h in ipairs(s.heaps) do x = xor(x, h) end
  return x
end

function Logic.new()
  return { heaps = { 3, 5, 7 }, turn = 1, over = false, winner = 0 }
end

function Logic.empty(s)
  for _, h in ipairs(s.heaps) do if h > 0 then return false end end
  return true
end

function Logic.take(s, heap, count)
  if s.over or not s.heaps[heap] then return false end
  if count < 1 or count > s.heaps[heap] then return false end
  s.heaps[heap] = s.heaps[heap] - count
  if Logic.empty(s) then s.over = true; s.winner = s.turn        -- last to take wins
  else s.turn = (s.turn == 1) and 2 or 1 end
  return true
end

-- perfect play: leave nim-sum 0 when possible, else take 1 from the largest heap
function Logic.aiMove(s)
  local x = Logic.nimsum(s)
  if x ~= 0 then
    for h, cnt in ipairs(s.heaps) do
      local target = xor(cnt, x)
      if target < cnt then return h, cnt - target end
    end
  end
  local bh, bc = 1, 0
  for h, cnt in ipairs(s.heaps) do if cnt > bc then bh, bc = h, cnt end end
  return bh, 1
end

------------------------------------------------------------------------
-- View
------------------------------------------------------------------------
local frame, rows, state, overlay, overlayText, busy

local function render()
  for h, row in ipairs(rows) do
    for i, peg in ipairs(row.pegs) do
      if i <= state.heaps[h] then peg:Show() else peg:Hide() end
    end
  end
  ns.SetInfo(state.over and "" or (state.turn == 1 and "Your turn" or "AI thinking..."))
end

local function finish()
  overlayText:SetText(state.winner == 1 and "|cff9be7a0You win!|r" or "|cffff6677The AI wins|r")
  overlay:Show()
end

local function newGame() state = Logic.new(); busy = false; overlay:Hide(); render() end

local function onPeg(h, i)
  if busy or state.over or state.turn ~= 1 then return end
  local count = state.heaps[h] - i + 1        -- take this peg and all to its right
  if not Logic.take(state, h, count) then return end
  render(); ns.Sound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION)
  if state.over then finish(); return end
  busy = true
  C_Timer.After(0.5, ns.Safe(function()
    local hh, cc = Logic.aiMove(state); Logic.take(state, hh, cc)
    render(); busy = false
    if state.over then finish() end
  end))
end

local function build(content)
  frame = CreateFrame("Frame", nil, content); frame:SetAllPoints()
  local head = ns.Header(frame, "Take the last piece", 16); head:SetPoint("TOP", 0, -6)
  rows = {}
  local maxH = 7
  for h = 1, 3 do
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(maxH * 52, 46); row:SetPoint("TOP", 0, -44 - (h - 1) * 66)
    row.pegs = {}
    local cnt = ({ 3, 5, 7 })[h]
    for i = 1, cnt do
      local b = CreateFrame("Button", nil, row)
      b:SetSize(44, 44); b:SetPoint("LEFT", (i - 1) * 50, 0)
      local t = b:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints()
      ns.Grad(t, "VERTICAL", { ns.C.accent[1] * 0.8, ns.C.accent[2] * 0.8, ns.C.accent[3] * 0.8 }, ns.C.accentLite)
      local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.14)
      b.h, b.i = h, i
      b:SetScript("OnClick", function(self) onPeg(self.h, self.i) end)
      row.pegs[i] = b
    end
    rows[h] = row
  end
  local newBtn = ns.NewButton(frame, "New Game", 120, 26, function() newGame() end)
  newBtn:SetPoint("BOTTOM", 0, 10)

  overlay = CreateFrame("Frame", nil, frame); overlay:SetAllPoints()
  overlay:SetFrameLevel(frame:GetFrameLevel() + 30)
  local obg = overlay:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints(); obg:SetColorTexture(0.05, 0.03, 0.09, 0.8)
  overlayText = ns.Header(overlay, "", 22); overlayText:SetPoint("CENTER", 0, 16)
  local again = ns.NewButton(overlay, "Play Again", 120, 26, function() newGame() end); again:SetPoint("CENTER", 0, -28)
  overlay:Hide()
end

local function start(content) if not frame then build(content) end frame:Show(); newGame() end
local function stop() if frame then frame:Hide() end end

ns.Register({ category = "Vs AI", id = "nim", name = "Nim", desc = "Perfect-play strategy game.",
              icon = "Interface\\Icons\\INV_Misc_Rune_04", start = start, stop = stop })
