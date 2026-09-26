-- client.lua

local editorBrowser = nil
local editorGui = nil
local isMinimized = false

local function toggleInput(state)
    guiSetInputEnabled(state)
    guiSetInputMode(state and "no_binds" or "allow_binds")
end

addEventHandler("onClientBrowserInputFocusChanged", root, function(hasFocus)
    guiSetInputEnabled(hasFocus)
end)

function createEditorPanel()
    if editorGui then return true end
    local sw, sh = guiGetScreenSize()
    editorGui = guiCreateBrowser(0, 0, sw, sh, true, true, false)
    if editorGui then
        editorBrowser = guiGetBrowser(editorGui)
        addEventHandler("onClientBrowserCreated", editorGui, function()
            loadBrowserURL(editorBrowser, "http://mta/local/web/editor.html")
            focusBrowser(editorBrowser)
        end)
        guiSetVisible(editorGui, true)
        showCursor(true)
        return true
    end
end

local isSelectingObject = false

function toggleEditor(state, skipResourceFetch)
    if isSelectingObject and state then
        isSelectingObject = false
    end

    if state then
        if not editorGui then 
            createEditorPanel() 
        else
            if not guiGetVisible(editorGui) then
                guiSetVisible(editorGui, true)
                showCursor(true)
                focusBrowser(editorBrowser)
                isMinimized = false
            end
            if not skipResourceFetch then
                triggerServerEvent("editor:requestResources", localPlayer)
            end
        end
        toggleInput(true)
    else
        if editorGui and guiGetVisible(editorGui) then
            guiSetVisible(editorGui, false)
            showCursor(false)
            toggleInput(false)
            isMinimized = true
        end
    end
end

addEvent("editor:forceClose", true)
addEventHandler("editor:forceClose", root, function() toggleEditor(false) end)

bindKey("F2", "down", function()
    local isCurrentlyOpen = (editorGui and guiGetVisible(editorGui))
    if isCurrentlyOpen then
        toggleEditor(false)
        cancelEvent()
    else
        toggleEditor(true)
        cancelEvent()
    end
end)

-- SYNC (SERVER -> CEF)
addEvent("editor:receiveResources", true)
addEventHandler("editor:receiveResources", root, function(resList)
    if editorBrowser and type(resList) == "table" then
        executeBrowserJavascript(editorBrowser, "setResources(" .. toJSON(resList):sub(2, -2) .. ");")
    end
end)

addEvent("editor:receiveFiles", true)
addEventHandler("editor:receiveFiles", root, function(filesList)
    if editorBrowser and type(filesList) == "table" then
        executeBrowserJavascript(editorBrowser, "setFiles(" .. toJSON(filesList):sub(2, -2) .. ");")
    end
end)

addEvent("editor:receiveContent", true)
addEventHandler("editor:receiveContent", root, function(content, res, file)
    if not editorBrowser then return end
    executeBrowserJavascript(editorBrowser, "setEditorContent(" .. toJSON(content or ""):sub(2, -2) .. ", " .. toJSON(file):sub(2, -2) .. ", " .. toJSON(res):sub(2, -2) .. ");")
end)

addEvent("editor:receiveLogs", true)
addEventHandler("editor:receiveLogs", root, function(logs)
    if editorBrowser then executeBrowserJavascript(editorBrowser, "showLogsModal(" .. toJSON(logs):sub(2, -2) .. ");") end
end)

addEvent("editor:receiveBackups", true)
addEventHandler("editor:receiveBackups", root, function(backups)
    if editorBrowser then executeBrowserJavascript(editorBrowser, "showBackupModal(" .. toJSON(backups):sub(2, -2) .. ");") end
end)

addEvent("editor:actionComplete", true)
addEventHandler("editor:actionComplete", root, function()
    if editorBrowser then executeBrowserJavascript(editorBrowser, "actionComplete();") end
end)

-- CALLBACKS (CEF -> LUA)
addEvent("editor:onEditorStatus", true)
addEventHandler("editor:onEditorStatus", root, function(text, color)
    if editorBrowser then executeBrowserJavascript(editorBrowser, "updateStatus('"..text.."', '"..color.."')") end
end)

