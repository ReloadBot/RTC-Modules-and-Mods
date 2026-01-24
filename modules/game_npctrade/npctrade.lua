BUY = 1
SELL = 2
CURRENCY = 'gold'
CURRENCYID = GOLD_COINS
CURRENCY_DECIMAL = false
WEIGHT_UNIT = 'oz'
LAST_INVENTORY = 10
SORT_BY = 'name'

npcWindow = nil
itemsPanel = nil
radioTabs = nil
radioItems = nil
searchText = nil
setupPanel = nil
quantity = nil
quantityScroll = nil
amountText = nil
idLabel = nil
nameLabel = nil
priceLabel = nil
currencyMoneyLabel = nil
moneyLabel = nil
weightDesc = nil
weightLabel = nil
capacityDesc = nil
capacityLabel = nil
tradeButton = nil
itemButton = nil
headPanel = nil
currencyItem = nil
itemBorder = nil
currencyLabel = nil
buyTab = nil
sellTab = nil
initialized = false

showWeight = true
local buyWithBackpack = false
local ignoreCapacity = false
local ignoreEquipped = true
showAllItems = nil
sellAllButton = nil
sellAllWithDelayButton = nil
playerFreeCapacity = 0
playerMoney = 0
tradeItems = {}
playerItems = {}
sellAllWhitelist = {}
selectedItem = nil

quickSellButton = nil

cancelNextRelease = nil
sellAllWithDelayEvent = nil

-- Batch processing configuration for large item lists
local BATCH_SIZE = 30
local currentBatchIndex = 0
local filteredTradeItems = {}
local batchProcessingEvent = nil

-- Throttle configuration for refreshPlayerGoods
local refreshPlayerGoodsEvent = nil
local REFRESH_THROTTLE_MS = 200

function getFilterFile()
  local player = g_game.getLocalPlayer()
  if not player then return nil end
  return "/characterdata/" .. player:getId() .. "/npctrade.json"
end

function saveData()
  if not g_game.isOnline() then return end
  
  local player = g_game.getLocalPlayer()
  if not player then return end

  -- Ensure the characterdata directory exists
  pcall(function() g_resources.makeDir("/characterdata") end)
  local characterDir = "/characterdata/" .. player:getId()
  pcall(function() g_resources.makeDir(characterDir) end)

  local file = getFilterFile()
  if not file then return end
  
  g_logger.info("NPC Trade: Saving to " .. file)
  
  local status, result = pcall(function() return json.encode(sellAllWhitelist, 2) end)
  if not status then
    return g_logger.error("Error while saving NPC Trade blacklist. Data won't be saved. Details: " .. result)
  end

  if result:len() > 100 * 1024 * 1024 then
    return g_logger.error("NPC Trade: Something went wrong, file is above 100MB, won't be saved")
  end
  
  g_resources.writeFileContents(file, result)
  g_logger.info("NPC Trade: Settings saved successfully")
end

function loadData()
  if not g_game.isOnline() then return end
  
  local player = g_game.getLocalPlayer()
  if not player then return end

  local file = getFilterFile()
  if not file then 
    sellAllWhitelist = {}
    return 
  end
  
  sellAllWhitelist = {}
  
  if g_resources.fileExists(file) then
    local status, result = pcall(function()
      return json.decode(g_resources.readFileContents(file))
    end)

    if not status then
      g_logger.error("NPC Trade: Error reading blacklist file. Details: " .. tostring(result))
      return
    end

    sellAllWhitelist = result or {}

  end
end

function removeItemInList(clientId)
  if type(clientId) ~= "number" then
    return
  end
  if not table.contains(sellAllWhitelist, clientId) then
    return
  end
  for k, v in pairs(sellAllWhitelist) do
    if v == clientId then
      table.remove(sellAllWhitelist, k)
      break
    end
  end
end

function inWhiteList(clientId)
  if not clientId then
    clientId = 0
  end
  if not sellAllWhitelist then
    return false
  end

  return table.contains(sellAllWhitelist, clientId)
end

function addToWhitelist(clientId)
  if type(clientId) ~= "number" then
    return
  end

  if table.contains(sellAllWhitelist, clientId) then
    return
  end

  table.insert(sellAllWhitelist, clientId)
end

function init()
  g_ui.importStyle('/data/styles/30-npctrader')
  npcWindow = g_ui.loadUI('npctrade')
  npcWindow:show()
  npcWindow:setVisible(false)

  itemsPanel = npcWindow:recursiveGetChildById('contentsPanel')
  if not itemsPanel:getLayout() then
    local layout = UIVerticalLayout.create(itemsPanel)
    layout:setAlignBottom(false)
  end
  searchText = npcWindow:recursiveGetChildById('searchText')

  setupPanel = npcWindow:recursiveGetChildById('setupPanel')
  quantityScroll = setupPanel:getChildById('quantityScroll')
  amountText = setupPanel:getChildById('amountText')

  priceLabel = setupPanel:getChildById('price')
  currencyMoneyLabel = setupPanel:getChildById('currencyMoneyLabel')
  moneyLabel = setupPanel:getChildById('money')
  itemButton = setupPanel:getChildById('item')
  tradeButton = npcWindow:recursiveGetChildById('tradeButton')
  headPanel = npcWindow:recursiveGetChildById('headPanel')
  currencyItem = headPanel:getChildById('currencyItem')
  itemBorder = headPanel:getChildById('itemBorder')
  currencyLabel = headPanel:getChildById('currencyLabel')

  buyTab = npcWindow:recursiveGetChildById('buyTab')
  sellTab = npcWindow:recursiveGetChildById('sellTab')

  quickSellButton = npcWindow:recursiveGetChildById('quickSellButton')

  radioTabs = UIRadioGroup.create()
  radioTabs:addWidget(buyTab)
  radioTabs:addWidget(sellTab)
  radioTabs:selectWidget(buyTab)
  radioTabs.onSelectionChange = onTradeTypeChange

  cancelNextRelease = false
  if g_game.isOnline() then
    playerFreeCapacity = g_game.getLocalPlayer():getFreeCapacity()
  end

  connect(g_game, {
    onGameStart = start,
    onGameEnd = hide,
    onOpenNpcTrade = onOpenNpcTrade,
    onCloseNpcTrade = onCloseNpcTrade,
    onPlayerGoods = onPlayerGoods
  })

  connect(LocalPlayer, {
    onFreeCapacityChange = onFreeCapacityChange,
    onInventoryChange = onInventoryChange
  })

  -- Register to intercept trade messages for Quick Sell total tracking
  registerMessageMode(MessageModes.TradeNpc, onQuickSellTradeMessage)

  initialized = true
