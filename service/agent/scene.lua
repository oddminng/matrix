local skynet = require "skynet"
local s = require "service"
local runconfig = require "runconfig"
local mynode = skynet.getenv("node")

s.snode = nil -- scene_node
s.sname = nil -- scene_id

function random_scene()
    -- 选择node
    local nodes = {}
    for i, v in pairs(runconfig.scene) do
        table.insert(nodes, i)
        if runconfig.scene[mynode] then table.insert(nodes, mynode) end
    end
    local idx = math.random(1, #nodes)
    local scenenode = nodes[idx]
    -- 具体场景
    local scenelist = runconfig.scene[scenenode]
    local idx = math.random(1, #scenelist)
    local sceneid = scenelist[idx]
    return scenenode, sceneid
end

-- 进入场景
-- enter
s.client[0x040001] = function(msg)
    if s.sname then
        return {
            0x040001,
            {code = "RC_ERR_ALREADY_EXISTS", msg = "已经在场景中"}
        }
    end
    local snode, sid = random_scene()
    local sname = "scene" .. sid
    local isok = s.call(snode, sname, "enter", s.id, mynode, skynet.self())
    if not isok then return {0x040001, {code = "RC_ERR", msg = "进入失败"}} end
    s.snode = snode
    s.sname = sname
    return {0x040001, {code = "RC_OK"}}
end

-- 改变方向
-- shift
s.client[0x040002] = function(msg)
    if not s.sname then return end
    local x = msg.x or 0
    local y = msg.y or 0
    s.call(s.snode, s.sname, "shift", s.id, x, y)
end

s.leave_scene = function()
    -- 不在场景
    if not s.sname then return end
    s.call(s.snode, s.sname, "leave", s.id)
    s.snode = nil
    s.sname = nil
end
