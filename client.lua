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

function toggleEditor(state)
    if state then
        if not editorGui then createEditorPanel() else
            if not guiGetVisible(editorGui) then
                guiSetVisible(editorGui, true)
                showCursor(true)
                focusBrowser(editorBrowser)
                isMinimized = false
            end
            triggerServerEvent("editor:requestResources", localPlayer)
        end
        toggleInput(true)
    else
        if editorGui then
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
    local state = not (editorGui and guiGetVisible(editorGui))
    toggleEditor(state)
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
            
            -- FIX: Hier ist das Grün-Färben und Ausblenden des Ladekreises wieder!
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
