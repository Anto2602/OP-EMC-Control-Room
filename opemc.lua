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

local reserveCount = 64
local trackedEMCPerRMF = 10059784
local rodEMC = 1536

-- Use wall time, not CPU time, for throughput statistics.
local function wallSeconds()
    if os.epoch then
        return os.epoch("utc") / 1000
    end
    return os.clock()
end

-- Rods moved into RMF condensers (input flow).
local totalTransferred = 0
-- RM furnaces successfully moved out of RMF condensers (actual output).
local totalRMFTransferred = 0
local lastCheckTime = wallSeconds()

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
                        local moved = cond.pushItems(peripheral.getName(bhu), slot, item.count) or 0
                        if moved > 0 then
                            totalRMFTransferred = totalRMFTransferred + moved
                        end
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


local liveStart = wallSeconds()
local liveTransferred = totalTransferred
local liveRMFTransferred = totalRMFTransferred
local liveEmcPerMinute = 0
local liveRodsPerMinute = 0
local liveRmfPerMinute = 0
local lastHudRefresh = 0
local animationFrame = 0
local rateWindowStart = liveStart
local rateWindowRMF = totalRMFTransferred
local rateWindowRods = totalTransferred
local lastRMFForLoad = totalRMFTransferred
local lastRodForLoad = totalTransferred

local allMonitors = {}
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then
        local m = peripheral.wrap(name)
        if m then
            m.setTextScale(0.5)
            table.insert(allMonitors, { name = name, monitor = m })
        end
    end
end

table.sort(allMonitors, function(a, b) return a.name < b.name end)

local leftMon = allMonitors[1]
local centerMon = allMonitors[2]
local rightMon = allMonitors[3]
if #allMonitors == 1 then
    centerMon = allMonitors[1]
    leftMon = nil
    rightMon = nil
elseif #allMonitors == 2 then
    leftMon = allMonitors[1]
    centerMon = allMonitors[2]
    rightMon = nil
end

local function clearMonitor(m)
    if not m then return 0, 0 end
    local w, h = m.getSize()
    m.setBackgroundColor(colors.black)
    m.setTextColor(colors.white)
    m.clear()
    return w, h
end

local function clampX(m, x)
    local w = m.getSize()
    if x < 1 then return 1 end
    if x > w then return w end
    return x
end

local function writeAt(m, x, y, text, fg, bg)
    if not m then return end
    local w, h = m.getSize()
    if y < 1 or y > h then return end
    x = clampX(m, x)
    local maxLen = w - x + 1
    if maxLen <= 0 then return end
    if #text > maxLen then text = text:sub(1, maxLen) end
    m.setCursorPos(x, y)
    m.setTextColor(fg or colors.white)
    m.setBackgroundColor(bg or colors.black)
    m.write(text)
end

