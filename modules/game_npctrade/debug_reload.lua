if g_modules.getModule('game_npctrade') then
  g_modules.getModule('game_npctrade'):reload()
end

-- Use loadUI to load the style file and create the window instance defined in it
local window = g_ui.loadUI('/modules/game_npctrade/styles/quicksell', g_ui.getRootWidget())

if window then
  window:show()
  window:raise()
  window:focus()
else
  print("Failed to load window from styles/quicksell")
end
