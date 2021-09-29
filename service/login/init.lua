local skynet = require "skynet"
local s = require "service"

s.client = {}
s.resp.client = function(source, fd, cmd, msg)
    if s.client[cmd] then
        local ret_msg = s.client[cmd](fd, msg, source)
        skynet.send(source, "lua", "send_by_fd", fd, ret_msg)
    else
        skynet.error("s.resp.client fail", cmd)
    end
end

-- 用户登录
-- login
s.client[0x020001] = function(fd, msg, source)
    if not msg.playerid or not msg.pw then
        return {code="RC_ERR", msg=string.format("playerid 错误")}
    end
    local playerid = msg.playerid
    local pw = msg.pw
    local gate = source
    node = skynet.getenv("node")
    -- 校验用户名密码
    if pw ~= "123" then return {0x020001, {code="RC_ERR_PASSWORD_FAIL", msg="密码错误"}} end
    -- 发给agentmgr
    local isok, agent = skynet.call("agentmgr", "lua", "reqlogin", playerid,
                                    node, gate)
    if not isok then return {0x020001, {code="RC_ERR", msg="请求 agentmgr 失败"}} end
    -- 回应gate
    local isok = skynet.call(gate, "lua", "sure_agent", fd, playerid, agent)
    if not isok then return {0x020001, {code="RC_ERR", msg="请求 gate 失败"}} end

    skynet.error("login succ " .. playerid)
    return {0x020001, {code="RC_OK", msg="登录成功"}}
end

s.start(...)