end

function terminate()
  initialized = false
  
  -- Cancel any ongoing batch processing
  removeEvent(batchProcessingEvent)
  batchProcessingEvent = nil
  filteredTradeItems = {}
  
  -- Cancel any pending refresh
  removeEvent(refreshPlayerGoodsEvent)
  refreshPlayerGoodsEvent = nil
  
  npcWindow:destroy()

  sellAllWhitelist = {}

  disconnect(g_game, {
    onGameEnd = hide,
    onOpenNpcTrade = onOpenNpcTrade,
    onCloseNpcTrade = onCloseNpcTrade,
    onPlayerGoods = onPlayerGoods
  })

  disconnect(LocalPlayer, {
    onFreeCapacityChange = onFreeCapacityChange,
    onInventoryChange = onInventoryChange
  })

  -- Unregister the trade message callback
  unregisterMessageMode(MessageModes.TradeNpc, onQuickSellTradeMessage)
  
  npcWindow = nil
  itemsPanel = nil
  quantityScroll = nil
  tradeButton = nil
  setupPanel = nil
end

function show()
  if g_game.isOnline() then
    if #tradeItems[BUY] > 0 then
      radioTabs:selectWidget(buyTab)
      quickSellButton:setEnabled(false)
    else
      radioTabs:selectWidget(sellTab)
      quickSellButton:setEnabled(true)
    end

    npcWindow:show()
    npcWindow:raise()
    
    local container = nil
    if modules.npc_dialog then
      container = modules.npc_dialog.getTradeContainer()
    end
    
    if container then
        npcWindow:setParent(container)
        npcWindow:fill('parent')
        npcWindow:setVisible(true)
    else
        -- Fallback to side panel
        if not m_interface.addToPanels(npcWindow) then
          return false
        end
        if npcWindow and npcWindow:isVisible() then
          npcWindow:getParent():moveChildToIndex(npcWindow, #npcWindow:getParent():getChildren())
          npcWindow.close = function() closeNpcTrade() end
        end
    end
    
    npcWindow:focus()
    setupPanel:enable()
  end
end

function start()
  local benchmark = g_clock.millis()
  loadData()

end

function hide()
  if not npcWindow then
    return
  end

  -- Cancel any ongoing batch processing
  removeEvent(batchProcessingEvent)
  batchProcessingEvent = nil
  filteredTradeItems = {}
  
  -- Cancel any pending refresh
  removeEvent(refreshPlayerGoodsEvent)
  refreshPlayerGoodsEvent = nil

  saveData()

  npcWindow:hide()

  toggleNPCFocus(false)
  m_interface.getConsole():focus()

  local layout = itemsPanel:getLayout()
  if layout then
    layout:disableUpdates()
  end

  clearSelectedItem()

  searchText:clearText()
  setupPanel:disable()
  itemsPanel:destroyChildren()

  if radioItems then
    radioItems:destroy()
    radioItems = nil
  end

  layout:enableUpdates()
  layout:update()
end

function onItemBoxChecked(widget)
  itemButton:setItemId(0)
  quantityScroll:setValue(0)
  if widget:isChecked() then
    local item = widget.item
    selectedItem = item
    refreshItem(item)
    tradeButton:enable()

    if getCurrentTradeType() == SELL then
      quantityScroll:setValue(quantityScroll:getMaximum())
      amountText:setText(quantityScroll:getMaximum())
    end
  end
end

function onQuantityValueChange(quantity)
  if selectedItem then
    priceLabel:setText(comma_value(formatCurrency(getItemPrice(selectedItem))))
    amountText:setText(quantity)
  end
end

function onTradeTypeChange(radioTabs, selected, deselected)
  tradeButton:setText(selected:getText())
  selected:setOn(true)
  deselected:setOn(false)

  if selected == buyTab then
    quickSellButton:setEnabled(false)
  else
    quickSellButton:setEnabled(true)
  end

  refreshTradeItems()
  refreshPlayerGoods()
end

function onTradeClick()
  if not selectedItem then return end
  removeEvent(sellAllWithDelayEvent)
  if getCurrentTradeType() == BUY then
    g_game.buyItem(selectedItem.ptr, quantityScroll:getValue(), ignoreCapacity, buyWithBackpack)
  else
    g_game.sellItem(selectedItem.ptr, quantityScroll:getValue(), ignoreEquipped)
  end
end

function onSearchTextChange()
  refreshPlayerGoods()
  clearSelectedItem()
end

function onExtraMenu()
  local mousePosition = g_window.getMousePosition()
  if cancelNextRelease then
    cancelNextRelease = false
    return false
  end

  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addCheckBoxOption(tr('Sort by name'), function()
    SORT_BY = 'name'; refreshPlayerGoods()
  end, "", SORT_BY == 'name')
  menu:addCheckBoxOption(tr('Sort by price'), function()
    SORT_BY = 'price'; refreshPlayerGoods()
  end, "", SORT_BY == 'price')
  menu:addCheckBoxOption(tr('Sort by weight'), function()
    SORT_BY = 'weight'; refreshPlayerGoods()
  end, "", SORT_BY == 'weight')
  menu:addSeparator()
  if getCurrentTradeType() == BUY then
    if CURRENCYID == GOLD_COINS then
      menu:addCheckBoxOption(tr('Buy in shopping bags'),
        function()
          buyWithBackpack = not buyWithBackpack; refreshPlayerGoods()
        end, "", buyWithBackpack)
    end
    menu:addCheckBoxOption(tr('Ignore capacity'), function()
      ignoreCapacity = not ignoreCapacity; refreshPlayerGoods()
    end, "", ignoreCapacity)
  else
    local equippedState = true
    if ignoreEquipped then
      equippedState = false
    end
    menu:addCheckBoxOption(tr('Sell equipped'),
      function()
        ignoreEquipped = not ignoreEquipped; refreshTradeItems(); refreshPlayerGoods()
      end, "", equippedState)
  end
  menu:addSeparator()
  menu:addCheckBoxOption(tr('Show search field'), function() end, "", true)
  menu:addCheckBoxOption(tr('Do not show a warning when trading large amounts'), function() end, "", false)
  menu:display(mousePosition)
  return true
end

function itemPopup(self, mousePosition, mouseButton)
  if cancelNextRelease then
    cancelNextRelease = false
    return false
  end

  local itemWidget = self:getChildById('item')
  if not itemWidget then
    itemWidget = self
  end

  if mouseButton == MouseRightButton then
    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)
    menu:addOption(tr('Look'), function() return g_game.inspectNpcTrade(itemWidget:getItem()) end)
    menu:addOption(tr('Inspect'), function() g_game.sendInspectionObject(3, itemWidget:getItem():getId(), 1) end)
    menu:addSeparator()
    menu:addCheckBoxOption(tr('Sort by name'), function()
      SORT_BY = 'name'; refreshPlayerGoods()
    end, "", SORT_BY == 'name')
    menu:addCheckBoxOption(tr('Sort by price'), function()
      SORT_BY = 'price'; refreshPlayerGoods()
    end, "", SORT_BY == 'price')
    menu:addCheckBoxOption(tr('Sort by weight'), function()
      SORT_BY = 'weight'; refreshPlayerGoods()
    end, "", SORT_BY == 'weight')
    menu:addSeparator()
    if getCurrentTradeType() == BUY then
      if CURRENCYID == GOLD_COINS then
        menu:addCheckBoxOption(tr('Buy in shopping bags'),
          function()
            buyWithBackpack = not buyWithBackpack; refreshPlayerGoods()
          end, "", buyWithBackpack)
      end
      menu:addCheckBoxOption(tr('Ignore capacity'),
        function()
          ignoreCapacity = not ignoreCapacity; refreshPlayerGoods()
        end, "", ignoreCapacity)
    else
      local equippedState = true
      if ignoreEquipped then
        equippedState = false
      end

      menu:addCheckBoxOption(tr('Sell equipped'),
        function()
          ignoreEquipped = not ignoreEquipped; refreshTradeItems(); refreshPlayerGoods()
        end, "", equippedState)
    end
    menu:addSeparator()
    menu:addCheckBoxOption(tr('Show search field'), function() end, "", true)
    menu:addCheckBoxOption(tr('Do not show a warning when trading large amounts'), function() end, "", false)
    menu:display(mousePosition)
    return true
  elseif ((g_mouse.isPressed(MouseLeftButton) and mouseButton == MouseRightButton)
        or (g_mouse.isPressed(MouseRightButton) and mouseButton == MouseLeftButton)) then
    cancelNextRelease = true
    g_game.inspectNpcTrade(itemWidget:getItem())
    return true
  end
  return false
