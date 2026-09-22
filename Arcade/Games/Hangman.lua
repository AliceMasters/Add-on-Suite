--[[ Azeroth Arcade — Hangman.  Guess the word before you run out of tries. ]]
local ADDON, ns = ...

local Logic = {}
ns.logic["hangman"] = Logic

local WORDS = {
  "AZEROTH", "STORMWIND", "ORGRIMMAR", "DRAGON", "PALADIN", "WARLOCK", "MURLOC",
  "HEARTHSTONE", "ELWYNN", "DARNASSUS", "GNOME", "TAUREN", "FELGUARD", "ARCANE",
  "AMETHYST", "VELVET", "NONOGRAM", "ARCADE", "PICROSS", "SAPPHIRE", "EMERALD",
  "TREASURE", "GRYPHON", "QUEST", "DUNGEON", "RAID", "SHADOW", "FROSTMOURNE",
}

function Logic.new(rng)
  rng = rng or math.random
  local word = WORDS[rng(#WORDS)]
  return { word = word, guessed = {}, wrong = 0, max = 6, over = false, won = false }
end

function Logic.masked(s)
  local out = {}
  for i = 1, #s.word do
    local ch = s.word:sub(i, i)
    out[i] = s.guessed[ch] and ch or "_"
  end
  return table.concat(out, " ")
end

function Logic.allRevealed(s)
  for i = 1, #s.word do if not s.guessed[s.word:sub(i, i)] then return false end end
  return true
end

-- returns "hit","miss","none","win","lose"
function Logic.guess(s, letter)
  if s.over or s.guessed[letter] then return "none" end
  s.guessed[letter] = true
  if s.word:find(letter, 1, true) then
    if Logic.allRevealed(s) then s.won = true; s.over = true; return "win" end
    return "hit"
  else
    s.wrong = s.wrong + 1
    if s.wrong >= s.max then s.over = true; return "lose" end
    return "miss"
  end
end

------------------------------------------------------------------------
-- View
------------------------------------------------------------------------
local frame, wordFS, livesFS, letterBtns, state, overlay, overlayText

local function render()
  wordFS:SetText(Logic.masked(state))
  livesFS:SetText("Tries left  " .. (state.max - state.wrong))
  for ch, b in pairs(letterBtns) do
    if state.guessed[ch] then b:SetAlpha(0.3); b:EnableMouse(false)
    else b:SetAlpha(1); b:EnableMouse(true) end
  end
end

local function newGame()
  state = Logic.new(); overlay:Hide(); render()
end

local function onLetter(ch)
  if state.over then return end
  local r = Logic.guess(state, ch)
  if r == "none" then return end
  ns.Sound(SOUNDKIT and (r == "miss" and SOUNDKIT.IG_QUEST_FAILED or SOUNDKIT.IG_MAINMENU_OPTION))
  render()
  if state.over then
    if state.won then overlayText:SetText("|cff9be7a0You got it!|r\n" .. state.word)
      ns.SubmitBest("hangman", ns.Best("hangman") + 1)
    else overlayText:SetText("|cffff6677Out of tries|r\nIt was " .. state.word) end
    overlay:Show()
  end
end

local function build(content)
  frame = CreateFrame("Frame", nil, content); frame:SetAllPoints()
  wordFS = frame:CreateFontString(nil, "OVERLAY"); wordFS:SetFont(ns.FONT_FANCY, 30)
  wordFS:SetTextColor(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3]); wordFS:SetPoint("TOP", 0, -40)
  livesFS = ns.Label(frame, "", 14, ns.C.text); livesFS:SetPoint("TOP", 0, -90)

  letterBtns = {}
  local cols = 9
  local bw = 42
  local startY = -130
  for i = 0, 25 do
    local ch = string.char(65 + i)
    local col, row = i % cols, math.floor(i / cols)
    local b = ns.NewButton(frame, ch, bw, 30, nil)
    b:SetPoint("TOPLEFT", 6 + col * (bw + 4), startY - row * 34)
    b:SetScript("OnClick", function() onLetter(ch) end)
    letterBtns[ch] = b
  end
  local newBtn = ns.NewButton(frame, "New Word", 120, 26, function() newGame() end)
  newBtn:SetPoint("BOTTOM", 0, 10)

  overlay = CreateFrame("Frame", nil, frame); overlay:SetAllPoints()
  overlay:SetFrameLevel(frame:GetFrameLevel() + 30)
  local obg = overlay:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints(); obg:SetColorTexture(0.05, 0.03, 0.09, 0.82)
  overlayText = ns.Header(overlay, "", 20); overlayText:SetPoint("CENTER", 0, 16)
  local again = ns.NewButton(overlay, "Play Again", 120, 26, function() newGame() end); again:SetPoint("CENTER", 0, -30)
  overlay:Hide()
end

local function start(content) if not frame then build(content) end frame:Show(); newGame() end
local function stop() if frame then frame:Hide() end end

ns.Register({ category = "Puzzle", id = "hangman", name = "Hangman", desc = "Guess the hidden word.",
              icon = "Interface\\Icons\\INV_Misc_Book_07", start = start, stop = stop })
