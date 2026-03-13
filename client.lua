-- client.lua

local mainWin, resGrid, fileGrid
local searchEdit -- Added for resource search
local btnNew, btnCopy, btnRename, btnDelete, btnCloseMain
local editWin, editMemo, btnSave, btnRevert, btnCloseEdit, tplCombo, tplBtn
local unsavedLabel -- Added for unsaved changes indicator
local promptWin, promptLabel, promptEdit, promptCombo, btnPromptOK, btnPromptCancel

local currentRes, currentFile, originalContent = nil, nil, ""
local promptAction = "" 
local resListCache = {}
local isSearchFocused = false -- Tracks searchbar focus
local wasEditOpen, wasPromptOpen = false, false -- Tracks window states for F2 toggling

-- ==========================================
-- SMART INPUT MANAGER (Fixes hotkey bleeding)
-- ==========================================
local function updateInput()
    if guiGetVisible(editWin) or guiGetVisible(promptWin) or isSearchFocused then
        guiSetInputEnabled(true) -- Hard captures keyboard, blocking 'P', 'T', etc.
    else
        guiSetInputEnabled(false) -- Releases keyboard back to the game
    end
end

-- ==========================================
-- UI TOGGLE MANAGER
-- ==========================================
local function toggleUI(state)
    guiSetVisible(mainWin, state)
    
    if state then
        -- Restore previous window states when opening
        if wasEditOpen then guiSetVisible(editWin, true) end
        if wasPromptOpen then guiSetVisible(promptWin, true) end
        triggerServerEvent("editor:requestResources", localPlayer)
    else
        -- Save states before hiding
        wasEditOpen = guiGetVisible(editWin)
        wasPromptOpen = guiGetVisible(promptWin)
        
        guiSetVisible(editWin, false)
        guiSetVisible(promptWin, false)
        isSearchFocused = false
    end
    
    showCursor(state)
    updateInput()
end

-- ==========================================
-- AUTO-INCREMENT PARSER
-- ==========================================
local function getNextIndex(prefix)
    local text = guiGetText(editMemo)
    local maxIdx = 0
    for match in string.gmatch(text, prefix .. "(%d+)") do
        local num = tonumber(match)
        if num and num > maxIdx then
            maxIdx = num
        end
    end
    return maxIdx + 1
end

-- ==========================================
-- DYNAMIC TEMPLATE GENERATOR
-- ==========================================
local function generateTemplate(templateName)
    if templateName == "Jump Marker" then
        local idx = getNextIndex("jumpMarker")
        return string.format([[

-- Jump Marker %d
local jumpMarker%d = createMarker(0, 0, 0, "corona", 5, 255, 255, 255, 255)

function onJumpMarkerHit%d(player)    
    if player == localPlayer and isPedInVehicle(player) then
        local vehicle = getPedOccupiedVehicle(player)   
        if vehicle then 
            setElementVelocity(vehicle, 0, 0, 0)     
        end
    end
end
addEventHandler("onClientMarkerHit", jumpMarker%d, onJumpMarkerHit%d)
]], idx, idx, idx, idx, idx)

    elseif templateName == "Teleport Marker" then
        local idx = getNextIndex("tpMarker")
        return string.format([[

-- Teleport Marker %d
local tpMarker%d = createMarker(0, 0, 0, "corona", 5, 255, 255, 255, 255)

function onTpMarkerHit%d(player)    
    if player == localPlayer and isPedInVehicle(player) then
        local vehicle = getPedOccupiedVehicle(player)   
        if vehicle then 
            setElementPosition(vehicle, 0, 0, 0) -- Change destination here     
        end
    end
end
addEventHandler("onClientMarkerHit", tpMarker%d, onTpMarkerHit%d)
]], idx, idx, idx, idx, idx)

    elseif templateName == "Explosion Rotation Marker" then
        local idx = getNextIndex("expRotMarker")
        return string.format([[

-- Explosion Rotation Marker %d
local expRotMarker%d = createMarker(0, 0, 0, "corona", 5, 255, 0, 0, 255)

function onExpRotMarkerHit%d(player)    
    if player == localPlayer and isPedInVehicle(player) then
        local vehicle = getPedOccupiedVehicle(player)   
        if vehicle then 
            local targetRotZ = 0 -- The required Z rotation
            local tolerance = 30 -- Degrees of tolerance

            local _, _, rz = getElementRotation(vehicle)
            local diff = math.abs(rz - targetRotZ)
            if diff > 180 then diff = 360 - diff end

            if diff > tolerance then
                local x, y, z = getElementPosition(vehicle)
                createExplosion(x, y, z, 7) -- Visual explosion
                setElementHealth(vehicle, 0) -- Destroy vehicle
            end
        end
    end
end
addEventHandler("onClientMarkerHit", expRotMarker%d, onExpRotMarkerHit%d)
]], idx, idx, idx, idx, idx)

    elseif templateName == "BW Marker" then
        local idx = getNextIndex("backwardsMarker")
        return string.format([[

-- BW Marker %d
local backwardsMarker%d = createMarker(0, 0, 0, "corona", 7, 0, 0, 0, 0)

addEventHandler("onClientMarkerHit", root, function(hitElement, sameDimension)
    if (hitElement ~= localPlayer or not sameDimension) then return end
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if not vehicle then return end
    
    local velX, velY, velZ = getElementVelocity(vehicle)
    local speed = 0
    
    if (source == backwardsMarker%d) then
        setElementVelocity(vehicle, -velX * speed, -velY * speed, -velZ * speed)
    end
end)
]], idx, idx, idx)

    elseif templateName == "Rotation Modifier Marker" then
        local idx = getNextIndex("rotModMarker")
        return string.format([[

-- Rotation Modifier Marker %d
local rotModMarker%d = createMarker(0, 0, 0, "corona", 5, 0, 255, 255, 255)

function onRotModMarkerHit%d(player)    
    if player == localPlayer and isPedInVehicle(player) then
        local vehicle = getPedOccupiedVehicle(player)   
        if vehicle then 
            local targetRX, targetRY, targetRZ = 0, 0, 0
            
            -- Save current velocity
            local vx, vy, vz = getElementVelocity(vehicle)
            
            -- Apply new rotation
            setElementRotation(vehicle, targetRX, targetRY, targetRZ)
            
            -- Restore velocity so momentum isn't lost
            setElementVelocity(vehicle, vx, vy, vz)
        end
    end
end
addEventHandler("onClientMarkerHit", rotModMarker%d, onRotModMarkerHit%d)
]], idx, idx, idx, idx, idx)
    end

    return ""
