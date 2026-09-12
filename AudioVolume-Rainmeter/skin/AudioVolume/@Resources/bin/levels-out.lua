-- AudioVolume / levels-out.lua
-- Rainmeter keys Lua states by ScriptFile path; two sibling measures on ONE file share the
-- same table, so Update() would run once and both cards would get the same number.
-- Two physical files => two independent states => one channel each.
--
-- Returns a SINGLE number: mixing two values into "out mic" does not work because a
-- section-variable reference in a Calc formula is truncated at the first number.

local MODE      = "out"
local levelPath = nil
local raw       = 0
local value     = 0
local lastMs    = 0

local FALL_PER_S = 130
local GATE       = 7

local function nowMs()
  return math.floor(os.clock() * 1000)
end

local function gate(v)
  if v <= GATE then return 0 end
  local scaled = (v - GATE) * 100 / (100 - GATE)
  if scaled > 100 then scaled = 100 end
  return scaled
end

local function readRaw()
  local f = io.open(levelPath, "r")
  if not f then return 0 end
  local s = f:read("*all")
  f:close()
  if MODE == "mic" then
    return gate(tonumber(string.match(s, "mic=(%d+)")) or 0)
  end
  return gate(tonumber(string.match(s, "out=(%d+)")) or 0)
end

function Initialize()
  levelPath = SKIN:GetVariable("CURRENTPATH") .. "@Resources/bin/level.txt"
  raw = readRaw()
  value = raw
  lastMs = nowMs()
end

function Update()
  local t = nowMs()
  local dt = t - lastMs
  if dt < 0 then dt = 0 end
  lastMs = t

  raw = readRaw()
  if raw > value then
    value = raw
  else
    value = value - FALL_PER_S * dt / 1000
    if value < raw then value = raw end
  end
  return math.floor(value + 0.5)
end
