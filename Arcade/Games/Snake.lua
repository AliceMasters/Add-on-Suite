--[[ Azeroth Arcade — Snake.  Eat, grow, don't bite yourself or the walls. ]]
local ADDON, ns = ...

------------------------------------------------------------------------
-- Pure logic
------------------------------------------------------------------------
local Logic = {}
ns.logic["snake"] = Logic

local DIRS = { up = { -1, 0 }, down = { 1, 0 }, left = { 0, -1 }, right = { 0, 1 } }
local OPP = { up = "down", down = "up", left = "right", right = "left" }

function Logic.placeFood(s, rng)
  rng = rng or math.random
  local occ = {}
  for _, seg in ipairs(s.snake) do occ[seg[1] * 100 + seg[2]] = true end
  local empties = {}
  for r = 1, s.n do for c = 1, s.n do
    if not occ[r * 100 + c] then empties[#empties + 1] = { r, c } end
  end end
  if #empties == 0 then return false end
  s.food = empties[rng(#empties)]
  return true
end

function Logic.new(n, rng)
  n = n or 17
  local mid = math.floor(n / 2)
  local s = { n = n, snake = { { mid, mid }, { mid, mid - 1 }, { mid, mid - 2 } },
              dir = "right", nextDir = "right", food = nil, over = false, win = false, score = 0 }
  Logic.placeFood(s, rng)
  return s
end

function Logic.setDir(s, d)
  if not DIRS[d] then return end
  if d == OPP[s.dir] then return end     -- can't reverse into yourself
  s.nextDir = d
end

function Logic.tick(s, rng)
  if s.over then return end
  s.dir = s.nextDir or s.dir
  local d = DIRS[s.dir]
  local head = s.snake[1]
  local nr, nc = head[1] + d[1], head[2] + d[2]
  if nr < 1 or nr > s.n or nc < 1 or nc > s.n then s.over = true; return end
  local eating = (nr == s.food[1] and nc == s.food[2])
  local checkTo = eating and #s.snake or (#s.snake - 1)   -- tail vacates unless growing
  for i = 1, checkTo do
    if s.snake[i][1] == nr and s.snake[i][2] == nc then s.over = true; return end
  end
  table.insert(s.snake, 1, { nr, nc })
  if eating then
    s.score = s.score + 1
    if not Logic.placeFood(s, rng) then s.over = true; s.win = true end
  else
    table.remove(s.snake)
  end
end

------------------------------------------------------------------------
-- View
------------------------------------------------------------------------
local N, SIZE, GAP = 17, 22, 1
local frame, cells, state, overlay, overlayText, running = nil, nil, nil, nil, nil, 0

local function paint(r, c, col)
  local t = cells[r][c]
  t:SetColorTexture(col[1], col[2], col[3], 1)
end

local EMPTY = { 0.10, 0.11, 0.13 }
local BODY  = { 0.30, 0.80, 0.35 }
local HEAD  = { 0.55, 1.00, 0.55 }
local FOOD  = { 0.95, 0.30, 0.30 }

local function render()
  for r = 1, N do for c = 1, N do paint(r, c, EMPTY) end end
  if state.food then paint(state.food[1], state.food[2], FOOD) end
  for i = #state.snake, 1, -1 do
    local seg = state.snake[i]
    paint(seg[1], seg[2], i == 1 and HEAD or BODY)
  end
end

local function showOver()
  overlayText:SetText((state.win and "|cff40ff40You filled it!|r" or "|cffff5555Game Over|r")
    .. "\n|cffffd200Score " .. state.score .. "|r")
  overlay:Show()
end

local function loop(myGen)
  if myGen ~= running or not state then return end
  if not state.over then
    Logic.tick(state)
    render()
    ns.SetScore(state.score)
    ns.SubmitBest("snake", state.score)
    if state.over then showOver(); return end
    local interval = math.max(0.07, 0.16 - state.score * 0.005)
    C_Timer.After(interval, ns.Safe(function() loop(myGen) end))
  end
end

local function newGame()
  state = Logic.new(N)
  overlay:Hide()
  render()
  ns.SetScore(0)
  running = running + 1
  local g = running
  C_Timer.After(0.4, ns.Safe(function() loop(g) end))
end

local KEYDIR = { LEFT = "left", A = "left", RIGHT = "right", D = "right",
                 UP = "up", W = "up", DOWN = "down", S = "down" }

local function build(content)
  frame = CreateFrame("Frame", nil, content)
  frame:SetAllPoints()

  local board = CreateFrame("Frame", nil, frame)
  local dim = N * SIZE + (N + 1) * GAP
  board:SetSize(dim, dim)
  board:SetPoint("TOP", 0, -4)
  local bbg = board:CreateTexture(nil, "BACKGROUND"); bbg:SetAllPoints(); bbg:SetColorTexture(0, 0, 0, 0.6)

  cells = {}
  for r = 1, N do
    cells[r] = {}
    for c = 1, N do
      local t = board:CreateTexture(nil, "ARTWORK")
      t:SetSize(SIZE, SIZE)
      t:SetPoint("TOPLEFT", GAP + (c - 1) * (SIZE + GAP), -(GAP + (r - 1) * (SIZE + GAP)))
      cells[r][c] = t
    end
  end

  local newBtn = ns.NewButton(frame, "Restart (N)", 110, 22, function() newGame() end)
  newBtn:SetPoint("BOTTOMLEFT", 4, 4)
  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMRIGHT", -6, 8)
  hint:SetText("Arrow keys / WASD")

  overlay = CreateFrame("Frame", nil, frame)
  overlay:SetAllPoints(board); overlay:SetFrameLevel(board:GetFrameLevel() + 20)
  local obg = overlay:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints(); obg:SetColorTexture(0, 0, 0, 0.72)
  overlayText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge"); overlayText:SetPoint("CENTER", 0, 18)
  local again = ns.NewButton(overlay, "Play Again", 120, 26, function() newGame() end)
  again:SetPoint("CENTER", 0, -30)
  overlay:Hide()

  frame:EnableKeyboard(true)
  frame:SetScript("OnKeyDown", function(self, key)
    if key == "N" then newGame(); self:SetPropagateKeyboardInput(false); return end
    local d = KEYDIR[key]
    if d then self:SetPropagateKeyboardInput(false); if state then Logic.setDir(state, d) end
    else self:SetPropagateKeyboardInput(true) end
  end)
end

local function start(content)
  if not frame then build(content) end
  frame:Show()
  frame:EnableKeyboard(true)
  newGame()
end

local function stop()
  running = running + 1               -- cancel the loop
  if frame then frame:EnableKeyboard(false); frame:Hide() end
end

ns.Register({ id = "snake", name = "Snake", desc = "Eat, grow, don't crash.",
              start = start, stop = stop })
