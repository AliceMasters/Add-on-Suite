--[[ Azeroth Arcade — Mastermind.  Crack the 4-colour code in ten guesses. ]]
local ADDON, ns = ...

local Logic = {}
ns.logic["mastermind"] = Logic

local SLOTS, COLORS, MAXG = 4, 6, 10

function Logic.new(rng)
  rng = rng or math.random
  local code = {}
  for i = 1, SLOTS do code[i] = rng(COLORS) end
  return { code = code, guesses = {}, over = false, won = false, max = MAXG }
end

-- returns black (right colour+spot), white (right colour wrong spot)
function Logic.score(code, guess)
  local black, white = 0, 0
  local cCount, gCount = {}, {}
  for i = 1, SLOTS do
    if guess[i] == code[i] then black = black + 1
    else cCount[code[i]] = (cCount[code[i]] or 0) + 1; gCount[guess[i]] = (gCount[guess[i]] or 0) + 1 end
  end
  for col = 1, COLORS do white = white + math.min(cCount[col] or 0, gCount[col] or 0) end
  return black, white
end

function Logic.guess(s, pegs)
  if s.over then return nil end
  local black, white = Logic.score(s.code, pegs)
  s.guesses[#s.guesses + 1] = { pegs = { pegs[1], pegs[2], pegs[3], pegs[4] }, black = black, white = white }
  if black == SLOTS then s.won = true; s.over = true
  elseif #s.guesses >= s.max then s.over = true end
  return black, white
end

------------------------------------------------------------------------
-- View
------------------------------------------------------------------------
local PAL = {
  { 0.90, 0.25, 0.28 }, { 0.35, 0.62, 0.98 }, { 0.35, 0.80, 0.42 },
  { 0.95, 0.80, 0.22 }, { 0.70, 0.40, 0.92 }, { 0.30, 0.82, 0.82 },
}
local frame, rows, guessSlots, state, current, overlay, overlayText

local function peg(parent, sz) local t = parent:CreateTexture(nil, "ARTWORK"); t:SetSize(sz, sz); return t end

local function renderHistory()
  for i = 1, MAXG do
    local row = rows[i]
    local g = state.guesses[i]
    for j = 1, SLOTS do
      if g then local col = PAL[g.pegs[j]]; row.pegs[j]:SetColorTexture(col[1], col[2], col[3], 1)
      else row.pegs[j]:SetColorTexture(ns.C.cell[1], ns.C.cell[2], ns.C.cell[3], 1) end
    end
    row.fb:SetText(g and ("|cff20ff60" .. g.black .. "|r|cffffffff/" .. g.white .. "|r") or "")
  end
end

local function renderCurrent()
  for j = 1, SLOTS do
    if current[j] then local col = PAL[current[j]]; guessSlots[j]:SetColorTexture(col[1], col[2], col[3], 1)
    else guessSlots[j]:SetColorTexture(ns.C.cell[1], ns.C.cell[2], ns.C.cell[3], 1) end
  end
end

local function newGame()
  state = Logic.new(); current = {}
  overlay:Hide(); renderHistory(); renderCurrent()
  ns.SetInfo("Guess  0 / " .. MAXG)
end

local function submit()
  if state.over then return end
  local n = 0; for j = 1, SLOTS do if current[j] then n = n + 1 end end
  if n < SLOTS then return end
  Logic.guess(state, current)
  current = {}
  renderHistory(); renderCurrent()
  ns.SetInfo("Guess  " .. #state.guesses .. " / " .. MAXG)
  ns.Sound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION)
  if state.over then
    overlayText:SetText(state.won and ("|cff9be7a0Cracked it!|r\n" .. #state.guesses .. " guesses")
      or "|cffff6677Out of guesses|r")
    if state.won then ns.SubmitBest("mastermind", ns.Best("mastermind") + 1) end
    overlay:Show()
  end
end

local function addColor(col)
  if state.over then return end
  for j = 1, SLOTS do if not current[j] then current[j] = col; renderCurrent(); return end end
end

local function build(content)
  frame = CreateFrame("Frame", nil, content); frame:SetAllPoints()
  local head = ns.Header(frame, "Crack the code", 16); head:SetPoint("TOP", 0, -4)

  rows = {}
  for i = 1, MAXG do
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(300, 26); row:SetPoint("TOP", 0, -28 - (i - 1) * 28)
    row.pegs = {}
    for j = 1, SLOTS do row.pegs[j] = peg(row, 22); row.pegs[j]:SetPoint("LEFT", 40 + (j - 1) * 28, 0) end
    row.fb = ns.Label(row, "", 13, ns.C.text); row.fb:SetPoint("LEFT", 40 + SLOTS * 28 + 12, 0)
    rows[i] = row
  end

  -- current guess slots
  guessSlots = {}
  local gr = CreateFrame("Frame", nil, frame); gr:SetSize(300, 30); gr:SetPoint("BOTTOM", 0, 66)
  for j = 1, SLOTS do guessSlots[j] = peg(gr, 26); guessSlots[j]:SetPoint("LEFT", 40 + (j - 1) * 30, 0) end

  -- colour palette
  for i = 1, COLORS do
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(34, 26); b:SetPoint("BOTTOM", frame, "BOTTOM", (i - (COLORS + 1) / 2) * 40, 34)
    local t = b:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints(); t:SetColorTexture(PAL[i][1], PAL[i][2], PAL[i][3], 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
    b.col = i
    b:SetScript("OnClick", function(self) addColor(self.col) end)
  end
  local clr = ns.NewButton(frame, "Clear", 70, 24, function() current = {}; renderCurrent() end)
  clr:SetPoint("BOTTOMLEFT", 8, 6)
  local sub = ns.NewButton(frame, "Guess", 90, 24, function() submit() end)
  sub:SetPoint("BOTTOMRIGHT", -8, 6)

  overlay = CreateFrame("Frame", nil, frame); overlay:SetAllPoints()
  overlay:SetFrameLevel(frame:GetFrameLevel() + 30)
  local obg = overlay:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints(); obg:SetColorTexture(0.05, 0.03, 0.09, 0.78)
  overlayText = ns.Header(overlay, "", 20); overlayText:SetPoint("CENTER", 0, 16)
  local again = ns.NewButton(overlay, "Play Again", 120, 26, function() newGame() end); again:SetPoint("CENTER", 0, -30)
  overlay:Hide()
end

local function start(content) if not frame then build(content) end frame:Show(); newGame() end
local function stop() if frame then frame:Hide() end end

ns.Register({ id = "mastermind", name = "Mastermind", desc = "Deduce the hidden code.",
              category = "Puzzle", icon = "Interface\\Icons\\INV_Misc_Gem_Variety_02", start = start, stop = stop })
