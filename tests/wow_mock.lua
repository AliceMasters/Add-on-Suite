-- Minimal World of Warcraft API mock, enough to load and drive Bejeweled.lua
-- headlessly. Frames/textures are plain tables; unknown methods are no-ops.
-- C_Timer is backed by a fake clock + queue that the test harness pumps, so the
-- addon's real timer-driven cascade runs deterministically without a game client.

local CLOCK = 0
local TIMERS = {}
CHAT_LOG = {}          -- captures DEFAULT_CHAT_FRAME:AddMessage (incl. Safe() errors)

-- ---- object factory: methods table + no-op fallback via __index ----
local function makeobj(methods, kind)
  local o = { _kind = kind, _scripts = {}, _shown = true,
              _vc = {1, 1, 1}, _tex = nil, _fill = nil, _text = nil }
  setmetatable(o, { __index = function(_, k)
    local m = methods[k]
    if m then return m end
    return function() return nil end          -- everything else is a no-op
  end })
  return o
end

local TexMethods, FrameMethods = {}, {}

function TexMethods.SetTexture(self, p) self._tex = p end
function TexMethods.SetVertexColor(self, r, g, b) self._vc = {r, g, b} end
function TexMethods.SetColorTexture(self, r, g, b, a) self._fill = {r, g, b, a} end
function TexMethods.Show(self) self._shown = true end
function TexMethods.Hide(self) self._shown = false end

function FrameMethods.SetScript(self, name, fn) self._scripts[name] = fn end
function FrameMethods.GetScript(self, name) return self._scripts[name] end
function FrameMethods.HookScript(self, name, fn) self._scripts[name] = fn end
function FrameMethods.IsShown(self) return self._shown end
function FrameMethods.Show(self) self._shown = true end
function FrameMethods.Hide(self) self._shown = false end
function FrameMethods.CreateTexture(self) return makeobj(TexMethods, "texture") end
function FrameMethods.CreateFontString(self) return makeobj(FrameMethods, "fontstring") end
function FrameMethods.SetText(self, t) self._text = t end
function FrameMethods.GetEffectiveScale() return 1 end
function FrameMethods.GetLeft() return 0 end
function FrameMethods.GetTop() return 0 end
function FrameMethods.GetCenter() return 0, 0 end
function FrameMethods.RegisterEvent() end
function FrameMethods.UnregisterEvent() end

_G.CreateFrame = function(_, name, _, _)
  local f = makeobj(FrameMethods, "frame")
  if name then _G[name] = f end
  return f
end

_G.C_Timer = { After = function(delay, fn)
  table.insert(TIMERS, { t = CLOCK + delay, fn = fn })
end }

_G.GetTime = function() return CLOCK end
_G.GetCursorPosition = function() return 0, 0 end

-- pump all due timers (and any they schedule) until the queue drains
function PumpTimers()
  local ran = 0
  while #TIMERS > 0 do
    -- find earliest
    local bi, bt = 1, TIMERS[1].t
    for i = 2, #TIMERS do if TIMERS[i].t < bt then bi, bt = i, TIMERS[i].t end end
    local job = table.remove(TIMERS, bi)
    CLOCK = job.t
    job.fn()
    ran = ran + 1
    if ran > 200000 then error("PumpTimers runaway (possible infinite cascade)") end
  end
  return ran
end

-- globals the addon touches
_G.UIParent       = makeobj(FrameMethods, "frame")
_G.WorldFrame     = makeobj(FrameMethods, "frame")
_G.Minimap        = makeobj(FrameMethods, "frame")
_G.UIErrorsFrame  = makeobj(FrameMethods, "frame")
_G.GameTooltip    = makeobj(FrameMethods, "frame")
_G.DEFAULT_CHAT_FRAME = makeobj(FrameMethods, "frame")
_G.DEFAULT_CHAT_FRAME.AddMessage = function(_, msg) table.insert(CHAT_LOG, msg) end

_G.SlashCmdList = {}
_G.IsMouseButtonDown = function() return false end
_G.PlaySound = function() end
_G.CreateColor = function(r, g, b, a)
  return { r = r, g = g, b = b, a = a or 1, GetRGBA = function(self) return self.r, self.g, self.b, self.a end }
end
-- deterministic clock for streak tests: MOCK_TIME settable from the harness
MOCK_TIME = 1758400000
_G.time = function() return MOCK_TIME end
_G.date = function(fmt) return "2026-09-21" end
_G.SOUNDKIT = setmetatable({}, { __index = function() return 0 end })
