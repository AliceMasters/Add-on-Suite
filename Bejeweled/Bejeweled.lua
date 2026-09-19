--[[ Bejeweled — a single-player match-3 for World of Warcraft.
     /bej  /bejeweled  /gems  to open. ]]

local ADDON = ...

------------------------------------------------------------------------
-- Config / constants
------------------------------------------------------------------------
local ROWS, COLS   = 8, 8
local CELL, GAP    = 42, 5
local BOARD_W      = COLS * CELL + (COLS + 1) * GAP
local BOARD_H      = ROWS * CELL + (ROWS + 1) * GAP
local SPEED        = 900          -- gem movement px/sec
local SWAP_TIME    = 0.16
local FADE_TIME    = 0.20
local FALL_TIME    = 0.30
local IDLE_HINT    = 8            -- seconds idle before auto-hint

-- The seven gem types.
--   bg   = cell background colour (always shows the gem's colour)
--   icon = vertex tint applied to the icon texture. Tinting is what makes a
--          gem ALWAYS read as its true colour: even if the icon file resolves
--          to a generic grey crystal, or a recycled button kept a stale
--          texture from a previous gem, the tint forces it to the right hue.
--          This is the fix for "gems not showing what they represent."
local GEMS = {
  { name = "Ruby",     tex = "Interface\\Icons\\INV_Misc_Gem_Bloodstone_01", bg = {0.45, 0.06, 0.08}, icon = {1.00, 0.28, 0.28} },
  { name = "Sapphire", tex = "Interface\\Icons\\INV_Misc_Gem_Sapphire_02",   bg = {0.08, 0.18, 0.55}, icon = {0.40, 0.60, 1.00} },
  { name = "Emerald",  tex = "Interface\\Icons\\INV_Misc_Gem_Emerald_02",    bg = {0.06, 0.38, 0.14}, icon = {0.35, 1.00, 0.45} },
  { name = "Topaz",    tex = "Interface\\Icons\\INV_Misc_Gem_Topaz_02",      bg = {0.55, 0.44, 0.03}, icon = {1.00, 0.88, 0.22} },
  { name = "Amethyst", tex = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02",   bg = {0.38, 0.12, 0.58}, icon = {0.82, 0.45, 1.00} },
  { name = "Opal",     tex = "Interface\\Icons\\INV_Misc_Gem_Opal_01",       bg = {0.58, 0.28, 0.04}, icon = {1.00, 0.62, 0.20} },
  { name = "Diamond",  tex = "Interface\\Icons\\INV_Misc_Gem_Diamond_04",    bg = {0.30, 0.55, 0.62}, icon = {0.70, 0.95, 1.00} },
}
local NCOLORS = #GEMS
local HYPER_TEX = "Interface\\Icons\\INV_Enchant_ShardPrismaticLarge"
local FLAME_TEX = "Interface\\Icons\\Spell_Fire_Fire"

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local board = {}          -- board[r][c] = gem (or nil)
local activeGems = {}      -- set of live gems (for OnUpdate)
local pool = {}            -- recycled buttons
local selected            -- currently selected gem
local inputLocked = true
local comboLevel = 0
local score, level, levelScore, levelTarget = 0, 1, 0, 1000
local lastSwap            -- {r,c} used to place special gems
local lastInput = 0
local built = false
local gameGen = 0         -- bumped on New Game; stale async callbacks check it and bail

local mainFrame, boardFrame, minimapBtn
local scoreFS, levelFS, bestFS, progress, selMarker
local hintTex = {}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function Msg(t)
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffBejeweled|r: " .. t)
end

local function Sound(kit)
  if BejeweledDB and BejeweledDB.sound and kit then pcall(PlaySound, kit) end
end

-- Wrap async callbacks so any error is shown in chat instead of failing
-- silently (and never leaves the board permanently locked).
local function Safe(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff4444Bejeweled ERROR|r: " .. tostring(err))
      inputLocked = false
    end
  end
end
local S = {}   -- resolved lazily (SOUNDKIT may not exist on ancient clients)
local function InitSounds()
  if not SOUNDKIT then return end
  S.select  = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
  S.swap    = SOUNDKIT.IG_MAINMENU_OPTION
  S.bad     = SOUNDKIT.IG_QUEST_FAILED
  S.match   = SOUNDKIT.IG_MAINMENU_OPEN
  S.special = SOUNDKIT.IG_MAINMENU_CLOSE
  S.level   = SOUNDKIT.LEVELUP
end

local function CellOffset(r, c)
  local ox = GAP + (c - 1) * (CELL + GAP)
  local oy = -(GAP + (r - 1) * (CELL + GAP))
  return ox, oy
end

------------------------------------------------------------------------
-- Gem buttons (pooled) + appearance
------------------------------------------------------------------------
local OnGemClick, OnGemDragStart, OnGemDragStop   -- forward decls

local function AcquireButton()
  local b = table.remove(pool)
  if b then b:Show(); b:SetAlpha(1); return b end
  b = CreateFrame("Button", nil, boardFrame)
  b:SetSize(CELL, CELL)
  b:RegisterForClicks("LeftButtonUp")
  b:RegisterForDrag("LeftButton")
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(1, 1, 1, 1)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 3, -3)
  b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.badge = b:CreateTexture(nil, "OVERLAY")
  b.badge:SetSize(18, 18)
  b.badge:SetPoint("TOPRIGHT", 2, 2)
  b.badge:Hide()
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.18)
  b:SetScript("OnClick",     function(self) if self.gem then OnGemClick(self.gem) end end)
  b:SetScript("OnDragStart", function(self) if self.gem then OnGemDragStart(self.gem) end end)
  b:SetScript("OnDragStop",  function(self) if self.gem then OnGemDragStop(self.gem) end end)
  return b
end

local function SetGemAppearance(gem)
  local b = gem.btn
  if gem.special == "hyper" then
    b.bg:SetColorTexture(0.10, 0.10, 0.16, 1)
    b.icon:SetTexture(HYPER_TEX)
    b.icon:SetVertexColor(1, 1, 1)
    b.badge:Hide()
  else
    local g = GEMS[gem.color]
    b.bg:SetColorTexture(g.bg[1], g.bg[2], g.bg[3], 1)
    b.icon:SetTexture(g.tex)
    b.icon:SetVertexColor(g.icon[1], g.icon[2], g.icon[3])   -- force true hue (fixes stale/greyscale icons)
    if gem.special == "flame" then
      b.badge:SetTexture(FLAME_TEX)
      b.badge:Show()
    else
      b.badge:Hide()
    end
  end
end

local function NewGem(color, r, c)
  local gem = { color = color, r = r, c = c, alpha = 1 }
  gem.btn = AcquireButton()
  gem.btn.gem = gem
  SetGemAppearance(gem)
  activeGems[gem] = true
  return gem
end

local function ReleaseGem(gem)
  activeGems[gem] = nil
  local b = gem.btn
  if b then
    b.gem = nil
    b:Hide()
    b:SetAlpha(1)
    b.badge:Hide()
    table.insert(pool, b)
  end
  gem.btn = nil
end

local function PlaceGemInstant(gem)
  local ox, oy = CellOffset(gem.r, gem.c)
  gem.curX, gem.curY, gem.tgtX, gem.tgtY, gem.anim = ox, oy, ox, oy, false
  gem.btn:ClearAllPoints()
  gem.btn:SetPoint("TOPLEFT", boardFrame, "TOPLEFT", ox, oy)
end

-- animate gem to a (curX/curY untouched -> it slides from wherever it is)
local function AnimGemTo(gem, r, c)
  gem.r, gem.c = r, c
  gem.tgtX, gem.tgtY = CellOffset(r, c)
  gem.anim = true
end

------------------------------------------------------------------------
-- Match finding
------------------------------------------------------------------------
-- returns list of groups: { {r=,c=}, ..., len=, color= }
local function FindMatches()
  local groups = {}
  -- horizontal
  for r = 1, ROWS do
    local c = 1
    while c <= COLS do
      local g = board[r][c]
      local col = g and g.color
      local run = 1
      if col and col > 0 then
        while c + run <= COLS and board[r][c + run] and board[r][c + run].color == col do
          run = run + 1
        end
      end
      if col and col > 0 and run >= 3 then
        local grp = { len = run, color = col }
        for i = 0, run - 1 do grp[#grp + 1] = { r = r, c = c + i } end
        groups[#groups + 1] = grp
      end
      c = c + run
    end
  end
  -- vertical
  for c = 1, COLS do
    local r = 1
    while r <= ROWS do
      local g = board[r][c]
      local col = g and g.color
      local run = 1
      if col and col > 0 then
        while r + run <= ROWS and board[r + run][c] and board[r + run][c].color == col do
          run = run + 1
        end
      end
      if col and col > 0 and run >= 3 then
        local grp = { len = run, color = col }
        for i = 0, run - 1 do grp[#grp + 1] = { r = r + i, c = c } end
        groups[#groups + 1] = grp
      end
      r = r + run
    end
  end
  return groups
end

------------------------------------------------------------------------
-- Scoring / UI updates
------------------------------------------------------------------------
local function UpdateUI()
  scoreFS:SetText("Score: " .. score)
  levelFS:SetText("Level " .. level)
  bestFS:SetText("Best: " .. (BejeweledDB and BejeweledDB.highScore or 0))
  progress:SetMinMaxValues(0, levelTarget)
  progress:SetValue(levelScore)
end

local function AddScore(pts)
  score = score + pts
  levelScore = levelScore + pts
  if BejeweledDB and score > (BejeweledDB.highScore or 0) then
    BejeweledDB.highScore = score
  end
  while levelScore >= levelTarget do
    levelScore = levelScore - levelTarget
    level = level + 1
    levelTarget = math.floor(levelTarget * 1.4)
    Sound(S.level)
    UIErrorsFrame:AddMessage("Bejeweled — Level " .. level .. "!", 0.4, 1, 0.4)
  end
  UpdateUI()
end

------------------------------------------------------------------------
-- Resolve matches -> clears -> gravity -> refill -> cascade
------------------------------------------------------------------------
local ResolveStep, Collapse, CheckNoMoves

local function ProcessMatches(groups)
  local clear = {}                         -- clear[r*100+c] = true
  local convert = {}                       -- list of {r,c,kind}
  local function key(r, c) return r * 100 + c end

  -- decide specials, mark clears
  for _, grp in ipairs(groups) do
    for _, cell in ipairs(grp) do clear[key(cell.r, cell.c)] = true end
    if grp.len >= 4 then
      -- place on the swapped cell if it's in this group, else the middle
      local target
      if lastSwap then
        for _, cell in ipairs(grp) do
          if cell.r == lastSwap.r and cell.c == lastSwap.c then target = cell; break end
        end
      end
      target = target or grp[math.ceil(grp.len / 2)]
      convert[#convert + 1] = { r = target.r, c = target.c,
                                kind = (grp.len >= 5) and "hyper" or "flame" }
    end
  end

  -- flame detonation: any flame gem being cleared blows up its 3x3
  local queue = {}
  for k in pairs(clear) do
    local r, c = math.floor(k / 100), k % 100
    local g = board[r][c]
    if g and g.special == "flame" then queue[#queue + 1] = { r = r, c = c } end
  end
  while #queue > 0 do
    local cur = table.remove(queue)
    for dr = -1, 1 do
      for dc = -1, 1 do
        local nr, nc = cur.r + dr, cur.c + dc
        if nr >= 1 and nr <= ROWS and nc >= 1 and nc <= COLS then
          local k = key(nr, nc)
          local g = board[nr][nc]
          if g and not clear[k] then
            clear[k] = true
            if g.special == "flame" then queue[#queue + 1] = { r = nr, c = nc } end
          end
        end
      end
    end
  end

  -- converted cells survive (don't clear them)
  for _, cv in ipairs(convert) do clear[key(cv.r, cv.c)] = nil end

  -- score
  local n = 0
  for _ in pairs(clear) do n = n + 1 end
  local mult = comboLevel
  AddScore(n * 40 * mult)
  if #convert > 0 then AddScore(#convert * 120); Sound(S.special) end
  Sound(S.match)

  -- start fades on cleared gems
  for k in pairs(clear) do
    local r, c = math.floor(k / 100), k % 100
    local g = board[r][c]
    if g then g.removed = true; g.fading = true end
  end
  -- convert survivors into specials
  for _, cv in ipairs(convert) do
    local g = board[cv.r][cv.c]
    if g then
      g.special = cv.kind
      if cv.kind == "hyper" then g.color = 0 end
      SetGemAppearance(g)
    end
  end

  return n > 0
end

local function RemoveFaded()
  for r = 1, ROWS do
    for c = 1, COLS do
      local g = board[r][c]
      if g and g.removed then
        ReleaseGem(g)
        board[r][c] = nil
      end
    end
  end
end

function Collapse()
  for c = 1, COLS do
    -- gather survivors bottom-up
    local stack = {}
    for r = ROWS, 1, -1 do
      if board[r][c] then stack[#stack + 1] = board[r][c]; board[r][c] = nil end
    end
    local row = ROWS
    for _, gem in ipairs(stack) do
      board[row][c] = gem
      if gem.r ~= row then AnimGemTo(gem, row, c) else gem.r = row end
      row = row - 1
    end
    -- spawn new gems in the empty top rows (1..row), dropping from above
    local empty = row
    for rr = 1, empty do
      local gem = NewGem(math.random(NCOLORS), rr, c)
      board[rr][c] = gem          -- CRITICAL: register the spawned gem in the board grid
      local tx = select(1, CellOffset(rr, c))
      local _, startY = CellOffset(rr - empty, c)   -- above the board
      gem.curX, gem.curY = tx, startY
      gem.tgtX, gem.tgtY = CellOffset(rr, c)
      gem.anim = true
      gem.btn:ClearAllPoints()
      gem.btn:SetPoint("TOPLEFT", boardFrame, "TOPLEFT", gem.curX, gem.curY)
    end
  end
end

function ResolveStep()
  local groups = FindMatches()
  if #groups == 0 then
    comboLevel = 0
    lastSwap = nil
    CheckNoMoves()
    inputLocked = false
    return
  end
  comboLevel = comboLevel + 1
  ProcessMatches(groups)
  local gen = gameGen
  C_Timer.After(FADE_TIME, Safe(function()
    if gen ~= gameGen then return end
    RemoveFaded()
    Collapse()
    lastSwap = nil
    C_Timer.After(FALL_TIME, Safe(function()
      if gen ~= gameGen then return end
      ResolveStep()
    end))
  end))
end

------------------------------------------------------------------------
-- Valid-move detection + shuffle + hint
------------------------------------------------------------------------
local function AnyMatch() return #FindMatches() > 0 end

-- try every swap; returns move {r1,c1,r2,c2} or nil (also true if a hyper exists)
local function FindMove()
  for r = 1, ROWS do
    for c = 1, COLS do
      local g = board[r][c]
      if g and g.special == "hyper" then return { r, c, r, c } end
      -- swap right
      if c < COLS and board[r][c + 1] then
        board[r][c], board[r][c + 1] = board[r][c + 1], board[r][c]
        local ok = AnyMatch()
        board[r][c], board[r][c + 1] = board[r][c + 1], board[r][c]
        if ok then return { r, c, r, c + 1 } end
      end
      -- swap down
      if r < ROWS and board[r + 1][c] then
        board[r][c], board[r + 1][c] = board[r + 1][c], board[r][c]
        local ok = AnyMatch()
        board[r][c], board[r + 1][c] = board[r + 1][c], board[r][c]
        if ok then return { r, c, r + 1, c } end
      end
    end
  end
  return nil
end

local function Shuffle()
  for _ = 1, 80 do
    for r = 1, ROWS do
      for c = 1, COLS do
        local g = board[r][c]
        if g then g.special = nil; g.color = math.random(NCOLORS); SetGemAppearance(g) end
      end
    end
    if not AnyMatch() and FindMove() then return true end
  end
  return true
end

function CheckNoMoves()
  if not FindMove() then
    Msg("No moves left — shuffling.")
    Shuffle()
  end
end

local function ShowHint()
  local mv = FindMove()
  for i = 1, 2 do hintTex[i]:Hide() end
  if not mv then return end
  local pts = { { mv[1], mv[2] }, { mv[3], mv[4] } }
  for i = 1, 2 do
    local ox, oy = CellOffset(pts[i][1], pts[i][2])
    hintTex[i]:ClearAllPoints()
    hintTex[i]:SetPoint("TOPLEFT", boardFrame, "TOPLEFT", ox - 3, oy + 3)
    hintTex[i]:SetSize(CELL + 6, CELL + 6)
    hintTex[i]:Show()
  end
  C_Timer.After(2.5, function() for i = 1, 2 do hintTex[i]:Hide() end end)
end

------------------------------------------------------------------------
-- Swapping / input
------------------------------------------------------------------------
local function Adjacent(a, b)
  return (a.r == b.r and math.abs(a.c - b.c) == 1)
      or (a.c == b.c and math.abs(a.r - b.r) == 1)
end

local function ClearSelection()
  selected = nil
  selMarker:Hide()
end

local function SelectGem(gem)
  selected = gem
  selMarker:ClearAllPoints()
  selMarker:SetPoint("CENTER", gem.btn, "CENTER")
  selMarker:Show()
  Sound(S.select)
end

-- swap two gems in the board + animate; run `after` when the tween ends
local function DoSwapAnim(g1, g2, after)
  local r1, c1, r2, c2 = g1.r, g1.c, g2.r, g2.c
  board[r1][c1], board[r2][c2] = g2, g1
  AnimGemTo(g1, r2, c2)
  AnimGemTo(g2, r1, c1)
  C_Timer.After(SWAP_TIME, Safe(after))
end

local function ActivateHyper(hyperGem, otherGem)
  inputLocked = true
  Sound(S.special)
  local gen = gameGen
  local targetColor = otherGem.color
  hyperGem.removed = true; hyperGem.fading = true
  if targetColor and targetColor > 0 then
    for r = 1, ROWS do
      for c = 1, COLS do
        local g = board[r][c]
        if g and g.color == targetColor then g.removed = true; g.fading = true end
      end
    end
  else
    otherGem.removed = true; otherGem.fading = true
  end
  comboLevel = 1
  local n = 0
  for r = 1, ROWS do for c = 1, COLS do if board[r][c] and board[r][c].removed then n = n + 1 end end end
  AddScore(n * 60)
  C_Timer.After(FADE_TIME, Safe(function()
    if gen ~= gameGen then return end
    RemoveFaded(); Collapse()
    C_Timer.After(FALL_TIME, Safe(function()
      if gen ~= gameGen then return end
      ResolveStep()
    end))
  end))
end

local function TrySwap(g1, g2)
  inputLocked = true
  ClearSelection()
  Sound(S.swap)

  -- hypercube: activates on swap without needing a line match
  if g1.special == "hyper" or g2.special == "hyper" then
    local hyper = (g1.special == "hyper") and g1 or g2
    local other = (hyper == g1) and g2 or g1
    ActivateHyper(hyper, other)
    return
  end

  local gen = gameGen
  lastSwap = { r = g2.r, c = g2.c }
  DoSwapAnim(g1, g2, function()
    if gen ~= gameGen then return end
    if AnyMatch() then
      comboLevel = 0
      ResolveStep()
    else
      -- invalid: swap back
      Sound(S.bad)
      DoSwapAnim(g1, g2, function()
        if gen ~= gameGen then return end
        inputLocked = false; lastSwap = nil
      end)
    end
  end)
end

function OnGemClick(gem)
  lastInput = GetTime()
  if inputLocked then return end
  if not selected then
    SelectGem(gem)
  elseif selected == gem then
    ClearSelection()
  elseif Adjacent(selected, gem) then
    TrySwap(selected, gem)
  else
    SelectGem(gem)
  end
end

function OnGemDragStart(gem)
  lastInput = GetTime()
  if inputLocked then return end
  gem._drag = { GetCursorPosition() }
  SelectGem(gem)
end

function OnGemDragStop(gem)
  lastInput = GetTime()
  if inputLocked or not gem._drag then return end
  gem._drag = nil
  local x, y = GetCursorPosition()
  local scale = boardFrame:GetEffectiveScale()
  x, y = x / scale, y / scale
  local relx = x - boardFrame:GetLeft()
  local rely = boardFrame:GetTop() - y
  local c = math.floor((relx - GAP) / (CELL + GAP)) + 1
  local r = math.floor((rely - GAP) / (CELL + GAP)) + 1
  if r >= 1 and r <= ROWS and c >= 1 and c <= COLS then
    local target = board[r][c]
    if target and target ~= gem and Adjacent(gem, target) then
      TrySwap(gem, target)
      return
    end
  end
end

------------------------------------------------------------------------
-- New game
------------------------------------------------------------------------
local function ColorAvoiding(r, c)
  while true do
    local col = math.random(NCOLORS)
    local bad = false
    if c >= 3 and board[r][c-1] and board[r][c-2]
       and board[r][c-1].color == col and board[r][c-2].color == col then bad = true end
    if r >= 3 and board[r-1] and board[r-1][c] and board[r-2][c]
       and board[r-1][c].color == col and board[r-2][c].color == col then bad = true end
    if not bad then return col end
  end
end

local function NewGame()
  -- clear existing
  for r = 1, ROWS do
    board[r] = board[r] or {}
    for c = 1, COLS do
      if board[r][c] then ReleaseGem(board[r][c]); board[r][c] = nil end
    end
  end
  ClearSelection()
  score, level, levelScore, levelTarget = 0, 1, 0, 1000
  comboLevel, lastSwap = 0, nil
  gameGen = gameGen + 1     -- invalidate any in-flight cascade callbacks
  for r = 1, ROWS do
    for c = 1, COLS do
      local gem = NewGem(ColorAvoiding(r, c), r, c)
      board[r][c] = gem
      PlaceGemInstant(gem)
    end
  end
  if not FindMove() then Shuffle() end
  inputLocked = false
  lastInput = GetTime()
  UpdateUI()
end

------------------------------------------------------------------------
-- UI construction
------------------------------------------------------------------------
local function BuildUI()
  local f = CreateFrame("Frame", "BejeweledFrame", UIParent)
  mainFrame = f
  f:SetSize(BOARD_W + 24, BOARD_H + 150)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("HIGH")
  f:Hide()

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.04, 0.04, 0.06, 0.94)

  -- gold-ish border
  local border = CreateFrame("Frame", nil, f)
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)
  local function edge(p1, p2, w, h)
    local t = border:CreateTexture(nil, "BORDER")
    t:SetColorTexture(0.65, 0.55, 0.25, 1)
    t:SetPoint(p1); t:SetPoint(p2)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
    return t
  end
  edge("TOPLEFT", "TOPRIGHT", nil, 2)
  edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
  edge("TOPLEFT", "BOTTOMLEFT", 2, nil)
  edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil)

  -- title bar (drag handle)
  local title = CreateFrame("Frame", nil, f)
  title:SetPoint("TOPLEFT", 2, -2)
  title:SetPoint("TOPRIGHT", -2, -2)
  title:SetHeight(24)
  title:EnableMouse(true)
  title:RegisterForDrag("LeftButton")
  title:SetScript("OnDragStart", function() f:StartMoving() end)
  title:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
  local tbg = title:CreateTexture(nil, "ARTWORK")
  tbg:SetAllPoints()
  tbg:SetColorTexture(0.12, 0.10, 0.04, 1)
  local tfs = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  tfs:SetPoint("CENTER")
  tfs:SetText("|cffffd200Bejeweled|r")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() f:Hide() end)

  -- info row
  scoreFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  scoreFS:SetPoint("TOPLEFT", 14, -34)
  levelFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  levelFS:SetPoint("TOP", 0, -34)
  bestFS = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  bestFS:SetPoint("TOPRIGHT", -14, -34)

  -- progress bar
  progress = CreateFrame("StatusBar", nil, f)
  progress:SetPoint("TOPLEFT", 14, -60)
  progress:SetPoint("TOPRIGHT", -14, -60)
  progress:SetHeight(10)
  progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  progress:SetStatusBarColor(0.3, 0.7, 1)
  progress:SetMinMaxValues(0, 1)
  local pbg = progress:CreateTexture(nil, "BACKGROUND")
  pbg:SetAllPoints()
  pbg:SetColorTexture(0, 0, 0, 0.6)

  -- board
  boardFrame = CreateFrame("Frame", nil, f)
  boardFrame:SetSize(BOARD_W, BOARD_H)
  boardFrame:SetPoint("TOPLEFT", 12, -78)
  local bbg = boardFrame:CreateTexture(nil, "BACKGROUND")
  bbg:SetAllPoints()
  bbg:SetColorTexture(0, 0, 0, 0.55)

  boardFrame:SetScript("OnUpdate", function(self, dt)
    for gem in pairs(activeGems) do
      if gem.anim and gem.btn then
        local dx = gem.tgtX - gem.curX
        local dy = gem.tgtY - gem.curY
        local dist = math.sqrt(dx * dx + dy * dy)
        local step = SPEED * dt
        if dist <= step or dist < 0.5 then
          gem.curX, gem.curY, gem.anim = gem.tgtX, gem.tgtY, false
        else
          gem.curX = gem.curX + dx / dist * step
          gem.curY = gem.curY + dy / dist * step
        end
        gem.btn:SetPoint("TOPLEFT", boardFrame, "TOPLEFT", gem.curX, gem.curY)
      end
      if gem.fading and gem.btn then
        gem.alpha = gem.alpha - dt / FADE_TIME
        if gem.alpha <= 0 then gem.alpha, gem.fading = 0, false; gem.btn:Hide() end
        gem.btn:SetAlpha(gem.alpha)
      end
    end
    -- idle auto-hint
    if not inputLocked and lastInput > 0 and (GetTime() - lastInput) > IDLE_HINT then
      lastInput = GetTime()
      ShowHint()
    end
  end)

  -- selection marker
  selMarker = boardFrame:CreateTexture(nil, "OVERLAY")
  selMarker:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  selMarker:SetBlendMode("ADD")
  selMarker:SetSize(CELL + 20, CELL + 20)
  selMarker:Hide()

  for i = 1, 2 do
    local t = boardFrame:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    t:SetBlendMode("ADD")
    t:SetVertexColor(0.4, 1, 0.4)
    t:Hide()
    hintTex[i] = t
  end

  -- footer buttons
  local hintBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  hintBtn:SetSize(90, 24)
  hintBtn:SetPoint("BOTTOMLEFT", 14, 12)
  hintBtn:SetText("Hint")
  hintBtn:SetScript("OnClick", function() if not inputLocked then ShowHint(); lastInput = GetTime() end end)

  local newBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  newBtn:SetSize(90, 24)
  newBtn:SetPoint("BOTTOM", 0, 12)
  newBtn:SetText("New Game")
  newBtn:SetScript("OnClick", function() NewGame() end)

  local sndBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sndBtn:SetSize(90, 24)
  sndBtn:SetPoint("BOTTOMRIGHT", -14, 12)
  local function sndText() sndBtn:SetText("Sound: " .. (BejeweledDB.sound and "On" or "Off")) end
  sndBtn:SetScript("OnClick", function()
    BejeweledDB.sound = not BejeweledDB.sound
    sndText()
  end)
  sndText()

  built = true
end

local function Toggle()
  if not built then BuildUI() end
  if mainFrame:IsShown() then
    mainFrame:Hide()
  else
    mainFrame:Show()
    -- start a game the first time
    local empty = true
    for r = 1, ROWS do if board[r] and board[r][1] then empty = false break end end
    if empty then NewGame() end
  end
end

------------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------------
local function CreateMinimapButton()
  if minimapBtn then return end
  local b = CreateFrame("Button", "BejeweledMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")

  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Gem_Bloodstone_01")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 1)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  local function UpdatePos()
    local angle = math.rad(BejeweledDB.minimapAngle or 200)
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
      local atan2 = math.atan2 or math.atan   -- atan2 removed in some client Lua builds
      BejeweledDB.minimapAngle = math.deg(atan2(cy - my, cx - mx))
      UpdatePos()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" and built and mainFrame:IsShown() then
      NewGame()
    else
      Toggle()
    end
  end)

  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cffffd200Bejeweled|r")
    GameTooltip:AddLine("|cffffffffLeft-click|r  play / hide", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cffffffffRight-click|r  new game", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cffffffffDrag|r  move this icon", 0.8, 0.8, 0.8)
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
  BejeweledDB = BejeweledDB or {}
  if BejeweledDB.highScore == nil then BejeweledDB.highScore = 0 end
  if BejeweledDB.sound == nil then BejeweledDB.sound = true end
  if BejeweledDB.minimapAngle == nil then BejeweledDB.minimapAngle = 200 end
  InitSounds()
  CreateMinimapButton()
  boot:UnregisterEvent("ADDON_LOADED")
  Msg("loaded. Type |cffffd200/bej|r to play. High score: " .. BejeweledDB.highScore)
end)

SLASH_BEJEWELED1 = "/bej"
SLASH_BEJEWELED2 = "/bejeweled"
SLASH_BEJEWELED3 = "/gems"
SlashCmdList["BEJEWELED"] = function() Toggle() end
