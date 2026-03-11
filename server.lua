-- server.lua

-- ==========================================
-- UPDATER CONFIGURATION
-- ==========================================
local CURRENT_VERSION = 1.0 -- Change this when you push new updates
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/ZUNII/DynamicResourceEditor/main/"

local FILES_TO_UPDATE = {
    "server.lua",
    "client.lua",
    "meta.xml"
}

-- ==========================================
-- UTILITY FUNCTIONS
-- ==========================================
local function isPlayerAdmin(player)
    local account = getPlayerAccount(player)
    if not account or isGuestAccount(account) then return false end
    return isObjectInACLGroup("user." .. getAccountName(account), aclGetGroup("Admin"))
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
                local newType = "file"
                if fileName:match("%.lua$") then newType = "script"
                elseif fileName:match("%.map$") then newType = "map" end
                xmlNodeSetName(node, newType)
                changed = true
                break
            end
        end
    end

    if changed then xmlSaveFile(meta) end
    xmlUnloadFile(meta)
end

local function finishAction(client, targetRes, msg)
    refreshResources(true)
    local res = getResourceFromName(targetRes)
    if res and getResourceState(res) == "running" then 
        restartResource(res) 
    end
    if msg then outputChatBox(msg, client, 0, 255, 0) end
    triggerClientEvent(client, "editor:syncDirectory", client)
end

-- ==========================================
-- DATA FETCHING
-- ==========================================
addEvent("editor:requestResources", true)
addEventHandler("editor:requestResources", root, function()
    if not isPlayerAdmin(client) then return end
    local resTable = {}
    for _, res in ipairs(getResources()) do table.insert(resTable, getResourceName(res)) end
    table.sort(resTable)
    triggerClientEvent(client, "editor:receiveResources", client, resTable)
end)

addEvent("editor:requestFiles", true)
addEventHandler("editor:requestFiles", root, function(resName)
    if not isPlayerAdmin(client) then return end
    local files = {"meta.xml"}
    local meta = xmlLoadFile(":" .. resName .. "/meta.xml")
    if meta then
        for _, node in ipairs(xmlNodeGetChildren(meta)) do
            local src = xmlNodeGetAttribute(node, "src")
            if src then table.insert(files, src) end
        end
        xmlUnloadFile(meta)
    end
    triggerClientEvent(client, "editor:receiveFiles", client, files)
end)

addEvent("editor:requestContent", true)
addEventHandler("editor:requestContent", root, function(resName, fileName)
    if not isPlayerAdmin(client) then return end
    local path = ":" .. resName .. "/" .. fileName
    if fileExists(path) then
        local file = fileOpen(path, true)
        local content = fileGetSize(file) > 0 and fileRead(file, fileGetSize(file)) or ""
        fileClose(file)
        triggerClientEvent(client, "editor:receiveContent", client, content, resName, fileName)
    end
end)

-- ==========================================
-- FILE OPERATIONS
-- ==========================================
addEvent("editor:saveFile", true)
addEventHandler("editor:saveFile", root, function(resName, fileName, content)
    if not isPlayerAdmin(client) then return end
    local path = ":" .. resName .. "/" .. fileName
    if fileExists(path) then fileDelete(path) end
    local file = fileCreate(path)
    if file then
        fileWrite(file, content)
        fileClose(file)
        finishAction(client, resName, "Saved & Refreshed: " .. fileName)
    else
        outputChatBox("Error: Could not save file.", client, 255, 0, 0)
    end
end)

addEvent("editor:createFile", true)
addEventHandler("editor:createFile", root, function(resName, fileName)
    if not isPlayerAdmin(client) then return end
    local path = ":" .. resName .. "/" .. fileName
    
    if fileExists(path) then 
        return outputChatBox("Error: File already exists! Delete it first.", client, 255, 0, 0) 
    end
    
    local file = fileCreate(path)
    if file then
        fileClose(file)
        updateMeta(resName, "add", fileName)
        finishAction(client, resName, "Created new file: " .. fileName)
    else
        outputChatBox("Error: Failed to create file (Check ACL).", client, 255, 0, 0)
    end
end)

addEvent("editor:copyFile", true)
addEventHandler("editor:copyFile", root, function(srcRes, srcFile, tgtRes, tgtFile)
    if not isPlayerAdmin(client) then return end
    local srcPath = ":" .. srcRes .. "/" .. srcFile
    local tgtPath = ":" .. tgtRes .. "/" .. tgtFile
    
    if not fileExists(srcPath) then return outputChatBox("Error: Source file missing.", client, 255, 0, 0) end
    if fileExists(tgtPath) then fileDelete(tgtPath) end
    
    if fileCopy(srcPath, tgtPath) then
        updateMeta(tgtRes, "add", tgtFile)
        finishAction(client, tgtRes, "Copied to " .. tgtRes .. " as " .. tgtFile)
    else
        outputChatBox("Error: Failed to copy file.", client, 255, 0, 0)
    end
end)

addEvent("editor:renameFile", true)
addEventHandler("editor:renameFile", root, function(resName, oldName, newName)
    if not isPlayerAdmin(client) then return end
    if oldName == "meta.xml" then return outputChatBox("Cannot rename meta.xml", client, 255, 0, 0) end
    local oldPath = ":" .. resName .. "/" .. oldName
    local newPath = ":" .. resName .. "/" .. newName
    
    if fileRename(oldPath, newPath) then
        updateMeta(resName, "rename", newName, oldName)
        finishAction(client, resName, "Renamed " .. oldName .. " to " .. newName)
    end
end)

addEvent("editor:deleteFile", true)
addEventHandler("editor:deleteFile", root, function(resName, fileName)
    if not isPlayerAdmin(client) then return end
    if fileName == "meta.xml" then return outputChatBox("Cannot delete meta.xml", client, 255, 0, 0) end
    local path = ":" .. resName .. "/" .. fileName
    
    if fileExists(path) and fileDelete(path) then
        updateMeta(resName, "remove", fileName)
        finishAction(client, resName, "Deleted file: " .. fileName)
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
                
                -- Download the next file in the list
                downloadFile(index + 1, newVersion, player)
            else
                outputChatBox("[Updater] Error: Could not save " .. fileName, player or root, 255, 0, 0)
            end
        else
            outputChatBox("[Updater] HTTP Error " .. errorNo .. " while downloading " .. fileName, player or root, 255, 0, 0)
        end
    end)
end

addCommandHandler("updateeditor", function(player)
    if not isPlayerAdmin(player) then return end
    
    outputChatBox("[Updater] Checking GitHub for updates...", player, 0, 200, 255)
    
    fetchRemote(GITHUB_RAW_URL .. "version.txt", function(responseData, errorNo)
        if errorNo == 0 then
            local remoteVersion = tonumber(responseData)
            
            if remoteVersion then
                if remoteVersion > CURRENT_VERSION then
                    outputChatBox("[Updater] New version found! (v" .. remoteVersion .. "). Starting download...", player, 0, 255, 0)
                    downloadFile(1, remoteVersion, player)
                else
                    outputChatBox("[Updater] Dynamic Resource Editor is up to date (v" .. CURRENT_VERSION .. ").", player, 0, 255, 0)
                end
            else
                outputChatBox("[Updater] Error: version.txt on GitHub is not a valid number.", player, 255, 0, 0)
            end
        else
            outputChatBox("[Updater] Failed to reach GitHub (Error: " .. errorNo .. ").", player, 255, 0, 0)
        end
    end)
end)