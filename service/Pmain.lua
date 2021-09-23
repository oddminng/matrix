local skynet = require "skynet"
local cjson = require "cjson"
local pb = require "protobuf"

function test1()
    local msg = {
        _cmd = "balllist",
        balls = {
            [1] = {id=102,x=10,y=20,size=1},
            [2] = {id=103,x=10,y=40,size=2},
        }
    }
    local buff = cjson.encode(msg)
    print(buff)
end


function test4()
    pb.register_file("./proto/login.pb")
    local msg = {
        id = 101,
        pw = "123456",
    }
    local buff = pb.encode("login.Login", msg)
    print("len:"..string.len(buff))

    local umsg = pb.decode("login.Login", buff)
    if umsg then
        print("id:"..umsg.id)
        print("pw:"..umsg.pw)
    else
        print("error")
    end
end

skynet.start(function ()
    test4()
end)