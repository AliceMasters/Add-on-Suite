--[[ Azeroth Arcade — a jewel-box of mini-games.
     Core.lua: velvet/amethyst theme, home cabinet, streak/stats/achievements,
     settings, game registry, minimap. /arcade  /ac  to open. ]]

local ADDON, ns = ...

------------------------------------------------------------------------
-- Constants exposed to game modules
------------------------------------------------------------------------
ns.MAIN_W, ns.MAIN_H = 470, 600
ns.CONTENT_W, ns.CONTENT_H = 436, 452
ns.GOLD = "|cffe9d5a0"
ns.FONT       = "Fonts\\FRIZQT__.TTF"
ns.FONT_FANCY = "Fonts\\MORPHEUS.TTF"

ns.games = {}     -- ordered list of game defs
ns.logic = {}     -- id -> pure logic (for headless tests)

------------------------------------------------------------------------
-- Palette (velvet base, switchable accent)
------------------------------------------------------------------------
local ACCENTS = {
  amethyst = { base = { 0.44, 0.26, 0.62 }, lite = { 0.66, 0.44, 0.90 }, name = "Amethyst" },
  rose     = { base = { 0.56, 0.22, 0.38 }, lite = { 0.88, 0.46, 0.64 }, name = "Rose" },
  emerald  = { base = { 0.16, 0.44, 0.34 }, lite = { 0.36, 0.78, 0.56 }, name = "Emerald" },
  sapphire = { base = { 0.22, 0.32, 0.60 }, lite = { 0.42, 0.58, 0.94 }, name = "Sapphire" },
}
local ORDER = { "amethyst", "rose", "emerald", "sapphire" }

ns.C = {
  bg1   = { 0.10, 0.07, 0.14 }, bg2 = { 0.05, 0.03, 0.09 },
  panel = { 0.15, 0.10, 0.20 }, panelLo = { 0.10, 0.06, 0.14 },
  edge  = { 0.40, 0.28, 0.55 }, edgeLo = { 0.24, 0.16, 0.34 },
  text  = { 0.95, 0.93, 0.97 }, sub = { 0.74, 0.68, 0.82 },
  gold  = { 0.91, 0.83, 0.63 },
  accent = ACCENTS.amethyst.base, accentLite = ACCENTS.amethyst.lite,
}

local mainFrame, contentFrame, homeFrame, titleFS, scoreFS, bestFS, backBtn, minimapBtn
local settingsPanel, statsPanel, toastFrame, toastText, pillStreak, pillPlays, pillTrophy
local homeCards = {}
local current
local built = false
local skinBtns = {}     -- buttons to re-tint on accent change

------------------------------------------------------------------------
-- Theme helpers
------------------------------------------------------------------------
local function c4(t, a) return t[1], t[2], t[3], a or 1 end

function ns.Grad(tex, orient, c1, c2)
  -- Always lay down a solid, drawable surface first: SetGradient tints the
  -- current texture, so without this the gradient renders nothing (transparent).
  tex:SetColorTexture(c1[1], c1[2], c1[3], c1[4] or 1)
  if CreateColor and tex.SetGradient then
    pcall(tex.SetGradient, tex, orient,
      CreateColor(c1[1], c1[2], c1[3], c1[4] or 1),
      CreateColor(c2[1], c2[2], c2[3], c2[4] or 1))
  end
end

