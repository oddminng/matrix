package.cpath = package.cpath .. ";luaclib/?.so;skynet/luaclib/?.so"
package.path = "etc/?.lua;lualib/?.lua;skynet/lualib/?.lua"

local socket = require "client.socket"
local jsonUtil = require "cjson.util"
local pb = require "protobuf"
local pbconfig = require "pbconfig"

local function proto_pack(pbindex, msg)
    local typeName = pbconfig.c2s[pbindex]
    if not typeName then
        error(string.format("protocal %06X not found", pbindex))
        return
    end
    print(string.format("typeName : %s msg : %s", typeName, jsonUtil.serialise_value(msg)))
    local body = pb.encode(typeName, msg) -- 协议体字节流
    local bodylen = string.len(body) -- 协议体长度
    local len = 4 + bodylen -- 协议总长度
    local format = string.format("> i2 i4 c%d", bodylen)
    local buff = string.pack(format, len, pbindex, body)
    return buff
end

local function proto_unpack(buff)
    local len = string.len(buff)
    print(string.format("unpack_package bodylen:%d", len))
    local pbindex_format = string.format("> i4 c%d", len - 4)
    local pbindex, bodybuff = string.unpack(pbindex_format, buff)
    print(string.format("unpack_package pbindex:%06X", pbindex))
    local typeName = pbconfig.s2c[pbindex]
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

local function send_proto(fd, pbindex, msg)
    local msgbuff = proto_pack(pbindex, msg)
    socket.send(fd, msgbuff)
end

local unpack_package = function(readbuff)
    local size = string.len(readbuff)
    if size > 0 then
        print(string.format("size %d", size))
    end
    if size < 2 then return nil, readbuff end
    -- 取协议头中的bodylen
    local bodylen_format = string.format("> i2 c%d", size - 2)
    local bodylen, last = string.unpack(bodylen_format, readbuff)
    print(string.format("bodylen %d", bodylen))
    if size < bodylen + 2 then return nil, readbuff end
    local body_format = string.format("> c%d c%d", bodylen, size - 2 - bodylen)
    local bodybuff, last = string.unpack(body_format, last)
    return bodybuff, last
end

local _last = ""
local _fd = assert(socket.connect(arg[1], math.tointeger(arg[2])))

local function recv_package(last)
    local result
    result, last = unpack_package(last)
    if result then return result, last end
    local r = socket.recv(_fd)
    if not r then return nil, last end
    if r == "" then error "Server closed" end
    return unpack_package(last .. r)
end

local function dispatch_package()
    while true do
        local bodybuff
        bodybuff, _last = recv_package(_last)
        if not bodybuff then break end
        local pbindex, msg = proto_unpack(bodybuff)
        print(string.format("%s: receive packet: 0x%06X\n%s\n",
                            os.date("%Y-%m-%d %H:%M:%S"), pbindex,
                            jsonUtil.serialise_value(msg)))
    end
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

while true do
    loadpbconfig()
    dispatch_package()
    local cmd = socket.readstdin()
    if cmd then
        cmd = string.lower(cmd)
        if cmd == "login" then
            send_proto(_fd, 0x020001, {playerid = 10001, pw = "123"})
        elseif cmd == "work" then
            send_proto(_fd, 0x030001, {})
        elseif cmd == "enter" then
            send_proto(_fd, 0x040001, {})
        elseif cmd == "testsocket" then
            print("testsocket")
            socket.send(_fd, "testsocket")
        end
    else
        socket.usleep(1000)
    end
end