local saveBuffer = ""
addEvent("editor:onRequestSave", true)
addEventHandler("editor:onRequestSave", root, function(res, file, chunk, currentChunk, totalChunks)
    if currentChunk == 1 then saveBuffer = chunk else saveBuffer = saveBuffer .. chunk end
    if currentChunk == totalChunks then
        local finalContent = saveBuffer
        saveBuffer = ""
        setTimer(function()
            if file and string.find(file, "%.lua$") then
                local func, err = loadstring(finalContent)
                if not func then
                    outputChatBox("DRE [Error]: Save aborted! Syntax error:", 255, 50, 50)
                    outputChatBox(tostring(err), 255, 150, 150)
                    executeBrowserJavascript(editorBrowser, "updateStatus('SYNTAX ERROR', '#ff5252'); actionComplete();")
                    return
                end
            end
            
            triggerServerEvent("editor:saveFile", localPlayer, res, file, finalContent)
            
            if editorBrowser then
                executeBrowserJavascript(editorBrowser, "updateStatus('Saved Successfully', '#4CAF50'); actionComplete();")
            end
        end, 50, 1)
    end
end)

addEvent("editor:onRequestClose", true)
addEventHandler("editor:onRequestClose", root, function() toggleEditor(false) end)

addEvent("editor:onUIReady", true)
addEventHandler("editor:onUIReady", root, function() triggerServerEvent("editor:requestResources", localPlayer) end)

addEvent("editor:syncDirectory", true)
addEventHandler("editor:syncDirectory", root, function()
    executeBrowserJavascript(editorBrowser, "syncDirectory();")
end)

-- BRIDGE
addEvent("editor:requestFiles", true)
addEventHandler("editor:requestFiles", root, function(res) triggerServerEvent("editor:requestFiles", localPlayer, res) end)

addEvent("editor:requestContent", true)
addEventHandler("editor:requestContent", root, function(res, file) triggerServerEvent("editor:requestContent", localPlayer, res, file) end)

addEvent("editor:createFile", true)
addEventHandler("editor:createFile", root, function(res, file) triggerServerEvent("editor:createFile", localPlayer, res, file) end)

addEvent("editor:deleteFile", true)
addEventHandler("editor:deleteFile", root, function(res, file) triggerServerEvent("editor:deleteFile", localPlayer, res, file) end)

addEvent("editor:copyFile", true)
addEventHandler("editor:copyFile", root, function(sRes, sFile, tRes, tFile) triggerServerEvent("editor:copyFile", localPlayer, sRes, sFile, tRes, tFile) end)

addEvent("editor:renameFile", true)
addEventHandler("editor:renameFile", root, function(res, old, new) triggerServerEvent("editor:renameFile", localPlayer, res, old, new) end)

addEvent("editor:moveFile", true)
addEventHandler("editor:moveFile", root, function(sRes, sFile, tRes, tFile) triggerServerEvent("editor:moveFile", localPlayer, sRes, sFile, tRes, tFile) end)

addEvent("editor:requestLogs", true)
addEventHandler("editor:requestLogs", root, function() triggerServerEvent("editor:requestLogs", localPlayer) end)

addEvent("editor:requestBackups", true)
addEventHandler("editor:requestBackups", root, function(res) triggerServerEvent("editor:requestBackups", localPlayer, res) end)

addEvent("editor:restoreBackup", true)
addEventHandler("editor:restoreBackup", root, function(res, details, ts) triggerServerEvent("editor:restoreBackup", localPlayer, res, details, ts) end)

addEvent("editor:copyMultipleFiles", true)
addEventHandler("editor:copyMultipleFiles", root, function(sRes, filesData, tRes) 
    triggerServerEvent("editor:copyMultipleFiles", localPlayer, sRes, filesData, tRes) 
end)

-- ==============================================================
-- MATHEMATICAL 3D RAY-TO-POINT DISTANCE (FOR ACCURATE MARKERS)
-- ==============================================================
local function getDistanceToRay(px, py, pz, rx1, ry1, rz1, rx2, ry2, rz2)
    local dx, dy, dz = rx2 - rx1, ry2 - ry1, rz2 - rz1
    local magSq = dx * dx + dy * dy + dz * dz
    if magSq == 0 then return 999999 end
    local u = ((px - rx1) * dx + (py - ry1) * dy + (pz - rz1) * dz) / magSq
    if u < 0 then u = 0 elseif u > 1 then u = 1 end
    local nx, ny, nz = rx1 + u * dx, ry1 + u * dy, rz1 + u * dz
    return getDistanceBetweenPoints3D(px, py, pz, nx, ny, nz)
