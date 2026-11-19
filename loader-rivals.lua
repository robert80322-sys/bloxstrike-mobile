-- RIVALS 手机版加载器 v2（Delta：HttpGet 为 nil，走 request / http_request / game.HttpGet）
local URLS = {
    "https://cdn.jsdelivr.net/gh/robert80322-sys/bloxstrike-mobile@v10/rivals-mobile.lua",
    "https://raw.githubusercontent.com/robert80322-sys/bloxstrike-mobile/main/rivals-mobile.lua",
    "https://raw.githack.com/robert80322-sys/bloxstrike-mobile/main/rivals-mobile.lua",
}

local function body(r)
    if type(r) == "table" then return r.Body or r.body or r.ResponseBody end
    if type(r) == "string" and #r > 0 then return r end
    return nil
end

local function GET(u)
    local methods = {}
    if type(request) == "function" then
        local ok, r = pcall(request, { Url = u, Method = "GET" })
        if ok then local b = body(r); if type(b) == "string" and #b > 0 then return b, "request" end end
    end
    if type(http_request) == "function" then
        local ok, r = pcall(http_request, { Url = u, Method = "GET" })
        if ok then local b = body(r); if type(b) == "string" and #b > 0 then return b, "http_request" end end
    end
    if type(HttpGet) == "function" then
        local ok, r = pcall(HttpGet, u)
        local b = body(r); if ok and type(b) == "string" and #b > 0 then return b, "HttpGet" end
    end
    local okG, g = pcall(function() return game.HttpGet end)
    if okG and type(g) == "function" then
        local ok, r = pcall(g, game, u)
        local b = body(r); if ok and type(b) == "string" and #b > 0 then return b, "game:HttpGet" end
    end
    local okH, rH = pcall(function() return game:GetService("HttpService"):GetAsync(u) end)
    if okH and type(rH) == "string" and #rH > 0 then return rH, "HttpService" end
    return nil, nil
end

local lastErr = "没有可用的 HTTP 接口"
for _, u in ipairs(URLS) do
    local src, how = GET(u)
    if type(src) == "string" and #src > 5000 then
        print("[loader] OK " .. #src .. "B via " .. tostring(how) .. " <- " .. u)
        local fn, err = loadstring(src, "=rivals_mobile")
        if fn then
            fn()
            return
        end
        lastErr = "编译失败: " .. tostring(err)
        warn("[loader] " .. lastErr)
    else
        lastErr = "下载失败（" .. tostring(src and #src or "nil") .. "B）"
        warn("[loader] " .. u .. " -> " .. lastErr)
    end
end
warn("[loader] 全部镜像失败：" .. tostring(lastErr))
