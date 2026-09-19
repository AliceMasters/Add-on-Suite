--[[ Azeroth Arcade — a cabinet of mini-games in one window.
     Core.lua: shared shell, game registry, hub menu, scores, minimap button.
     /arcade  /ac  to open. ]]

local ADDON, ns = ...

------------------------------------------------------------------------
-- Constants exposed to game modules
------------------------------------------------------------------------
ns.MAIN_W, ns.MAIN_H = 460, 588
ns.CONTENT_W, ns.CONTENT_H = 436, 452
ns.GOLD = "|cffffd200"

ns.games = {}     -- ordered list of game defs
ns.logic = {}     -- id -> pure logic table (for headless tests)

local mainFrame, contentFrame, menuFrame, titleFS, scoreFS, bestFS, backBtn, minimapBtn
local current            -- currently running game def
local built = false

------------------------------------------------------------------------
-- Helpers (shared with game modules via ns.*)
------------------------------------------------------------------------
function ns.Msg(t)
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffArcade|r: " .. t)
end

function ns.Sound(kit)
  if ArcadeDB and ArcadeDB.sound and kit then pcall(PlaySound, kit) end
end

-- run an async callback safely: surfaces errors, never leaves the UI wedged
function ns.Safe(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff4444Arcade ERROR|r: " .. tostring(err))
    end
  end
end

function ns.Register(def)
  ns.games[#ns.games + 1] = def
end

function ns.Best(id)
  return (ArcadeDB and ArcadeDB.best and ArcadeDB.best[id]) or 0
end

function ns.NewButton(parent, text, w, h, onclick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 100, h or 24)
  b:SetText(text or "")
  if onclick then b:SetScript("OnClick", onclick) end
  return b
end

-- consistent dark panel with a gold edge
function ns.Panel(parent)
  local p = CreateFrame("Frame", nil, parent)
  local bg = p:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
  return p
end

------------------------------------------------------------------------
-- Score / footer
------------------------------------------------------------------------
function ns.SetScore(n)
  if scoreFS then scoreFS:SetText("Score: " .. (n or 0)) end
end

-- arbitrary text in the score slot (e.g. "Mines: 7")
function ns.SetInfo(t)
  if scoreFS then scoreFS:SetText(t or "") end
end

function ns.SubmitBest(id, n)
  ArcadeDB.best = ArcadeDB.best or {}
  if n > (ArcadeDB.best[id] or 0) then
    ArcadeDB.best[id] = n
  end
  if bestFS then bestFS:SetText("Best: " .. ns.Best(id)) end
  return ArcadeDB.best[id]
end

------------------------------------------------------------------------
-- Navigation
------------------------------------------------------------------------
function ns.ShowMenu()
  if current and current.stop then pcall(current.stop) end
  current = nil
  if titleFS then titleFS:SetText(ns.GOLD .. "Azeroth Arcade|r") end
  if scoreFS then scoreFS:SetText("") end
  if bestFS then bestFS:SetText("") end
  if backBtn then backBtn:Hide() end
  if contentFrame then contentFrame:Hide() end
  if menuFrame then menuFrame:Show() end
end

function ns.PlayGame(id)
  for _, def in ipairs(ns.games) do
    if def.id == id then
      if current and current.stop then pcall(current.stop) end
      current = def
      menuFrame:Hide()
      contentFrame:Show()
      titleFS:SetText(ns.GOLD .. def.name .. "|r")
      scoreFS:SetText("Score: 0")
      bestFS:SetText("Best: " .. ns.Best(id))
      backBtn:Show()
      def.start(contentFrame)
      return
    end
  end
end

------------------------------------------------------------------------
-- Menu (built from the registry)
------------------------------------------------------------------------
local function BuildMenu()
  menuFrame = CreateFrame("Frame", nil, mainFrame)
  menuFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT")
  menuFrame:SetSize(ns.CONTENT_W, ns.CONTENT_H)

  local head = menuFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  head:SetPoint("TOP", 0, -6)
  head:SetText("Choose your game")

  local y = -44
  for _, def in ipairs(ns.games) do
    local row = ns.NewButton(menuFrame, "", ns.CONTENT_W - 40, 52)
    row:SetPoint("TOP", 0, y)
    row:SetText("")
    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("LEFT", 14, 8)
    name:SetText(ns.GOLD .. def.name .. "|r")
    local desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("LEFT", 14, -12)
    desc:SetText(def.desc or "")
    local best = row:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    best:SetPoint("RIGHT", -14, 0)
    row.best = best
    row:SetScript("OnClick", function() ns.PlayGame(def.id) end)
    row:SetScript("OnShow", function() best:SetText("Best\n" .. ns.Best(def.id)) end)
    y = y - 62
  end

  local hint = menuFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOM", 0, 8)
  hint:SetText("Drag the title bar to move  •  /arcade to toggle")
end

------------------------------------------------------------------------
-- Main window
------------------------------------------------------------------------
local function BuildUI()
  local f = CreateFrame("Frame", "AzerothArcadeFrame", UIParent)
  mainFrame = f
  f:SetSize(ns.MAIN_W, ns.MAIN_H)
  f:SetPoint("CENTER")
  f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  f:SetFrameStrata("HIGH")
  f:Hide()

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(); bg:SetColorTexture(0.04, 0.04, 0.06, 0.95)

  local border = CreateFrame("Frame", nil, f)
  border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
  local function edge(p1, p2, w, h)
    local t = border:CreateTexture(nil, "BORDER")
    t:SetColorTexture(0.65, 0.55, 0.25, 1)
    t:SetPoint(p1); t:SetPoint(p2)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
  end
  edge("TOPLEFT", "TOPRIGHT", nil, 2); edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
  edge("TOPLEFT", "BOTTOMLEFT", 2, nil); edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil)

  -- title bar (drag handle)
  local title = CreateFrame("Frame", nil, f)
  title:SetPoint("TOPLEFT", 2, -2); title:SetPoint("TOPRIGHT", -2, -2); title:SetHeight(24)
  title:EnableMouse(true); title:RegisterForDrag("LeftButton")
  title:SetScript("OnDragStart", function() f:StartMoving() end)
  title:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  local tbg = title:CreateTexture(nil, "ARTWORK")
  tbg:SetAllPoints(); tbg:SetColorTexture(0.12, 0.10, 0.04, 1)
  titleFS = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titleFS:SetPoint("CENTER")
  titleFS:SetText(ns.GOLD .. "Azeroth Arcade|r")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() f:Hide() end)

  backBtn = ns.NewButton(f, "‹ Menu", 70, 22, function() ns.ShowMenu() end)
  backBtn:SetPoint("TOPLEFT", 8, -32)
  backBtn:Hide()

  scoreFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  scoreFS:SetPoint("TOP", 0, -36)
  bestFS = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  bestFS:SetPoint("TOPRIGHT", -12, -36)

  contentFrame = CreateFrame("Frame", nil, f)
  contentFrame:SetPoint("TOPLEFT", 12, -58)
  contentFrame:SetSize(ns.CONTENT_W, ns.CONTENT_H)
  contentFrame:Hide()

  BuildMenu()
  built = true
