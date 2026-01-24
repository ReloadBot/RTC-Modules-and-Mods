local npcName = nil
local dialogStarted = false
local connectedPlayer = nil

local config = {
  bankNpcs = {"paulie", "suzy", "naji", "eva", "rokyn", "finarfin", "tezila", "muzir", "ebenizer", "gnomillion", "tesha", "ferks", "jefrey", "elgar", "raffael", "jessica", "znozel", "murim", "eighty"},
  captainNpcs = {"anna",
    "brodrosch",
    "captain bluebear",
    "captain breezelda",
    "captain chelop",
    "captain cookie",
    "captain dreadnought",
    "captain fearless",
    "captain greyhound",
    "captain gulliver",
    "captain haba",
    "captain harava",
    "captain jack",
    "captain jack rat",
    "captain kurt",
    "captain max",
    "captain pelagia",
    "captain seagull",
    "captain seahorse",
    "captain sinbeard",
    "captain tiberius",
    "captain waverider",
    "charles",
    "dalbrect",
    "ghost captain",
    "graubart",
    "gurbasch",
    "harlow",
    "hawkhurst",
    "jack fate",
    "junkar",
    "karith",
    "kendra",
    "maris",
    "pemaret",
    "petros",
    "sebastian",
    "thorgrin",
    "urks the mute",
    "zurak"}
}

function init()
  npcWindow = g_ui.displayUI('npc_dialog')
  
  -- Bind Input Enter Key explicitly via keyboard handler
  g_keyboard.bindKeyPress('Enter', function()
    if npcWindow and npcWindow:isVisible() then
      local textInput = npcWindow:recursiveGetChildById('textInput')
      if textInput:isFocused() then
        onTextSubmit()
      end
    end
  end, npcWindow)
  
  connect(g_game, {
    onTalk = onTalk,
    onGameStart = refreshPlayerConnection,
    onGameEnd = disconnectPlayer
  })
  
  if g_game.isOnline() then
    refreshPlayerConnection()
  end
end

-- ... (rest of file)

function sendTalk(message)
  if not g_game.isOnline() then return end
  
  -- Try to use game_console logic to mirror behavior
  if modules.game_console then
    local console = modules.game_console
    local tab = console.getTab("NPCs") or console.getTab("NPC") -- Check likely names
    if tab then
      console.sendMessage(message, tab)
      -- console.sendMessage handles sending packet AND adding to console tab
      -- We still add to our window for feedback
      local player = g_game.getLocalPlayer()
      local playerName = player and player:getName() or 'You'
      addText(playerName .. ': ' .. message, MessageModes.NpcTo)
      return
    end
  end

  -- Fallback if game_console/NPC tab not found
  g_game.talk(message)
  local player = g_game.getLocalPlayer()
  local playerName = player and player:getName() or 'You'
  addText(playerName .. ': ' .. message, MessageModes.NpcTo)
end

function terminate()
  disconnectPlayer()
  disconnect(g_game, {
    onTalk = onTalk,
    onGameStart = refreshPlayerConnection,
    onGameEnd = disconnectPlayer
  })

  if npcWindow then
    npcWindow:destroy()
    npcWindow = nil
  end
end

function refreshPlayerConnection()
  disconnectPlayer()
  local player = g_game.getLocalPlayer()
  if player then
    connect(player, { onPositionChange = onPlayerPositionChange })
    connectedPlayer = player
  end
end

function disconnectPlayer()
  if connectedPlayer then
    disconnect(connectedPlayer, { onPositionChange = onPlayerPositionChange })
    connectedPlayer = nil
  end
end

function onPlayerPositionChange(creature, newPos, oldPos)
  -- Close dialog on teleport (distance > 1 or Z change)
  if oldPos and (math.abs(newPos.x - oldPos.x) > 1 or math.abs(newPos.y - oldPos.y) > 1 or newPos.z ~= oldPos.z) then
    if npcWindow and npcWindow:isVisible() then
       close()
    end
  end
end

local lastCloseTime = 0

function show()
  if npcWindow and g_clock.millis() > lastCloseTime + 2000 then
    if not npcWindow:isVisible() then
      npcWindow:setWidth(397)
      local separator = npcWindow:recursiveGetChildById('separator')
      if separator then separator:setVisible(false) end
    end
    npcWindow:show()
    npcWindow:raise()
    npcWindow:focus()
  end
