--[[ Azeroth Arcade — Memory.  Flip two cards; find every matching pair. ]]
local ADDON, ns = ...

------------------------------------------------------------------------
-- Pure logic
------------------------------------------------------------------------
local Logic = {}
ns.logic["memory"] = Logic

local function shuffle(t, rng)
  rng = rng or math.random
  for i = #t, 2, -1 do local j = rng(i); t[i], t[j] = t[j], t[i] end
end

function Logic.new(pairs, rng)
  pairs = pairs or 8
  local faces = {}
  for f = 1, pairs do faces[#faces + 1] = f; faces[#faces + 1] = f end
  shuffle(faces, rng)
  local cards = {}
  for i, f in ipairs(faces) do cards[i] = { face = f, matched = false } end
  return { pairs = pairs, cards = cards, up = {}, moves = 0, pairsFound = 0, over = false, n = #cards }
end

function Logic.isUp(s, i)
  if s.cards[i].matched then return true end
  for _, j in ipairs(s.up) do if j == i then return true end end
  return false
end

function Logic.resolve(s)          -- hide a shown mismatch (called after a delay)
  if #s.up == 2 then s.up = {} end
end

-- flip card i. returns "flip","match","mismatch","none"
function Logic.flip(s, i)
  if s.over then return "none" end
  local card = s.cards[i]
  if not card or card.matched then return "none" end
  if #s.up == 2 then s.up = {} end             -- clear a prior mismatch
  for _, j in ipairs(s.up) do if j == i then return "none" end end
  s.up[#s.up + 1] = i
  if #s.up == 2 then
    s.moves = s.moves + 1
    local a, b = s.cards[s.up[1]], s.cards[s.up[2]]
    if a.face == b.face then
      a.matched = true; b.matched = true
      s.pairsFound = s.pairsFound + 1; s.up = {}
      if s.pairsFound == s.pairs then s.over = true end
      return "match"
    end
    return "mismatch"
  end
  return "flip"
end

------------------------------------------------------------------------
-- View
------------------------------------------------------------------------
local COLS, ROWS = 4, 4         -- 8 pairs
local SIZE, GAP = 96, 8
local FACE = {
  { 0.90, 0.25, 0.28 }, { 0.35, 0.62, 0.98 }, { 0.35, 0.80, 0.42 }, { 0.95, 0.80, 0.22 },
  { 0.70, 0.40, 0.92 }, { 0.30, 0.82, 0.82 }, { 0.96, 0.52, 0.75 }, { 0.95, 0.55, 0.20 },
}
local frame, cards, state, overlay, overlayText, locked

local function renderCard(i)
  local cd = cards[i]
  if Logic.isUp(state, i) then
    local col = FACE[state.cards[i].face]
    ns.Grad(cd.bg, "VERTICAL", { col[1] * 0.8, col[2] * 0.8, col[3] * 0.8 }, col)
    cd.q:SetText("")
    cd:SetAlpha(state.cards[i].matched and 0.72 or 1)
  else
    ns.Grad(cd.bg, "VERTICAL", ns.C.panel, ns.C.panelLo)
    cd.q:SetText("?")
    cd:SetAlpha(1)
  end
end

local function render() for i = 1, state.n do renderCard(i) end
  ns.SetInfo("Moves  " .. state.moves) end

local function newGame()
  state = Logic.new(8)
  overlay:Hide(); locked = false
  render()
end

local function onFlip(i)
  if locked or not state or state.over then return end
  local res = Logic.flip(state, i)
  if res == "none" then return end
  render()
  ns.Sound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION)
  if res == "mismatch" then
    locked = true
    C_Timer.After(0.8, ns.Safe(function() Logic.resolve(state); render(); locked = false end))
  elseif res == "match" and state.over then
    ns.Unlock("memory")
    ns.SubmitBest("memory", ns.Best("memory") + 1)
    overlayText:SetText("|cffe9d5a0Total Recall|r\nCleared in " .. state.moves .. " moves")
    overlay:Show(); ns.Sound(SOUNDKIT and SOUNDKIT.LEVELUP)
  end
end

local function build(content)
  frame = CreateFrame("Frame", nil, content); frame:SetAllPoints()
  local board = CreateFrame("Frame", nil, frame)
  board:SetSize(COLS * SIZE + (COLS + 1) * GAP, ROWS * SIZE + (ROWS + 1) * GAP)
  board:SetPoint("TOP", 0, -8)

  cards = {}
  for i = 1, COLS * ROWS do
    local col = (i - 1) % COLS
    local row = math.floor((i - 1) / COLS)
    local cd = CreateFrame("Button", nil, board)
    cd:SetSize(SIZE, SIZE)
    cd:SetPoint("TOPLEFT", GAP + col * (SIZE + GAP), -(GAP + row * (SIZE + GAP)))
    cd.bg = cd:CreateTexture(nil, "BACKGROUND"); cd.bg:SetAllPoints()
    cd.q = cd:CreateFontString(nil, "OVERLAY"); cd.q:SetFont(ns.FONT_FANCY, 30)
    cd.q:SetTextColor(ns.C.accentLite[1], ns.C.accentLite[2], ns.C.accentLite[3]); cd.q:SetPoint("CENTER")
    local hl = cd:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    cd.i = i
    cd:SetScript("OnClick", function(self) onFlip(self.i) end)
    cards[i] = cd
  end

  local newBtn = ns.NewButton(frame, "New Game", 120, 26, function() newGame() end)
  newBtn:SetPoint("BOTTOM", 0, 6)

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

ns.Register({ category = "Arcade", id = "memory", name = "Memory", desc = "Match every pair.",
              icon = "Interface\\Icons\\INV_Misc_Gem_Variety_01", start = start, stop = stop })
