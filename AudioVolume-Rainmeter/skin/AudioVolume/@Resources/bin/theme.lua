-- AudioVolume / theme.lua
-- Owns the day/night choice. The colors live in AudioVolume.ini [Variables].
--
-- Toggle() rewrites the palette into the ini with !WriteKeyValue and then refreshes the
-- skin, so every meter is created fresh with the right colors. Runtime !SetOption color
-- switching proved unreliable here: a bang-supplied Shape string that Rainmeter cannot
-- resolve leaves the meter blank, which is what made the cards disappear.

local statePath = nil

local PALETTES = {
  night = {
    ColorPanel      = "10,22,38,200",
    ColorPanelLine  = "64,96,134,170",
    ColorCard       = "20,40,64,210",
    ColorCardLine   = "92,134,180,190",
    ColorFrame      = "92,134,180,190",
    ColorTitle      = "255,255,255,255",
    ColorLabel      = "168,196,226,255",
    ColorDim        = "255,255,255,255",
    ColorBig        = "255,255,255,255",
    ColorBigAlt     = "150,182,216,255",
    ColorAccent     = "72,182,255,255",
    ColorAccentDim  = "64,216,178,255",
    ColorTrack      = "110,150,192,120",
  },
  day = {
    ColorPanel      = "176,190,208,205",
    ColorPanelLine  = "138,162,190,190",
    ColorCard       = "244,248,254,215",
    ColorCardLine   = "146,172,202,200",
    ColorFrame      = "112,140,174,255",
    ColorTitle      = "4,16,32,255",
    ColorLabel      = "40,62,88,255",
    ColorDim        = "8,22,40,255",
    ColorBig        = "0,8,22,255",
    ColorBigAlt     = "52,74,100,255",
    ColorAccent     = "10,92,174,255",
    ColorAccentDim  = "4,136,110,255",
    ColorTrack      = "152,178,206,200",
  },
}

local function readState()
  local f = io.open(statePath, "r")
  if not f then return "night" end
  local s = f:read("*all")
  f:close()
  if s then
    s = string.gsub(s, "%s+", "")
    if s == "day" then return "day" end
  end
  return "night"
end

local function writeState(name)
  local f = io.open(statePath, "w")
  if f then
    f:write(name)
    f:close()
  end
end

local function writePalette(name)
  local p = PALETTES[name] or PALETTES.night
  local n = 0
  for key, value in pairs(p) do
    SKIN:Bang("!WriteKeyValue", "Variables", key, value, SKIN:GetVariable("CURRENTPATH") .. "AudioVolume.ini")
    n = n + 1
  end
  SKIN:Bang("!Log", "AudioVolume theme: wrote " .. n .. " colors for " .. name)
end

function Initialize()
  statePath = SKIN:GetVariable("CURRENTPATH") .. "@Resources/bin/state.txt"
  SKIN:Bang("!SetVariable", "ThemeName", readState())
end

function Update()
  return 0
end

function Toggle()
  local nextTheme = (readState() == "day") and "night" or "day"
  writeState(nextTheme)
  writePalette(nextTheme)
  SKIN:Bang("!SetVariable", "ThemeName", nextTheme)
  SKIN:Bang("!Refresh")
end
