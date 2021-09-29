local skynet = require "skynet"
local socket = require "skynet.socket"
local runconfig = require "runconfig"
local s = require "service"
local cjson = require "cjson"
local cjsonutil = require "cjson.util"
local pb = nil
local pbconfig = nil
local closing = false

conns = {} -- [fn] = conn
players = {} -- [playerid] = gateplayer

-- 连接类
function conn()
    local m = {fd = nil, playerid = nil}
    return m
end

-- 玩家类
function gateplayer()
    local m = {
        playerid = nil,
        agent = nil,
        conn = nil,
        key = math.random(1, 999999999),
        lost_conn_time = nil,
        msgcache = {} -- 未送达消息缓存
    }
    return m
end

local str_unpack = function(msgstr)
    local msg = {}

    while true do
        local arg, rest = string.match(msgstr, "(.-),(.*)")
        if arg then
            msgstr = rest
            table.insert(msg, arg)
        else
            table.insert(msg, msgstr)
            break
        end
    end
    return msg[1], msg
end

local str_pack = function(cmd, msg) return table.concat(msg, ",") .. "\r\n" end

local function json_pack(cmd, msg)
    msg._cmd = cmd
    local body = cjson.encode(msg) -- 协议体字节流
    local namelen = string.len(cmd) -- 协议名长度
    local bodylen = string.len(body) -- 协议体长度
    local len = namelen + bodylen + 2 -- 协议总长度
    local format = string.format("> i2 i2 c%d c%d", namelen, bodylen)
    local buff = string.pack(format, len, namelen, cmd, body)
    return buff
end

local function json_unpack(buff)
    local len = string.len(buff)
    local namelen_format = string.format("> i2 c%d", len - 2)
    local namelen, other = string.unpack(namelen_format, buff)
    local bodylen = len - 2 - namelen
    local format = string.format("> c%d c%d", namelen, bodylen)
    local cmd, bodybuff = string.unpack(format, other)

    local isok, msg = pcall(cjson.decode, bodybuff)
    if not isok or not msg or not msg._cmd or not cmd == msg._cmd then
        print("error")
        return
    end
    return cmd, msg
end

local function proto_pack(pbindex, msg)
    local typeName = pbconfig.s2c[pbindex]
    if not typeName then
        error(string.format("protocal %s not found", pbindex))
        return
    end
    local body = pb.encode(typeName, msg) -- 协议体字节流
    local bodylen = string.len(body) -- 协议体长度
    local len = bodylen + 4 -- 协议总长度
    local format = string.format("> i2 i4 c%d", bodylen)
    local buff = string.pack(format, len, pbindex, body)
    return buff
end

local function proto_unpack(buff)
    local len = string.len(buff)
    local pbindex_format = string.format("> i4 c%d", len - 4)
    local pbindex, bodybuff = string.unpack(pbindex_format, buff)
    local typeName = pbconfig.c2s[pbindex]
    if not typeName then
        error(string.format("protocal %s not found", pbindex))
        return nil, nil
    end

    local msg = pb.decode(typeName, bodybuff)
    if not msg then
        error("protocal decode err err")
        return nil, nil
    end
    return pbindex, msg
end

local process_reconnet = function(fd, msg)
    local playerid = tonumber(msg[2])
    local key = tonumber(msg[3])
    -- conn
    local conn = conns[fd]
    if not conn then
        skynet.error("reconnect fail, conn not exist")
        return
    end
    -- gplayer
    local gplayer = players[playerid]
    if not gplayer then skynet.error("reconnect fail, player not exist") end
    if gplayer.conn then skynet.error("reconnect fail, conn not break") end
    if gplayer.key ~= key then skynet.error("reconnect fail, key error") end
    -- 绑定
    gplayer.conn = conn
    conn.playerid = playerid
    -- 回应
    s.resp.send_by_fd(nil, fd, {0x010001, {code = "RC_OK"}})
    -- 发送缓存消息
    for i, cmsg in ipairs(gplayer.msgcache) do
        s.resp.send_by_fd(nil, fd, cmsg)
    end
    gplayer.msgcache = {}
end

