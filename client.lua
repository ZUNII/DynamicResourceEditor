-- client.lua

local mainWin, resGrid, fileGrid
local btnNew, btnCopy, btnRename, btnDelete, btnCloseMain
local editWin, editMemo, btnSave, btnRevert, btnCloseEdit, tplCombo, tplBtn
local promptWin, promptLabel, promptEdit, promptCombo, btnPromptOK, btnPromptCancel

local currentRes, currentFile, originalContent = nil, nil, ""
local promptAction = "" 
local resListCache = {}

-- ==========================================
-- SMART INPUT MANAGER (Fixes hotkey bleeding)
-- ==========================================
local function updateInput()
    if guiGetVisible(editWin) or guiGetVisible(promptWin) then
        guiSetInputEnabled(true) -- Hard captures keyboard, blocking 'P', 'T', etc.
    else
        guiSetInputEnabled(false) -- Releases keyboard back to the game
    end
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
local jumpMarker%d = createMarker(0, 0, 5, "corona", 5, 255, 255, 255, 255)

function onJumpMarkerHit%d(player)    
    if player == localPlayer and isPedInVehicle(player) then
        local vehicle = getPedOccupiedVehicle(player)   
        if vehicle then 
            setElementVelocity(vehicle, 0, 0, 0.5)     
        end
    end
