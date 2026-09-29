-- server.lua

local allowedExtensions = {
    ["lua"] = true, ["xml"] = true, ["html"] = true, ["map"] = true,
    ["js"] = true, ["css"] = true, ["txt"] = true, ["json"] = true, ["fx"] = true, ["hlsl"] = true,
    ["png"] = true, ["jpg"] = true, ["jpeg"] = true, ["tga"] = true, ["dds"] = true
}

local CURRENT_VERSION = "3.0"
local CURRENT_VERSION_NUM = 3.0
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/ZUNII/DynamicResourceEditor/main/"

local FILES_TO_UPDATE = {
    "server.lua", "client.lua", "meta.xml", "web/editor.html", 
    "web/codemirror.min.css", "web/material-darker.min.css", "web/codemirror.min.js", "web/lua.min.js", 
    "web/dialog.min.css", "web/dialog.min.js", "web/searchcursor.min.js", "web/search.min.js", 
    "web/clike.min.js", "web/xml.min.js"
}

-- ==========================================
-- DATABASE (LOGS & USER PREFERENCES)
-- ==========================================
local db = dbConnect("sqlite", "logs.db")
dbExec(db, "CREATE TABLE IF NOT EXISTS activity_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, time TEXT, admin TEXT, action TEXT, details TEXT, extra TEXT)")
dbExec(db, "CREATE TABLE IF NOT EXISTS user_preferences (account TEXT PRIMARY KEY, settings TEXT)")

local function addLog(player, action, details, extra)
    local t = getRealTime()
    local timeStr = string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year+1900, t.month+1, t.monthday, t.hour, t.minute, t.second)
    local adminName = isElement(player) and (getPlayerName(player) .. " (" .. getAccountName(getPlayerAccount(player)) .. ")") or "Console"
    dbExec(db, "INSERT INTO activity_logs (time, admin, action, details, extra) VALUES (?, ?, ?, ?, ?)", timeStr, adminName, action, details, extra or "")
end

local function sendError(client, msg)
    outputChatBox("DRE [Error]: " .. msg, client, 255, 50, 50)
    triggerClientEvent(client, "editor:actionComplete", client)
end

local function isPlayerAdmin(player)
    if not isElement(player) then return false end
    local account = getPlayerAccount(player)
    if not account or isGuestAccount(account) then return false end
    return isObjectInACLGroup("user." .. getAccountName(account), aclGetGroup("Admin"))
end

local function isExtensionAllowed(fileName)
    local ext = fileName:match("%.([^%.]+)$") or ""
    return allowedExtensions[string.lower(ext)] or false
end

local function isResourceZipped(resName)
    local metaPath = ":" .. resName .. "/meta.xml"
    if not fileExists(metaPath) then return false end
    local testFile = fileOpen(metaPath, false)
    if not testFile then return true end
    fileClose(testFile)
    return false
end

local function detectResourceTags(resName, resElement)
    local isMap = (getResourceInfo(resElement, "type") == "map")
    local isScript = false
    local isShader = false

    local meta = xmlLoadFile(":" .. resName .. "/meta.xml")
    if meta then
        for _, node in ipairs(xmlNodeGetChildren(meta)) do
            local name = xmlNodeGetName(node)
            local src = (xmlNodeGetAttribute(node, "src") or ""):lower()
            
            if name == "map" or src:match("%.map$") then isMap = true end
            if name == "script" or src:match("%.lua$") then isScript = true end
            if src:match("%.fx$") or src:match("%.hlsl$") then isShader = true end
        end
        xmlUnloadFile(meta)
    end

    if not isMap and not isShader then
        isScript = true
    end

    return {
        isMap = isMap,
        isScript = isScript and not isMap,
        isShader = isShader
    }
end

