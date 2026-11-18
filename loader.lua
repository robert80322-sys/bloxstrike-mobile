-- BloxStrike 手机版（Delta/Codex/Fluxus 通用）
-- 通用 GET（Delta 没有 game:HttpGet）
local function G(u)
    if type(HttpGet) == "function" then
        local ok, r = pcall(HttpGet, u); if ok and r then return r end
    end
    if type(request) == "function" then
        local ok, r = pcall(request, { Url = u, Method = "GET" })
        if ok and type(r) == "table" then return r.Body or r.body end
    end
    if type(http_request) == "function" then
        local ok, r = pcall(http_request, { Url = u, Method = "GET" })
        if ok and type(r) == "table" then return r.Body or r.body end
    end
    local ok, g = pcall(function() return game.HttpGet end)
    if ok and type(g) == "function" then
        local ok2, r = pcall(g, game, u); if ok2 and r then return r end
    end
    return game:GetService("HttpService"):GetAsync(u)
end

loadstring(G("https://cdn.jsdelivr.net/gh/robert80322-sys/bloxstrike-mobile@v4/bloxstrike-mobile.lua"))()
