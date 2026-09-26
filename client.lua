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

-- SYNCHRONISATION (SERVER -> CEF)
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

-- RÜCKMELDUNGEN (CEF -> LUA)
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
                    executeBrowserJavascript(editorBrowser, "updateStatus('SYNTAXFEHLER', '#ff5252'); actionComplete();")
                    return
                end
            end
            
            triggerServerEvent("editor:saveFile", localPlayer, res, file, finalContent)
            
            if editorBrowser then
                executeBrowserJavascript(editorBrowser, "updateStatus('Erfolgreich gespeichert', '#4CAF50'); actionComplete();")
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

-- SCHNITTSTELLEN-EVENTS
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
-- MATHEMATISCHE BERECHNUNGEN
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
-- PRÄZISE MARKER-POSITIONSBESTIMMUNG
-- ==============================================================
local function getElementWorldPosition(element)
    -- 1. Direkt getElementPosition aufrufen, falls natives Marker-/Kind-Element
    if isElement(element) then
        local px, py, pz = getElementPosition(element)
        if px and py and pz and (px ~= 0 or py ~= 0 or pz ~= 0) then
            return px, py, pz
        end
    end

    -- 2. Wenn Parent, sichtbares Kind-Element prüfen
    for _, child in ipairs(getElementChildren(element)) do
        local cx, cy, cz = getElementPosition(child)
        if cx and cy and cz and (cx ~= 0 or cy ~= 0 or cz ~= 0) then
            return cx, cy, cz
        end
    end

    -- 3. Rückgriff auf posX, posY, posZ
    local x = tonumber(getElementData(element, "posX"))
    local y = tonumber(getElementData(element, "posY"))
    local z = tonumber(getElementData(element, "posZ"))
    if x and y and z then return x, y, z end

    -- 4. Rückgriff auf "position"-Zeichenkette
    local rawPos = getElementData(element, "position")
    if type(rawPos) == "string" then
        local parts = split(rawPos, ",")
        if #parts >= 3 then
            local sx, sy, sz = tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3])
            if sx and sy and sz then return sx, sy, sz end
        end
    end

    return 0, 0, 0
end

local function getElementProperties(element)
    local targetEl = element
    local parent = getElementParent(element)
    local parentType = parent and tostring(getElementType(parent)):lower() or ""
    
    local customTypes = {["jump"]=true, ["teleport"]=true, ["slowmotion"]=true, ["environment"]=true, ["camera"]=true, ["fx"]=true, ["advancedobject"]=true, ["movingobject"]=true}
    if customTypes[parentType] then
        targetEl = parent
    end

    local elType = tostring(getElementType(targetEl)):lower()
    local edID = getElementData(targetEl, "id") or getElementID(targetEl) or getElementData(element, "id") or getElementID(element) or ""

    local posX, posY, posZ = getElementWorldPosition(element)
    if posX == 0 and posY == 0 and posZ == 0 then
        posX, posY, posZ = getElementWorldPosition(targetEl)
    end

    local isMarkerLike = (elType == "marker" or elType == "jump" or elType == "teleport" or elType == "slowmotion" or elType == "environment" or elType == "camera")
    local markerType = getElementData(targetEl, "type") or getElementData(element, "type") or (elType == "marker" and getMarkerType(element)) or "corona"
    local markerSize = tonumber(getElementData(targetEl, "size")) or tonumber(getElementData(element, "size")) or (elType == "marker" and getMarkerSize(element)) or 2.25

    local vx = tonumber(getElementData(targetEl, "velocityX")) or tonumber(getElementData(element, "velocityX")) or 0
    local vy = tonumber(getElementData(targetEl, "velocityY")) or tonumber(getElementData(element, "velocityY")) or 0
    local vz = tonumber(getElementData(targetEl, "velocityZ")) or tonumber(getElementData(element, "velocityZ")) or 0

    local rotX, rotY, rotZ = 0, 0, 0
    if not isMarkerLike then
        rotX = tonumber(getElementData(targetEl, "rotX")) or 0
        rotY = tonumber(getElementData(targetEl, "rotY")) or 0
        rotZ = tonumber(getElementData(targetEl, "rotZ")) or 0
        if rotX == 0 and rotY == 0 and rotZ == 0 then
            local rx, ry, rz = getElementRotation(element)
            rotX, rotY, rotZ = tonumber(rx) or 0, tonumber(ry) or 0, tonumber(rz) or 0
        end
    end

    local modelIdentifier = "0"
    if isMarkerLike then
        modelIdentifier = string.format("%s (%s)", markerType, elType:upper())
    elseif string.find(elType, "object") then
        local mID = getElementData(targetEl, "model") or getElementModel(element)
        modelIdentifier = tostring(mID or 0)
    else
        modelIdentifier = elType
    end

    if edID and edID ~= "" then
        modelIdentifier = modelIdentifier .. " [" .. tostring(edID) .. "]"
    end

    return {
        name = modelIdentifier,
        x = posX, y = posY, z = posZ,
        rx = rotX, ry = rotY, rz = rotZ,
        isMarker = isMarkerLike,
        markerType = tostring(markerType),
        size = markerSize,
        isJump = (elType == "jump"),
        vx = vx, vy = vy, vz = vz
    }