-- hairline border around a frame using four thin textures
local function addBorder(f, col, inset)
  inset = inset or 0
  local function line(p1, p2, w, h)
    local t = f:CreateTexture(nil, "BORDER")
    t:SetColorTexture(col[1], col[2], col[3], col[4] or 1)
    t:SetPoint(p1, inset, -inset); t:SetPoint(p2, -inset, inset)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
    return t
  end
  line("TOPLEFT", "TOPRIGHT", nil, 1)
  line("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
  line("TOPLEFT", "BOTTOMLEFT", 1, nil)
  line("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
end

local function skinButton(b)
  local a, al = ns.C.accent, ns.C.accentLite
  ns.Grad(b._base, "VERTICAL", { a[1] * 0.7, a[2] * 0.7, a[3] * 0.7 }, { al[1], al[2], al[3] })
  b._glow:SetColorTexture(al[1], al[2], al[3], 0.28)
end

function ns.NewButton(parent, text, w, h, onclick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 100, h or 26)
  b._base = b:CreateTexture(nil, "BACKGROUND"); b._base:SetAllPoints()
  addBorder(b, { ns.C.accentLite[1], ns.C.accentLite[2], ns.C.accentLite[3], 0.5 })
  b._glow = b:CreateTexture(nil, "HIGHLIGHT"); b._glow:SetAllPoints()
  local fs = b:CreateFontString(nil, "OVERLAY")
  fs:SetFont(ns.FONT, 13); fs:SetTextColor(c4(ns.C.text)); fs:SetPoint("CENTER")
  b._fs = fs
  b.SetText = function(_, t) fs:SetText(t) end
  b.GetText = function() return fs:GetText() end
  b:SetText(text or "")
  b:SetScript("OnMouseDown", function() fs:SetPoint("CENTER", 0, -1) end)
  b:SetScript("OnMouseUp", function() fs:SetPoint("CENTER", 0, 0) end)
  if onclick then b:SetScript("OnClick", onclick) end
  skinButton(b)
  skinBtns[#skinBtns + 1] = b
  return b
end

function ns.Panel(parent)
  local p = CreateFrame("Frame", nil, parent)
  local bg = p:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
  ns.Grad(bg, "VERTICAL", ns.C.panel, ns.C.panelLo)
  addBorder(p, ns.C.edgeLo)
  return p
end

function ns.Header(parent, text, size)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(ns.FONT_FANCY, size or 20)
  fs:SetTextColor(c4(ns.C.gold))
  fs:SetText(text or "")
  return fs
end

function ns.Label(parent, text, size, col)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(ns.FONT, size or 12)
  col = col or ns.C.text; fs:SetTextColor(c4(col))
  fs:SetText(text or "")
  return fs
end

local function ApplyAccent()
  for _, b in ipairs(skinBtns) do if b._base then skinButton(b) end end
  if homeCards then for _, card in ipairs(homeCards) do if card._reskin then card._reskin() end end end
end

------------------------------------------------------------------------
-- Helpers shared with games
------------------------------------------------------------------------
function ns.Msg(t) DEFAULT_CHAT_FRAME:AddMessage("|cffb98cffArcade|r: " .. t) end
function ns.Sound(kit) if ArcadeDB and ArcadeDB.sound and kit then pcall(PlaySound, kit) end end
function ns.Safe(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then DEFAULT_CHAT_FRAME:AddMessage("|cffff5566Arcade ERROR|r: " .. tostring(err)) end
  end
end
function ns.Register(def) ns.games[#ns.games + 1] = def end
function ns.Best(id) return (ArcadeDB and ArcadeDB.best and ArcadeDB.best[id]) or 0 end

function ns.SetScore(n) if scoreFS then scoreFS:SetText("Score  " .. (n or 0)) end end
function ns.SetInfo(t) if scoreFS then scoreFS:SetText(t or "") end end
function ns.SubmitBest(id, n)
  ArcadeDB.best = ArcadeDB.best or {}
  if n > (ArcadeDB.best[id] or 0) then ArcadeDB.best[id] = n end
  if bestFS then bestFS:SetText("Best  " .. ns.Best(id)) end
  return ArcadeDB.best[id]
end

------------------------------------------------------------------------
-- Stats, daily streak, achievements  (pure-ish, exposed for tests)
------------------------------------------------------------------------
ns.ACH = {
  { id = "first",   name = "Welcome",         desc = "Play your first game." },
  { id = "streak3", name = "Habit Forming",   desc = "Reach a 3-day streak." },
  { id = "nono5",   name = "Picture Perfect", desc = "Solve 5 nonograms." },
  { id = "t512",    name = "Getting Big",     desc = "Reach 512 in 2048." },
  { id = "snake20", name = "Slither",         desc = "Score 20 in Snake." },
  { id = "sweep",   name = "Bomb Squad",      desc = "Clear a Minesweeper board." },
  { id = "lights",  name = "Enlightened",     desc = "Solve Lights Out." },
  { id = "memory",  name = "Total Recall",    desc = "Win a Memory game." },
  { id = "simon",   name = "Good Ear",        desc = "Reach round 8 in Simon." },
}
local ACH_BY_ID = {}
for _, a in ipairs(ns.ACH) do ACH_BY_ID[a.id] = a end

local function showToast(title, sub)
  if not toastFrame then return end
  toastText:SetText("|cffe9d5a0" .. title .. "|r\n" .. (sub or ""))
  toastFrame:Show(); toastFrame:SetAlpha(1)
  toastFrame._until = GetTime() + 3
end

function ns.Unlock(id)
  ArcadeDB.ach = ArcadeDB.ach or {}
  if ArcadeDB.ach[id] then return false end
  ArcadeDB.ach[id] = true
  local a = ACH_BY_ID[id]
  ns.Sound(SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 or (SOUNDKIT and SOUNDKIT.LEVELUP))
  if a then showToast("Achievement: " .. a.name, a.desc) end
  if pillTrophy then pillTrophy:SetText(ns.TrophyText()) end
  return true
end

function ns.AchCount()
  local n = 0
  if ArcadeDB and ArcadeDB.ach then for _ in pairs(ArcadeDB.ach) do n = n + 1 end end
  return n
end
function ns.TrophyText() return "Trophies  " .. ns.AchCount() .. "/" .. #ns.ACH end

-- day-number streak using epoch time() (deterministic + testable)
function ns.RecordPlay(gameId)
  local s = ArcadeDB.stats
  s.plays[gameId] = (s.plays[gameId] or 0) + 1
  s.total = (s.total or 0) + 1
  local day = math.floor(time() / 86400)
  if s.lastDay == day then
    -- same day, streak unchanged
  elseif s.lastDay == day - 1 then
    s.streak = (s.streak or 0) + 1
  else
    s.streak = 1
  end
  s.lastDay = day
  s.bestStreak = math.max(s.bestStreak or 0, s.streak)
  ns.Unlock("first")
  if s.streak >= 3 then ns.Unlock("streak3") end
  return s.streak
end

------------------------------------------------------------------------
-- Navigation
------------------------------------------------------------------------
local function refreshHome()
  if pillStreak then pillStreak:SetText("Streak  " .. (ArcadeDB.stats.streak or 0)) end
  if pillPlays then pillPlays:SetText("Played  " .. (ArcadeDB.stats.total or 0)) end
  if pillTrophy then pillTrophy:SetText(ns.TrophyText()) end
  for _, card in ipairs(homeCards) do
    if card._best then card._best:SetText("Best  " .. ns.Best(card._id)) end
  end
end

function ns.ShowMenu()
  if current and current.stop then pcall(current.stop) end
  current = nil
  if settingsPanel then settingsPanel:Hide() end
  if statsPanel then statsPanel:Hide() end
  titleFS:SetText("Azeroth Arcade")
  scoreFS:SetText(""); bestFS:SetText("")
  backBtn:Hide()
  contentFrame:Hide()
  refreshHome()
  homeFrame:Show()
end

function ns.PlayGame(id)
  for _, def in ipairs(ns.games) do
    if def.id == id then
      if current and current.stop then pcall(current.stop) end
      current = def
      homeFrame:Hide()
      if settingsPanel then settingsPanel:Hide() end
      if statsPanel then statsPanel:Hide() end
      contentFrame:Show()
      titleFS:SetText(def.name)
      scoreFS:SetText(""); bestFS:SetText("Best  " .. ns.Best(id))
      backBtn:Show()
      ns.RecordPlay(id)
      refreshHome()
      def.start(contentFrame)
      return
    end
  end
end

------------------------------------------------------------------------
-- Home (cabinet of cards)
------------------------------------------------------------------------
local function makeCard(parent, def, w, h)
  local card = CreateFrame("Button", nil, parent)
  card:SetSize(w, h)
  card._id = def.id
  local base = card:CreateTexture(nil, "BACKGROUND"); base:SetAllPoints()
  ns.Grad(base, "VERTICAL", ns.C.panel, ns.C.panelLo)
  addBorder(card, ns.C.edge)
  local glow = card:CreateTexture(nil, "HIGHLIGHT"); glow:SetAllPoints()

  local iconBorder = card:CreateTexture(nil, "ARTWORK")
  iconBorder:SetSize(46, 46); iconBorder:SetPoint("TOPLEFT", 12, -12)
  local icon = card:CreateTexture(nil, "ARTWORK")
  icon:SetSize(40, 40); icon:SetPoint("CENTER", iconBorder, "CENTER")
  icon:SetTexture(def.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local nm = ns.Header(card, def.name, 15); nm:SetPoint("TOPLEFT", 66, -16)
  local desc = ns.Label(card, def.desc or "", 10, ns.C.sub); desc:SetPoint("TOPLEFT", 66, -38)
  desc:SetPoint("RIGHT", -10, 0); desc:SetJustifyH("LEFT")
  local best = ns.Label(card, "Best  " .. ns.Best(def.id), 11, ns.C.gold)
  best:SetPoint("BOTTOMLEFT", 66, 10)
  card._best = best

  card._reskin = function()
    glow:SetColorTexture(ns.C.accentLite[1], ns.C.accentLite[2], ns.C.accentLite[3], 0.16)
    iconBorder:SetColorTexture(ns.C.accentLite[1], ns.C.accentLite[2], ns.C.accentLite[3], 0.85)
  end
  card._reskin()
  card:SetScript("OnClick", function() ns.PlayGame(def.id) end)
  return card
end

local function buildHome()
  homeFrame = CreateFrame("Frame", nil, mainFrame)
  homeFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT")
  homeFrame:SetSize(ns.CONTENT_W, ns.CONTENT_H)

  -- stat pills
  local pillY = -2
  local function pill(x, w)
    local p = ns.Panel(homeFrame); p:SetSize(w, 22); p:SetPoint("TOPLEFT", x, pillY)
    local fs = ns.Label(p, "", 11, ns.C.gold); fs:SetPoint("CENTER")
    return fs
  end
  pillStreak = pill(0, 132)
  pillPlays  = pill(140, 132)
  pillTrophy = pill(280, 156)

  -- scrolling card grid
  local vpY = -32
  local vpH = ns.CONTENT_H - 34
  local vp = CreateFrame("Frame", nil, homeFrame)
  vp:SetPoint("TOPLEFT", 0, vpY); vp:SetSize(ns.CONTENT_W, vpH)
  vp:SetClipsChildren(true); vp:EnableMouseWheel(true)
  local list = CreateFrame("Frame", nil, vp); list:SetPoint("TOPLEFT", 0, 0)

  local cw, ch, gap = ns.CONTENT_W, 92, 8
  for i, def in ipairs(ns.games) do
    local card = makeCard(list, def, cw, ch)
    card:SetPoint("TOPLEFT", 0, -(i - 1) * (ch + gap))
    homeCards[i] = card
  end
  local listH = #ns.games * (ch + gap)
  list:SetSize(cw, listH)
  local maxScroll = math.max(0, listH - vpH)
  local scroll = 0
  vp:SetScript("OnMouseWheel", function(_, d)
    scroll = math.max(0, math.min(maxScroll, scroll - d * 46))
    list:SetPoint("TOPLEFT", vp, "TOPLEFT", 0, scroll)
  end)
end

------------------------------------------------------------------------
-- Settings + Stats panels
------------------------------------------------------------------------
local function buildSettings()
  settingsPanel = ns.Panel(mainFrame)
  settingsPanel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT")
  settingsPanel:SetSize(ns.CONTENT_W, ns.CONTENT_H)
  settingsPanel:SetFrameLevel(mainFrame:GetFrameLevel() + 20)
  settingsPanel:Hide()

  local h = ns.Header(settingsPanel, "Settings", 20); h:SetPoint("TOP", 0, -14)

  local sndLbl = ns.Label(settingsPanel, "Sound", 14); sndLbl:SetPoint("TOPLEFT", 24, -60)
  local sndBtn = ns.NewButton(settingsPanel, "", 90, 26, function() end)
  sndBtn:SetPoint("TOPRIGHT", -24, -54)
  local function sndText() sndBtn:SetText(ArcadeDB.sound and "On" or "Off") end
  sndBtn:SetScript("OnClick", function() ArcadeDB.sound = not ArcadeDB.sound; sndText() end)
  sndText()

  local accLbl = ns.Label(settingsPanel, "Theme", 14); accLbl:SetPoint("TOPLEFT", 24, -104)
  for i, key in ipairs(ORDER) do
    local a = ACCENTS[key]
    local sw = CreateFrame("Button", nil, settingsPanel)
    sw:SetSize(64, 26); sw:SetPoint("TOPLEFT", 24 + (i - 1) * 74, -134)
    local t = sw:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints()
    ns.Grad(t, "VERTICAL", { a.base[1] * 0.7, a.base[2] * 0.7, a.base[3] * 0.7 }, a.lite)
    addBorder(sw, ns.C.edge)
    sw:SetScript("OnClick", function()
      ArcadeDB.accent = key
      ns.C.accent, ns.C.accentLite = a.base, a.lite
      ApplyAccent()
    end)
  end

  local close = ns.NewButton(settingsPanel, "Back", 100, 28, function() ns.ShowMenu() end)
  close:SetPoint("BOTTOM", 0, 16)
end

local function buildStats()
  statsPanel = ns.Panel(mainFrame)
  statsPanel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT")
  statsPanel:SetSize(ns.CONTENT_W, ns.CONTENT_H)
  statsPanel:SetFrameLevel(mainFrame:GetFrameLevel() + 20)
  statsPanel:Hide()

  local h = ns.Header(statsPanel, "Trophies", 20); h:SetPoint("TOP", 0, -14)
  statsPanel._lines = {}
  for i, a in ipairs(ns.ACH) do
    local row = ns.Label(statsPanel, "", 12); row:SetPoint("TOPLEFT", 20, -44 - (i - 1) * 30)
    row:SetPoint("RIGHT", -20, 0); row:SetJustifyH("LEFT")
    statsPanel._lines[i] = row
  end
  local close = ns.NewButton(statsPanel, "Back", 100, 28, function() ns.ShowMenu() end)
  close:SetPoint("BOTTOM", 0, 16)
end

local function showStats()
  homeFrame:Hide(); contentFrame:Hide()
  for i, a in ipairs(ns.ACH) do
    local got = ArcadeDB.ach and ArcadeDB.ach[a.id]
    statsPanel._lines[i]:SetText((got and "|cffe9d5a0" or "|cff555060")
      .. a.name .. "|r  |cff8a8090" .. a.desc .. "|r")
  end
  statsPanel:Show()
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local function buildUI()
  local f = CreateFrame("Frame", "AzerothArcadeFrame", UIParent)
  mainFrame = f
  f:SetSize(ns.MAIN_W, ns.MAIN_H)
  f:SetPoint("CENTER")
  f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true); f:SetFrameStrata("HIGH")
  f:Hide()

  local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
  ns.Grad(bg, "VERTICAL", ns.C.bg1, ns.C.bg2)
  addBorder(f, ns.C.edge)

  -- title bar
  local title = CreateFrame("Frame", nil, f)
  title:SetPoint("TOPLEFT", 1, -1); title:SetPoint("TOPRIGHT", -1, -1); title:SetHeight(30)
  title:SetFrameLevel(f:GetFrameLevel() + 1)
  title:EnableMouse(true); title:RegisterForDrag("LeftButton")
  title:SetScript("OnDragStart", function() f:StartMoving() end)
  title:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  local tbg = title:CreateTexture(nil, "ARTWORK"); tbg:SetAllPoints()
  ns.Grad(tbg, "VERTICAL", { 0.20, 0.13, 0.28 }, { 0.11, 0.07, 0.16 })
  titleFS = title:CreateFontString(nil, "OVERLAY")
  titleFS:SetFont(ns.FONT_FANCY, 19); titleFS:SetTextColor(c4(ns.C.gold))
  titleFS:SetPoint("CENTER"); titleFS:SetText("Azeroth Arcade")

  local topLvl = f:GetFrameLevel() + 6   -- above the draggable title bar
  local close = ns.NewButton(f, "X", 26, 22, function() f:Hide() end)
  close:SetPoint("TOPRIGHT", -4, -4); close:SetFrameLevel(topLvl)
  local gear = ns.NewButton(f, "Settings", 74, 22, function()
    homeFrame:Hide(); contentFrame:Hide(); if statsPanel then statsPanel:Hide() end
    settingsPanel:Show()
  end)
  gear:SetPoint("TOPRIGHT", -34, -4); gear:SetFrameLevel(topLvl)
  local trophyBtn = ns.NewButton(f, "Trophies", 74, 22, function() showStats() end)
  trophyBtn:SetPoint("TOPRIGHT", -112, -4); trophyBtn:SetFrameLevel(topLvl)

  backBtn = ns.NewButton(f, "< Menu", 66, 22, function() ns.ShowMenu() end)
  backBtn:SetPoint("TOPLEFT", 6, -4); backBtn:SetFrameLevel(topLvl); backBtn:Hide()

  scoreFS = ns.Label(f, "", 13, ns.C.text); scoreFS:SetPoint("TOP", -60, -38)
  bestFS = ns.Label(f, "", 13, ns.C.gold); bestFS:SetPoint("TOP", 70, -38)

  contentFrame = CreateFrame("Frame", nil, f)
  contentFrame:SetPoint("TOPLEFT", 16, -60)
  contentFrame:SetSize(ns.CONTENT_W, ns.CONTENT_H)
  contentFrame:Hide()

  -- toast
  toastFrame = ns.Panel(f)
  toastFrame:SetSize(300, 42); toastFrame:SetPoint("TOP", 0, -62)
  toastFrame:SetFrameStrata("DIALOG")
  toastText = ns.Label(toastFrame, "", 12, ns.C.text); toastText:SetPoint("CENTER")
  toastFrame:SetScript("OnUpdate", function(self)
    if self._until and GetTime() > self._until then
      local a = self:GetAlpha() - 0.03
      if a <= 0 then self:Hide(); self._until = nil else self:SetAlpha(a) end
    end
  end)
  toastFrame:Hide()

  buildHome()
  buildSettings()
  buildStats()
  built = true
end

local function Toggle()
  if not built then buildUI() end
  if mainFrame:IsShown() then mainFrame:Hide()
  else mainFrame:Show(); if not current then ns.ShowMenu() end end
end
ns.Toggle = Toggle

------------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------------
local function createMinimap()
  if minimapBtn then return end
  local b = CreateFrame("Button", "AzerothArcadeMinimapButton", Minimap)
  b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp"); b:RegisterForDrag("LeftButton")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Dice_01")
  icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local ring = b:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); ring:SetSize(53, 53); ring:SetPoint("TOPLEFT")
  local function pos()
    local ang = math.rad(ArcadeDB.minimapAngle or 210)
    b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", math.cos(ang) * 80, math.sin(ang) * 80)
  end
  pos()
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter(); local s = Minimap:GetEffectiveScale()
      local cx, cy = GetCursorPosition(); cx, cy = cx / s, cy / s
      local atan2 = math.atan2 or math.atan
      ArcadeDB.minimapAngle = math.deg(atan2(cy - my, cx - mx)); pos()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function() Toggle() end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cffb98cffAzeroth Arcade|r")
    GameTooltip:AddLine("Click to play", 0.8, 0.8, 0.8); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  minimapBtn = b
end

------------------------------------------------------------------------
-- Bootstrap
------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, _, name)
  if name ~= ADDON then return end
  ArcadeDB = ArcadeDB or {}
  ArcadeDB.best = ArcadeDB.best or {}
  ArcadeDB.ach = ArcadeDB.ach or {}
  ArcadeDB.stats = ArcadeDB.stats or {}
  ArcadeDB.stats.plays = ArcadeDB.stats.plays or {}
  if ArcadeDB.sound == nil then ArcadeDB.sound = true end
  if ArcadeDB.minimapAngle == nil then ArcadeDB.minimapAngle = 210 end
  local acc = ACCENTS[ArcadeDB.accent or "amethyst"] or ACCENTS.amethyst
  ns.C.accent, ns.C.accentLite = acc.base, acc.lite
  createMinimap()
  boot:UnregisterEvent("ADDON_LOADED")
  ns.Msg("loaded — " .. #ns.games .. " games. Type " .. ns.GOLD .. "/arcade|r to play.")
end)
ns.boot = boot

SLASH_AZEROTHARCADE1 = "/arcade"
SLASH_AZEROTHARCADE2 = "/ac"
SlashCmdList["AZEROTHARCADE"] = function() Toggle() end
