local skynet = require "skynet"
local cjson = require "cjson"
local pb = require "protobuf"
local pbconfig = require "pbconfig"

function test1()
    local msg = {
        _cmd = "balllist",
        balls = {
            [1] = {id = 102, x = 10, y = 20, size = 1},
            [2] = {id = 103, x = 10, y = 40, size = 2}
        }
    }
    local buff = cjson.encode(msg)
    print(buff)
end

function json_pack(cmd, msg)
    msg._cmd = cmd
    local body = cjson.encode(msg) -- 协议体字节流
    local namelen = string.len(cmd) -- 协议名长度
    local bodylen = string.len(body) -- 协议体长度
    local len = namelen + bodylen + 2 -- 协议总长度
    local format = string.format("> i2 i2 c%d c%d", namelen, bodylen)
    local buff = string.pack(format, len, namelen, cmd, body)
    return buff
end

function json_unpack(buff)
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

function test3()
    local msg = {
        _cmd = "playerinfo",
        coin = 100,
        bag = {
            [1] = {1001, 1}, -- 倚天剑*1
            [2] = {1005, 5} -- 草药*5
        }
    }
    -- 编码
    local buff_with_len = json_pack("playerinfo", msg)
    local len = string.len(buff_with_len)
    print("ENCODE====================")
    print("len:" .. len)
    print(buff_with_len)
    print("ENCODE====================")
    -- 解码
    local format = string.format(">i2 c%d", len - 2)
    local _, buff = string.unpack(format, buff_with_len)
    local cmd, umsg = json_unpack(buff)
    print("DENCODE===================")
    print("cmd:" .. cmd)
    print("coin:" .. umsg.coin)
    print("sword:" .. umsg.bag[1][2])
    print("yao:" .. umsg.bag[2][2])
    print("DENCODE===================")
end

function test4()
    pb.register_file("./proto/login.pb")
    local msg = {id = 101, pw = "123456"}
    local buff = pb.encode("login.Login", msg)
    print("len:" .. string.len(buff))

    local umsg = pb.decode("login.Login", buff)
    if umsg then
        print("id:" .. umsg.id)
        print("pw:" .. umsg.pw)
    else
        print("error")
    end
end

local function proto_pack(pbindex, msg)
    local typeName = pbconfig.s2c[pbindex]
    if not typeName then
        error(string.format("protocal %s not found", pbindex))
        return
    end
    local body = pb.encode(typeName, msg) -- 协议体字节流
    local bodylen = string.len(body) -- 协议体长度
    local len = 2 + 4 + bodylen -- 协议总长度
    local format = string.format("> i2 i4 c%d", bodylen)
    local buff = string.pack(format, len, pbindex, body)
    return buff
end

local function proto_unpack(buff)
    local len = string.len(buff)
    local format = string.format("> i2 i4 c%d", len - 6)
    local _, pbindex, bodybuff = string.unpack(format, buff)

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

function test5()

    for _, v in pairs(pbconfig.files) do
        local file = string.format("%s/%s", "./protos/pbs", v)
        print("register pb file: " .. file)
        pb.register_file(file);
    end

    local msg = {id = 101, pw = "123456"}
    local buff = proto_pack(0xF00001, msg)
    print("len:" .. string.len(buff))

    local cmd, umsg = proto_unpack(buff)
    if cmd and umsg then
        print(string.format("cmd: 16[%06X]", cmd))
        print("id:" .. umsg.id)
        print("pw:" .. umsg.pw)
    else
        print("error")
    end
end

function test6()
    testNum1 = 0x000001
    print(string.format("testNum1: 16[%06X]\n", testNum1))
    print(string.format("testNum1: 10[%d]\n", testNum1))
    testNum2 = 0x000010
    print(string.format("testNum2: 16[%06X]\n", testNum2))
    print(string.format("testNum2: 10[%d]\n", testNum2))
    testNum2 = 0xFFFFFF
    print(string.format("testNum2: 16[%06X]\n", testNum2))
    print(string.format("testNum2: 10[%d]\n", testNum2))

end

skynet.start(function() test5() end)
