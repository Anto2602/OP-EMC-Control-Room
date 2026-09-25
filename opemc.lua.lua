-- === SECURE AUTH SYSTEM ===
local ENCRYPTED_HEX = "10252d240b1036236d7b574c"
local XOR_KEY = "UP_Key"
local accessHashPath = "/.access_granted"
local programName = shell.getRunningProgram()

local function str2hexa(s)
  return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function num2s(l, n)
  local s = ""
  for i = 1, n do
    local rem = l % 256
    s = string.char(rem) .. s
    l = (l - rem) / 256
  end
  return s
end

local function s232num(s, i)
  local n = 0
  for i = i, i + 3 do n = n * 256 + s:byte(i) end
  return n
end

local function preproc(msg, len)
  local extra = 64 - ((len + 9) % 64)
  len = num2s(8 * len, 8)
  msg = msg .. "\128" .. string.rep("\0", extra) .. len
  assert(#msg % 64 == 0)
  return msg
end

local function rol(value, shift)
  return bit32.band(bit32.bor(bit32.lshift(value, shift), bit32.rshift(value, 32 - shift)), 0xFFFFFFFF)
end

local function digestblock(msg, i, H)
  local w = {}
  for j = 1, 16 do w[j] = s232num(msg, i + (j - 1) * 4) end
  for j = 17, 80 do
    local a = bit32.bxor(w[j - 3], w[j - 8], w[j - 14], w[j - 16])
    w[j] = rol(a, 1)
  end

  local a, b, c, d, e = H[1], H[2], H[3], H[4], H[5]

  for j = 1, 80 do
    local f, k
    if j <= 20 then
      f = bit32.bor(bit32.band(b, c), bit32.band(bit32.bnot(b), d))
      k = 0x5A827999
    elseif j <= 40 then
      f = bit32.bxor(b, c, d)
      k = 0x6ED9EBA1
    elseif j <= 60 then
      f = bit32.bor(bit32.band(b, c), bit32.band(b, d), bit32.band(c, d))
      k = 0x8F1BBCDC
    else
      f = bit32.bxor(b, c, d)
      k = 0xCA62C1D6
    end

    local temp = (rol(a, 5) + f + e + k + w[j]) % 2^32
    e, d, c, b, a = d, c, rol(b, 30), a, temp
  end

  H[1] = (H[1] + a) % 2^32
  H[2] = (H[2] + b) % 2^32
  H[3] = (H[3] + c) % 2^32
  H[4] = (H[4] + d) % 2^32
  H[5] = (H[5] + e) % 2^32
end

local function sha1(msg)
  local H = {
    0x67452301,
    0xEFCDAB89,
    0x98BADCFE,
    0x10325476,
    0xC3D2E1F0
  }
  msg = preproc(msg, #msg)
  for i = 1, #msg, 64 do digestblock(msg, i, H) end
  return str2hexa(table.concat({
    num2s(H[1], 4),
    num2s(H[2], 4),
    num2s(H[3], 4),
    num2s(H[4], 4),
    num2s(H[5], 4)
  }))
end

local function hmac_sha1(key, message)
  local blocksize = 64
  if #key > blocksize then
    key = hexToStr(sha1(key))
  end
  key = key .. string.rep("\0", blocksize - #key)
  local o_key_pad = key:gsub(".", function(c) return string.char(bit32.bxor(string.byte(c), 0x5c)) end)
  local i_key_pad = key:gsub(".", function(c) return string.char(bit32.bxor(string.byte(c), 0x36)) end)
  return sha1(o_key_pad .. sha1(i_key_pad .. message))
end


local function hexToStr(hex)
  return hex:gsub("..", function(cc) return string.char(tonumber(cc, 16)) end)
end

local function xor(str, key)
  local result = ""
  for i = 1, #str do
    local s = string.byte(str, i)
    local k = string.byte(key, ((i - 1) % #key) + 1)
    result = result .. string.char(bit32.bxor(s, k))
  end
  return result
end

local function isAuthorized()
  if not fs.exists(accessHashPath) then return false end
  local f = fs.open(accessHashPath, "r")
  local content = f.readAll()
  f.close()
  return content == hmac_sha1(XOR_KEY, programName)
end

if not isAuthorized() then
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  print("OP EMC PANEL MANAGER:")
  term.write("Enter Password: ")
  local input = read("*")

  if xor(input, XOR_KEY) == hexToStr(ENCRYPTED_HEX) then
    print("Access granted")
    local f = fs.open(accessHashPath, "w")
    f.write(hmac_sha1(XOR_KEY, programName))
    f.close()
  else
    print("Access denied. ERROR 404")
    fs.delete(programName)
    sleep(1)
    os.shutdown()
  end
end

-- === EMBEDDED AQUARIUM VISUAL ===
-- The GIF is embedded so this script is self-contained.
-- Farm/transfer logic is not changed by the embedded asset.
local aquariumData = table.concat({
    "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",
})

local function base64Decode(data)
    local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    data = data:gsub("[^" .. b .. "=]", "")
    return (data:gsub(".", function(x)
        if x == "=" then return "" end
        local r, f = "", (b:find(x, 1, true) - 1)
        for i = 6, 1, -1 do
            r = r .. (f % 2^i - f % 2^(i-1) > 0 and "1" or "0")
        end
        return r
    end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
        if #x ~= 8 then return "" end
        local c = 0
        for i = 1, 8 do
            c = c + (x:sub(i,i) == "1" and 2^(8-i) or 0)
        end
        return string.char(c)
    end))
end

local mon = peripheral.find("monitor")
if not mon then error("Monitor not found") end
mon.setTextScale(0.5)
term.redirect(mon)
local monW, monH = term.getSize()

local originalAquarium = "OP_EMC_AQUARIUM_SOURCE.gif"
local aquariumH = math.max(1, monH - 5)
local storedAquarium = "GIFs/" .. monW .. "x" .. aquariumH .. "_aquarium_hud.gif"
if not fs.exists("GIF") then
    shell.run("pastebin", "get", "5uk9uRjC", "GIF")
end
os.loadAPI("GIF")

if not fs.exists(originalAquarium) then
    local f = assert(fs.open(originalAquarium, "wb"))
    f.write(base64Decode(aquariumData))
    f.close()
end

if not fs.exists("GIFs") then fs.makeDir("GIFs") end
if not fs.exists(storedAquarium) then
    local image = GIF.loadGIF(originalAquarium)
    image = GIF.resizeGIF(image, monW, aquariumH)
    GIF.saveGIF(image, storedAquarium)
end
local image = GIF.loadGIF(storedAquarium)

local function _syncClock()
  if not fs.exists(accessHashPath) then
    error("✘ Security block missing: access file not found")
  end
  local f = fs.open(accessHashPath, "r")
  local val = f.readAll()
  f.close()
  if val ~= hmac_sha1(XOR_KEY, programName) then
    error("✘ Security block mismatch: tampered or invalid")
  end
end

local wrappedPeripherals = {}
for _, name in ipairs(peripheral.getNames()) do
    wrappedPeripherals[name] = peripheral.wrap(name)
end

local reserveCount = 64
local trackedEMCPerRMF = 10059784
local rodEMC = 1536
local totalTransferred = 0
local lastCheckTime = os.clock()

local powderCondensers = {}
local rmfCondensers = {}

local inventoryCache = {}

local function createCacheWorker(startIndex, step)
    return function()
        while true do
            for i = startIndex, #powderCondensers, step do
                local name = powderCondensers[i]
                local wrapped = wrappedPeripherals[name]

                local status, items = pcall(function()
                    return wrapped.list()
                end)

                if status and items then
                    local rodSlots = {}
                    local totalRods = 0

                    for slot, item in pairs(items) do
                        if item.name == "minecraft:blaze_rod" then
                            local count = item.count or 0
                            rodSlots[#rodSlots + 1] = {
                                slot = slot,
                                count = count
                            }
                            totalRods = totalRods + count
                        end
                    end

                    inventoryCache[name] = {
                        rodSlots = rodSlots,
                        totalRods = totalRods
                    }
                else
                    inventoryCache[name] = nil
                end

                os.queueEvent("yield")
                os.pullEvent("yield")
            end
            sleep(1)
        end
    end
end

local bhuName
local bhu
for _, name in ipairs(peripheral.getNames()) do
    if name:find("industrialforegoing:black_hole_unit_tile") then
        _syncClock()
        bhuName = name
        bhu = peripheral.wrap(name)
        break
    end
end

local function centerText(text, y)
    local x = math.floor((monW - #text) / 2)
    mon.setCursorPos(x, y)
    mon.write(text)
end

local function drawBootScreenWithSetup(setupFn)
    mon.setBackgroundColor(colors.black)
    mon.clear()
    mon.setTextColor(colors.white)
    centerText("NEW OP EMC Generator", math.floor(monH / 2) - 2)
    centerText("Powering On, Please Wait...", math.floor(monH / 2) - 1)

    local barWidth = monW - 10
    local barX = math.floor((monW - barWidth) / 2)
    local barY = math.floor(monH / 2) + 1
    local sweepWidth = 5
    local delay = 0.1
    local cycles = 3

    local done = false
    
    parallel.waitForAny(
        function()
            setupFn()
            done = true
        end,
        function()
            for cycle = 1, cycles do
                for i = 1, barWidth + sweepWidth do
                    mon.setCursorPos(barX, barY)
                    for j = 1, barWidth do
                        if j >= i and j < i + sweepWidth then
                            mon.setBackgroundColor(colors.lime)
                        else
                            mon.setBackgroundColor(colors.gray)
                        end
                        mon.write(" ")
                    end
                    sleep(delay)
                    if done then return end
                end
            end
        end
    )

    mon.setBackgroundColor(colors.black)
    mon.clear()
end


local enderChests = {}
for _, name in ipairs(peripheral.getNames()) do
    if name:lower():find("ender chest") then
        table.insert(enderChests, name)
    end
end

local function classifyCondensers()
powderCondensers = {}
rmfCondensers = {}

    for _, name in ipairs(peripheral.getNames()) do
        if name:match("^projecte:condenser_mk2_") then
			_syncClock()
            local inv = wrappedPeripherals[name]
            local hasBlazeRod = false

            for _, item in pairs(inv.list()) do
                if item.name == "minecraft:blaze_rod" then
                    hasBlazeRod = true
                    break
                end
            end

            if hasBlazeRod then
                table.insert(powderCondensers, name)
            else
                table.insert(rmfCondensers, name)
            end
        end
    end
end
drawBootScreenWithSetup(function()
    classifyCondensers()
    _syncClock()
end)

local wrappedPeripherals = {}
local enderChests = {}

for _, name in ipairs(peripheral.getNames()) do
    wrappedPeripherals[name] = peripheral.wrap(name)
    if name:lower():find("ender chest") then
        table.insert(enderChests, name)
    end
end

local function runDrainLoop()
    while true do
		_syncClock()
        if bhu then
            for _, condName in ipairs(rmfCondensers) do
                local cond = wrappedPeripherals[condName]
                for slot, item in pairs(cond.list()) do
                    if item.name == "projecte:rm_furnace" then
                        cond.pushItems(peripheral.getName(bhu), slot, item.count)
                    end
                end
            end
        end
        sleep(0.1)
    end
end

local function createTransferWorker(startIndex, step)
    return function()
        local index = startIndex
        local cyclesPerCondenser = 12
        local rmfIndex = 1

        while true do
            if #powderCondensers == 0 or #rmfCondensers == 0 then
                sleep(0.5)
            else
                local name = powderCondensers[index]
                local inv = wrappedPeripherals[name]
                local cachedList = inventoryCache[name]

                if cachedList then
                    local rodSlots = cachedList.rodSlots
                    local totalRods = cachedList.totalRods

                    if totalRods > reserveCount then
                        local available = totalRods - reserveCount

                        for cycle = 1, cyclesPerCondenser do
                            for _, rodSlot in ipairs(rodSlots) do
                                if available <= 0 then break end

                                local rmfName = rmfCondensers[rmfIndex]
                                local toMove = math.min(rodSlot.count, available)
                                local moved = 0

                                if toMove > 0 then
                                    moved = inv.pushItems(rmfName, rodSlot.slot, toMove) or 0
                                end

                                totalTransferred = totalTransferred + moved
                                available = available - moved
                                rodSlot.count = rodSlot.count - moved
                                cachedList.totalRods = cachedList.totalRods - moved

                                -- Rotate RMF target
                                rmfIndex = rmfIndex + 1
                                if rmfIndex > #rmfCondensers then rmfIndex = 1 end
                            end
                        end
                    end
                end

                index = index + step
                if index > #powderCondensers then
                    index = (index - 1) % step + 1
                end

                sleep(0.01)
            end
        end
    end
end


local function refillEnderChests()
    while true do
        if not bhu then sleep(2) end

        for _, name in ipairs(enderChests) do
            local chest = wrappedPeripherals[name]
            local count = 0

            for _, item in pairs(chest.list()) do
                if item.name == "projecte:rm_furnace" then
                    count = count + item.count
                end
            end

            if count < 1728 then
                local needed = 1728 - count
                for slot, item in pairs(bhu.list()) do
                    if item.name == "projecte:rm_furnace" then
                        local toMove = math.min(item.count, needed)
                        if toMove > 0 then
                            bhu.pushItems(name, slot, toMove)
                            needed = needed - toMove
                            if needed <= 0 then break end
                        end
                    end
                end
            end
        end

        sleep(2)
    end
end


local function runTransfers()
    local tasks = {}
    local numWorkers = math.min(#powderCondensers, 14)
    for i = 1, numWorkers do
        table.insert(tasks, createTransferWorker(i, numWorkers))
    end
    table.insert(tasks, runDrainLoop)
    for i = 1, 4 do
        table.insert(tasks, createCacheWorker(i, 4))
    end
    parallel.waitForAll(table.unpack(tasks))
end



-- === MULTI-MONITOR EMC CONTROL ROOM ===
-- Visual layer only. The farm engine above is intentionally left unchanged.

local allMonitors = {}
for _, name in ipairs(peripheral.getNames()) do
    local pType = peripheral.getType(name)
    if pType == "monitor" then
        local m = peripheral.wrap(name)
        if m then
            m.setTextScale(0.5)
            table.insert(allMonitors, { name = name, monitor = m })
        end
    end
end

-- ComputerCraft does not guarantee physical left-to-right peripheral ordering.
-- The default is sorted-name order: left, center, right.
table.sort(allMonitors, function(a, b) return a.name < b.name end)

local leftMon = allMonitors[1]
local centerMon = allMonitors[2]
local rightMon = allMonitors[3]

if #allMonitors == 1 then
    centerMon = allMonitors[1]
    rightMon = nil
elseif #allMonitors == 2 then
    -- With two monitors, use the first as statistics and second as the main core.
    -- The LIVE CONTROL panel is simply omitted.
    rightMon = nil
end

local function clearMonitor(m)
    local w, h = m.getSize()
    m.setBackgroundColor(colors.black)
    m.setTextColor(colors.white)
    m.clear()
    return w, h
end

local function shortNumber(n)
    local abs = math.abs(n)
    if abs >= 1e12 then return string.format("%.2fT", n / 1e12)
    elseif abs >= 1e9 then return string.format("%.2fB", n / 1e9)
    elseif abs >= 1e6 then return string.format("%.2fM", n / 1e6)
    elseif abs >= 1e3 then return string.format("%.2fK", n / 1e3)
    else return string.format("%.0f", n) end
end

local function writeAt(m, x, y, text, fg, bg)
    local w, h = m.getSize()
    if y < 1 or y > h or x > w then return end
    if x < 1 then x = 1 end
    local maxLen = w - x + 1
    if #text > maxLen then text = text:sub(1, maxLen) end
    m.setCursorPos(x, y)
    m.setTextColor(fg or colors.white)
    m.setBackgroundColor(bg or colors.black)
    m.write(text)
end

local function centerAt(m, y, text, fg, bg)
    local w = m.getSize()
    local x = math.floor((w - #text) / 2) + 1
    if x < 1 then x = 1 end
    writeAt(m, x, y, text, fg, bg)
end

local function rule(m, y, title, color, left, right)
    local w = m.getSize()
    if y < 1 or y > m.getSize() then return end
    local line = string.rep("-", math.max(0, w))
    writeAt(m, 1, y, line, colors.gray, colors.black)
    local shown = title or ""
    local x = math.max(2, math.floor((w - #shown) / 2) + 1)
    writeAt(m, x, y, shown, color or colors.lightBlue, colors.black)
    if left then writeAt(m, 2, y, left, colors.gray, colors.black) end
    if right then writeAt(m, math.max(1, w - #right - 1), y, right, colors.gray, colors.black) end
end

local function safeBHUStats()
    local rmfCount, storedEMC = 0, 0
    if bhu then
        local ok, items = pcall(function() return bhu.list() end)
        if ok and items then
            for _, item in pairs(items) do
                if item.name == "projecte:rm_furnace" then
                    rmfCount = rmfCount + item.count
                    storedEMC = storedEMC + item.count * trackedEMCPerRMF
                end
            end
        end
    end
    return rmfCount, storedEMC
end

local function formatUptime(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

local liveStart = os.clock()
local liveTransferred = totalTransferred
local liveEmcPerMinute = 0
local liveRodsPerSecond = 0
local nextLiveReset = liveStart + 5
local lastHudRefresh = 0
local animationFrame = 0

-- Static background / headings are drawn once; data is refreshed every second.
local function setupMonitor(m, title)
    if not m then return end
    local w, h = clearMonitor(m)
    centerAt(m, 1, title, colors.white, colors.black)
    writeAt(m, 2, 2, "OP-EMC SYSTEM", colors.lime, colors.black)
    writeAt(m, math.max(1, w - 12), 2, "[ ONLINE ]", colors.lime, colors.black)
    return w, h
end

local leftW, leftH
local centerW, centerH
local rightW, rightH

if leftMon then leftW, leftH = setupMonitor(leftMon.monitor, "STATISTICS // EMC") end
if centerMon then centerW, centerH = setupMonitor(centerMon.monitor, "MAIN CORE // EMC") end
if rightMon then rightW, rightH = setupMonitor(rightMon.monitor, "LIVE CONTROL // EMC") end

local function drawLeft(m, stats)
    if not m then return end
    local w, h = m.getSize()

    centerAt(m, 1, "STATISTICS // EMC", colors.white, colors.black)
    writeAt(m, 2, 2, "OP-EMC / HISTORICAL", colors.lightBlue, colors.black)
    writeAt(m, math.max(1, w - 12), 2, "[ ONLINE ]", colors.lime, colors.black)

    rule(m, 4, "STATISTICS / MIN", colors.lime)
    writeAt(m, 3, 5, "EMC GENERATED", colors.gray)
    writeAt(m, math.max(22, w - 17), 5, shortNumber(stats.emcMin), colors.lime)
    writeAt(m, 3, 6, "EMC / MAC", colors.gray)
    writeAt(m, math.max(22, w - 17), 6, shortNumber(stats.emcMac), colors.lightBlue)
    writeAt(m, 3, 7, "RODS / SEC", colors.gray)
    writeAt(m, math.max(22, w - 17), 7, shortNumber(stats.rodsSec), colors.orange)

    rule(m, 9, "STATISTICS / HOUR", colors.lightBlue)
    writeAt(m, 3, 10, "EMC GENERATED", colors.gray)
    writeAt(m, math.max(22, w - 17), 10, shortNumber(stats.emcHour), colors.lightBlue)
    writeAt(m, 3, 11, "RODS MOVED", colors.gray)
    writeAt(m, math.max(22, w - 17), 11, shortNumber(stats.rodsHour), colors.orange)

    rule(m, 13, "SYSTEM", colors.orange)
    writeAt(m, 3, 14, "CONDENSERS", colors.gray)
    writeAt(m, math.max(22, w - 17), 14, tostring(stats.condensers), colors.lime)
    writeAt(m, 3, 15, "MACERATORS", colors.gray)
    writeAt(m, math.max(22, w - 17), 15, tostring(stats.macerators), colors.lime)
    writeAt(m, 3, 16, "RMF STORED", colors.gray)
    writeAt(m, math.max(22, w - 17), 16, shortNumber(stats.rmf), colors.orange)
    writeAt(m, 3, 17, "UPTIME", colors.gray)
    writeAt(m, math.max(22, w - 17), 17, stats.uptime, colors.white)

    if h >= 20 then
        centerAt(m, h - 2, "TRANSFER ENGINE ACTIVE", colors.lime, colors.black)
        centerAt(m, h, "(C) Anto2602", colors.red, colors.black)
    else
        writeAt(m, 2, h, "(C) Anto2602", colors.red, colors.black)
    end
end

local function drawCenterHud(m, stats)
    if not m then return end
    local w, h = m.getSize()
    local panelW = math.floor(w * 0.48)

    -- Clear only the data area, leaving the aquarium area free for animation.
    for y = 1, math.min(h, 6) do
        writeAt(m, 1, y, string.rep(" ", panelW), colors.white, colors.black)
    end

    centerAt(m, 1, "MAIN CORE // EMC", colors.white, colors.black)
    writeAt(m, 2, 2, "EMC/m", colors.gray, colors.black)
    writeAt(m, 10, 2, shortNumber(stats.emcMin), colors.lime, colors.black)
    writeAt(m, 2, 3, "EMC/M", colors.gray, colors.black)
    writeAt(m, 10, 3, shortNumber(stats.emcHour), colors.lightBlue, colors.black)
    writeAt(m, 2, 4, "EMC/s", colors.gray, colors.black)
    writeAt(m, 10, 4, shortNumber(stats.emcSec), colors.lightBlue, colors.black)
    writeAt(m, 2, 5, "RODS/s", colors.gray, colors.black)
    writeAt(m, 10, 5, shortNumber(stats.liveRodsSec), colors.orange, colors.black)
    writeAt(m, 2, 6, "LIVE/m", colors.gray, colors.black)
    writeAt(m, 10, 6, shortNumber(stats.liveEmcMin), colors.white, colors.black)

    -- Small animated EMC core at the top-right, like the reference control panel.
    local coreCx = math.min(w - 8, panelW + 8)
    local coreCy = 4
    local phase = animationFrame % 8
    local dots = {"o", "O", "0", "O"}
    for i = 1, 4 do
        local ang = (phase + i * 2) * math.pi / 4
        local px = math.floor(coreCx + math.cos(ang) * 5)
        local py = math.floor(coreCy + math.sin(ang) * 2)
        writeAt(m, px, py, dots[(i % #dots) + 1], colors.purple, colors.black)
    end

    -- Aquarium animation is rendered by drawAllMonitors().
    -- Keeping it in one loop avoids competing GIF render calls.

    -- Repaint the left HUD after the animation frame in case the image overlaps.
    for y = 1, 6 do
        writeAt(m, 1, y, string.rep(" ", panelW), colors.white, colors.black)
    end
    centerAt(m, 1, "MAIN CORE // EMC", colors.white, colors.black)
    writeAt(m, 2, 2, "EMC/m", colors.gray, colors.black)
    writeAt(m, 10, 2, shortNumber(stats.emcMin), colors.lime, colors.black)
    writeAt(m, 2, 3, "EMC/M", colors.gray, colors.black)
    writeAt(m, 10, 3, shortNumber(stats.emcHour), colors.lightBlue, colors.black)
    writeAt(m, 2, 4, "EMC/s", colors.gray, colors.black)
    writeAt(m, 10, 4, shortNumber(stats.emcSec), colors.lightBlue, colors.black)
    writeAt(m, 2, 5, "RODS/s", colors.gray, colors.black)
    writeAt(m, 10, 5, shortNumber(stats.liveRodsSec), colors.orange, colors.black)
    writeAt(m, 2, 6, "LIVE/m", colors.gray, colors.black)
    writeAt(m, 10, 6, shortNumber(stats.liveEmcMin), colors.white, colors.black)

    local statusX = math.max(1, w - 12)
    writeAt(m, statusX, 1, "[ ONLINE ]", colors.lime, colors.black)
    writeAt(m, math.max(1, w - 13), h, "RMF:" .. shortNumber(stats.rmf), colors.orange, colors.black)
end

local function drawRight(m, stats)
    if not m then return end
    local w, h = m.getSize()
    centerAt(m, 1, "LIVE CONTROL // EMC", colors.white, colors.black)
    writeAt(m, 2, 2, "LIVE THROUGHPUT", colors.magenta, colors.black)
    writeAt(m, math.max(1, w - 12), 2, "[ ONLINE ]", colors.lime, colors.black)

    rule(m, 4, "LIVE EMC", colors.lime)
    writeAt(m, 3, 5, "EMC / MIN", colors.gray)
    writeAt(m, math.max(22, w - 17), 5, shortNumber(stats.liveEmcMin), colors.lime)
    writeAt(m, 3, 6, "EMC / SEC", colors.gray)
    writeAt(m, math.max(22, w - 17), 6, shortNumber(stats.liveEmcSec), colors.lightBlue)
    writeAt(m, 3, 7, "RODS / SEC", colors.gray)
    writeAt(m, math.max(22, w - 17), 7, shortNumber(stats.liveRodsSec), colors.orange)

    rule(m, 9, "OUTPUT", colors.magenta)
    writeAt(m, 3, 10, "RMF STORED", colors.gray)
    writeAt(m, math.max(22, w - 17), 10, shortNumber(stats.rmf), colors.orange)
    writeAt(m, 3, 11, "STORED EMC", colors.gray)
    writeAt(m, math.max(22, w - 17), 11, shortNumber(stats.storedEMC), colors.lightBlue)
    writeAt(m, 3, 12, "TOTAL RODS", colors.gray)
    writeAt(m, math.max(22, w - 17), 12, shortNumber(stats.totalRods), colors.lime)

    rule(m, 14, "EMC BUS", colors.purple)
    local baseY = 15
    local pulse = animationFrame % math.max(2, w - 8) + 1
    local bus = string.rep("-", math.max(1, w - 12))
    writeAt(m, 4, baseY, "[EMC1]" .. bus .. "[EMC2]", colors.gray, colors.black)
    writeAt(m, 4 + math.min(#bus, pulse), baseY, ">", colors.lime, colors.black)

    rule(m, 17, "RMF BUS", colors.magenta)
    writeAt(m, 4, 18, "[RMF1]" .. bus .. "[RMF2]", colors.gray, colors.black)
    writeAt(m, 4 + math.min(#bus, (pulse * 2) % math.max(1, #bus + 1)), 18, ">", colors.orange, colors.black)

    if h >= 21 then
        centerAt(m, h - 2, "BHU: ONLINE   TRANSFER: ACTIVE", colors.lime, colors.black)
        centerAt(m, h, "(C) Anto2602", colors.red, colors.black)
    else
        writeAt(m, 2, h, "(C) Anto2602", colors.red, colors.black)
    end
end

local function drawAllMonitors()
    while true do
        local now = os.clock()

        if now >= nextLiveReset then
            local elapsed = now - liveStart
            if elapsed <= 0 then elapsed = 0.001 end
            local moved = totalTransferred - liveTransferred
            liveEmcPerMinute = (moved * rodEMC) / (elapsed / 60)
            liveRodsPerSecond = moved / elapsed
            liveTransferred = totalTransferred
            liveStart = now
            nextLiveReset = now + 5
        end

        if now >= lastHudRefresh then
            local elapsedTotal = now - lastCheckTime
            if elapsedTotal <= 0 then elapsedTotal = 0.001 end
            local totalEMCGenerated = totalTransferred * rodEMC
            local emcMin = totalEMCGenerated / (elapsedTotal / 60)
            local emcHour = emcMin * 60
            local emcSec = emcMin / 60
            local macerators = #powderCondensers * 3
            local emcMac = macerators > 0 and emcMin / macerators or 0
            local rmf, stored = safeBHUStats()

            local stats = {
                emcMin = emcMin,
                emcHour = emcHour,
                emcSec = emcSec,
                emcMac = emcMac,
                rodsSec = totalTransferred / elapsedTotal,
                rodsHour = totalTransferred / (elapsedTotal / 3600),
                liveEmcMin = liveEmcPerMinute,
                liveEmcSec = liveEmcPerMinute / 60,
                liveRodsSec = liveRodsPerSecond,
                condensers = #powderCondensers,
                macerators = macerators,
                rmf = rmf,
                storedEMC = stored,
                totalRods = totalTransferred,
                uptime = formatUptime(elapsedTotal),
            }

            drawLeft(leftMon and leftMon.monitor, stats)
            drawCenterHud(centerMon and centerMon.monitor, stats)
            drawRight(rightMon and rightMon.monitor, stats)
            lastHudRefresh = now + 1
        end

        animationFrame = animationFrame + 1

        -- Center aquarium is animated every frame; HUD data refreshes once/sec.
        if centerMon and image then
            local m = centerMon.monitor
            local w, h = m.getSize()
            local panelW = math.floor(w * 0.48)
            local ix = math.max(panelW + 2, w - image.width + 1)
            local iy = math.max(7, h - image.height)
            term.redirect(m)
            m.setBackgroundColor(image.backgroundCol or colors.black)
            GIF.animateGIF(image, ix, iy)
        end

        sleep(0.15)
    end
end

parallel.waitForAny(
    drawAllMonitors,
    runTransfers,
    refillEnderChests
)