end

local function Toggle()
  if not built then BuildUI() end
  if mainFrame:IsShown() then
    mainFrame:Hide()
  else
    mainFrame:Show()
    if not current then ns.ShowMenu() end
  end
end
ns.Toggle = Toggle

------------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------------
local function CreateMinimapButton()
  if minimapBtn then return end
  local b = CreateFrame("Button", "AzerothArcadeMinimapButton", Minimap)
  b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp"); b:RegisterForDrag("LeftButton")

  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Dice_01")
  icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local ring = b:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  ring:SetSize(53, 53); ring:SetPoint("TOPLEFT")

  local function UpdatePos()
    local angle = math.rad(ArcadeDB.minimapAngle or 210)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
  end
  UpdatePos()

  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local scale = Minimap:GetEffectiveScale()
      local cx, cy = GetCursorPosition()
      cx, cy = cx / scale, cy / scale
      local atan2 = math.atan2 or math.atan
      ArcadeDB.minimapAngle = math.deg(atan2(cy - my, cx - mx))
      UpdatePos()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function() Toggle() end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(ns.GOLD .. "Azeroth Arcade|r")
    GameTooltip:AddLine("Click to play", 0.8, 0.8, 0.8)
    GameTooltip:Show()
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
  if ArcadeDB.sound == nil then ArcadeDB.sound = true end
  if ArcadeDB.minimapAngle == nil then ArcadeDB.minimapAngle = 210 end
  CreateMinimapButton()
  boot:UnregisterEvent("ADDON_LOADED")
  ns.Msg("loaded — " .. #ns.games .. " games. Type " .. ns.GOLD .. "/arcade|r to play.")
end)
ns.boot = boot

SLASH_AZEROTHARCADE1 = "/arcade"
SLASH_AZEROTHARCADE2 = "/ac"
SlashCmdList["AZEROTHARCADE"] = function() Toggle() end
