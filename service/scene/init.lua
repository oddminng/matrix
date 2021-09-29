local skynet = require "skynet"
local s = require "service"

local balls = {} -- [playerid] = ball
local foods = {} -- [id] = food
local food_maxid = 0
local food_count = 0

-- 球类
function ball()
    local m = {
        playerid = nil,
        node = nil,
        agent = nil,
        x = math.random(0, 100),
        y = math.random(0, 100),
        size = 2,
        speedx = 0,
        speedy = 0
    }
    return m
end

-- 球
local function balllist_msg()
    local ret_balls = {}
    for _, v in pairs(balls) do
        table.insert(ret_balls,
                     {playerid = v.playerid, x = v.x, y = v.y, size = v.size})
    end
    return {0x040008, {balls = ret_balls}}
end

-- 食物
function food()
    local m = {id = nil, x = math.random(0, 100), y = math.random(0, 100)}
    return m
end

local function foodlist_msg()
    local ret_foods = {}
    for _, v in pairs(foods) do
        table.insert(ret_foods, {id = v.id, x = v.x, y = v.y})
    end
    return {0x040009, {foods = ret_foods}}
end

function broadcast(msg)
    for _, b in pairs(balls) do s.send(b.node, b.agent, "send", msg) end
end

-- 进入
s.resp.enter = function(source, playerid, node, agent)
    if balls[playerid] then return false end

    local b = ball()
    b.playerid = playerid
    b.node = node
    b.agent = agent
    -- 广播
    local entermsg = {
        0x040007,
        {ball = {playerid = playerid, x = b.x, y = b.y, size = b.size}}
    }
    broadcast(entermsg)
    -- 记录
    balls[playerid] = b
    -- 回应
    local ret_msg = {0x040001, {code = "RC_OK"}}
    s.send(b.node, b.agent, "send", ret_msg)
    -- 发战场信息
    s.send(b.node, b.agent, "send", balllist_msg())
    s.send(b.node, b.agent, "send", foodlist_msg())
    return true
end

-- 离开
s.resp.leave = function(source, playerid)
    if not balls[playerid] then return false end
    balls[playerid] = nil
    local leavemsg = {0x040003, {playerid = playerid}}
    broadcast(leavemsg)
end

-- 改变速度
s.resp.shift = function(source, playerid, x, y)
    local b = balls[playerid]
    if not b then return false end
    b.speedx = x
    b.speedy = y
end

function food_update()
    if food_count > 50 then return end

    if math.random(1, 100) < 98 then return end

    food_maxid = food_maxid + 1
    food_count = food_count + 1
    local f = food()
    f.id = food_maxid
    foods[f.id] = f

    local msg = {0x040004, {food = {id = f.id, x = f.x, y = f.y}}}
    broadcast(msg)
end

function move_update()
    for _, v in pairs(balls) do
        v.x = v.x + v.speedx * 0.2
        v.y = v.y + v.speedy * 0.2
        if v.speedx ~= 0 or v.speedy ~= 0 then
            local msg = {0x040006, {playerid = v.playerid, x = v.x, y = v.y}}
            broadcast {msg}
        end
    end
end

function eat_upate()
    for _, b in pairs(balls) do
        for fid, f in pairs(foods) do
            if (b.x - f.x) ^ 2 + (b.y - f.y) ^ 2 < b.size ^ 2 then
                b.size = b.size + 1
                food_count = food_count - 1
                local msg = {
                    0x040005, {playerid = b.playerid, fid = fid, size = b.size}
                }
                broadcast(msg)
                foods[fid] = nil
            end
        end
    end
end

function update(frame)
    food_update()
    move_update()
    eat_upate()
    -- 碰撞
    -- 分裂
end

s.init = function()
    skynet.fork(function()
        -- 保持帧率运行
        local stime = skynet.now()
        local frame = 0
        while true do
            frame = frame + 1
            local isok, err = pcall(update, frame)
            if not isok then skynet.error(err) end
            local etime = skynet.now()
            local waittime = frame * 20 - (etime - stime)
            if waittime <= 0 then waittime = 2 end
            skynet.sleep(waittime)
        end
    end)
end

s.start(...)
