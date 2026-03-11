-- client.lua

guiSetInputMode("no_binds_when_editing")

local mainWin, resGrid, fileGrid
local btnNew, btnCopy, btnRename, btnDelete, btnCloseMain
local editWin, editMemo, btnSave, btnRevert, btnCloseEdit, tplCombo, tplBtn
local promptWin, promptLabel, promptEdit, promptCombo, btnPromptOK, btnPromptCancel

local currentRes, currentFile, originalContent = nil, nil, ""
local promptAction = "" 
local resListCache = {}

local TEMPLATES = {
    ["Jump Marker"] = [[
-- Jump Marker
local jumpMarker1 = createMarker(X, Y, Z, "corona", 5, 255, 255, 255, 255)

function onJumpMarkerHit1(player)    
    if player == localPlayer and isPedInVehicle(player) then
        local vehicle = getPedOccupiedVehicle(player)   
        if vehicle then 
            setElementVelocity(vehicle, velX, velY, velZ)     
        end
    end
end
addEventHandler("onClientMarkerHit", jumpMarker1, onJumpMarkerHit1)

]],
    ["Teleport Marker"] = [[
-- Teleport Marker
local tpMarker1 = createMarker(startX, startY, startZ, "corona", 5, 255, 255, 255, 255)

function onTpMarkerHit1(player)    
    if player == localPlayer and isPedInVehicle(player) then
        local vehicle = getPedOccupiedVehicle(player)   
        if vehicle then 
            setElementPosition(vehicle, destX, destY, destZ)     
        end
    end
end
addEventHandler("onClientMarkerHit", tpMarker1, onTpMarkerHit1)

]]
}

local function buildGUI()
    local sw, sh = guiGetScreenSize()
    
    -- MAIN WINDOW (Rebranded)
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

    -- EDITOR WINDOW
    editWin = guiCreateWindow(sw/2 - 400, sh/2 - 325, 800, 650, "Editor", false)
    guiWindowSetSizable(editWin, true)
    
    editMemo = guiCreateMemo(10, 30, 780, 500, "", false, editWin)
    
    btnSave = guiCreateButton(10, 540, 120, 30, "Save & Refresh", false, editWin)
    btnRevert = guiCreateButton(140, 540, 100, 30, "Revert", false, editWin)
    
    tplCombo = guiCreateComboBox(260, 540, 150, 100, "Select Template...", false, editWin)
    guiComboBoxAddItem(tplCombo, "Jump Marker")
    guiComboBoxAddItem(tplCombo, "Teleport Marker")
    tplBtn = guiCreateButton(420, 540, 100, 30, "Insert", false, editWin)
    
    -- Button Rebranded
    btnCloseEdit = guiCreateButton(690, 540, 100, 30, "Close Editor", false, editWin)
    guiSetVisible(editWin, false)

    -- ACTION PROMPT WINDOW
    promptWin = guiCreateWindow(sw/2 - 150, sh/2 - 100, 300, 200, "Action", false)
    guiWindowSetSizable(promptWin, false)
    promptLabel = guiCreateLabel(10, 30, 280, 20, "Enter details:", false, promptWin)
    promptEdit = guiCreateEdit(10, 55, 280, 30, "", false, promptWin)
    promptCombo = guiCreateComboBox(10, 95, 280, 150, "Select Target Resource...", false, promptWin)
    btnPromptOK = guiCreateButton(10, 160, 100, 30, "Confirm", false, promptWin)
    btnPromptCancel = guiCreateButton(190, 160, 100, 30, "Cancel", false, promptWin)
    guiSetVisible(promptWin, false)

    -- Double Click Editor Launch
    addEventHandler("onClientGUIDoubleClick", fileGrid, function()
        local row = guiGridListGetSelectedItem(fileGrid)
        if row ~= -1 and currentRes then
            currentFile = guiGridListGetItemText(fileGrid, row, 1)
            triggerServerEvent("editor:requestContent", localPlayer, currentRes, currentFile)
        end
    end, false)

    -- Primary Click Handlers
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
                if TEMPLATES[txt] then 
                    local currentCode = guiGetText(editMemo)
                    guiSetText(editMemo, currentCode .. TEMPLATES[txt]) 
                end
            end

        elseif source == btnCloseEdit then
            guiSetVisible(editWin, false)
            showCursor(guiGetVisible(mainWin))

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

        elseif source == btnPromptCancel then
            guiSetVisible(promptWin, false)
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

        elseif source == btnCloseMain then
            guiSetVisible(mainWin, false)
            guiSetVisible(promptWin, false)
            showCursor(false)
        end
    end)
end
addEventHandler("onClientResourceStart", resourceRoot, buildGUI)

-- Keybinds and Syncing
bindKey("F2", "down", function()
    local state = not guiGetVisible(mainWin)
    guiSetVisible(mainWin, state)
    showCursor(state)
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
    -- Window Text Rebranded
    guiSetText(editWin, "Editing: " .. resName .. " -> " .. fName)
    guiSetVisible(editWin, true)
    guiBringToFront(editWin)
end)

addEvent("editor:syncDirectory", true)
addEventHandler("editor:syncDirectory", root, function()
    setTimer(function()
        if currentRes and guiGetVisible(mainWin) then
            triggerServerEvent("editor:requestFiles", localPlayer, currentRes)
        end
    end, 150, 1)
end)