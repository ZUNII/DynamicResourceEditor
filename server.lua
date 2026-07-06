-- server.lua

local allowedExtensions = {
    ["lua"] = true, ["xml"] = true, ["html"] = true, ["map"] = true,
    ["js"] = true, ["css"] = true, ["txt"] = true, ["json"] = true, ["fx"] = true, ["hlsl"] = true
}

local CURRENT_VERSION = 2.1
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/ZUNII/DynamicResourceEditor/main/"

local FILES_TO_UPDATE = {
    "server.lua", "client.lua", "meta.xml", "web/editor.html", 
    "web/codemirror.min.js", "web/codemirror.min.css", "web/lua.min.js", "web/material-darker.min.css",
    "web/search.js", "web/searchcursor.js", "web/dialog.js", "web/dialog.css", "web/clike.js", "web/xml.js"
}

-- ==========================================
-- DATABASE (ADMIN LOGS)
-- ==========================================
local db = dbConnect("sqlite", "logs.db")
dbExec(db, "CREATE TABLE IF NOT EXISTS activity_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, time TEXT, admin TEXT, action TEXT, details TEXT)")

local function addLog(player, action, details)
    local t = getRealTime()
    local timeStr = string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year+1900, t.month+1, t.monthday, t.hour, t.minute, t.second)
    local adminName = getPlayerName(player) .. " (" .. getAccountName(getPlayerAccount(player)) .. ")"
    dbExec(db, "INSERT INTO activity_logs (time, admin, action, details) VALUES (?, ?, ?, ?)", timeStr, adminName, action, details)
end

-- ==========================================
-- UTILITIES & SECURITY
-- ==========================================
local function isPlayerAdmin(player)
    local account = getPlayerAccount(player)
    if not account or isGuestAccount(account) then return false end
    return isObjectInACLGroup("user." .. getAccountName(account), aclGetGroup("Admin"))
end

local function sendError(client, msg)
    outputChatBox("DRE [Error]: " .. msg, client, 255, 50, 50)
    triggerClientEvent(client, "editor:actionComplete", client)
end

local function checkAccess(player)
    if not isPlayerAdmin(player) then
        outputChatBox("DRE: You do not have 'Admin' ACL permissions to use the Editor.", player, 255, 50, 50)
        triggerClientEvent(player, "editor:forceClose", player)
        return false
    end
    return true
end

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
    triggerClientEvent(client, "editor:syncDirectory", client)
end

-- ==========================================
-- BACKUP SYSTEM
-- ==========================================
local function createBackup(resName, fileName)
    local path = ":" .. resName .. "/" .. fileName
    if fileExists(path) then
        local file = fileOpen(path, true)
        local content = fileRead(file, fileGetSize(file))
        fileClose(file)

        local t = getRealTime()
        local ts = string.format("%04d_%02d_%02d_%02d%02d%02d", t.year+1900, t.month+1, t.monthday, t.hour, t.minute, t.second)
        local safeFileName = fileName:gsub("/", "_")
        local backupPath = "backups/" .. resName .. "/" .. safeFileName .. "_" .. ts .. ".backup"
        
        local bFile = fileCreate(backupPath)
        if bFile then
            fileWrite(bFile, content)
            fileClose(bFile)
        end
    end
end

-- ==========================================
-- EVENTS (INCL. MULTI-COPY)
-- ==========================================
addEvent("editor:copyMultipleFiles", true)
addEventHandler("editor:copyMultipleFiles", root, function(sourceResName, filesData, targetResName)
    if not checkAccess(client) then return end
    
    local files = {}
    
    -- Extract delimiter and convert to table
    if type(filesData) == "string" then
        files = split(filesData, "|")
    end
    
    if type(files) == "table" and #files > 0 then
        local count = 0
        for _, fileName in ipairs(files) do
            if fileName and fileName ~= "" then
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
        addLog(client, "MULTI-COPY", "From " .. sourceResName .. " to " .. targetResName .. " (" .. count .. " files)")
        finishAction(client, targetResName, "Successfully copied " .. count .. " files.")
    else
        sendError(client, "Failed to read file list. Please try again.")
    end
end)

addEvent("editor:requestResources", true)
addEventHandler("editor:requestResources", root, function()
    if not checkAccess(client) then return end
    local resList = {}
    for _, res in ipairs(getResources()) do table.insert(resList, getResourceName(res)) end
    table.sort(resList)
    triggerClientEvent(client, "editor:receiveResources", client, resList)
end)

