local skynet = require "skynet"
local socket = require "skynet.socket"
local s = require "service"
local runconfig = require "runconfig"
local mynode = skynet.getenv("node")
require "skynet.manager"

local function shutdown_gate()
    skynet.error("admin do shutdown gate")
    for node, _ in pairs(runconfig.cluster) do
        local nodecfg = runconfig[node]
        for i, _ in pairs(nodecfg.gateway or {}) do
            local name = "gateway"..i
            s.call(node, name, "shutdown")
        end
    end
end

local function shutdown_agent()
    skynet.error("admin do shutdown agent")
    local anode = runconfig.agentmgr.node
    while true do
        local online_num = s.call(anode, "agentmgr", "shutdown", 3)
        if online_num <= 0 then
            break
        end
        skynet.sleep(100)
    end
end

local function shutdown_node()
    for node, _ in pairs(runconfig.cluster) do
        if node ~= mynode then
            s.send(node, "nodemgr", "shutdown")
        end
    end
    skynet.sleep(200)
    skynet.abort()
end

local function stop()
    skynet.error("admin do stop")
    shutdown_gate()
    shutdown_agent()
    shutdown_node()
    return "ok"
end

local function reloadpb()
    skynet.error("admin do reloadpb gate")
    for node, _ in pairs(runconfig.cluster) do
        local nodecfg = runconfig[node]
        for i, _ in pairs(nodecfg.gateway or {}) do
            local name = "gateway"..i
            s.call(node, name, "reloadpb")
        end
    end
end

function connect(fd, addr)
    socket.start(fd)
    socket.write(fd, "Please enter cmd\r\n")
    local cmd = socket.readline(fd, "\r\n")
    if cmd == "stop" then
        stop()
    elseif  cmd == "reloadpb" then
        reloadpb()
    end
end

s.init = function ()
    local listenfd = socket.listen("127.0.0.1", runconfig.admin.port)
    socket.start(listenfd, connect)
end

s.start(...)