end

function onBuyWithBackpackChange()
  if selectedItem then
    refreshItem(selectedItem)
  end
end

function onIgnoreCapacityChange()
  refreshPlayerGoods()
end

function onIgnoreEquippedChange()
  refreshPlayerGoods()
end

function onShowAllItemsChange()
  refreshPlayerGoods()
end

function setCurrency(currency, decimal)
  CURRENCY = currency
  CURRENCY_DECIMAL = decimal
end

function setShowWeight(state)
  showWeight = state
end

function setShowYourCapacity(state)

end

function clearSelectedItem()
  priceLabel:setText("0")
  if quantityScroll and quantityScroll.setRange then
    quantityScroll:setRange(0, 0)
    quantityScroll:setValue(0)
    quantityScroll:setOn(true)
  end
  amountText:setText('0')
  if selectedItem then
    radioItems:selectWidget(nil)
    selectedItem = nil
  end
end

function getCurrentTradeType()
  if tradeButton:getText() == tr('Buy') then
    return BUY
  else
    return SELL
  end
end

function getItemPrice(item, single)
  local amount = 1
  local single = single or false
  if not single then
    amount = quantityScroll:getValue()
  end
  if getCurrentTradeType() == BUY then
    if buyWithBackpack then
      if item.ptr:isStackable() then
        return item.price * amount + 20
      else
        return item.price * amount + math.ceil(amount / 20) * 20
      end
    end
  end
  return item.price * amount
end

function getSellQuantity(item)
  if not item or not playerItems[item:getId()] then return 0 end
  local removeAmount = 0
  if ignoreEquipped then
    local localPlayer = g_game.getLocalPlayer()
    for i = 1, LAST_INVENTORY do
      local inventoryItem = localPlayer:getInventoryItem(i)
      if inventoryItem and (inventoryItem:getId() == item:getId() and inventoryItem:getTier() == item:getTier()) then
        removeAmount = removeAmount + inventoryItem:getCount()
      end
    end
  end
  return playerItems[item:getId()] - removeAmount
end

function canTradeItem(item)
  if getCurrentTradeType() == BUY then
    return (ignoreCapacity or (not ignoreCapacity and playerFreeCapacity >= item.weight)) and
    getPlayerMoney() >= getItemPrice(item, true)
  else
    return getSellQuantity(item.ptr) > 0
  end
end

function refreshItem(item)
  priceLabel:setText(formatCurrency(getItemPrice(item)))
  itemButton:setItem(item.ptr)
  itemButton.onMouseRelease = itemPopup

  if getCurrentTradeType() == BUY then
    local capacityMaxCount = math.floor(playerFreeCapacity / item.weight)
    if ignoreCapacity then
      capacityMaxCount = uint32Max
    end
    local priceMaxCount = math.floor(getPlayerMoney() / getItemPrice(item, true))
    local finalCount = math.max(0, math.min(getMaxAmount(item), math.min(priceMaxCount, capacityMaxCount)))
    quantityScroll:setRange(1, finalCount)
  else
    quantityScroll:setRange(1, math.max(0, math.min(getMaxAmount(), getSellQuantity(item.ptr))))
  end

  local text = tonumber(amountText:getText())
  if not text then
    amountText:setText(quantityScroll:getMinimum())
  elseif text < quantityScroll:getMinimum() then
    amountText:setText(quantityScroll:getMinimum())
  elseif text > quantityScroll:getMaximum() then
    amountText:setText(quantityScroll:getMaximum())
  end

  setupPanel:enable()
  g_mouse.bindPress(itemButton,
    function(mousePos, mouseMoved) if g_keyboard.isShiftPressed() then g_game.inspectNpcTrade(itemButton:getItem()) end end)
end

function refreshTradeItems()
  if not g_game.isOnline() then
    return
  end

  -- Cancel any ongoing batch processing
  removeEvent(batchProcessingEvent)
  batchProcessingEvent = nil

  local layout = itemsPanel:getLayout()
  layout:disableUpdates()

  clearSelectedItem()

  searchText:clearText()
  itemsPanel:destroyChildren()

  if radioItems then
    radioItems:destroy()
  end
  radioItems = UIRadioGroup.create()

  -- Get and sort items
  local currentTradeItems = tradeItems[getCurrentTradeType()]
  filteredTradeItems = {}
  
  -- For SELL mode: only include items player actually has in inventory
  -- For BUY mode: include all items
  if getCurrentTradeType() == SELL then
    for _, item in ipairs(currentTradeItems) do
      local qty = getSellQuantity(item.ptr)
      if qty > 0 then
        table.insert(filteredTradeItems, item)
      end
    end
    
    -- Sort by quantity descending
    table.sort(filteredTradeItems, function(a, b)
      local qtyA = getSellQuantity(a.ptr)
      local qtyB = getSellQuantity(b.ptr)
      return qtyA > qtyB
    end)
  else
    -- BUY mode: copy all items
    for _, item in ipairs(currentTradeItems) do
      table.insert(filteredTradeItems, item)
    end
  end
  
  currentBatchIndex = 0

  layout:enableUpdates()

  -- Start batch processing
  processNextBatch()
