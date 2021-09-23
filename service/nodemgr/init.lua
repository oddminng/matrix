local skynet = require "skynet"
local s = require "service"
require "skynet.manager"

s.resp.newservice = function (source, name, ...)
    local srv = skynet.newservice(name, ...)
    return srv
end

s.resp.shutdown = function (source)
    skynet.abort()
end

s.start(...)