local function centerAt(m, y, text, fg, bg)
    if not m then return end
    local w = m.getSize()
    local x = math.floor((w - #text) / 2) + 1
    writeAt(m, x, y, text, fg, bg)
end

local function rule(m, y, title, fg)
    if not m then return end
    local w, h = m.getSize()
    if y < 1 or y > h then return end
    local line = string.rep("-", w)
    writeAt(m, 1, y, line, colors.gray, colors.black)
    if title and #title > 0 then
        local x = math.max(2, math.floor((w - #title) / 2) + 1)
        writeAt(m, x, y, title, fg or colors.lightBlue, colors.black)
    end
end

local function boxTop(m, y, title, fg, left, right)
    if not m then return end
    local w, h = m.getSize()
    if y < 1 or y > h then return end
    writeAt(m, 1, y, "+-" .. (title or "") .. string.rep("-", math.max(0, w - 4 - #(title or ""))) .. "+", colors.gray, colors.black)
    if left then writeAt(m, 2, y, left, colors.gray, colors.black) end
    if right then writeAt(m, math.max(1, w - #right - 1), y, right, colors.gray, colors.black) end
end

local function boxBottom(m, y)
    if not m then return end
    local w, h = m.getSize()
    if y < 1 or y > h then return end
    writeAt(m, 1, y, "+" .. string.rep("-", math.max(0, w - 2)) .. "+", colors.gray, colors.black)
end

local function padLabel(label, width)
    if #label >= width then return label:sub(1, width) end
    return label .. string.rep(" ", width - #label)
end

local function valueRow(m, y, label, value, valueColor, labelWidth)
    local w = m.getSize()
    labelWidth = labelWidth or math.floor(w * 0.62)
    writeAt(m, 2, y, "| " .. padLabel(label, labelWidth), colors.lightGray, colors.black)
    writeAt(m, math.max(2, w - #value - 3), y, value, valueColor or colors.white, colors.black)
end

local function shortNumber(n)
    n = tonumber(n) or 0
    local a = math.abs(n)
    if a >= 1e12 then return string.format("%.2fT", n / 1e12)
    elseif a >= 1e9 then return string.format("%.2fB", n / 1e9)
    elseif a >= 1e6 then return string.format("%.2fM", n / 1e6)
    elseif a >= 1e3 then return string.format("%.2fK", n / 1e3)
    else return string.format("%.0f", n) end
end

local function formatUptime(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function safeBHUStats()
    local rmfCount, storedEMC = 0, 0
    if bhu then
        local ok, items = pcall(function() return bhu.list() end)
        if ok and items then
            for _, item in pairs(items) do
                if item.name == "projecte:rm_furnace" then
                    rmfCount = rmfCount + (item.count or 0)
                    storedEMC = storedEMC + (item.count or 0) * trackedEMCPerRMF
                end
            end
        end
    end
    return rmfCount, storedEMC
end

local function drawStatus(m, status)
    local w, h = m.getSize()
    centerAt(m, 1, status.title, colors.white, colors.black)
    writeAt(m, math.max(2, w - #status.mode - 2), 1, status.mode, colors.lime, colors.black)
    if h >= 2 then
        writeAt(m, 2, 2, status.subtitle, colors.gray, colors.black)
    end
end

-- ============================== CENTER MONITOR ==============================
local function drawCenter(m, stats)
    if not m then return end
    local w, h = clearMonitor(m)

    centerAt(m, 1, "Z-EMC // PRODUCTION MATRIX", colors.lightBlue, colors.black)
    writeAt(m, math.max(2, w - 10), 1, "NOMINAL", colors.lime, colors.black)
    writeAt(m, 2, 2, "HIGH EFFICIENCY CONTROLLER", colors.gray, colors.black)

    local divider = math.floor(w * 0.66)
    local leftW = divider - 1
    local rightX = divider + 2

    -- THROUGHPUT
    boxTop(m, 4, " THROUGHPUT ", colors.lightBlue)
    valueRow(m, 5, "EMC / MIN", shortNumber(stats.emcMin), colors.cyan, math.max(16, leftW - 14))
    valueRow(m, 6, "EMC / HOUR", shortNumber(stats.emcHour), colors.lightBlue, math.max(16, leftW - 14))
    valueRow(m, 7, "RODS / MIN", shortNumber(stats.rodsMin), colors.orange, math.max(16, leftW - 14))
    valueRow(m, 8, "RODS / HOUR", shortNumber(stats.rodsHour), colors.orange, math.max(16, leftW - 14))
    writeAt(m, 2, 9, "| PULSE", colors.magenta, colors.black)
    local pulseW = math.max(8, leftW - 11)
    local pulsePos = (animationFrame % (pulseW * 2)) + 1
    if pulsePos > pulseW then pulsePos = pulseW * 2 - pulsePos end
    local pulse = string.rep(".", pulseW)
    pulse = pulse:sub(1, math.max(0, pulsePos - 1)) .. "/" .. pulse:sub(pulsePos + 1)
    writeAt(m, 10, 9, pulse, colors.magenta, colors.black)
    boxBottom(m, 10)

    -- OUTPUT
    boxTop(m, 11, " OUTPUT ", colors.magenta)
    valueRow(m, 12, "RM FURNACES / MIN", shortNumber(stats.rmfMin), colors.orange, math.max(18, leftW - 14))
    valueRow(m, 13, "RM FURNACES / HOUR", shortNumber(stats.rmfHour), colors.orange, math.max(18, leftW - 14))
    valueRow(m, 14, "RM FURNACES STORED", shortNumber(stats.rmfStored), colors.lime, math.max(18, leftW - 14))
    valueRow(m, 15, "TOTAL RM FURNACES", shortNumber(stats.totalRMF), colors.white, math.max(18, leftW - 14))
    valueRow(m, 16, "TOTAL EMC MOVED", shortNumber(stats.totalEMCMoved), colors.cyan, math.max(18, leftW - 14))
    boxBottom(m, 17)

    -- SYSTEM
    boxTop(m, 18, " SYSTEM ", colors.lime)
    if h >= 19 then valueRow(m, 19, "ROD CONDENSERS", tostring(stats.condensers), colors.lime, math.max(18, leftW - 14)) end
    if h >= 20 then valueRow(m, 20, "RMF CONDENSERS", tostring(stats.rmfCondensers), colors.lime, math.max(18, leftW - 14)) end
    if h >= 21 then valueRow(m, 21, "WORKERS / ERRORS", tostring(stats.workers) .. " / " .. tostring(stats.errors), colors.orange, math.max(18, leftW - 14)) end
    if h >= 22 then valueRow(m, 22, "UPTIME", stats.uptime, colors.white, math.max(18, leftW - 14)) end

    -- Right column: EMC core + link
    writeAt(m, rightX, 4, "+- EMC CORE " .. string.rep("-", math.max(0, w - rightX - 12)) .. "+", colors.gray, colors.black)
    local cx = math.floor((rightX + w) / 2)
    local cy = 7
    local phase = animationFrame
    local rings = {
        {r = 1, y = 1, c = colors.lightBlue, chars = {"o", "O", "0", "O"}},
        {r = 3, y = 1, c = colors.purple, chars = {"·", "o", "O", "o"}},
        {r = 5, y = 2, c = colors.magenta, chars = {".", ":", "*", ":"}},
    }
    for ri, ring in ipairs(rings) do
        for i = 1, 8 do
            local ang = (i * math.pi / 4) + (phase * (ri * 0.08))
            local px = math.floor(cx + math.cos(ang) * ring.r)
            local py = math.floor(cy + math.sin(ang) * ring.y)
            if px >= rightX + 1 and px <= w - 1 and py >= 5 and py <= 11 then
                writeAt(m, px, py, ring.chars[(i + animationFrame) % #ring.chars + 1], ring.c, colors.black)
            end
        end
    end
    centerAt(m, cy, "@", colors.white, colors.black)

    writeAt(m, rightX, 12, "TRANSFER LOAD", colors.gray, colors.black)
    local loadW = math.max(8, w - rightX - 3)
    local loadFilled = math.floor(math.min(1, stats.rodLoad) * loadW)
    writeAt(m, rightX, 13, string.rep("#", loadFilled) .. string.rep("-", loadW - loadFilled), colors.cyan, colors.black)
    writeAt(m, rightX, 14, string.format("+%.2fK rods/s avg", stats.rodsSec), colors.white, colors.black)

    writeAt(m, rightX, 16, "+- LINK " .. string.rep("-", math.max(0, w - rightX - 10)) .. "+", colors.gray, colors.black)
    writeAt(m, rightX + 1, 17, "| BHU: LINKED", colors.lime, colors.black)
    writeAt(m, rightX + 1, 18, "| AUTO DISCOVERY: ON", colors.lime, colors.black)
    if h >= 19 then writeAt(m, rightX + 1, 19, "| SAFE I/O: ON", colors.lime, colors.black) end

    if h >= 24 then
        centerAt(m, h - 1, "buffered UI | role cache | backoff", colors.gray, colors.black)
        centerAt(m, h, "(C) Anto2602", colors.red, colors.black)
    elseif h >= 22 then
        centerAt(m, h, "(C) Anto2602", colors.red, colors.black)
    end
end

-- =============================== LEFT MONITOR ===============================
local function drawLeft(m, stats)
    if not m then return end
    local w, h = clearMonitor(m)
    centerAt(m, 1, "STATISTIK / EMC", colors.white, colors.black)
    writeAt(m, 2, 2, "HOCHLEISTUNGS-CONTROLLER", colors.gray, colors.black)
    writeAt(m, math.max(2, w - 10), 2, "NOMINAL", colors.lime, colors.black)

    boxTop(m, 4, "Statistik pro Minute", colors.lightBlue)
    valueRow(m, 5, "Anzahl EMC", shortNumber(stats.emcMin), colors.lime, math.max(17, w - 18))
    valueRow(m, 6, "Anzahl RM Öfen", shortNumber(stats.rmfMin), colors.orange, math.max(17, w - 18))
    boxBottom(m, 7)

    if h >= 8 then boxTop(m, 8, "Statistik pro Stunde", colors.orange) end
    if h >= 9 then valueRow(m, 9, "Anzahl EMC", shortNumber(stats.emcHour), colors.yellow, math.max(17, w - 18)) end
    if h >= 10 then valueRow(m, 10, "Anzahl RM Öfen", shortNumber(stats.rmfHour), colors.orange, math.max(17, w - 18)) end
    if h >= 11 then boxBottom(m, 11) end

    if h >= 12 then boxTop(m, 12, "Statistik Insgesamt", colors.yellow) end
    if h >= 13 then valueRow(m, 13, "Anzahl EMC", shortNumber(stats.totalEMCMoved), colors.yellow, math.max(17, w - 18)) end
    if h >= 14 then valueRow(m, 14, "Anzahl RM Öfen", shortNumber(stats.totalRMF), colors.orange, math.max(17, w - 18)) end
    if h >= 15 then boxBottom(m, 15) end

    if h >= 16 then boxTop(m, 16, "System Statistik", colors.lime) end
    if h >= 17 then valueRow(m, 17, "Rod Kondensers", tostring(stats.condensers), colors.lime, math.max(17, w - 18)) end
    if h >= 18 then valueRow(m, 18, "RMF Kondensers", tostring(stats.rmfCondensers), colors.lime, math.max(17, w - 18)) end
    if h >= 19 then valueRow(m, 19, "RM im BHU", shortNumber(stats.rmfStored), colors.orange, math.max(17, w - 18)) end
    if h >= 20 then valueRow(m, 20, "Laufzeit", stats.uptime, colors.white, math.max(17, w - 18)) end

    -- Animated core on the lower-right, matching the reference monitor.
    local coreX = math.floor(w * 0.80)
    local coreY = math.max(11, math.floor(h * 0.68))
    for i = 1, 10 do
        local ang = (i * math.pi / 5) + animationFrame * 0.12
        local rr = (i % 2 == 0) and 3 or 2
        local px = math.floor(coreX + math.cos(ang) * rr)
        local py = math.floor(coreY + math.sin(ang) * 1.8)
        if px > 1 and px < w then
            writeAt(m, px, py, (i % 2 == 0) and "O" or "o", (i % 2 == 0) and colors.purple or colors.magenta, colors.black)
        end
    end
    writeAt(m, coreX, coreY, "@", colors.white, colors.black)

    if h >= 22 then centerAt(m, h - 1, "AUTO DISCOVERY: ON", colors.lime, colors.black) end
    if h >= 21 then centerAt(m, h, "(C) Anto2602", colors.red, colors.black) end
end

-- ============================== RIGHT MONITOR ===============================
local function drawRight(m, stats)
    if not m then return end
    local w, h = clearMonitor(m)
    local split = math.floor(w * 0.44)

    -- Left half: EMC FLOW
    writeAt(m, 2, 1, "+- EMC FLOW " .. string.rep("-", math.max(0, split - 14)), colors.gray, colors.black)
    valueRow(m, 3, "EMC / MIN", shortNumber(stats.emcMin), colors.cyan, math.max(15, split - 12))
    valueRow(m, 4, "EMC / HOUR", shortNumber(stats.emcHour), colors.cyan, math.max(15, split - 12))
    writeAt(m, 2, 5, "| FLOW", colors.magenta, colors.black)
    local flowW = math.max(8, split - 10)
    local pulsePos = animationFrame % (flowW * 2)
    if pulsePos > flowW then pulsePos = flowW * 2 - pulsePos end
    writeAt(m, 10, 5, string.rep("/", math.max(1, pulsePos)) .. string.rep(".", math.max(0, flowW - pulsePos)), colors.magenta, colors.black)
    writeAt(m, 2, 6, "| LOAD", colors.gray, colors.black)
    local fill = math.floor(math.min(1, stats.rodLoad) * flowW)
    writeAt(m, 10, 6, string.rep("#", fill) .. string.rep("-", flowW - fill), colors.lime, colors.black)
    writeAt(m, 2, 7, "| " .. string.format("%.2fK rods/s", stats.rodsSec), colors.white, colors.black)
    boxBottom(m, 8)

    -- Right half: LIVE TOWER
    local rx = split + 3
    writeAt(m, rx, 1, "LIVE TOWER", colors.magenta, colors.black)
    local towerCx = math.min(w - 7, rx + math.floor((w - rx) / 2))
    writeAt(m, towerCx - 6, 3, "+- EMC BUS -+", colors.cyan, colors.black)
    writeAt(m, towerCx - 5, 4, "[SRC]---[SRC]", colors.lime, colors.black)
    writeAt(m, towerCx - 5, 6, "[MK2]---[MK2]", colors.purple, colors.black)
    writeAt(m, towerCx - 5, 8, "[MK2]---[MK2]", colors.purple, colors.black)
    writeAt(m, towerCx - 5, 10, "[RMF]---[RMF]", colors.magenta, colors.black)
    writeAt(m, towerCx, 11, "#", colors.orange, colors.black)
    writeAt(m, towerCx, 12, "v", colors.gray, colors.black)
    writeAt(m, towerCx - 5, 13, "+- RMF BUS -+", colors.magenta, colors.black)
    writeAt(m, towerCx, 15, "[ BHU ]", colors.cyan, colors.black)

    if h >= 17 then
        writeAt(m, 2, h - 1, "BHU: ONLINE   TRANSFER: ACTIVE", colors.lime, colors.black)
        writeAt(m, math.max(2, w - 13), h, "(C) Anto2602", colors.red, colors.black)
    else
        writeAt(m, 2, h, "(C) Anto2602", colors.red, colors.black)
    end
end

local function drawBootState()
    for _, info in ipairs(allMonitors) do
        local m = info.monitor
        if m then
            clearMonitor(m)
            centerAt(m, math.floor(m.getSize() / 2), "Z-EMC", colors.lightBlue, colors.black)
            centerAt(m, math.floor(m.getSize() / 2) + 1, "INITIALIZING CONTROL ROOM...", colors.gray, colors.black)
        end
    end
end

drawBootState()

local function renderCore()
    local now = wallSeconds()

    -- 5-second live rate, based on actual successful RMF transfers to the BHU.
    if now - liveStart >= 5 then
        local elapsed = now - liveStart
        local rmfMoved = totalRMFTransferred - liveRMFTransferred
        local rodsMoved = totalTransferred - liveTransferred
        liveRmfPerMinute = rmfMoved * (60 / elapsed)
        liveEmcPerMinute = liveRmfPerMinute * trackedEMCPerRMF
        liveRodsPerMinute = rodsMoved * (60 / elapsed)
        liveTransferred = totalTransferred
        liveRMFTransferred = totalRMFTransferred
        liveStart = now
    end

    -- Rolling window for the main EMC/MIN value.
    local windowElapsed = now - rateWindowStart
    if windowElapsed >= 60 then
        rateWindowStart = now
        rateWindowRMF = totalRMFTransferred
        rateWindowRods = totalTransferred
        windowElapsed = 0.001
    end
    local windowRMF = totalRMFTransferred - rateWindowRMF
    local windowRods = totalTransferred - rateWindowRods
    if windowElapsed <= 0 then windowElapsed = 0.001 end

    local emcMin = (windowRMF * trackedEMCPerRMF) * (60 / windowElapsed)
    local emcHour = emcMin * 60
    local rodsMin = windowRods * (60 / windowElapsed)
    local rodsHour = rodsMin * 60
    local rmfMin = windowRMF * (60 / windowElapsed)
    local rmfHour = rmfMin * 60
    local rmf, stored = safeBHUStats()
    local elapsedTotal = now - lastCheckTime

    -- If the output side has not yet completed a full cycle, show input EMC flow
    -- as a provisional live figure rather than a permanent zero.
    if emcMin <= 0 and liveRodsPerMinute > 0 then
        emcMin = liveRodsPerMinute * rodEMC
        emcHour = emcMin * 60
        rmfMin = liveRodsPerMinute * rodEMC / trackedEMCPerRMF
        rmfHour = rmfMin * 60
    end

    local maxRodRate = math.max(1, #powderCondensers * 128)
    local rodLoad = math.min(1, liveRodsPerMinute / maxRodRate)

    local stats = {
        emcMin = emcMin,
        emcHour = emcHour,
        rodsMin = rodsMin,
        rodsHour = rodsHour,
        rodsSec = liveRodsPerMinute / 60,
        rmfMin = rmfMin,
        rmfHour = rmfHour,
        rmfStored = rmf,
        totalRMF = totalRMFTransferred,
        totalEMCMoved = totalRMFTransferred * trackedEMCPerRMF,
        rmfCondensers = #rmfCondensers,
        condensers = #powderCondensers,
        workers = math.min(#powderCondensers, 14),
        errors = 0,
        uptime = formatUptime(elapsedTotal),
        rodLoad = rodLoad,
    }

    drawLeft(leftMon and leftMon.monitor, stats)
    drawCenter(centerMon and centerMon.monitor, stats)
    drawRight(rightMon and rightMon.monitor, stats)
end

local function drawAllMonitors()
    while true do
        renderCore()
        animationFrame = animationFrame + 1
        sleep(0.25)
    end
end

parallel.waitForAny(
    drawAllMonitors,
    runTransfers,
    refillEnderChests
)