end

function close()
  if npcWindow then
    npcWindow:hide()
    clearContext()
    npcName = nil
    dialogStarted = false
    lastCloseTime = g_clock.millis()
  end
end

-- Local definitions to match console colors
local NpcSpeakTypes = {
  [MessageModes.NpcTo] = { color = '#9F9DFD' },
  [MessageModes.NpcFrom] = { color = '#5FF7F7' },
  [MessageModes.NpcFromStartBlock] = { color = '#5FF7F7' }
}

-- Helper to parse {keyword}
function getHighlightedText(text)
  local tmpData = {}
  repeat
    local tmp = {string.find(text, '{([^}]+)}', tmpData[#tmpData - 1])}
    for _, v in pairs(tmp) do
      table.insert(tmpData, v)
    end
  until not (string.find(text, '{([^}]+)}', tmpData[#tmpData - 1]))
  return tmpData
end

function addText(text, mode, colorOverride)
  if not npcWindow then return end
  local panel = npcWindow:recursiveGetChildById('dialogPanel')
  if not panel then return end

  local label = g_ui.createWidget('NpcDialogLabel', panel)
  label.highlightInfo = {}
  
  local speaktype = NpcSpeakTypes[mode]
  local color = '#5FF7F7' -- Default NPC
  if speaktype and speaktype.color then
    color = speaktype.color
  end
  if colorOverride then
    color = colorOverride
  end
  label:setColor(color)

  -- Process highlighting if NPC message
  if mode == MessageModes.NpcFrom or mode == MessageModes.NpcFromStartBlock then
    local formattedText = ""
    local plainText = ""
    local lastIndex = 1
    local found = false
    
    for s, word, e in text:gmatch("()%{(.-)%}()") do
        found = true
        -- Text before matches
        local pre = text:sub(lastIndex, s - 1)
        if #pre > 0 then
            formattedText = formattedText .. string.format("{%s, %s}", pre, color)
            plainText = plainText .. pre
        end
        
        -- The keyword
        local startMap = #plainText + 1
        
        formattedText = formattedText .. string.format("{%s, %s}", word, '#1f9ffe')
        plainText = plainText .. word
        
        local endMap = #plainText
        
        -- Map indices for click detection
        for i = startMap, endMap do
            label.highlightInfo[i] = word
        end
        
        lastIndex = e
    end
    
    if found then
        -- Remaining text
        local post = text:sub(lastIndex)
        if #post > 0 then
            formattedText = formattedText .. string.format("{%s, %s}", post, color)
            plainText = plainText .. post
        end
        label:setColoredText(formattedText)
    else
        label:setText(text)
    end
  else
    label:setText(text)
  end
  
  -- Click handler
  label.onMouseRelease = function(self, mousePos, mouseButton)
    if mouseButton == MouseLeftButton then
      local position = label:getTextPos(mousePos)
      if position and label.highlightInfo[position] then
        sendTalk(label.highlightInfo[position])
      end
    end
  end
end

function updateBankButtons(visible)
  if not npcWindow then return end
  local buttonBalance = npcWindow:recursiveGetChildById('buttonBalance')
  local buttonDeposit = npcWindow:recursiveGetChildById('buttonDeposit')
  local buttonWithdraw = npcWindow:recursiveGetChildById('buttonWithdraw')
  
  if visible then
    buttonBalance:setVisible(true)
    buttonBalance:setWidth(35)
    buttonBalance:setHeight(35)
    
    buttonDeposit:setVisible(true)
    buttonDeposit:setWidth(35)
    buttonDeposit:setHeight(35)
    
    buttonWithdraw:setVisible(true)
    buttonWithdraw:setWidth(35)
    buttonWithdraw:setHeight(35)
  else
    buttonBalance:setVisible(false)
    buttonBalance:setWidth(0)
    buttonBalance:setHeight(0)
    
    buttonDeposit:setVisible(false)
    buttonDeposit:setWidth(0)
    buttonDeposit:setHeight(0)
    
    buttonWithdraw:setVisible(false)
    buttonWithdraw:setWidth(0)
    buttonWithdraw:setHeight(0)
  end
end

function updateSailButton(visible)
  if not npcWindow then return end
  local buttonSail = npcWindow:recursiveGetChildById('buttonSail')
  
  if visible then
    buttonSail:setVisible(true)
    buttonSail:setWidth(35)
    buttonSail:setHeight(35)
  else
    buttonSail:setVisible(false)
    buttonSail:setWidth(0)
    buttonSail:setHeight(0)
  end
end

function updateButtonsLayout()
  -- Layout is handled by OTUI horizontalBox
end

function checkNpcConfig(name)
  local nameLower = string.lower(name)
  
  -- Bank
  local isBanker = false
  for _, bankName in pairs(config.bankNpcs) do
    if string.find(nameLower, bankName) then
      isBanker = true
      break
    end
  end
  updateBankButtons(isBanker)
  
  -- Hide Trade for Bankers
local buttonTrade = npcWindow:recursiveGetChildById('buttonTrade')
if buttonTrade then
  if isBanker or isCaptain then
    buttonTrade:setVisible(false)
    buttonTrade:setWidth(0)
  else
    buttonTrade:setVisible(true)
    buttonTrade:setWidth(35)
  end
end
  
  -- Captain
  local isCaptain = false
  for _, capName in pairs(config.captainNpcs) do
    if string.find(nameLower, capName) then
      isCaptain = true
      break
    end
  end
  updateSailButton(isCaptain)
  
  -- Layout
  updateButtonsLayout()
end

function findNpcCreature(name, pos)
  local spectators = g_map.getSpectators(pos, false)
  for _, creature in pairs(spectators) do
    if creature:getName() == name then
      return creature
    end
  end
  return nil
end

function clearContext()
  if not npcWindow then return end
  local panel = npcWindow:recursiveGetChildById('dialogPanel')
  if panel then
    panel:destroyChildren()
  end
end

function onTalk(name, level, mode, text, channelId, creaturePos)
  if mode == MessageModes.NpcFromStartBlock then
    -- Novo NPC ou novo diálogo
    if npcName ~= name then
      clearContext()
      dialogStarted = false
    end

    npcName = name
    show()
    checkNpcConfig(name)

    -- Outfit
    local npcOutfitWidget = npcWindow:recursiveGetChildById('npcOutfit')
    if npcOutfitWidget and creaturePos then
      local creature = findNpcCreature(name, creaturePos)
      if creature then
        npcOutfitWidget:setOutfit(creature:getOutfit())
      end
    end

    -- Nome do NPC
    local nameLabel = npcWindow:recursiveGetChildById('npcNameLabel')
    if nameLabel then
      nameLabel:setText(name)
    end

    -- ✅ Timestamp APENAS no início do diálogo
    if not dialogStarted then
      local timestamp = os.date("%H:%M:%S")
      addText(timestamp .. ' Talking To ' .. name, mode, '#FFFFFF')
      dialogStarted = true
    end

    addText(name .. ' says: ' .. text, mode)

  elseif mode == MessageModes.NpcFrom then
    addText(name .. ' says: ' .. text, mode)

  elseif mode == MessageModes.NpcTo then
    addText(name .. ': ' .. text, mode)
  end
end

function doBalance()
  sendTalk('balance')
end

function doDepositAll()
  sendTalk('deposit all')
end

function doWithdraw()
  sendTalk('withdraw')
end

function doSail()
  sendTalk('sail')
end

function doYes()
  sendTalk('yes')
end

function doNo()
  sendTalk('no')
end

function doTrade()
  sendTalk('trade')
  if npcWindow then
    npcWindow:setWidth(600)
    local separator = npcWindow:recursiveGetChildById('separator')
    if separator then separator:setVisible(true) end
  end
end

function doBye()
  sendTalk('bye')
  close()
end

function doChatToggle()
  local chatButton = npcWindow:recursiveGetChildById('chatButton')
  local textInput = npcWindow:recursiveGetChildById('textInput')
  
  if chatButton:getText() == tr('Chat On') then
    chatButton:setText(tr('Chat Off'))
    textInput:setEnabled(false)
    textInput:clearFocus()
  else
    chatButton:setText(tr('Chat On'))
    textInput:setEnabled(true)
    textInput:focus()
  end
end

function getTradeContainer()
  if npcWindow then
    return npcWindow:recursiveGetChildById('tradeContainer')
  end
  return nil
end

function onTextSubmit()
  local textInput = npcWindow:recursiveGetChildById('textInput')
  local text = textInput:getText()
  if #text > 0 then
    sendTalk(text)
    textInput:setText('')
  end
end
