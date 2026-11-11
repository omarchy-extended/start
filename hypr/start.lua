-- Start's keyboard shortcut, from ~/.config/omext/start.json ("shortcut"; set in
-- Start's Settings). Not there: SUPER + ALT + M, which Omarchy leaves free.
-- "SUPER + SPACE" takes the place of Omarchy's menu; "" binds nothing.
local config = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/omext/start.json"
-- Turned off (Omarchy menu › Setup › Omarchy Extended › Start): nothing bound, Super + Space stays Omarchy's.
local state = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/omext/start/disabled"
local offf = io.open(state, "r")
if offf then offf:close() return end

local default = "SUPER + ALT + M"
local key, menu = default, default
local f = io.open(config, "r")
if f then
  local text = f:read("*a")
  f:close()
  key = text:match('"shortcut"%s*:%s*"([^"]*)"') or key
  menu = text:match('"omarchyMenu"%s*:%s*"([^"]*)"') or menu
end
if key ~= "" then
  pcall(hl.unbind, key)
  o.bind(key, "Start menu", "omarchy-shell omext.start toggle")
end

-- Omarchy's dock turned off by omext core (asked for in Start's Settings or
-- Setup › Omarchy Extended, or while omext taskbar is on, in its place): its
-- app grid's keys open Start's apps instead.
local dockoff = io.open(state:gsub("start/disabled$", "core/omarchy-dock-off"), "r")
if dockoff then
  dockoff:close()
  pcall(hl.unbind, "SUPER + ALT + SPACE")
  o.bind("SUPER + ALT + SPACE", "Apps (Start)", "omarchy-shell omext.start page apps")
end

-- Start on Super + Space: Omarchy's menu moves ("omarchyMenu": Start's default
-- keys, a swap, unless set otherwise; "" leaves it on Start's right click only).
if key == "SUPER + SPACE" and menu ~= "" then
  pcall(hl.unbind, menu)
  o.bind(menu, "Omarchy menu", { menu = "root" })
end