end

-- ==============================================================
-- ZIELSUCHE DURCH KAMERA-AUSRICHTUNG
-- ==============================================================
local function findCrosshairTarget()
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

    -- 1. Marker & KMST-Marker scannen
    local markerList = {}
    for _, marker in ipairs(getElementsByType("marker")) do table.insert(markerList, marker) end
    
    local kmstMarkerTypes = {"jump", "teleport", "slowmotion", "environment", "camera", "fx"}
    for _, cType in ipairs(kmstMarkerTypes) do
        for _, el in ipairs(getElementsByType(cType)) do
            table.insert(markerList, el)
            for _, child in ipairs(getElementChildren(el)) do
                table.insert(markerList, child)
            end
        end
    end

    for _, el in ipairs(markerList) do
        local px, py, pz = getElementWorldPosition(el)
        local distFromCam = getDistanceBetweenPoints3D(cx, cy, cz, px, py, pz)
        if distFromCam < 500 then
            local rayDist = getDistanceToRay(px, py, pz, cx, cy, cz, ex, ey, ez)
            local size = tonumber(getElementData(el, "size")) or 2.25
            local threshold = math.max(3.0, size * 1.5)

            if rayDist <= threshold and rayDist < bestDist then
                bestDist = rayDist
                chosenElement = el
            end
        end
    end

    if chosenElement then
        return chosenElement
    end

    -- 2. Physischer Raycast für Standard-Objekte
    local hit, hx, hy, hz, hitEl = processLineOfSight(cx, cy, cz, ex, ey, ez, true, true, true, true, true, false, false, false, localPlayer)
    if hit and hitEl and isElement(hitEl) then
        return hitEl
    end

    -- 3. Rückgriff auf Karten-Objekte
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
-- AUSWAHL-KLICK-HANDLER
-- ==============================================================
onSelectionClick = function()
    if not isSelectingObject then return end
    
    isSelectingObject = false
    unbindKey("mouse1", "down", onSelectionClick)

    local targetElement = findCrosshairTarget()

    setTimer(function()
        if targetElement and isElement(targetElement) then
            local p = getElementProperties(targetElement)
            toggleEditor(true, true)

            setTimer(function()
                if isElement(editorBrowser) then
                    local payloadJSON = toJSON(p):sub(2, -2)
                    local js = string.format("showInspectedElement(%s);", payloadJSON)
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
    
    setTimer(function()
        if isSelectingObject then
            bindKey("mouse1", "down", onSelectionClick)
        end
    end, 150, 1)
end)