end

-- ==========================================
-- GUI CREATION
-- ==========================================
local function buildGUI()
    local sw, sh = guiGetScreenSize()
    
    mainWin = guiCreateWindow(sw/2 - 350, sh/2 - 250, 700, 500, "Dynamic Resource Editor", false)
    guiWindowSetSizable(mainWin, false)
    
    -- Added Resource Search Bar
    searchEdit = guiCreateEdit(10, 30, 330, 25, "Search resources...", false, mainWin)
    
    -- Shifted resGrid down to make room for search bar
    resGrid = guiCreateGridList(10, 60, 330, 390, false, mainWin)
    guiGridListAddColumn(resGrid, "Resources", 0.9)
    
    fileGrid = guiCreateGridList(350, 30, 340, 420, false, mainWin)
    guiGridListAddColumn(fileGrid, "Files (Double-Click to Edit)", 0.9)
    
    btnNew = guiCreateButton(10, 460, 80, 30, "New File", false, mainWin)
    btnCopy = guiCreateButton(100, 460, 80, 30, "Copy", false, mainWin)
    btnRename = guiCreateButton(190, 460, 80, 30, "Rename", false, mainWin)
    btnDelete = guiCreateButton(280, 460, 80, 30, "Delete", false, mainWin)
    btnCloseMain = guiCreateButton(600, 460, 90, 30, "Close", false, mainWin)
    guiSetVisible(mainWin, false)

    editWin = guiCreateWindow(sw/2 - 400, sh/2 - 325, 800, 650, "Editor", false)
    guiWindowSetSizable(editWin, true)
    
    editMemo = guiCreateMemo(10, 30, 780, 500, "", false, editWin)
    
    -- SWAPPED BUTTONS
    btnCloseEdit = guiCreateButton(10, 540, 120, 30, "Close Editor", false, editWin)
    btnRevert = guiCreateButton(140, 540, 100, 30, "Revert", false, editWin)
    
    tplCombo = guiCreateComboBox(260, 540, 200, 150, "Select Template...", false, editWin)
    guiComboBoxAddItem(tplCombo, "Jump Marker")
    guiComboBoxAddItem(tplCombo, "Teleport Marker")
    guiComboBoxAddItem(tplCombo, "Explosion Rotation Marker")
    guiComboBoxAddItem(tplCombo, "BW Marker")
    guiComboBoxAddItem(tplCombo, "Rotation Modifier Marker")
    tplBtn = guiCreateButton(470, 540, 100, 30, "Insert", false, editWin)
    
    btnSave = guiCreateButton(670, 540, 120, 30, "Save & Refresh", false, editWin)
    
    -- Added Unsaved Changes Label
    unsavedLabel = guiCreateLabel(10, 580, 300, 20, "⚠️ FILE HAS UNSAVED CHANGES", false, editWin)
    guiLabelSetColor(unsavedLabel, 255, 50, 50)
    guiSetFont(unsavedLabel, "default-bold-small")
    guiSetVisible(unsavedLabel, false)

    guiSetVisible(editWin, false)

    promptWin = guiCreateWindow(sw/2 - 150, sh/2 - 100, 300, 200, "Action", false)
    guiWindowSetSizable(promptWin, false)
    promptLabel = guiCreateLabel(10, 30, 280, 20, "Enter details:", false, promptWin)
    promptEdit = guiCreateEdit(10, 55, 280, 30, "", false, promptWin)
    promptCombo = guiCreateComboBox(10, 95, 280, 150, "Select Target Resource...", false, promptWin)
    btnPromptOK = guiCreateButton(10, 160, 100, 30, "Confirm", false, promptWin)
    btnPromptCancel = guiCreateButton(190, 160, 100, 30, "Cancel", false, promptWin)
    guiSetVisible(promptWin, false)

    -- Handle text changes (Search and Unsaved indicator)
    addEventHandler("onClientGUIChanged", root, function()
        if source == searchEdit then
            local text = guiGetText(searchEdit):lower()
            if text == "search resources..." then return end -- Ignore placeholder
            
            guiGridListClear(resGrid)
            for _, res in ipairs(resListCache) do
                if text == "" or string.find(res:lower(), text, 1, true) then
                    local row = guiGridListAddRow(resGrid)
                    guiGridListSetItemText(resGrid, row, 1, res, false, false)
                end
            end
        elseif source == editMemo then
            -- Compare current text with original content
            if guiGetText(editMemo) ~= originalContent then
                guiSetVisible(unsavedLabel, true)
            else
                guiSetVisible(unsavedLabel, false)
            end
        end
    end)

    -- Handle focus to enable/disable hotkeys safely
    addEventHandler("onClientGUIFocus", searchEdit, function()
        isSearchFocused = true
        updateInput()
        if guiGetText(searchEdit) == "Search resources..." then
            guiSetText(searchEdit, "")
        end
    end, false)
    
    addEventHandler("onClientGUIBlur", searchEdit, function()
        isSearchFocused = false
        updateInput()
        if guiGetText(searchEdit) == "" then
            guiSetText(searchEdit, "Search resources...")
        end
    end, false)

    addEventHandler("onClientGUIDoubleClick", fileGrid, function()
        local row = guiGridListGetSelectedItem(fileGrid)
        if row ~= -1 and currentRes then
            currentFile = guiGridListGetItemText(fileGrid, row, 1)
            triggerServerEvent("editor:requestContent", localPlayer, currentRes, currentFile)
        end
    end, false)

    addEventHandler("onClientGUIClick", root, function(btn)
        if btn ~= "left" then return end
        
        if source == resGrid then
            local row = guiGridListGetSelectedItem(resGrid)
            if row ~= -1 then
                currentRes = guiGridListGetItemText(resGrid, row, 1)
                guiGridListClear(fileGrid)
                triggerServerEvent("editor:requestFiles", localPlayer, currentRes)
            end

        elseif source == btnSave then
            local currentText = guiGetText(editMemo)
            triggerServerEvent("editor:saveFile", localPlayer, currentRes, currentFile, currentText)
            originalContent = currentText -- Update original content so it marks as saved locally
            guiSetVisible(unsavedLabel, false)
            
        elseif source == btnRevert then
            guiSetText(editMemo, originalContent)
            guiSetVisible(unsavedLabel, false) -- Resets the unsaved warning
        
        elseif source == tplBtn then
            local sel = guiComboBoxGetSelected(tplCombo)
            if sel ~= -1 then
                local txt = guiComboBoxGetItemText(tplCombo, sel)
                local dynamicCode = generateTemplate(txt)
                if dynamicCode ~= "" then 
                    local currentCode = guiGetText(editMemo)
                    guiSetText(editMemo, currentCode .. dynamicCode) 
                    -- onClientGUIChanged will automatically trigger here and show the unsaved label
                end
            end

        elseif source == btnCloseEdit then
            guiSetVisible(editWin, false)
            wasEditOpen = false -- Ensure we log that the user explicitly closed it
            showCursor(guiGetVisible(mainWin))
            updateInput()

        elseif source == btnDelete then
            local row = guiGridListGetSelectedItem(fileGrid)
            if row ~= -1 and currentRes then
                local fName = guiGridListGetItemText(fileGrid, row, 1)
                triggerServerEvent("editor:deleteFile", localPlayer, currentRes, fName)
            end

        elseif source == btnNew then
            if not currentRes then return outputChatBox("Select a resource first!", 255, 0, 0) end
            promptAction = "new"
            guiSetText(promptWin, "Create New File")
            guiSetText(promptLabel, "Filename (e.g. script.lua):")
            guiSetText(promptEdit, "new_script.lua")
            guiSetVisible(promptCombo, false)
            guiSetVisible(promptWin, true)
            guiBringToFront(promptWin)
            updateInput()

        elseif source == btnRename then
            local row = guiGridListGetSelectedItem(fileGrid)
            if row == -1 then return outputChatBox("Select a file to rename!", 255, 0, 0) end
            currentFile = guiGridListGetItemText(fileGrid, row, 1)
            promptAction = "rename"
            guiSetText(promptWin, "Rename File")
            guiSetText(promptLabel, "New name for " .. currentFile .. ":")
            guiSetText(promptEdit, currentFile)
            guiSetVisible(promptCombo, false)
            guiSetVisible(promptWin, true)
            guiBringToFront(promptWin)
            updateInput()

        elseif source == btnCopy then
            local row = guiGridListGetSelectedItem(fileGrid)
            if row == -1 then return outputChatBox("Select a file to copy!", 255, 0, 0) end
            currentFile = guiGridListGetItemText(fileGrid, row, 1)
            promptAction = "copy"
            guiSetText(promptWin, "Copy File To...")
            guiSetText(promptLabel, "Save as:")
            guiSetText(promptEdit, currentFile)
            
            guiComboBoxClear(promptCombo)
            for _, r in ipairs(resListCache) do guiComboBoxAddItem(promptCombo, r) end
            guiSetVisible(promptCombo, true)
            guiSetVisible(promptWin, true)
            guiBringToFront(promptWin)
            updateInput()

        elseif source == btnPromptCancel then
            guiSetVisible(promptWin, false)
            wasPromptOpen = false
            updateInput()
            
        elseif source == btnPromptOK then
            local txt = guiGetText(promptEdit)
            if txt == "" then return end
            
            if promptAction == "new" then
                triggerServerEvent("editor:createFile", localPlayer, currentRes, txt)
            elseif promptAction == "rename" then
                triggerServerEvent("editor:renameFile", localPlayer, currentRes, currentFile, txt)
            elseif promptAction == "copy" then
                local sel = guiComboBoxGetSelected(promptCombo)
                if sel == -1 then return outputChatBox("Select a target resource from the dropdown!", 255, 0, 0) end
                local targetRes = guiComboBoxGetItemText(promptCombo, sel)
                triggerServerEvent("editor:copyFile", localPlayer, currentRes, currentFile, targetRes, txt)
            end
            guiSetVisible(promptWin, false)
            wasPromptOpen = false
            updateInput()

        elseif source == btnCloseMain then
            toggleUI(false)
        end
    end)