end

-- ==============================================================
-- UNIVERSAL SELECTION (MARKER PRIORITY & MAP-EDITOR SUPPORT)
-- ==============================================================
addEventHandler("onClientClick", root, function(button, state, absoluteX, absoluteY, worldX, worldY, worldZ, clickedElement)
    if not isSelectingObject then return end
    if button ~= "left" or state ~= "down" then return end
    
    isSelectingObject = false

    local targetElement = nil
    local camX, camY, camZ = getCameraMatrix()
    local endX, endY, endZ = getWorldFromScreenPosition(absoluteX, absoluteY, 300)

    -- Step 1: Search through all markers & map editor representation elements first
    local candidateElements = {}
    for _, marker in ipairs(getElementsByType("marker")) do table.insert(candidateElements, marker) end
    for _, pickup in ipairs(getElementsByType("pickup")) do table.insert(candidateElements, pickup) end

    local bestDistToRay = 999999
    local closestRayElement = nil

    for _, el in ipairs(candidateElements) do
        local ex, ey, ez = getElementPosition(el)
        local distFromCam = getDistanceBetweenPoints3D(camX, camY, camZ, ex, ey, ez)
        if distFromCam < 300 then
            local distRay = getDistanceToRay(ex, ey, ez, camX, camY, camZ, endX, endY, endZ)
            local allowedRadius = 4.0
            if getElementType(el) == "marker" then
                local mSize = getMarkerSize(el) or 2.0
                allowedRadius = math.max(3.0, mSize * 1.5)
            end
            
            if distRay <= allowedRadius and distRay < bestDistToRay then
                bestDistToRay = distRay
                closestRayElement = el
            end
        end
    end

    if closestRayElement then
        targetElement = closestRayElement
    end

    -- Step 2: If no marker was selected, check directly clicked entity
    if not targetElement and clickedElement and isElement(clickedElement) then
        targetElement = clickedElement
    end

    -- Step 3: Raycast for physical world objects
    if not targetElement then
        local hit, hx, hy, hz, hitEl = processLineOfSight(camX, camY, camZ, endX, endY, endZ, true, true, true, true, true, false, false, false, localPlayer)
        if hit and hitEl and isElement(hitEl) then
            targetElement = hitEl
        end
    end

    -- Step 4: Screen space fallback for nearby objects
    if not targetElement then
        local minScreenDist = 999999
        for _, obj in ipairs(getElementsByType("object", root, true)) do
            if isElementOnScreen(obj) then
                local ox, oy, oz = getElementPosition(obj)
                local sx, sy = getScreenFromWorldPosition(ox, oy, oz)
                if sx and sy then
                    local sDist = getDistanceBetweenPoints2D(absoluteX, absoluteY, sx, sy)
                    if sDist < 60 and sDist < minScreenDist then
                        minScreenDist = sDist
                        targetElement = obj
                    end
                end
            end
        end
    end

    -- Extract exact F3 properties
    if targetElement and isElement(targetElement) then
        local elType = getElementType(targetElement)
        local model = 0
        
        if elType == "object" or elType == "vehicle" or elType == "pickup" then
            model = getElementModel(targetElement)
        elseif elType == "marker" then
            model = '"' .. tostring(getMarkerType(targetElement)) .. '"'
        end

        local x, y, z = getElementPosition(targetElement)
        local rx, ry, rz = getElementRotation(targetElement)
        local int = getElementInterior(targetElement)
        local dim = getElementDimension(targetElement)

        toggleEditor(true, true)

        setTimer(function()
            if isElement(editorBrowser) then
                local js = string.format("showObjectProperties(%s, %.4f, %.4f, %.4f, %.4f, %.4f, %.4f, %d, %d);", 
                    tostring(model), x, y, z, rx, ry, rz, int, dim)
                executeBrowserJavascript(editorBrowser, js)
            end
        end, 100, 1)
    else
        toggleEditor(true)
    end
end)

addEvent("editor:onStartObjectSelection", true)
addEventHandler("editor:onStartObjectSelection", root, function()
    isSelectingObject = true
    toggleEditor(false)
    showCursor(true)
end)