end
addEventHandler("onClientMarkerHit", jumpMarker%d, onJumpMarkerHit%d)
]], idx, idx, idx, idx, idx)

    elseif templateName == "Teleport Marker" then
        local idx = getNextIndex("tpMarker")
        return string.format([[

-- Teleport Marker %d
local tpMarker%d = createMarker(0, 0, 5, "corona", 5, 255, 255, 255, 255)

function onTpMarkerHit%d(player)    
    if player == localPlayer and isPedInVehicle(player) then
        local vehicle = getPedOccupiedVehicle(player)   
        if vehicle then 
            setElementPosition(vehicle, 10, 10, 5) -- Change destination here     
        end
    end
end
addEventHandler("onClientMarkerHit", tpMarker%d, onTpMarkerHit%d)
]], idx, idx, idx, idx, idx)

    elseif templateName == "Explosion Rotation Marker" then
        local idx = getNextIndex("expRotMarker")
        return string.format([[

-- Explosion Rotation Marker %d
local expRotMarker%d = createMarker(0, 0, 5, "corona", 5, 255, 0, 0, 255)

function onExpRotMarkerHit%d(player)    
    if player == localPlayer and isPedInVehicle(player) then
        local vehicle = getPedOccupiedVehicle(player)   
        if vehicle then 
            local targetRotZ = 90 -- The required Z rotation
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

    elseif templateName == "Bounce Marker" then
        local idx = getNextIndex("bounceMarker")
        return string.format([[

-- Bounce Marker %d
local bounceMarker%d = createMarker(0, 0, 5, "corona", 5, 255, 255, 0, 255)

function onBounceMarkerHit%d(player)    
    if player == localPlayer and isPedInVehicle(player) then
        local vehicle = getPedOccupiedVehicle(player)   
        if vehicle then 
            local vx, vy, vz = getElementVelocity(vehicle)
            local bounceMultiplier = -1.2 -- Negative to go backwards, >1 to gain speed
            
            -- Keep vertical momentum normal, but flip and boost horizontal
            setElementVelocity(vehicle, vx * bounceMultiplier, vy * bounceMultiplier, vz)     
        end
    end
end
addEventHandler("onClientMarkerHit", bounceMarker%d, onBounceMarkerHit%d)
]], idx, idx, idx, idx, idx)

    elseif templateName == "Rotation Modifier Marker" then
        local idx = getNextIndex("rotModMarker")
        return string.format([[

-- Rotation Modifier Marker %d
local rotModMarker%d = createMarker(0, 0, 5, "corona", 5, 0, 255, 255, 255)

function onRotModMarkerHit%d(player)    
    if player == localPlayer and isPedInVehicle(player) then
        local vehicle = getPedOccupiedVehicle(player)   
        if vehicle then 
            local targetRX, targetRY, targetRZ = 0, 0, 180
            
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
    
    resGrid = guiCreateGridList(10, 30, 330, 420, false, mainWin)
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
    
    btnSave = guiCreateButton(10, 540, 120, 30, "Save & Refresh", false, editWin)
    btnRevert = guiCreateButton(140, 540, 100, 30, "Revert", false, editWin)
    
    tplCombo = guiCreateComboBox(260, 540, 200, 150, "Select Template...", false, editWin)
    guiComboBoxAddItem(tplCombo, "Jump Marker")
    guiComboBoxAddItem(tplCombo, "Teleport Marker")
    guiComboBoxAddItem(tplCombo, "Explosion Rotation Marker")
    guiComboBoxAddItem(tplCombo, "BW Marker")
    guiComboBoxAddItem(tplCombo, "Rotation Modifier Marker")
    tplBtn = guiCreateButton(470, 540, 100, 30, "Insert", false, editWin)
    
    btnCloseEdit = guiCreateButton(690, 540, 100, 30, "Close Editor", false, editWin)
    guiSetVisible(editWin, false)

    promptWin = guiCreateWindow(sw/2 - 150, sh/2 - 100, 300, 200, "Action", false)
    guiWindowSetSizable(promptWin, false)
    promptLabel = guiCreateLabel(10, 30, 280, 20, "Enter details:", false, promptWin)
    promptEdit = guiCreateEdit(10, 55, 280, 30, "", false, promptWin)
    promptCombo = guiCreateComboBox(10, 95, 280, 150, "Select Target Resource...", false, promptWin)
    btnPromptOK = guiCreateButton(10, 160, 100, 30, "Confirm", false, promptWin)
    btnPromptCancel = guiCreateButton(190, 160, 100, 30, "Cancel", false, promptWin)
    guiSetVisible(promptWin, false)

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
            triggerServerEvent("editor:saveFile", localPlayer, currentRes, currentFile, guiGetText(editMemo))
        elseif source == btnRevert then
            guiSetText(editMemo, originalContent)
        
        elseif source == tplBtn then
            local sel = guiComboBoxGetSelected(tplCombo)
            if sel ~= -1 then
                local txt = guiComboBoxGetItemText(tplCombo, sel)
                local dynamicCode = generateTemplate(txt)
                if dynamicCode ~= "" then 
                    local currentCode = guiGetText(editMemo)
                    guiSetText(editMemo, currentCode .. dynamicCode) 
                end
            end

        elseif source == btnCloseEdit then
            guiSetVisible(editWin, false)
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
            updateInput()

        elseif source == btnCloseMain then
            guiSetVisible(mainWin, false)
            guiSetVisible(promptWin, false)
            guiSetVisible(editWin, false)
            showCursor(false)
            updateInput()
        end
    end)
end
addEventHandler("onClientResourceStart", resourceRoot, buildGUI)

-- Keybinds and Syncing
bindKey("F2", "down", function()
    local state = not guiGetVisible(mainWin)
    guiSetVisible(mainWin, state)
    
    if not state then
        -- Close sub-windows safely if hiding everything
        guiSetVisible(editWin, false)
        guiSetVisible(promptWin, false)
    end
    
    showCursor(state)
    updateInput()
    
    if state then triggerServerEvent("editor:requestResources", localPlayer) end
end)

addEvent("editor:receiveResources", true)
addEventHandler("editor:receiveResources", root, function(resTable)
    resListCache = resTable
    guiGridListClear(resGrid)
    guiGridListClear(fileGrid)
    for _, res in ipairs(resTable) do
        local row = guiGridListAddRow(resGrid)
        guiGridListSetItemText(resGrid, row, 1, res, false, false)
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
