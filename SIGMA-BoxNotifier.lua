local WEBHOOK_URL = "DISCORD_WEBHOOK" -- Change this with your Discord webhook URL
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")

local AUTO_CHECK_ENABLED = true
local LAST_CHECK_TIME = 0


local ANTI_AFK_ENABLED = true
local LAST_AFK_ACTION = 0
local AFK_INTERVAL = 60
local AFK_METHODS = {"move", "jump", "mouse"}

local function sendWebhook(data)
    if WEBHOOK_URL == "DISCORD_WEBHOOK" then
        print("⚠️ Webhook URL not configured. Please set your Discord webhook URL.")
        return false
    end

    if http_request then
        local success, err = pcall(function()
            http_request({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = HttpService:JSONEncode(data)
            })
        end)
        
        if success then
            print("✅ Webhook sent successfully!")
            return true
        else
            print("❌ Failed to send webhook: " .. tostring(err))
            return false
        end
    else
        return false
    end
end



local function checkEventStock()
    print("=== Checking Event Box Stock ===")
    
    local success, result = pcall(function()
        return game:GetService("ReplicatedStorage"):WaitForChild("NetworkContainer"):WaitForChild("RemoteFunctions"):WaitForChild("EventStock"):InvokeServer()
    end)

    if success then
        print("Event Stock Data:")
        local stockInfo = ""
        
        if type(result) == "table" then
            local function printTable(tbl, indent)
                indent = indent or ""
                for key, value in pairs(tbl) do
                    if type(value) == "table" then
                        print(indent .. tostring(key) .. ":")
                        stockInfo = stockInfo .. indent .. tostring(key) .. ":\n"
                        printTable(value, indent .. "  ")
                    else
                        print(indent .. tostring(key) .. ": " .. tostring(value))
                        stockInfo = stockInfo .. indent .. tostring(key) .. ": " .. tostring(value) .. "\n"
                    end
                end
            end
            printTable(result, "  ")
        else
            print("  Result: " .. tostring(result))
            stockInfo = "Result: " .. tostring(result)
        end
        
        local function formatBoxStock(stockData)
            local formatted = ""
            local totalBoxes = 0
            if type(stockData) == "table" and stockData.items then
                for i = 1, 10 do
                    local item = stockData.items[i]
                    if item and type(item) == "table" then
                        local emoji = "📦"
                        local boxName = item.id or "Unknown Box"
                        local stock = item.stock or 0
                        if string.find(boxName:lower(), "legendary") then
                            emoji = "🟨"
                        elseif string.find(boxName:lower(), "epic") then
                            emoji = "🟪"
                        elseif string.find(boxName:lower(), "rare") then
                            emoji = "🟦"
                        elseif string.find(boxName:lower(), "common") then
                            emoji = "🟩"
                        end
                        totalBoxes = totalBoxes + stock
                        formatted = formatted .. emoji .. " **" .. boxName .. "** — x" .. stock .. "\n"
                    end
                end
            end
            return formatted, totalBoxes
        end
        
        local stockDisplay, totalBoxes = formatBoxStock(result)
        local timeLeft = ""
        local discordTimestamp = ""
        local hasLegendary = false
        
        if type(result) == "table" and result.items then
            for i = 1, 10 do
                local item = result.items[i]
                if item and type(item) == "table" and item.id then
                    if string.find(item.id:lower(), "legendary") and (item.stock or 0) > 0 then
                        hasLegendary = true
                        break
                    end
                end
            end
        end
        
        if result and result.timeLeft then
            local minutes = math.floor(result.timeLeft / 60)
            local seconds = result.timeLeft % 60
            timeLeft = string.format("%dm %ds", minutes, seconds)

            local currentUnixTime = os.time()
            local nextRefreshTime = currentUnixTime + result.timeLeft
            
            
            discordTimestamp = "<t:" .. nextRefreshTime .. ":R>"
        else
            local currentTime = os.time()
            local currentMinutes = tonumber(os.date("%M", currentTime))
            local currentSeconds = tonumber(os.date("%S", currentTime))
            local minutesToNext = (10 - (currentMinutes % 10)) % 10
            if minutesToNext == 0 and currentSeconds > 0 then
                minutesToNext = 10
            end
            local secondsToNext = (minutesToNext * 60) - currentSeconds
            
            local nextRefreshTime = currentTime + secondsToNext
            discordTimestamp = "<t:" .. nextRefreshTime .. ":R>"
            timeLeft = string.format("%dm %ds", math.floor(secondsToNext / 60), secondsToNext % 60)
        end
        
        local currentTime = os.date("*t")
        local timeString = string.format("%02d:%02d", currentTime.hour, currentTime.min)
        
        local webhookData = {
            content = hasLegendary and "@everyone **LEGENDARY BOX!!!**" or "",
            embeds = {
                {
                    title = " **🛒 Current Box Stock**",
                    description = "📦 **Boxes Available**\n" .. stockDisplay .. "\n⏰ **Next Refresh**\n " .. (discordTimestamp ~= "" and discordTimestamp or (timeLeft ~= "" and "in " .. timeLeft or "Unknown")),
                    color = hasLegendary and 16766720 or 3447003,
                    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                    footer = {
                        text = "Box Notifier",
                        icon_url = "https://cdn.discordapp.com/icons/783166729069133853/50191c811042aab73a2dfd64f439d855.png?size=480"
                    }
                }
            }
        }
        
        sendWebhook(webhookData)
    else
        print("Error getting event stock: " .. tostring(result))
        
        local errorData = {
            content = "",
            embeds = {
                {
                    title = "❌ Box Stock Check Error",
                    description = "```\nError: " .. tostring(result) .. "```",
                    color = 15158332,
                    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                    footer = {
                        text = "Box Notifier"
                    }
                }
            }
        }
        
        sendWebhook(errorData)
    end
    
    print("=== Stock Check Complete ===")