addEvent("editor:requestFiles", true)
addEventHandler("editor:requestFiles", root, function(resName)
    if not checkAccess(client) then return end
    local fileList = {}
    local meta = xmlLoadFile(":" .. resName .. "/meta.xml")
    if meta then
        table.insert(fileList, "meta.xml")
        for _, node in ipairs(xmlNodeGetChildren(meta)) do
            local src = xmlNodeGetAttribute(node, "src")
            if src then table.insert(fileList, src) end
        end
        xmlUnloadFile(meta)
    end
    triggerClientEvent(client, "editor:receiveFiles", client, fileList)
end)

addEvent("editor:requestContent", true)
addEventHandler("editor:requestContent", root, function(resName, fileName)
    if not checkAccess(client) then return end
    local ext = fileName:match("%.([^%.]+)$") or ""
    if not allowedExtensions[string.lower(ext)] then return sendError(client, "Filetype not supported!") end
    local path = ":" .. resName .. "/" .. fileName
    if fileExists(path) then
        local file = fileOpen(path, true)
        local size = fileGetSize(file)
        if size > 1048576 then fileClose(file) return sendError(client, "File too big!") end
        local content = size > 0 and fileRead(file, size) or ""
        fileClose(file)
        triggerClientEvent(client, "editor:receiveContent", client, content, resName, fileName)
    else
        sendError(client, "File not found.")
    end
end)

addEvent("editor:saveFile", true)
addEventHandler("editor:saveFile", root, function(resName, fileName, content)
    if not checkAccess(client) then return end
    createBackup(resName, fileName)
    local path = ":" .. resName .. "/" .. fileName
    if fileExists(path) then fileDelete(path) end
    local file = fileCreate(path)
    if file then
        fileWrite(file, content)
        fileClose(file)
        addLog(client, "SAVE", resName .. "/" .. fileName)
        finishAction(client, resName, "Saved: " .. fileName)
    else sendError(client, "Save failed.") end
end)

addEvent("editor:createFile", true)
addEventHandler("editor:createFile", root, function(resName, fileName)
    if not checkAccess(client) then return end
    local path = ":" .. resName .. "/" .. fileName
    if fileExists(path) then return sendError(client, "File exists!") end
    local file = fileCreate(path)
    if file then
        fileClose(file)
        updateMeta(resName, "add", fileName)
        addLog(client, "CREATE", resName .. "/" .. fileName)
        finishAction(client, resName, "Created: " .. fileName)
    end
end)

addEvent("editor:deleteFile", true)
addEventHandler("editor:deleteFile", root, function(resName, fileName)
    if not checkAccess(client) or fileName == "meta.xml" then return end
    createBackup(resName, fileName)
    local path = ":" .. resName .. "/" .. fileName
    if fileExists(path) and fileDelete(path) then
        updateMeta(resName, "remove", fileName)
        addLog(client, "DELETE", resName .. "/" .. fileName)
        finishAction(client, resName, "Deleted: " .. fileName)
    end
end)

addEvent("editor:copyFile", true)
addEventHandler("editor:copyFile", root, function(srcRes, srcFile, tgtRes, tgtFile)
    if not checkAccess(client) then return end
    local srcPath = ":" .. srcRes .. "/" .. srcFile
    local tgtPath = ":" .. tgtRes .. "/" .. tgtFile
    if fileExists(tgtPath) then fileDelete(tgtPath) end
    if fileExists(srcPath) and fileCopy(srcPath, tgtPath) then
        updateMeta(tgtRes, "add", tgtFile)
        addLog(client, "COPY", srcPath .. " -> " .. tgtPath)
        finishAction(client, tgtRes, "Copied file.")
    end
end)

addEvent("editor:renameFile", true)
addEventHandler("editor:renameFile", root, function(resName, oldName, newName)
    if not checkAccess(client) or oldName == "meta.xml" then return end
    if fileRename(":"..resName.."/"..oldName, ":"..resName.."/"..newName) then
        updateMeta(resName, "rename", newName, oldName)
        addLog(client, "RENAME", oldName .. " -> " .. newName)
        finishAction(client, resName, "Renamed file.")
    end
end)

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
                outputChatBox("[Updater] Downloaded: " .. fileName, player or root, 200, 200, 200)
                downloadFile(index + 1, newVersion, player)
            end
        end
    end)
end

addCommandHandler("updateeditor", function(player)
    if not checkAccess(player) then return end
    fetchRemote(GITHUB_RAW_URL .. "version.txt", function(responseData, errorNo)
        if errorNo == 0 then
            local remoteVersion = tonumber(responseData)
            if remoteVersion and remoteVersion > CURRENT_VERSION then
                downloadFile(1, remoteVersion, player)
            end
        end
    end)
end)