end
addEventHandler("onClientResourceStart", resourceRoot, buildGUI)

-- Keybinds and Syncing
bindKey("F2", "down", function()
    local state = not guiGetVisible(mainWin)
    toggleUI(state)
end)

addEvent("editor:receiveResources", true)
addEventHandler("editor:receiveResources", root, function(resTable)
    resListCache = resTable
    
    -- Re-apply search filter when receiving fresh resource list
    local searchText = guiGetText(searchEdit):lower()
    if searchText == "search resources..." then searchText = "" end
    
    guiGridListClear(resGrid)
    guiGridListClear(fileGrid)
    
    for _, res in ipairs(resTable) do
        if searchText == "" or string.find(res:lower(), searchText, 1, true) then
            local row = guiGridListAddRow(resGrid)
            guiGridListSetItemText(resGrid, row, 1, res, false, false)
        end
    end
end)

addEvent("editor:receiveFiles", true)
addEventHandler("editor:receiveFiles", root, function(files)
    guiGridListClear(fileGrid)
    for _, f in ipairs(files) do
        local row = guiGridListAddRow(fileGrid)
        guiGridListSetItemText(fileGrid, row, 1, f, false, false)
    end
end)

addEvent("editor:receiveContent", true)
addEventHandler("editor:receiveContent", root, function(content, resName, fName)
    originalContent = content
    guiSetText(editMemo, content)
    guiSetText(editWin, "Editing: " .. resName .. " -> " .. fName)
    guiSetVisible(unsavedLabel, false) -- Reset indicator for the new file
    guiSetVisible(editWin, true)
    guiBringToFront(editWin)
    updateInput()
end)

addEvent("editor:syncDirectory", true)
addEventHandler("editor:syncDirectory", root, function()
    setTimer(function()
        if currentRes and guiGetVisible(mainWin) then
            triggerServerEvent("editor:requestFiles", localPlayer, currentRes)
        end
    end, 150, 1)
end)