local process_msg = function(fd, bodybuff)
    local pbindex, msg = proto_unpack(bodybuff)
    if not pbindex then return end
    skynet.error(string.format("recf %d [0x%06X] %s", fd, pbindex, cjsonutil.serialise_value(msg)))
    local conn = conns[fd]
    local playerid = conn.playerid
    -- 特殊断线重连
    if pbindex == 0x010001 then
        process_reconnet(fd, msg)
        return
    end
    -- 尚未完成登录流程
    if not playerid then
        local node = skynet.getenv("node")
        local nodecfg = runconfig[node]
        local loginid = math.random(1, #nodecfg.login)
        local login = "login" .. loginid
        skynet.send(login, "lua", "client", fd, pbindex, msg)
    else
        local gplayer = players[playerid]
        local agent = gplayer.agent
        skynet.send(agent, "lua", "client", pbindex, msg)
    end
end

local unpack_package = function(readbuff)
    local size = string.len(readbuff)
    skynet.error(string.format("unpack_package size:%d", size))
    if size < 2 then
        return nil, readbuff
    end
    -- 取协议头中的bodylen
    local bodylen_format = string.format("> i2 c%d", size - 2)
    local bodylen, last = string.unpack(bodylen_format, readbuff)
    skynet.error(string.format("unpack_package bodylen:%d", bodylen))
    if size < bodylen + 2 then return nil, readbuff end
    local body_format = string.format("> c%d c%d", bodylen, size - 2 - bodylen)
    local bodybuff, last = string.unpack(body_format, last)
    return bodybuff, last
end

local process_buff = function(fd, readbuff)
    while true do
        local msgstr, rest = unpack_package(readbuff)
        if msgstr then
            readbuff = rest
            process_msg(fd, msgstr)
        else
            return readbuff
        end
    end
end

local disconnect = function(fd)
    local c = conns[fd]
    if not c then return end

    local playerid = c.playerid
    -- 还没完成登录
    if not playerid then
        return
        -- 已经在游戏中
    else
        local gplayer = players[playerid]
        gplayer.conn = nil
        skynet.timeout(300 * 100, function()
            if gplayer.conn ~= nil then return end
            local reason = "断线超时"
            skynet.call("agentmgr", "lua", "reqkick", playerid, reason)
        end)
    end
end

-- 每一条连接接受数据处理
-- 协议格式 cmd,arg1,arg2,... #
local recv_loop = function(fd)
    socket.start(fd)
    skynet.error("socket connected " .. fd)
    local readbuff = ""
    while true do
        local recvstr = socket.read(fd)
        if recvstr then
            readbuff = readbuff .. recvstr
            readbuff = process_buff(fd, readbuff)
        else
            skynet.error("socket close " .. fd)
            disconnect(fd)
            socket.close(fd)
            return
        end
    end
    -- while true do
    --     -- 读取包头 pbindex
    --     local pbindexbuff, succ = socket.read(fd, 4)
    --     if not succ then
    --         skynet.error("read pbindex err fd:" .. fd)
    --         disconnect(fd)
    --         socket.close(fd)
    --         return
    --     end
    --     -- 读取包头 包体总长
    --     local bodylen, succ = socket.read(fd, 2)
    --     if not succ then
    --         skynet.error("read bodylen err fd:" .. fd)
    --         disconnect(fd)
    --         socket.close(fd)
    --         return
    --     end
    --     -- 读取包体
    --     local bodybuff, succ = socket.read(fd, bodylen)
    --     if not succ then
    --         skynet.error("read bodylen err fd:" .. fd)
    --         disconnect(fd)
    --         socket.close(fd)
    --         return
    --     end
    --     process_msg(fd, bodybuff)
    -- end
end

local connect = function(fd, addr)
    if closing then return end
    print("connect form " .. addr .. " " .. fd)
    local c = conn()
    conns[fd] = c
    c.fd = fd
    skynet.fork(recv_loop, fd)
end

s.resp.send_by_fd = function(source, fd, msg)
    if not conns[fd] then return end

    skynet.error(string.format("send %d [0x%06X] %s", fd, msg[1], cjsonutil.serialise_value(msg[2])))

    local buff = proto_pack(msg[1], msg[2])
    socket.write(fd, buff)
end

s.resp.send = function(source, playerid, msg)
    local gplayer = players[playerid]
    if gplayer == nil then return end

    local c = gplayer.conn
    if c == nil then
        table.insert(gplayer.msgcache, msg)
        local len = #gplayer.msgcache
        if len > 500 then
            skynet.call("agentmgt", "lua", "reqkick", playerid,
                        "gete消息缓存过多")
        end
        return
    end

    s.resp.send_by_fd(nil, c.fd, msg)
end

s.resp.sure_agent = function(source, fd, playerid, agent)
    local conn = conns[fd]
    if not conn then
        skynet.call("agentmgr", "lua", "reqkick", playerid,
                    "未完成登录即下线")
        return false
    end

    conn.playerid = playerid
    local gplayer = gateplayer()
    skynet.error("sure_agent key:" .. gplayer.key)
    gplayer.playerid = playerid
    gplayer.agent = agent
    gplayer.conn = conn
    players[playerid] = gplayer

    return true
end

s.resp.kick = function(source, playerid)
    local gplayer = players[playerid]
    if not gplayer then return end

    local c = gplayer.conn
    players[playerid] = nil

    if not c then return end
    conns[c.fd] = nil
    disconnect(c.fd)
    socket.close(c.fd)
end

local function loadpbconfig()
    pb = require "protobuf"
    pbconfig = require "pbconfig"

    for _, v in pairs(pbconfig.files) do
        local file = string.format("%s/%s", "./protos/pbs", v)
        -- print("register pb file: "..file)
        pb.register_file(file);
    end
end

s.resp.reloadpb = function()
    loadpbconfig()
    return true
end

s.resp.shutdown = function() closing = true end

function s.init()
    local node = skynet.getenv("node")
    local nodecfg = runconfig[node]
    local port = nodecfg.gateway[s.id].port

    loadpbconfig()

    local listenfd = socket.listen("0.0.0.0", port)
    skynet.error("Listen socket:", "0.0.0.0", port)
    socket.start(listenfd, connect)
end

s.start(...)