local function sendResourceList(clientRef)
    if not isElement(clientRef) then return end
    local isAdmin = isPlayerAdmin(clientRef)
    local accessLevel = isAdmin and "editor" or "readonly"

    local resList = {}
    for _, res in ipairs(getResources()) do 
        local name = getResourceName(res)
        local tags = detectResourceTags(name, res)
        table.insert(resList, { 
            name = name, 
            isMap = tags.isMap, 
            isScript = tags.isScript, 
            isShader = tags.isShader 
        })
    end
    table.sort(resList, function(a, b) return a.name < b.name end)
    triggerClientEvent(clientRef, "editor:receiveResources", clientRef, resList, isAdmin, accessLevel, CURRENT_VERSION)
end

-- ==========================================
-- USER PREFERENCES & RECENTS
-- ==========================================
addEvent("editor:savePreferences", true)
addEventHandler("editor:savePreferences", root, function(settingsJSON)
    local clientRef = client
    local account = getPlayerAccount(clientRef)
    if not account or isGuestAccount(account) then return end
    local accName = getAccountName(account)
    dbExec(db, "INSERT OR REPLACE INTO user_preferences (account, settings) VALUES (?, ?)", accName, settingsJSON)
end)

addEvent("editor:requestPreferences", true)
addEventHandler("editor:requestPreferences", root, function()
    local clientRef = client
    local account = getPlayerAccount(clientRef)
    if not account or isGuestAccount(account) then 
        return triggerClientEvent(clientRef, "editor:receivePreferences", clientRef, nil)
    end
    local accName = getAccountName(account)
    dbQuery(function(qh, ply)
        local res = dbPoll(qh, 0)
        if res and #res > 0 then
            triggerClientEvent(ply, "editor:receivePreferences", ply, res[1].settings)
        else
            triggerClientEvent(ply, "editor:receivePreferences", ply, nil)
        end
    end, {clientRef}, db, "SELECT settings FROM user_preferences WHERE account = ?", accName)
end)

addEvent("editor:requestRecentTargets", true)
addEventHandler("editor:requestRecentTargets", root, function()
    local clientRef = client
    dbQuery(function(qh, ply)
        local res = dbPoll(qh, 0) or {}
        local unique = {}
        local out = {}
        for _, row in ipairs(res) do
            local details = tostring(row.details or "")
            local resName = nil
            
            local toRes = details:match("to%s+([%w_%-]+)")
            if toRes then
                resName = toRes
            else
                resName = details:match("^([%w_%-]+)/") or details:match("^([%w_%-]+)")
            end

            if resName and resName ~= "" and getResourceFromName(resName) and not unique[resName] then
                unique[resName] = true
                table.insert(out, resName)
                if #out >= 5 then break end
            end
        end
        triggerClientEvent(ply, "editor:receiveRecentTargets", ply, out)
    end, {clientRef}, db, "SELECT details FROM activity_logs WHERE action IN ('SAVE', 'CREATE', 'RENAME', 'COPY', 'MULTI-COPY') ORDER BY id DESC LIMIT 100")
end)

addEventHandler("onPlayerLogin", root, function()
    sendResourceList(source)
    triggerClientEvent(source, "editor:reloadPreferences", source)
end)

addEventHandler("onPlayerLogout", root, function()
    sendResourceList(source)
    triggerClientEvent(source, "editor:reloadPreferences", source)
end)

local function updateMeta(resName, action, fileName, oldFileName)
    local metaPath = ":" .. resName .. "/meta.xml"
    local meta = xmlLoadFile(metaPath)
    if not meta then return false end

    local changed = false
    if action == "add" then
        local exists = false
        for _, node in ipairs(xmlNodeGetChildren(meta)) do
            if xmlNodeGetAttribute(node, "src") == fileName then exists = true break end
        end
        if not exists then
            local nodeType = "file"
            if fileName:match("%.lua$") then nodeType = "script"
            elseif fileName:match("%.map$") then nodeType = "map" end
            local newNode = xmlCreateChild(meta, nodeType)
            xmlNodeSetAttribute(newNode, "src", fileName)
            if nodeType == "script" then xmlNodeSetAttribute(newNode, "type", "client") end
            changed = true
        end
    elseif action == "remove" then
        for _, node in ipairs(xmlNodeGetChildren(meta)) do
            if xmlNodeGetAttribute(node, "src") == fileName then
                xmlDestroyNode(node)
                changed = true
                break
            end
        end
    elseif action == "rename" then
        for _, node in ipairs(xmlNodeGetChildren(meta)) do
            if xmlNodeGetAttribute(node, "src") == oldFileName then
                xmlNodeSetAttribute(node, "src", fileName)
                changed = true
                break
            end
        end
    end
    if changed then xmlSaveFile(meta) end
    xmlUnloadFile(meta)
