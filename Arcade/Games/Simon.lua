--[[ Azeroth Arcade — Simon.  Watch the sequence, then repeat it. ]]
local ADDON, ns = ...

------------------------------------------------------------------------
-- Pure logic
------------------------------------------------------------------------
local Logic = {}
ns.logic["simon"] = Logic

function Logic.new()
  return { seq = {}, inputPos = 1, over = false }
end

function Logic.extend(s, rng)
  rng = rng or math.random
  s.seq[#s.seq + 1] = rng(4)
  s.inputPos = 1
end

-- returns "ok" (correct, more to go), "round" (sequence complete), "fail", "none"
function Logic.input(s, pad)
  if s.over then return "none" end
  if pad ~= s.seq[s.inputPos] then s.over = true; return "fail" end
  s.inputPos = s.inputPos + 1
  if s.inputPos > #s.seq then return "round" end
  return "ok"
end

function Logic.round(s) return #s.seq end

------------------------------------------------------------------------
-- View
------------------------------------------------------------------------
local PADS = {
  { dim = { 0.55, 0.16, 0.18 }, lit = { 1.00, 0.42, 0.44 } },  -- 1 red   TL
  { dim = { 0.16, 0.42, 0.20 }, lit = { 0.45, 0.95, 0.55 } },  -- 2 green TR
  { dim = { 0.18, 0.30, 0.58 }, lit = { 0.50, 0.72, 1.00 } },  -- 3 blue  BL
  { dim = { 0.55, 0.46, 0.12 }, lit = { 1.00, 0.92, 0.42 } },  -- 4 gold  BR
}
local frame, pads, state, overlay, overlayText, startBtn
local playGen, accepting = 0, false

local function setPad(i, lit)
  ns.Grad(pads[i].bg, "VERTICAL", lit and { PADS[i].lit[1] * 0.8, PADS[i].lit[2] * 0.8, PADS[i].lit[3] * 0.8 } or PADS[i].dim,
          lit and PADS[i].lit or PADS[i].dim)
end

local function flash(i)
  setPad(i, true)
  ns.Sound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION)
  local g = playGen
  C_Timer.After(0.32, ns.Safe(function() if g == playGen then setPad(i, false) end end))
end

local function playback()
  accepting = false
  local g = playGen
  local i = 1
  local function step()
    if g ~= playGen then return end
    if i > #state.seq then accepting = true; return end
    flash(state.seq[i]); i = i + 1
    C_Timer.After(0.62, ns.Safe(step))
  end
  C_Timer.After(0.5, ns.Safe(step))
end

local function newGame()
  playGen = playGen + 1
  state = Logic.new()
  Logic.extend(state)
  overlay:Hide()
  ns.SetInfo("Round  " .. Logic.round(state))
  playback()
end

local function onPad(i)
  if not accepting or not state or state.over then return end
  flash(i)
  local res = Logic.input(state, i)
  if res == "fail" then
    accepting = false
    ns.SubmitBest("simon", Logic.round(state) - 1)
    ns.Sound(SOUNDKIT and SOUNDKIT.IG_QUEST_FAILED)
    overlayText:SetText("|cffff6677Game Over|r\nReached round " .. Logic.round(state))
    overlay:Show()
  elseif res == "round" then
    accepting = false
    if Logic.round(state) >= 8 then ns.Unlock("simon") end
    ns.SubmitBest("simon", Logic.round(state))
    Logic.extend(state)
    ns.SetInfo("Round  " .. Logic.round(state))
    playback()
  end
end

local function build(content)
  frame = CreateFrame("Frame", nil, content); frame:SetAllPoints()
  local board = CreateFrame("Frame", nil, frame)
  local pw, ph, gap = 206, 176, 10
  board:SetSize(pw * 2 + gap, ph * 2 + gap); board:SetPoint("TOP", 0, -8)
  local coords = { { 0, 0 }, { pw + gap, 0 }, { 0, -(ph + gap) }, { pw + gap, -(ph + gap) } }
  pads = {}
  for i = 1, 4 do
    local p = CreateFrame("Button", nil, board)
    p:SetSize(pw, ph); p:SetPoint("TOPLEFT", coords[i][1], coords[i][2])
    p.bg = p:CreateTexture(nil, "BACKGROUND"); p.bg:SetAllPoints()
    local hl = p:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
    p.i = i
    p:SetScript("OnClick", function(self) onPad(self.i) end)
    pads[i] = p
    setPad(i, false)
  end

  startBtn = ns.NewButton(frame, "Start", 120, 26, function() newGame() end)
  startBtn:SetPoint("BOTTOM", 0, 6)

  overlay = CreateFrame("Frame", nil, frame); overlay:SetAllPoints(board)
  overlay:SetFrameLevel(board:GetFrameLevel() + 20)
  local obg = overlay:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints(); obg:SetColorTexture(0.05, 0.03, 0.09, 0.82)
  overlayText = ns.Header(overlay, "", 20); overlayText:SetPoint("CENTER", 0, 20)
  local again = ns.NewButton(overlay, "Play Again", 120, 26, function() newGame() end)
  again:SetPoint("CENTER", 0, -28)
  overlay:Hide()
end

local function start(content)
  if not frame then build(content) end
  frame:Show()
  playGen = playGen + 1; accepting = false
  state = Logic.new(); Logic.extend(state)
  overlay:Hide(); ns.SetInfo("Press Start")
  for i = 1, 4 do setPad(i, false) end
end

local function stop()
  playGen = playGen + 1; accepting = false
  if frame then frame:Hide() end
end

ns.Register({ category = "Arcade", id = "simon", name = "Simon", desc = "Repeat the growing sequence.",
              icon = "Interface\\Icons\\Spell_Holy_MagicalSentry", start = start, stop = stop })