end

-- Helper function to create a single item box widget
function createItemBoxWidget(item)
  local itemBox = g_ui.createWidget('NPCItemBox', itemsPanel)
  itemBox:setId("itemBox_" .. item.name)
  itemBox.item = item
  
  local price = formatCurrency(item.price)
  local informationText = 'Price ' .. price
  
  if showWeight and item.weight > 0 then
    local weight = string.format('%.2f', item.weight) .. ' ' .. WEIGHT_UNIT
    informationText = informationText .. ', ' .. weight
  end

  local description = string.format('%s\n%s', short_text(item.name, 15), short_text(informationText, 16))
  itemBox.nameLabel:setText(description, true)

  local itemWidget = itemBox:getChildById('item')
  itemWidget:setItem(item.ptr)
  itemBox.onMouseRelease = itemPopup

  if (string.len(item.name) > 15) or (string.len(informationText) > 16) then
    itemBox:setTooltip(string.format('%s\n%s', item.name, informationText))
  end

  if not canTradeItem(item) then
    itemBox.nameLabel:setColor('#707070')
  end

  radioItems:addWidget(itemBox)
end

-- Process items in batches to avoid UI freeze
function processNextBatch()
  if not filteredTradeItems or #filteredTradeItems == 0 then
    return
  end

  local startIdx = currentBatchIndex * BATCH_SIZE + 1
  local endIdx = math.min(startIdx + BATCH_SIZE - 1, #filteredTradeItems)

  if startIdx > #filteredTradeItems then
    return
  end

  local layout = itemsPanel:getLayout()
  layout:disableUpdates()

  for i = startIdx, endIdx do
    local item = filteredTradeItems[i]
    if item then
      createItemBoxWidget(item)
    end
  end

  layout:enableUpdates()
  layout:update()

  currentBatchIndex = currentBatchIndex + 1

  -- Schedule next batch if there are more items
  if endIdx < #filteredTradeItems then
    batchProcessingEvent = scheduleEvent(processNextBatch, 10)
  end
end


function refreshPlayerGoods()
  if not initialized then return end

  moneyLabel:setText(comma_value(formatCurrency(getPlayerMoney())))

  local currentTradeType = getCurrentTradeType()
  local searchFilter = searchText:getText():lower()
  local foundSelectedItem = false

  local itemWidgets = {}
  local items = itemsPanel:getChildCount()
  for i = 1, items do
    local itemWidget = itemsPanel:getChildByIndex(i)
    table.insert(itemWidgets, itemWidget)
  end

  local function sortByName(a, b)
    return a.item.name:lower() < b.item.name:lower()
  end

  local function sortByPrice(a, b)
    return a.item.price < b.item.price
  end

  local function sortByWeight(a, b)
    return a.item.weight < b.item.weight
  end

  -- For SELL mode, always prioritize items player has (by quantity desc), then apply secondary sort
  if currentTradeType == SELL then
    table.sort(itemWidgets, function(a, b)
      local qtyA = getSellQuantity(a.item.ptr)
      local qtyB = getSellQuantity(b.item.ptr)
      
      -- Both have quantity - sort by quantity descending
      if qtyA > 0 and qtyB > 0 then
        if SORT_BY == "name" then
          return a.item.name:lower() < b.item.name:lower()
        elseif SORT_BY == "price" then
          return a.item.price > b.item.price
        elseif SORT_BY == "weight" then
          return a.item.weight < b.item.weight
        end
        return qtyA > qtyB
      end
      
      -- Only one has quantity - that one comes first
      if qtyA > 0 and qtyB == 0 then return true end
      if qtyB > 0 and qtyA == 0 then return false end
      
      -- Both have no quantity - apply normal sort
      if SORT_BY == "name" then
        return a.item.name:lower() < b.item.name:lower()
      elseif SORT_BY == "price" then
        return a.item.price < b.item.price
      elseif SORT_BY == "weight" then
        return a.item.weight < b.item.weight
      end
      return a.item.name:lower() < b.item.name:lower()
    end)
  else
    -- BUY mode - use standard sorting
    if SORT_BY == "name" then
      table.sort(itemWidgets, sortByName)
    elseif SORT_BY == "price" then
      table.sort(itemWidgets, sortByPrice)
    elseif SORT_BY == "weight" then
      table.sort(itemWidgets, sortByWeight)
    end
  end

  for index, itemWidget in ipairs(itemWidgets) do
    itemsPanel:moveChildToIndex(itemWidget, index)
  end

  for _, itemWidget in ipairs(itemWidgets) do
    local item = itemWidget.item

    local canTrade = canTradeItem(item)
    
    -- In SELL mode, destroy widgets for items player no longer has
    if currentTradeType == SELL and not canTrade then
      radioItems:removeWidget(itemWidget)
      itemWidget:destroy()
    else
      itemWidget:setOn(canTrade)
      itemWidget.nameLabel:setEnabled(canTrade)
      local searchFilterEscaped = searchFilter:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
      local searchCondition = (searchFilterEscaped == '') or
      (searchFilterEscaped ~= '' and string.find(item.name:lower(), searchFilterEscaped) ~= nil)
      local showAllItemsCondition = (currentTradeType == BUY) or (currentTradeType == SELL and canTrade)
      itemWidget:setVisible(searchCondition and showAllItemsCondition)

      if selectedItem == item and itemWidget:isEnabled() and itemWidget:isVisible() then
        foundSelectedItem = true
      end
    end
  end

  if not foundSelectedItem then
    clearSelectedItem()
  end

  if selectedItem then
    refreshItem(selectedItem)
  end
end

function onOpenNpcTrade(items, currencyId, currencyName)
  CURRENCYID = currencyId
  currencyItem:setItemId(currencyId)
  currencyItem:setVisible(true)
  itemBorder:setVisible(true)
  currencyItem:setItemCount(100)
  currencyItem:setShowCount(false)
  currencyMoneyLabel:setText('Gold:')

  if currencyId ~= GOLD_COINS and currencyName == '' then
    currencyName = getItemServerName(currencyId)
    buyWithBackpack = false
    currencyMoneyLabel:setText('Stock:')
  elseif currencyName ~= '' then
    currencyItem:setVisible(false)
    itemBorder:setVisible(false)
    currencyMoneyLabel:setText('Stock:')
  end

  local currencyName = currencyName ~= '' and currencyName or 'Gold Coin'
  currencyLabel:setText(short_text(currencyName, 11))
  currencyLabel:removeTooltip()
  if #currencyName > 11 then
    currencyLabel:setTooltip(currencyName)
  end

  tradeItems[BUY] = {}
  tradeItems[SELL] = {}
  for _, item in pairs(items) do
    if item[4] > 0 then
      local newItem = {}
      newItem.ptr = item[1]
      newItem.name = item[2]
      newItem.weight = item[3] / 100
      newItem.price = item[4]
      table.insert(tradeItems[BUY], newItem)
    end

    if item[5] > 0 then
      local newItem = {}
      newItem.ptr = item[1]
      newItem.name = item[2]
      newItem.weight = item[3] / 100
      newItem.price = item[5]
      table.insert(tradeItems[SELL], newItem)
    end
  end

  addEvent(show) -- player goods has not been parsed yet
  scheduleEvent(refreshTradeItems, 50)
  scheduleEvent(refreshPlayerGoods, 50)
  if tradeButton:getText() == "Ok" then
    tradeButton:setText("Buy")
  end
end

function closeNpcTrade()
  g_game.doThing(false)
  g_game.closeNpcTrade()
  g_game.doThing(true)
  addEvent(hide)
end

function onCloseNpcTrade()
  addEvent(hide)
end

function onPlayerGoods(money, items)
  playerMoney = money
  playerItems = {}
  if not items then return end
  
  for _, entry in pairs(items) do
    local item = entry[1]
    local amount = entry[2]
    local id = item:getId()
    
    if not playerItems[id] then
      playerItems[id] = amount
    else
      playerItems[id] = playerItems[id] + amount
    end
  end

  scheduleRefreshPlayerGoods()
end

function onFreeCapacityChange(localPlayer, freeCapacity, oldFreeCapacity)
  playerFreeCapacity = freeCapacity

  if npcWindow:isVisible() then
    scheduleRefreshPlayerGoods()
  end
end

function onInventoryChange(inventory, item, oldItem)
  scheduleRefreshPlayerGoods()
end

-- Throttled refresh to avoid excessive updates during bulk operations
function scheduleRefreshPlayerGoods()
  removeEvent(refreshPlayerGoodsEvent)
  refreshPlayerGoodsEvent = scheduleEvent(function()
    refreshPlayerGoodsEvent = nil
    refreshPlayerGoods()
  end, REFRESH_THROTTLE_MS)
end

function getTradeItemData(id, type)
  if table.empty(tradeItems[type]) then
    return false
  end

  if type then
    for key, item in pairs(tradeItems[type]) do
      if item.ptr and item.ptr:getId() == id then
        return item
      end
    end
  else
    for _, items in pairs(tradeItems) do
      for key, item in pairs(items) do
        if item.ptr and item.ptr:getId() == id then
          return item
        end
      end
    end
  end
  return false
end

function checkSellAllTooltip()
  sellAllButton:setEnabled(true)
  sellAllButton:removeTooltip()
  sellAllWithDelayButton:setEnabled(true)
  sellAllWithDelayButton:removeTooltip()

  local total = 0
  local info = ''
  local first = true

  for key, amount in pairs(playerItems) do
    local data = getTradeItemData(key, SELL)
    if data then
      amount = getSellQuantity(data.ptr)
      if amount > 0 then
        if data and amount > 0 then
          info = info .. (not first and "\n" or "") ..
              amount .. " " ..
              data.name .. " (" ..
              data.price * amount .. " gold)"

          total = total + (data.price * amount)
          if first then first = false end
        end
      end
    end
  end
  if info ~= '' then
    info = info .. "\nTotal: " .. total .. " gold"
    sellAllButton:setTooltip(info)
    sellAllWithDelayButton:setTooltip(info)
  else
    sellAllButton:setEnabled(false)
    sellAllWithDelayButton:setEnabled(false)
  end
end

function formatCurrency(amount)
  if CURRENCY_DECIMAL then
    return string.format("%.02f", amount / 100.0)
  else
    return amount
  end
end

function getMaxAmount(item)
  if getCurrentTradeType() == SELL and g_game.getFeature(GameDoubleShopSellAmount) then
    return 10000
  end

  if item and getCurrentTradeType() == BUY and item.ptr:isStackable() then
    return 10000
  end

  return 100
end

function sellAll(delayed, exceptions)
  -- backward support
  if type(delayed) == "table" then
    exceptions = delayed
    delayed = false
  end
  exceptions = exceptions or {}
  removeEvent(sellAllWithDelayEvent)
  local queue = {}
  for _, entry in ipairs(tradeItems[SELL]) do
    local id = entry.ptr:getId()
    if not table.find(exceptions, id) then
      local sellQuantity = getSellQuantity(entry.ptr)
      while sellQuantity > 0 do
        local maxAmount = math.min(sellQuantity, getMaxAmount())
        if delayed then
          g_game.sellItem(entry.ptr, maxAmount, ignoreEquipped)
          sellAllWithDelayEvent = scheduleEvent(function() sellAll(true) end, 1100)
          return
        end
        table.insert(queue, { entry.ptr, maxAmount, ignoreEquipped })
        sellQuantity = sellQuantity - maxAmount
      end
    end
  end
  for _, entry in ipairs(queue) do
    g_game.sellItem(entry[1], entry[2], entry[3])
  end
end

function getPlayerMoney()
  playerMoney = g_game.getLocalPlayer():getResourceValue(ResourceBank) + g_game.getLocalPlayer():getResourceValue(ResourceInventary)
  if CURRENCYID ~= GOLD_COINS and CURRENCYID > 0 then
    playerMoney = g_game.getLocalPlayer():getResourceValue(ResourceNpcTrade)
  elseif CURRENCYID == 0 then
    playerMoney = g_game.getLocalPlayer():getResourceValue(ResourceNpcStorageTrade)
  end

  return playerMoney
end

function onAmountEdit(self)
  local text = tonumber(self:getText())
  if not text then
    return
  end

  local minValue = quantityScroll:getMinimum()
  local maxValue = quantityScroll:getMaximum()
  if minValue > text then
    self:setText(minValue, false)
    text = minValue
  elseif maxValue < text then
    self:setText(maxValue, false)
    text = maxValue
  end

  quantityScroll:setValue(text)
  onQuantityValueChange(tonumber(text))
end

function clearSearch()
  searchText:setText('')
  clearSelectedItem()
end

function onTypeFieldsHover(widget, hovered)
  if not npcWindow then
    return true
  end

  if not hovered and npcWindow:getBorderTopWidth() > 0 then
    return
  end

  m_interface.toggleFocus(hovered, "npctrade")
end

function toggleNPCFocus(visible)
  m_interface.toggleFocus(visible, "npctrade")
  if visible then
    npcWindow:setBorderWidth(2)
    npcWindow:setBorderColor('white')
  else
    npcWindow:setBorderWidth(0)
    m_interface.toggleInternalFocus()
  end
end

function checkItemToSell(self)
  local parent = self:getParent()
  local checkBox = parent:recursiveGetChildById('sellCheckbox')
  local gray = parent:recursiveGetChildById('gray')
  if checkBox:isChecked() then
    self:setBackgroundColor("#404040")
    checkBox:setChecked(false)
    gray:setVisible(true)
  else
    self:setBackgroundColor("#585858")
    checkBox:setChecked(true)
    gray:setVisible(false)
  end
end

-- Track accumulated sale total from server responses
local quickSellAccumulatedTotal = 0
local quickSellItemCount = 0
local quickSellExpectedItems = 0
local quickSellWindow = nil

-- Function to extract gold value from server trade message
function extractGoldFromTradeMessage(message)
  -- Pattern: "Sold Xx ItemName for Y gold."
  local gold = message:match("for (%d+) gold")
  if gold then
    return tonumber(gold)
  end
  return 0
end

-- Callback to intercept server trade messages during Quick Sell
function onQuickSellTradeMessage(mode, msg)
  if quickSellWindow and mode == MessageModes.TradeNpc then
    local gold = extractGoldFromTradeMessage(msg)
    if gold > 0 then
      quickSellAccumulatedTotal = quickSellAccumulatedTotal + gold
      -- Extract item count from message "Sold Xx ItemName..."
      local count = msg:match("Sold (%d+)x")
      if count then
        quickSellItemCount = quickSellItemCount + tonumber(count)
      end
    end
  end
end

function SellItemList(items, window)
  if not g_game.isOnline() then
    return
  end



  -- Reset accumulated totals
  quickSellAccumulatedTotal = 0
  quickSellItemCount = 0
  quickSellWindow = window

  local itemsToSell = {}
  local amounts = {}
  local maxItems = math.min(#items, 300)

  for i = 1, maxItems do
    local widget = items[i]
    if widget and widget.item.ptr and widget.item.ptr:getId() > 0 then
      local shouldSell = false
      if widget.isSelected ~= nil then
        shouldSell = widget.isSelected
      elseif widget.sellCheckbox then
        shouldSell = widget.sellCheckbox:isChecked()
      end
      
      if shouldSell then
        local quantity = getSellQuantity(widget.item.ptr)
        if quantity > 0 then
          -- Store table with ptr and widgetId
          table.insert(itemsToSell, {ptr = widget.item.ptr, widgetId = widget:getId()})
          table.insert(amounts, quantity)
        end
      end
    end
  end

  quickSellExpectedItems = #itemsToSell
  
  -- Initialize progress bar
  if quickSellWindow and quickSellWindow.saleProgress and quickSellWindow.saleProgress.progressBar then
      quickSellWindow.saleProgress.progressBar:setPercent(0)
  end

  local function recursiveSell(index)
    if index > #itemsToSell then
      -- Small delay to ensure last server message is processed
      scheduleEvent(function()
        g_client.setInputLockWidget(nil)
        
        if quickSellWindow and quickSellWindow.saleProgress then
           if quickSellWindow.saleProgress.progressLabel then
              local totalFormatted = convertLongGold(quickSellAccumulatedTotal, true, true)
              quickSellWindow.saleProgress.progressLabel:setText(string.format("Sale Completed (%s)", totalFormatted))
           end
           if quickSellWindow.saleProgress.progressBar then
              -- quickSellWindow.saleProgress.progressBar:setPercent(100)
              local parentWidth = quickSellWindow.saleProgress:getWidth()
              local margins = 6
              quickSellWindow.saleProgress.progressBar:setWidth(parentWidth - margins)
           end
        end

        -- Reset Sale Value Label
        if quickSellWindow and quickSellWindow.totalValuePanel then
           local valueLabel = quickSellWindow.totalValuePanel:getChildById('valueLabel')
           if valueLabel then
              valueLabel:setText("0")
           end
        end

        quickSellAccumulatedTotal = 0
        quickSellItemCount = 0
        quickSellExpectedItems = 0
        
      end, 200)
      return
    end
    
    -- Update progress
    if quickSellWindow and quickSellWindow.saleProgress and quickSellWindow.saleProgress.progressBar then
       local percent = math.floor((index / #itemsToSell) * 100)
       -- quickSellWindow.saleProgress.progressBar:setPercent(percent) 
       -- Manual width update because texture is 1px and anchors stretch it fully if anchored right
       local parentWidth = quickSellWindow.saleProgress:getWidth()
       local margins = 6 -- 3 left + 3 right
       local maxWidth = parentWidth - margins
       local newWidth = math.floor((percent / 100) * maxWidth)
       quickSellWindow.saleProgress.progressBar:setWidth(newWidth)
       
       if quickSellWindow.saleProgress.progressLabel then
          quickSellWindow.saleProgress.progressLabel:setText(string.format("Sale Progress: %d%%", percent))
       end
       
       -- Update Total Value Display with Accumulated Sold Value
       local valueLabel = quickSellWindow.totalValuePanel:getChildById('valueLabel')
       if valueLabel then
          valueLabel:setText(formatMoney(quickSellAccumulatedTotal, ","))
       end
    end
    
    -- Update List UI for the sold item
    if quickSellWindow and quickSellWindow.contentPanel and quickSellWindow.contentPanel.itemsPanel then
       local itemData = itemsToSell[index]
       if itemData and itemData.widgetId then
          local widget = quickSellWindow.contentPanel.itemsPanel:getChildById(itemData.widgetId)
          if widget then
             widget:destroy()
          end
       end
    end
    
    g_game.sellItem(itemsToSell[index].ptr, amounts[index], ignoreEquipped)
    scheduleEvent(function() recursiveSell(index + 1) end, 600)
  end

  if #itemsToSell > 0 then
    -- Using recursive Lua loop with delay instead of C++ sellAllItems to avoid server packet flood/exhaust
    recursiveSell(1)
    return -- Window close handled in recursion end
  end

  g_client.setInputLockWidget(nil)
  window:destroy()
  quickSellWindow = nil

end

local function updateBlacklist(window)
  if not window then
    return
  end

  local list = window:recursiveGetChildById('itemsList')
  if not list then
    return
  end

  list:destroyChildren()

  local count = 0
  -- Iterate over all sellable items, showing only those the player has in inventory
  for key, item in pairs(tradeItems[SELL]) do
    -- Only show items that the player can trade (has in inventory)
    if canTradeItem(item) then
      count = count + 1
      local itemId = item.ptr:getId()
      
      local widget = g_ui.createWidget('QuickSellItemBox', list)
      local color = (count % 2) == 0 and '#414141' or '#484848'
      widget:setId("blacklist_" .. itemId)
      
      widget.itemName:setText(item.name)
      widget.itemId:setItemId(itemId)
      widget:setBackgroundColor(color)
      
      -- Check the box if item is already in the blacklist
      local isBlacklisted = inWhiteList(itemId)
      widget.blacklistCheckbox:setChecked(isBlacklisted)
      
      -- Toggle blacklist when checkbox changes
      widget.blacklistCheckbox.onCheckChange = function(self)
        if self:isChecked() then
          addToWhitelist(itemId)
        else
          removeItemInList(itemId)
        end
        saveData()
      end
    end
  end
end

function openBlacklist()
  local blacklistWindow = g_ui.loadUI('styles/blacklist', g_ui.getRootWidget())
  if not blacklistWindow then
    onTradeAllClick()
    return
  end

  blacklistWindow:show()
  blacklistWindow:raise()
  blacklistWindow:focus()

  g_client.setInputLockWidget(blacklistWindow)

  updateBlacklist(blacklistWindow)

  local close = function()
    g_client.setInputLockWidget(nil)
    if blacklistWindow then
      blacklistWindow:destroy()
    end
    onTradeAllClick()
  end

  blacklistWindow.contentPanel.closeButton.onClick = close
end

function onTradeAllClick()
  if getCurrentTradeType() == BUY then
    return
  end

  local radio = UIRadioGroup.create()
  window = g_ui.loadUI('styles/quicksell', g_ui.getRootWidget())
  if not window then
    return true
  end


  window:setText("")
  window:show(true)
  window:raise()
  window:focus()

  local saleValue = 0
  local currentTab = 'sellAll' -- 'sellAll' or 'blacklist'
  
  -- Batch processing variables
  local QUICK_SELL_BATCH_SIZE = 20
  local batchedItems = {}
  local batchIndex = 0
  local batchEvent = nil

  local function cancelBatch()
    if batchEvent then
      removeEvent(batchEvent)
      batchEvent = nil
    end
  end

  local function updateTotalDisplay()
      local valueLabel = window.totalValuePanel:getChildById('valueLabel')
      if not valueLabel then
         valueLabel = g_ui.createWidget('Label', window.totalValuePanel)
         valueLabel:setId('valueLabel')
         valueLabel:addAnchor(AnchorRight, 'goldIcon', AnchorLeft)
         valueLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
         valueLabel:setMarginRight(5)
         valueLabel:setTextAlign(AlignRight)
         valueLabel:setFont("verdana-11px-rounded")
         valueLabel:setColor('#ffffff')
         valueLabel:setTextAutoResize(true)
      end
      valueLabel:setText(formatMoney(saleValue, ","))
  end
  
  local function createQuickSellItemWidget(item)
    local itemSquare = g_ui.createWidget('QuickSellItem', window.contentPanel.itemsPanel)
    itemSquare:setId("itemSquare_" .. item.name)
    itemSquare.item = item
    
    itemSquare:setItem(item.ptr)
    itemSquare:setTooltip(item.name .. "\nPrice: " .. formatCurrency(item.price))

    local quantity = getSellQuantity(item.ptr)
    itemSquare.quantityLabel:setText(quantity)
    
    local isSelected = true
    
    local function updateStatus()
      if isSelected then
        itemSquare.statusIcon:setImageSource('/images/store/icon-yes')
        itemSquare:setBorderColor('#ffffff')
        itemSquare:setBackgroundColor('#ffffff20')
      else
        itemSquare.statusIcon:setImageSource('/images/store/icon-no')
        itemSquare:setBorderColor('white')
        itemSquare:setBackgroundColor('alpha')
      end
    end
    
    itemSquare.onMouseRelease = function(widget, mousePos, mouseButton)
      if mouseButton == MouseLeftButton then
        isSelected = not isSelected
        itemSquare.isSelected = isSelected
        updateStatus()
        
        local price = item.price * quantity
        saleValue = saleValue + (isSelected and price or -price)
        updateTotalDisplay()
        return true
      end
    end
    
    updateStatus()
    saleValue = saleValue + (item.price * quantity)
    updateTotalDisplay()
    
    itemSquare.isSelected = isSelected
  end

  local function createBlacklistItemWidget(item)
    local itemSquare = g_ui.createWidget('QuickSellItem', window.contentPanel.itemsPanel)
    itemSquare:setId("blacklistItem_" .. item.name)
    itemSquare.item = item
    
    itemSquare:setItem(item.ptr)
    itemSquare:setTooltip(item.name)
    itemSquare.quantityLabel:hide() -- Hide quantity for blacklist view? Or show total owned? Let's hide for now or show 1.
    itemSquare.quantityLabel:setText("")

    -- Status: Checked means Blacklisted (Excluded)
    -- But usually visually: Green = Included, Red = Excluded/Blacklisted?
    -- User said: "ao clicar no item na lista deveria mudar para no e atualiar o sale value" (for Sell List)
    -- For Blacklist: If it's in the list, it IS blacklisted.
    -- Clicking it should REMOVE it from blacklist (and thus remove from this grid? or just toggle state?)
    -- Let's make it toggleable.
    
    local isBlacklisted = inWhiteList(item.ptr:getId()) -- inWhiteList actually checks if it's in the list (so, yes, blacklisted)
    
    local function updateStatus()
      if isBlacklisted then
         -- Item IS in blacklist (Excluded from sell)
         itemSquare.statusIcon:setImageSource('/images/store/icon-no') -- "No" = Not sold / Excluded
         itemSquare:setBorderColor('#ff0000') -- Red border?
         itemSquare:setBackgroundColor('#ff000020')
      else
         -- Item NOT in blacklist (Included in sell)
         itemSquare.statusIcon:setImageSource('/images/store/icon-yes') -- "Yes" = Sold / Included
         itemSquare:setBorderColor('#00ff00')
         itemSquare:setBackgroundColor('#00ff0020')
      end
    end

    itemSquare.onMouseRelease = function(widget, mousePos, mouseButton)
      if mouseButton == MouseLeftButton then
        isBlacklisted = not isBlacklisted
        if isBlacklisted then
          addToWhitelist(item.ptr:getId())
        else
          removeItemInList(item.ptr:getId())
        end
        saveData()
        updateStatus()
        return true
      end
    end
    
    updateStatus()
  end
  
  local function processBatch()
    local startIdx = batchIndex * QUICK_SELL_BATCH_SIZE + 1
    local endIdx = math.min(startIdx + QUICK_SELL_BATCH_SIZE - 1, #batchedItems)
    
    if startIdx > #batchedItems then return end
    
    for i = startIdx, endIdx do
      local item = batchedItems[i]
      if item then
        if currentTab == 'sellAll' then
          createQuickSellItemWidget(item)
        else
          createBlacklistItemWidget(item)
        end
      end
    end
    
    batchIndex = batchIndex + 1
    if endIdx < #batchedItems then
      batchEvent = scheduleEvent(processBatch, 10)
    end
  end

  local function refreshQuickSellGrid()
    cancelBatch()
    window.contentPanel.itemsPanel:destroyChildren()
    saleValue = 0
    updateTotalDisplay()
    
    batchedItems = {}
    local currentTradeItems = tradeItems[getCurrentTradeType()]
    for _, item in pairs(currentTradeItems) do
      if canTradeItem(item) and not inWhiteList(item.ptr:getId()) then
        table.insert(batchedItems, item)
      end
    end
    
    table.sort(batchedItems, function(a, b) return a.price > b.price end)
    
    batchIndex = 0
    processBatch()
    
    -- Update UI Visibility
    window.optionsTabBar.sellAllTab:setChecked(true)
    window.optionsTabBar.blacklistTab:setChecked(false)
    window.saleProgress:setVisible(true) -- Assuming keeping progress bar
    window.totalValuePanel:setVisible(true)
    window.saleValueLabel:setVisible(true)
    if window.sellAllButton then window.sellAllButton:setVisible(true) end
  end

  local function refreshBlacklistGrid()
    cancelBatch()
    window.contentPanel.itemsPanel:destroyChildren()
    
    batchedItems = {}
    -- Show all sellable items so user can toggle blacklist status
    -- Or only show currently blacklisted items?
    -- Usually better to show all items player has, indicating which are blacklisted.
    local currentTradeItems = tradeItems[getCurrentTradeType()]
    for _, item in pairs(currentTradeItems) do
        -- Show items player has capability to sell
       if canTradeItem(item) then
          table.insert(batchedItems, item)
       end
    end
    
    -- Sort: Blacklisted first?
    table.sort(batchedItems, function(a, b) 
      local aBL = inWhiteList(a.ptr:getId())
      local bBL = inWhiteList(b.ptr:getId())
      if aBL == bBL then return a.price > b.price end
      return aBL and not bBL -- Show blacklisted first
    end)
    
    batchIndex = 0
    processBatch()
    
    -- Update UI Visibility
    window.optionsTabBar.sellAllTab:setChecked(false)
    window.optionsTabBar.blacklistTab:setChecked(true)
    -- Hide Sell specific UI elements?
    window.saleProgress:setVisible(false) 
    window.totalValuePanel:setVisible(false)
    window.saleValueLabel:setVisible(false)
    if window.sellAllButton then window.sellAllButton:setVisible(false) end
  end

  local function switchTab(tab)
      currentTab = tab
      if tab == 'sellAll' then
          refreshQuickSellGrid()
      elseif tab == 'blacklist' then
          refreshBlacklistGrid()
      end
  end

  -- Initial Load
  switchTab('sellAll')

  g_client.setInputLockWidget(window)

  local close = function()
    cancelBatch()
    g_client.setInputLockWidget(nil)
    window:destroy()
  end
  
  -- Button Bindings
  window.optionsTabBar.sellAllTab.onClick = function() switchTab('sellAll') end
  window.optionsTabBar.blacklistTab.onClick = function() switchTab('blacklist') end

  -- ... (Rest of close/sell function logic)

  local sell = function()
    local warningWindow = nil
    local selectedItems = {}
    local notWorthItems = {}
    local items = window.contentPanel.itemsPanel:getChildren()
    for i, widget in ipairs(items) do
      if widget.isSelected then
        table.insert(selectedItems, widget.item)
        -- Reuse priceLabel check? No, widget doesn't have priceLabel visible as child maybe?
        -- Actually checking widget.item.price directly is better or tooltip.
        -- But for 'notWorthItems', let's check market value vs npc price.
        local marketValue = widget.item.ptr.getAverageMarketValue and widget.item.ptr:getAverageMarketValue() or 0
        if marketValue > 0 and widget.item.price < marketValue then
          table.insert(notWorthItems, widget.item)
        end
      end
    end

    if #selectedItems <= 0 then
      return
    end

    if #notWorthItems > 0 then
      local message = ""
      for i, item in ipairs(notWorthItems) do
        message = message .. string.format("  - %s\n", item.name)
      end
      local yesCallback = function()
        SellItemList(items, window)
        if warningWindow then
          warningWindow:destroy()
          warningWindow = nil
          g_client.setInputLockWidget(nil)
        end
      end
      local noCallback = function()
        if window then
          window:show()
          g_client.setInputLockWidget(window)
        else
          g_client.setInputLockWidget(nil)
        end
        if warningWindow then
          warningWindow:destroy()
          warningWindow = nil
        end
      end
      window:hide()
      warningWindow = g_ui.createWidget('WarningQuickWindow', rootWidget)
      warningWindow.itemTextWarning:setText(message)
      warningWindow.itemTextWarning:setEditable(false)
      warningWindow.itemTextWarning:setCursorVisible(false)
      warningWindow:getChildById('okButton').onClick = yesCallback
      warningWindow:getChildById('cancelButton').onClick = noCallback
      warningWindow:show()
      warningWindow:focus()
      g_client.setInputLockWidget(warningWindow)
    else
      SellItemList(items, window)
    end
  end


  
  -- Close button handles simple destroy
  -- window.closeButton is already handled via onEscape and explicit onClick in OTUI if defined there, 
  -- but checking if I need to re-bind it here. 
  -- In OTUI: @onClick: self:getParent():destroy() -> works fine.
  -- But here we have 'close' local function that clears input lock.
  -- So better to bind closeButton to this local close function.
  
  if window.closeButton then
    window.closeButton.onClick = close
  end

  window.onEscape = close
  
  -- Bind Sell All button
  if window.sellAllButton then
     window.sellAllButton.onClick = sell
  end
  window.onEnter = sell
end
