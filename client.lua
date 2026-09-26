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
local onSelectionClick

function toggleEditor(state, skipResourceFetch)
    if isSelectingObject and state then
        isSelectingObject = false
        unbindKey("mouse1", "down", onSelectionClick)
    end

    if state then
        if not editorGui then 
            createEditorPanel() 
        else
            guiSetVisible(editorGui, true)
            showCursor(true)
            focusBrowser(editorBrowser)
            isMinimized = false
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
-- MATHEMATICAL CALCULATIONS
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
-- DATA EXTRACTION (GUARD AGAINST BOOLEANS & NIL)
-- ==============================================================
local function getElementProperties(element)
    local edID = getElementData(element, "id") or getElementID(element)
    local posX = tonumber(getElementData(element, "posX"))
    local posY = tonumber(getElementData(element, "posY"))
    local posZ = tonumber(getElementData(element, "posZ"))
    local rotX = tonumber(getElementData(element, "rotX"))
    local rotY = tonumber(getElementData(element, "rotY"))
    local rotZ = tonumber(getElementData(element, "rotZ"))

    if not posX or not posY or not posZ then
        local px, py, pz = getElementPosition(element)
        posX = tonumber(px) or 0
        posY = tonumber(py) or 0
        posZ = tonumber(pz) or 0
    end

    if not rotX or not rotY or not rotZ then
        local rx, ry, rz = getElementRotation(element)
        rotX = tonumber(rx) or 0
        rotY = tonumber(ry) or 0
        rotZ = tonumber(rz) or 0
    end

    local modelIdentifier = "0"
    local elType = tostring(getElementType(element)):lower()

    if string.find(elType, "marker") then
        local mType = getElementData(element, "type") or (isElement(element) and getMarkerType(element)) or "corona"
        modelIdentifier = '"' .. tostring(mType) .. '" (Marker)'
    elseif string.find(elType, "object") then
        local mID = getElementData(element, "model") or getElementModel(element)
        modelIdentifier = tostring(mID or 0)
    else
        modelIdentifier = '"' .. elType .. '"'
    end

    if edID and edID ~= "" then
        modelIdentifier = modelIdentifier .. " [" .. tostring(edID) .. "]"
    end

    return modelIdentifier, posX, posY, posZ, rotX, rotY, rotZ
end

-- ==============================================================
-- TARGET DETECTION VIA CAMERA ALIGNMENT
-- ==============================================================
local function findCrosshairTarget()
    local editorRes = getResourceFromName("editor_main")
    if editorRes and getResourceState(editorRes) == "running" then
        local ok, sel = pcall(function() return exports.editor_main:getSelectedElement() end)
        if ok and isElement(sel) then
            return sel
        end
    end

    local cx, cy, cz, lx, ly, lz = getCameraMatrix()
    local dirX, dirY, dirZ = lx - cx, ly - cy, lz - cz
    local len = math.sqrt(dirX*dirX + dirY*dirY + dirZ*dirZ)
    if len > 0 then
        dirX, dirY, dirZ = dirX/len, dirY/len, dirZ/len
    else
        dirX, dirY, dirZ = 0, 1, 0
    end

    local rayEndDist = 500
    local ex, ey, ez = cx + (dirX * rayEndDist), cy + (dirY * rayEndDist), cz + (dirZ * rayEndDist)

    local bestDist = 999999
    local chosenElement = nil

    local scanList = {}
    for _, marker in ipairs(getElementsByType("marker")) do table.insert(scanList, marker) end
    for _, pickup in ipairs(getElementsByType("pickup")) do table.insert(scanList, pickup) end
    for _, col in ipairs(getElementsByType("colshape")) do table.insert(scanList, col) end

    local edMarkerRoot = getResourceRootElement(getResourceFromName("editor_main"))
    if isElement(edMarkerRoot) then
        for _, el in ipairs(getElementChildren(edMarkerRoot)) do
            table.insert(scanList, el)
        end
    end

    for _, el in ipairs(scanList) do
        local _, px, py, pz = getElementProperties(el)
        local distFromCam = getDistanceBetweenPoints3D(cx, cy, cz, px, py, pz)
        if distFromCam < 500 then
            local rayDist = getDistanceToRay(px, py, pz, cx, cy, cz, ex, ey, ez)
            local threshold = 6.0

            if rayDist <= threshold and rayDist < bestDist then
                bestDist = rayDist
                chosenElement = el
            end
        end
    end

    if chosenElement then
        return chosenElement
    end

    local hit, hx, hy, hz, hitEl = processLineOfSight(cx, cy, cz, ex, ey, ez, true, true, true, true, true, false, false, false, localPlayer)
    if hit and hitEl and isElement(hitEl) then
        return hitEl
    end

    for _, obj in ipairs(getElementsByType("object", root, true)) do
        local ox, oy, oz = getElementPosition(obj)
        local distFromCam = getDistanceBetweenPoints3D(cx, cy, cz, ox, oy, oz)
        if distFromCam < 300 then
            local rayDist = getDistanceToRay(ox, oy, oz, cx, cy, cz, ex, ey, ez)
            if rayDist < 3.0 and rayDist < bestDist then
                bestDist = rayDist
                chosenElement = obj
            end
        end
    end

    return chosenElement
end

-- ==============================================================
-- SINGLE-CLICK OBJECT SELECTION
-- ==============================================================
onSelectionClick = function()
    if not isSelectingObject then return end
    
    -- Immediate deactivation & unbind to prevent extra clicks from interfering with the UI
    isSelectingObject = false
    unbindKey("mouse1", "down", onSelectionClick)

    local targetElement = findCrosshairTarget()

    -- 100ms delay to ensure mouse button release does not trigger unintended UI clicks
    setTimer(function()
        if targetElement and isElement(targetElement) then
            local modelName, x, y, z, rx, ry, rz = getElementProperties(targetElement)
            local int = tonumber(getElementInterior(targetElement)) or 0
            local dim = tonumber(getElementDimension(targetElement)) or 0

            toggleEditor(true, true)

            setTimer(function()
                if isElement(editorBrowser) then
                    local js = string.format("showObjectProperties('%s', %.4f, %.4f, %.4f, %.4f, %.4f, %.4f, %d, %d);", 
                        tostring(modelName), tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0, tonumber(rx) or 0, tonumber(ry) or 0, tonumber(rz) or 0, int, dim)
                    executeBrowserJavascript(editorBrowser, js)
                end
            end, 150, 1)
        else
            toggleEditor(true)
        end
    end, 100, 1)
end

addEvent("editor:onStartObjectSelection", true)
addEventHandler("editor:onStartObjectSelection", root, function()
    isSelectingObject = true
    toggleEditor(false)
    showCursor(false)
    
    -- Delay binding by 150ms so clicking the UI button doesn't trigger instant selection
    setTimer(function()
        if isSelectingObject then
            bindKey("mouse1", "down", onSelectionClick)
        end
    end, 150, 1)
end)