end

local function shouldAutoCheck()
    if not AUTO_CHECK_ENABLED then return false end
    
    local currentTime = os.time()
    local timeTable = os.date("*t", currentTime)
    local currentMinute = timeTable.min

    local isCheckTime = (currentMinute % 10 == 0)
    
    local timeDiff = currentTime - LAST_CHECK_TIME
    local shouldCheck = isCheckTime and timeDiff >= 60
    
    if shouldCheck then
        LAST_CHECK_TIME = currentTime
        return true
    end
    
    return false
end

local function startAutoCheck()
    local connection
    connection = RunService.Heartbeat:Connect(function()
        if shouldAutoCheck() then
            local currentTime = os.date("*t")
            local timeString = string.format("%02d:%02d", currentTime.hour, currentTime.min)
            print("🕐 Auto-check triggered at " .. timeString)
            checkEventStock()
        end
    end)
    
    print("✅ Auto-check system started!")
 
    return connection
end

local function performAntiAFK()
    if not ANTI_AFK_ENABLED then return end
    
    local player = Players.LocalPlayer
    if not player or not player.Character then return end
    
    local character = player.Character
    local humanoid = character:FindFirstChild("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not rootPart then return end
    
    local method = AFK_METHODS[math.random(1, #AFK_METHODS)]
    
    local success, err = pcall(function()
        if method == "move" then
            local randomDirection = Vector3.new(
                math.random(-2, 2),
                0,
                math.random(-2, 2)
            )
            humanoid:Move(randomDirection, false)
            wait(0.1)
            humanoid:Move(Vector3.new(0, 0, 0), false)
            
        elseif method == "jump" then
            humanoid.Jump = true
            
        elseif method == "mouse" then
            local randomX = math.random(-5, 5)
            local randomY = math.random(-5, 5)
            VirtualInputManager:SendMouseMoveEvent(randomX, randomY, game)
        end
    end)
    
    if not success then
        print("⚠️ Anti-AFK error:", err)
    end
end

local function shouldPerformAntiAFK()
    if not ANTI_AFK_ENABLED then return false end
    
    local currentTime = os.time()
    local timeDiff = currentTime - LAST_AFK_ACTION
    
    if timeDiff >= AFK_INTERVAL then
        LAST_AFK_ACTION = currentTime
        return true
    end
    
    return false
end

local function startAntiAFK()
    local connection
    connection = RunService.Heartbeat:Connect(function()
        if shouldPerformAntiAFK() then
            performAntiAFK()
        end
    end)
    print("⏱️ Anti-AFK interval: " .. AFK_INTERVAL .. " seconds")
    
    return connection
end

local function manualCheck()
    print("🔍 Manual check initiated...")
    checkEventStock()
end

local function sendDisconnectWebhook(reason)
    reason = reason or "Unknown"
    local currentTime = os.date("*t")
    local timeString = string.format("%02d:%02d:%02d", currentTime.hour, currentTime.min, currentTime.sec)
    local webhookData = {
        content = "@everyone,
        embeds = {
            {
                title = "**⚠️ Disconnect Alert**",
                description = "Bot disconnected from the server, please contact the admin for assistance.",
                color = 15158332,
                fields = {
                    {
                        name = "Reason",
                        value = reason,
                        inline = false
                    }
                },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                footer = {
                    text = "Box Notifier",
                    icon_url = "https://cdn.discordapp.com/icons/783166729069133853/50191c811042aab73a2dfd64f439d855.png?size=480"
                }
            }
        }
    }
    sendWebhook(webhookData)
end

Players.PlayerRemoving:Connect(function(player)
    if player == Players.LocalPlayer then
        sendDisconnectWebhook("Player left the game or lost connection.")
    end
end)

checkEventStock()

local autoCheckConnection = startAutoCheck()
local antiAFKConnection = startAntiAFK()

_G.SigmaBoxStock = {
    manualCheck = manualCheck,
    toggleAutoCheck = function()
        AUTO_CHECK_ENABLED = not AUTO_CHECK_ENABLED
        print("🔄 Auto-check " .. (AUTO_CHECK_ENABLED and "ENABLED" or "DISABLED"))
    end,
    stopAutoCheck = function()
        if autoCheckConnection then
            autoCheckConnection:Disconnect()
            print("🛑 Auto-check system stopped!")
        end
    end,
    toggleAntiAFK = function()
        ANTI_AFK_ENABLED = not ANTI_AFK_ENABLED
        print("🛡️ Anti-AFK " .. (ANTI_AFK_ENABLED and "ENABLED" or "DISABLED"))
    end,
}
