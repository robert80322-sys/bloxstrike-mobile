-- RIVALS 手机版加载器（Delta / Codex / Fluxus 通用，自带多接口 + 多镜像 + 报错提示）
local URLS = {
    "https://cdn.jsdelivr.net/gh/robert80322-sys/bloxstrike-mobile@v9/rivals-mobile.lua",
    "https://raw.githubusercontent.com/robert80322-sys/bloxstrike-mobile/main/rivals-mobile.lua",
    "https://raw.githack.com/robert80322-sys/bloxstrike-mobile/main/rivals-mobile.lua",
}

local function GET(u)
    if type(HttpGet) == "function" then
        local ok, r = pcall(HttpGet, u)
        if ok and type(r) == "string" and #r > 0 then return r end
    end
    if type(request) == "function" then
        local ok, r = pcall(request, { Url = u, Method = "GET" })
        if ok and type(r) == "table" then return r.Body or r.body end
    end
    if type(http_request) == "function" then
        local ok, r = pcall(http_request, { Url = u, Method = "GET" })
        if ok and type(r) == "table" then return r.Body or r.body end
    end
    if type(syn) == "table" and type(syn.request) == "function" then
        local ok, r = pcall(syn.request, { Url = u, Method = "GET" })
        if ok and type(r) == "table" then return r.Body or r.body end
    end
    local ok, g = pcall(function() return game.HttpGet end)
    if ok and type(g) == "function" then
        local ok2, r = pcall(g, game, u)
        if ok2 and type(r) == "string" and #r > 0 then return r end
    end
    local ok3, r3 = pcall(function()
        return game:GetService("HttpService"):GetAsync(u)
    end)
    if ok3 then return r3 end
    return nil
end

local lastErr = "没有可用的 HTTP 接口"
for _, u in ipairs(URLS) do
    local src = GET(u)
    if type(src) == "string" and #src > 5000 then
        print("[loader] 下载 OK " .. #src .. "B <- " .. u)
        local fn, err = loadstring(src, "=rivals_mobile")
        if fn then
            return fn()
        else
            lastErr = "编译失败: " .. tostring(err)
            warn("[loader] " .. lastErr)
        end
    else
        lastErr = "下载失败（返回 " .. tostring(src and #src or "nil") .. "B）"
        warn("[loader] " .. u .. " -> " .. lastErr)
    end
end
warn("[loader] 全部镜像失败：" .. tostring(lastErr))