end

local function finishAction(client, targetRes, msg)
    refreshResources(false)
    if msg then outputChatBox(msg, client, 0, 255, 0) end
    triggerClientEvent(client, "editor:actionComplete", client)
    triggerClientEvent(client, "editor:syncDirectory", client, targetRes)
end

local function createBackup(resName, fileName)
    local path = ":" .. resName .. "/" .. fileName
    if fileExists(path) then
        local file = fileOpen(path, true)
        local content = fileRead(file, fileGetSize(file))
        fileClose(file)

        local t = getRealTime()
        local ts = string.format("%04d_%02d_%02d_%02d%02d%02d", t.year+1900, t.month+1, t.monthday, t.hour, t.minute, t.second)
        local safeFileName = fileName:gsub("[\\/]", "_")
        local backupPath = "backups/" .. resName .. "/" .. safeFileName .. "_" .. ts .. ".backup"
        
        local bFile = fileCreate(backupPath)
        if bFile then
            fileWrite(bFile, content)
            fileClose(bFile)
            return backupPath
        end
    end
    return nil
end

-- ==========================================
-- GITHUB AUTO-UPDATER
-- ==========================================
local function downloadFile(index, newVersion, player)
    if index > #FILES_TO_UPDATE then
        outputChatBox("[Updater] All files downloaded successfully! Restarting...", player or root, 0, 255, 0)
        restartResource(getThisResource())
        return
    end
    local fileName = FILES_TO_UPDATE[index]
    fetchRemote(GITHUB_RAW_URL .. fileName, function(responseData, errorNo)
        if errorNo == 0 then
            if fileExists(fileName) then fileDelete(fileName) end
            local file = fileCreate(fileName)
            if file then
                fileWrite(file, responseData)
                fileClose(file)
                if isElement(player) then
                    triggerClientEvent(player, "editor:onEditorStatus", string.format("Updating (%d/%d): %s", index, #FILES_TO_UPDATE, fileName), "#2196F3")
                end
                outputChatBox("[Updater] Downloaded: " .. fileName, player or root, 200, 200, 200)
                downloadFile(index + 1, newVersion, player)
            end
        end
    end)
end

local function checkForUpdates(player)
    if not isPlayerAdmin(player) then 
        return sendError(player, "Permission Denied: Only ACL Admins can use the updater.") 
    end
    outputChatBox("[Updater] Checking GitHub repository for new releases...", player, 200, 200, 255)
    fetchRemote(GITHUB_RAW_URL .. "version.txt", function(responseData, errorNo)
        if errorNo == 0 then
            local remoteVersion = tonumber(responseData)
            if remoteVersion and remoteVersion > CURRENT_VERSION_NUM then
                outputChatBox(string.format("[Updater] New version detected (v%.1f). Starting update...", remoteVersion), player, 0, 255, 0)
                downloadFile(1, remoteVersion, player)
            else
                outputChatBox(string.format("[Updater] DRE is already up to date (Current version: v%s).", CURRENT_VERSION), player, 0, 255, 255)
                triggerClientEvent(player, "editor:onEditorStatus", string.format("DRE is up to date (v%s)", CURRENT_VERSION), "#4CAF50")
                triggerClientEvent(player, "editor:actionComplete", player)
            end
        else
            sendError(player, "Failed to connect to GitHub update server (Error code: " .. tostring(errorNo) .. ").")
        end
    end)
end

addCommandHandler("updateeditor", function(player) checkForUpdates(player) end)
addEvent("editor:checkUpdate", true)
addEventHandler("editor:checkUpdate", root, function() checkForUpdates(client) end)

-- ==========================================
-- FILE & RESOURCE EVENTS
-- ==========================================
addEvent("editor:requestResources", true)
addEventHandler("editor:requestResources", root, function()
    sendResourceList(client)
end)

addEvent("editor:requestFiles", true)
addEventHandler("editor:requestFiles", root, function(resName)
    local clientRef = client
    local fileList = {}
    local meta = xmlLoadFile(":" .. resName .. "/meta.xml")
    if meta then
        table.insert(fileList, "meta.xml")
        for _, node in ipairs(xmlNodeGetChildren(meta)) do
            local src = xmlNodeGetAttribute(node, "src")
            if src and isExtensionAllowed(src) then 
                table.insert(fileList, src) 
            end
        end
        xmlUnloadFile(meta)
    end
    triggerClientEvent(clientRef, "editor:receiveFiles", clientRef, fileList)
end)

addEvent("editor:requestContent", true)
addEventHandler("editor:requestContent", root, function(resName, fileName)
    local clientRef = client
    if not isExtensionAllowed(fileName) then
        return sendError(clientRef, "Filetype not supported!")
    end
    local path = ":" .. resName .. "/" .. fileName
    if fileExists(path) then
        local file = fileOpen(path, true)
        local size = fileGetSize(file)
        if size > 2097152 then 
            fileClose(file) 
            return sendError(clientRef, "File too big (> 2MB)!") 
        end
        local content = (size > 0) and fileRead(file, size) or ""
        fileClose(file)
        triggerClientEvent(clientRef, "editor:receiveContent", clientRef, content, resName, fileName)
    else
        sendError(clientRef, "File not found.")
    end
end)

addEvent("editor:saveFile", true)
addEventHandler("editor:saveFile", root, function(resName, fileName, content)
    local clientRef = client
    if not isPlayerAdmin(clientRef) then 
        return sendError(clientRef, "Read-Only: You need to be an ACL Admin to save files!")
    end
    if not isExtensionAllowed(fileName) then
        return sendError(clientRef, "Filetype not supported!")
    end
    if isResourceZipped(resName) then
        return sendError(clientRef, "Resource is zipped! Unzip it on the server to save files.")
    end
    local bPath = createBackup(resName, fileName)
    local path = ":" .. resName .. "/" .. fileName
    if fileExists(path) then fileDelete(path) end
    local file = fileCreate(path)
    if file then
        fileWrite(file, content)
        fileClose(file)
        addLog(clientRef, "SAVE", resName .. "/" .. fileName, bPath or "")
        finishAction(clientRef, resName, "Saved: " .. fileName)
    else 
        sendError(clientRef, "Save failed.") 
    end
end)

addEvent("editor:createFile", true)
addEventHandler("editor:createFile", root, function(resName, fileName)
    local clientRef = client
    if not isPlayerAdmin(clientRef) then 
        return sendError(clientRef, "Read-Only: You need to be an ACL Admin to create files!")
    end
    if not isExtensionAllowed(fileName) then
        return sendError(clientRef, "Filetype not supported!")
    end
    if isResourceZipped(resName) then return sendError(clientRef, "Resource is zipped! Unzip it on the server.") end
    local path = ":" .. resName .. "/" .. fileName
    if fileExists(path) then return sendError(clientRef, "File exists!") end
    local file = fileCreate(path)
    if file then
        fileClose(file)
        updateMeta(resName, "add", fileName)
        addLog(clientRef, "CREATE", resName .. "/" .. fileName)
        finishAction(clientRef, resName, "Created: " .. fileName)
    end
end)

addEvent("editor:deleteFile", true)
addEventHandler("editor:deleteFile", root, function(resName, fileName)
    local clientRef = client
    if not isPlayerAdmin(clientRef) then 
        return sendError(clientRef, "Read-Only: You need to be an ACL Admin to delete files!")
    end
    if fileName == "meta.xml" then return sendError(clientRef, "meta.xml cannot be deleted.") end
    if isResourceZipped(resName) then return sendError(clientRef, "Resource is zipped!") end
    local bPath = createBackup(resName, fileName)
    local path = ":" .. resName .. "/" .. fileName
    if fileExists(path) and fileDelete(path) then
        updateMeta(resName, "remove", fileName)
        addLog(clientRef, "DELETE", resName .. "/" .. fileName, bPath or "")
        finishAction(clientRef, resName, "Deleted: " .. fileName)
    end
end)

addEvent("editor:copyFile", true)
addEventHandler("editor:copyFile", root, function(srcRes, srcFile, tgtRes, tgtFile)
    local clientRef = client
    if not isPlayerAdmin(clientRef) then 
        return sendError(clientRef, "Read-Only: You need to be an ACL Admin to copy files!")
    end
    if not isExtensionAllowed(tgtFile) then
        return sendError(clientRef, "Target filetype not supported!")
    end
    if isResourceZipped(tgtRes) then return sendError(clientRef, "Target resource is zipped!") end
    local srcPath = ":" .. srcRes .. "/" .. srcFile
    local tgtPath = ":" .. tgtRes .. "/" .. tgtFile
    if fileExists(tgtPath) then fileDelete(tgtPath) end
    if fileExists(srcPath) and fileCopy(srcPath, tgtPath) then
        updateMeta(tgtRes, "add", tgtFile)
        addLog(clientRef, "COPY", srcPath .. " -> " .. tgtPath)
        finishAction(clientRef, tgtRes, "Copied file.")
    end
end)

addEvent("editor:copyMultipleFiles", true)
addEventHandler("editor:copyMultipleFiles", root, function(sourceResName, filesData, targetResName)
    local clientRef = client
    if not isPlayerAdmin(clientRef) then 
        return sendError(clientRef, "Read-Only: You need to be an ACL Admin to copy files!")
    end
    if isResourceZipped(targetResName) then
        return sendError(clientRef, "Target resource '" .. targetResName .. "' is a ZIP archive!")
    end
    local files = type(filesData) == "string" and split(filesData, "|") or {}
    local count = 0
    for _, fileName in ipairs(files) do
        if fileName and fileName ~= "" and isExtensionAllowed(fileName) then
            local srcPath = ":" .. sourceResName .. "/" .. fileName
            local tgtPath = ":" .. targetResName .. "/" .. fileName
            if fileExists(srcPath) then
                if fileExists(tgtPath) then fileDelete(tgtPath) end
                if fileCopy(srcPath, tgtPath) then
                    updateMeta(targetResName, "add", fileName)
                    count = count + 1
                end
            end
        end
    end
    addLog(clientRef, "MULTI-COPY", "From " .. sourceResName .. " to " .. targetResName .. " (" .. count .. " files)")
    finishAction(clientRef, targetResName, "Successfully copied " .. count .. " files.")
end)

addEvent("editor:renameFile", true)
addEventHandler("editor:renameFile", root, function(resName, oldName, newName)
    local clientRef = client
    if not isPlayerAdmin(clientRef) then 
        return sendError(clientRef, "Read-Only: You need to be an ACL Admin to rename files!")
    end
    if oldName == "meta.xml" then return sendError(clientRef, "meta.xml cannot be renamed.") end
    if not isExtensionAllowed(newName) then
        return sendError(clientRef, "Target filetype not supported!")
    end
    if isResourceZipped(resName) then return sendError(clientRef, "Resource is zipped!") end
    if fileRename(":"..resName.."/"..oldName, ":"..resName.."/"..newName) then
        updateMeta(resName, "rename", newName, oldName)
        addLog(clientRef, "RENAME", oldName .. " -> " .. newName)
        finishAction(clientRef, resName, "Renamed file.")
    end
end)

addEvent("editor:moveFile", true)
addEventHandler("editor:moveFile", root, function(srcRes, srcFile, tgtRes, tgtFile)
    local clientRef = client
    if not isPlayerAdmin(clientRef) then 
        return sendError(clientRef, "Read-Only: You need to be an ACL Admin to move files!")
    end
    if not isExtensionAllowed(tgtFile) then
        return sendError(clientRef, "Target filetype not supported!")
    end
    if isResourceZipped(tgtRes) or isResourceZipped(srcRes) then return sendError(clientRef, "Resource is zipped!") end
    if fileRename(":"..srcRes.."/"..srcFile, ":"..tgtRes.."/"..tgtFile) then 
        updateMeta(srcRes, "remove", srcFile)
        updateMeta(tgtRes, "add", tgtFile)
        addLog(clientRef, "MOVE", srcFile .. " -> " .. tgtRes)
        finishAction(clientRef, tgtRes, "Moved file.")
    end
end)

addEvent("editor:requestLogs", true)
addEventHandler("editor:requestLogs", root, function()
    local clientRef = client
    if not isPlayerAdmin(clientRef) then return end
    dbQuery(function(qh, ply)
        local res = dbPoll(qh, 0)
        triggerClientEvent(ply, "editor:receiveLogs", ply, res)
    end, {clientRef}, db, "SELECT * FROM activity_logs ORDER BY id DESC LIMIT 100")
end)

addEvent("editor:requestBackups", true)
addEventHandler("editor:requestBackups", root, function(resName)
    local clientRef = client
    if not isPlayerAdmin(clientRef) then return end
    dbQuery(function(qh, ply)
        local res = dbPoll(qh, 0)
        triggerClientEvent(ply, "editor:receiveBackups", ply, res)
    end, {clientRef}, db, "SELECT id, time, action, details, extra FROM activity_logs WHERE action IN ('SAVE', 'DELETE') AND details LIKE ? ORDER BY id DESC LIMIT 50", resName .. "/%")
end)

addEvent("editor:restoreBackup", true)
addEventHandler("editor:restoreBackup", root, function(resName, details, timestamp, directBackupPath)
    local clientRef = client
    if not isPlayerAdmin(clientRef) then 
        return sendError(clientRef, "Read-Only: You need to be an ACL Admin to restore backups!")
    end
    
    local fileName = details:match("^[^/]+/(.+)$") or details
    local safeFileName = fileName:gsub("[\\/]", "_")
    
    local targetBackupFile = nil

    if directBackupPath and directBackupPath ~= "" and fileExists(directBackupPath) then
        targetBackupFile = directBackupPath
    end

    if not targetBackupFile then
        local tsDigits = timestamp:gsub("[^%d]", "")
        local candidateTs = string.format("%s_%s_%s_%s", tsDigits:sub(1,4), tsDigits:sub(5,6), tsDigits:sub(7,8), tsDigits:sub(9,14))
        local exactPath = "backups/" .. resName .. "/" .. safeFileName .. "_" .. candidateTs .. ".backup"
        if fileExists(exactPath) then
            targetBackupFile = exactPath
        end
    end

    if targetBackupFile and fileExists(targetBackupFile) then
        local bFile = fileOpen(targetBackupFile, true)
        local content = fileRead(bFile, fileGetSize(bFile))
        fileClose(bFile)
        
        local path = ":" .. resName .. "/" .. fileName
        if fileExists(path) then fileDelete(path) end
        local nFile = fileCreate(path)
        if nFile then
            fileWrite(nFile, content)
            fileClose(nFile)
            updateMeta(resName, "add", fileName)
            addLog(clientRef, "RESTORE", resName .. "/" .. fileName, targetBackupFile)
            finishAction(clientRef, resName, "Restored backup of: " .. fileName)
        else
            sendError(clientRef, "Failed to restore target file!")
        end
    else
        sendError(clientRef, "Backup file missing on server disk!")
    end
end)