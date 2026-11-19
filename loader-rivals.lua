-- RIVALS 手机版加载器 v3（多镜像 + request 优先 + 逐条报错）
local RAW = "https://raw.githubusercontent.com/robert80322-sys/bloxstrike-mobile/main/rivals-mobile.lua"
local URLS = {
    RAW,
    "https://ghproxy.net/" .. RAW,
    "https://gh-proxy.com/" .. RAW,
    "https://ghfast.top/" .. RAW,
    "https://cdn.jsdelivr.net/gh/robert80322-sys/bloxstrike-mobile@v10/rivals-mobile.lua",
    "https://raw.githack.com/robert80322-sys/bloxstrike-mobile/main/rivals-mobile.lua",
}

local function body(r)
    if type(r) == "table" then return r.Body or r.body or r.ResponseBody end
    if type(r) == "string" and #r > 0 then return r end
    return nil
end

local function GET(u)
    local tries = {
        { "request", function() return request({ Url = u, Method = "GET" }) end },
        { "http_request", function() return http_request({ Url = u, Method = "GET" }) end },
        { "HttpGet", function() return HttpGet(u) end },
        { "game:HttpGet", function() return game:HttpGet(u) end },
        { "HttpService", function() return game:GetService("HttpService"):GetAsync(u) end },
    }
    for _, t in ipairs(tries) do
        local fn = nil
        if t[1] == "HttpGet" then fn = rawget(getfenv(), "HttpGet") or _G.HttpGet
        elseif t[1] == "request" then fn = rawget(getfenv(), "request") or _G.request
        elseif t[1] == "http_request" then fn = rawget(getfenv(), "http_request") or _G.http_request
        else fn = true end
        if type(fn) == "function" or t[1] == "game:HttpGet" or t[1] == "HttpService" then
            local ok, r = pcall(t[2])
            if ok then
                local b = body(r)
                if type(b) == "string" and #b > 0 then return b, t[1] end
            end
        end
    end
    return nil, nil
end

for i, u in ipairs(URLS) do
    local src, how = GET(u)
    if type(src) == "string" and #src > 5000 then
        print("[loader] #" .. i .. " OK " .. #src .. "B via " .. tostring(how))
        local fn, err = loadstring(src, "=rivals_mobile")
        if fn then fn(); return end
        warn("[loader] 编译失败: " .. tostring(err))
    else
        warn("[loader] #" .. i .. " 失败 <- " .. u)
    end
end
warn("[loader] 全部镜像都连不上，检查网络/加速器")
