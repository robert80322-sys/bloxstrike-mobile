--[[
  RIVALS BEST FFA FARM (#237069) · pasteblox 免 key 尝试 + 抓包/落盘
  兼容版：Delta / Codex / Fluxus（不再依赖 game:HttpGet，Delta 没有这个成员）

  用法：执行器里直接跑本文件。
]]

local GENV = (typeof and typeof(getgenv) == "function" and getgenv()) or _G
local RAW  = "https://scriptblox.com/raw/RIVALS-BEST-FFA-FARM-237069"
local LOGF = "pasteblox_traffic.txt"

local function log(s)
    pcall(function() print("[PB] " .. tostring(s)) end)
    pcall(function() if appendfile then appendfile(LOGF, tostring(s) .. "\n") end end)
end

---------------------------------------------------------------------
-- HTTP 兼容层（Delta 没有 game:HttpGet）
---------------------------------------------------------------------
local function getService(n)
    local ok, s = pcall(function() return game:GetService(n) end)
    if ok then return s end
    return nil
end

local function bodyOf(r)
    if type(r) == "table" then return r.Body or r.body or r.ResponseBody or "" end
    return tostring(r or "")
end

local function requestTable(opts)
    if type(request) == "function" then
        local ok, r = pcall(request, opts)
        if ok then return r end
    end
    if type(http_request) == "function" then
        local ok, r = pcall(http_request, opts)
        if ok then return r end
    end
    if type(GENV.syn) == "table" and type(GENV.syn.request) == "function" then
        local ok, r = pcall(GENV.syn.request, opts)
        if ok then return r end
    end
    if type(GENV.http) == "table" and type(GENV.http.request) == "function" then
        local ok, r = pcall(GENV.http.request, opts)
        if ok then return r end
    end
    return nil
end

local function httpGet(url)
    if type(HttpGet) == "function" then
        local ok, r = pcall(HttpGet, url)
        if ok and type(r) == "string" then return r end
    end
    local okGame, g = pcall(function() return game.HttpGet end)
    if okGame and type(g) == "function" then
        local ok, r = pcall(g, game, url)
        if ok and type(r) == "string" then return r end
    end
    local r = requestTable({ Url = url, Method = "GET" })
    if r ~= nil then return bodyOf(r) end
    local hs = getService("HttpService")
    if hs and type(hs.GetAsync) == "function" then
        local ok, res = pcall(hs.GetAsync, hs, url)
        if ok then return tostring(res) end
    end
    error("这个执行器没有可用的 HTTP（HttpGet / request 都没有）")
end

local function httpPost(url, body, ct)
    if type(HttpPost) == "function" then
        local ok, r = pcall(HttpPost, url, body, ct)
        if ok then return bodyOf(r) end
    end
    local okGame, p = pcall(function() return game.HttpPost end)
    if okGame and type(p) == "function" then
        local ok, r = pcall(p, game, url, body, ct)
        if ok then return bodyOf(r) end
    end
    local r = requestTable({ Url = url, Method = "POST", Body = body, Headers = { ["Content-Type"] = ct or "application/json" } })
    if r ~= nil then return bodyOf(r) end
    local hs = getService("HttpService")
    if hs and type(hs.PostAsync) == "function" then
        local ok, res = pcall(hs.PostAsync, hs, url, body, ct)
        if ok then return tostring(res) end
    end
    return ""
end

---------------------------------------------------------------------
-- 伪响应
---------------------------------------------------------------------
local FAKE = '{"ok":true,"success":true,"valid":true,"key":"PBBYPASS-0000-0000",'
    .. '"data":{"ok":true,"valid":true,"key":"PBBYPASS-0000-0000","step":1,"total":1,'
    .. '"state":{"step":1,"total":1,"key":"PBBYPASS-0000-0000","boundToDevice":false}},'
    .. '"state":{"step":1,"total":1,"key":"PBBYPASS-0000-0000"},"message":"ok"}'

local function isPB(u) return type(u) == "string" and u:find("pasteblox%.com") ~= nil end

---------------------------------------------------------------------
-- 拦截：全局函数 + request 族 + game 方法（有才挂）
---------------------------------------------------------------------
do
    if type(HttpGet) == "function" then
        local orig = HttpGet
        GENV.HttpGet = function(url, ...)
            if isPB(url) then log("BLOCK HttpGet " .. tostring(url)) return FAKE end
            local r = orig(url, ...)
            log("HttpGet " .. tostring(url) .. " -> " .. #tostring(r) .. "B")
            return r
        end
        HttpGet = GENV.HttpGet
    end
    if type(HttpPost) == "function" then
        local orig = HttpPost
        GENV.HttpPost = function(url, body, ...)
            if isPB(url) then log("BLOCK HttpPost " .. tostring(url)) return FAKE end
            return orig(url, body, ...)
        end
        HttpPost = GENV.HttpPost
    end
    if type(request) == "function" then
        local orig = request
        GENV.request = function(t)
            local url = type(t) == "table" and (t.Url or t.url) or nil
            if isPB(url) then
                log("BLOCK request " .. tostring(t.Method or t.method or "GET") .. " " .. tostring(url))
                return { StatusCode = 200, Status = 200, Success = true, Body = FAKE, Headers = {} }
            end
            return orig(t)
        end
        request = GENV.request
    end
    if type(http_request) == "function" then
        local orig = http_request
        GENV.http_request = function(t)
            local url = type(t) == "table" and (t.Url or t.url) or nil
            if isPB(url) then
                log("BLOCK http_request " .. tostring(url))
                return { StatusCode = 200, Status = 200, Success = true, Body = FAKE, Headers = {} }
            end
            return orig(t)
        end
        http_request = GENV.http_request
    end
    if type(GENV.syn) == "table" and type(GENV.syn.request) == "function" then
        local orig = GENV.syn.request
        GENV.syn.request = function(t)
            local url = type(t) == "table" and (t.Url or t.url) or nil
            if isPB(url) then
                log("BLOCK syn.request " .. tostring(url))
                return { StatusCode = 200, Status = 200, Success = true, Body = FAKE, Headers = {} }
            end
            return orig(t)
        end
    end
    -- HttpService 全方法（很多 pasteblox 壳用 RequestAsync/PostAsync）
    pcall(function()
        local HS = game:GetService("HttpService")
        if type(HS.GetAsync) == "function" then
            local og = HS.GetAsync
            HS.GetAsync = function(self, url, ...)
                if isPB(url) then log("BLOCK GetAsync " .. tostring(url)) return FAKE end
                return og(self, url, ...)
            end
        end
        if type(HS.PostAsync) == "function" then
            local op = HS.PostAsync
            HS.PostAsync = function(self, url, body, ...)
                if isPB(url) then log("BLOCK PostAsync " .. tostring(url)) return FAKE end
                return op(self, url, body, ...)
            end
        end
        if type(HS.RequestAsync) == "function" then
            local orq = HS.RequestAsync
            HS.RequestAsync = function(self, opts, ...)
                local url = type(opts) == "table" and opts.Url
                if isPB(url) then log("BLOCK RequestAsync " .. tostring(url)) return { StatusCode = 200, Status = 200, Success = true, Body = FAKE, Headers = {} } end
                return orq(self, opts, ...)
            end
        end
    end)

    local okG, g = pcall(function() return game.HttpGet end)
    if okG and type(g) == "function" then
        local okS = pcall(function()
            game.HttpGet = function(self, url, ...)
                if isPB(url) then log("BLOCK game:HttpGet " .. tostring(url)) return FAKE end
                return g(self, url, ...)
            end
        end)
        log("hook game:HttpGet = " .. tostring(okS))
    end
    local okP, p = pcall(function() return game.HttpPost end)
    if okP and type(p) == "function" then
        pcall(function()
            game.HttpPost = function(self, url, body, ...)
                if isPB(url) then log("BLOCK game:HttpPost " .. tostring(url)) return FAKE end
                return p(self, url, body, ...)
            end
        end)
    end
end

---------------------------------------------------------------------
-- loadstring 落盘
---------------------------------------------------------------------
do
    local dumped, realLoad = 0, loadstring
    if type(realLoad) == "function" then
        GENV.loadstring = function(src, name, ...)
            if type(src) == "string" and #src > 400 then
                dumped = dumped + 1
                local f = "pasteblox_dump_" .. dumped .. ".lua"
                pcall(function() if writefile then writefile(f, src) end end)
                log("DUMP " .. f .. " (" .. #src .. "B) <- " .. tostring(name))
            end
            return realLoad(src, name, ...)
        end
        loadstring = GENV.loadstring
    end
end

---------------------------------------------------------------------
-- 跑原脚本
---------------------------------------------------------------------
log("===== 开始执行原脚本 =====")
local ok, err = pcall(function()
    local src = httpGet(RAW)
    log("原脚本 " .. #tostring(src) .. "B")
    local fn = loadstring(src, "=rivals_ffa")
    if not fn then error("编译失败") end
    return fn()
end)
log("exit ok=" .. tostring(ok) .. " err=" .. tostring(err))
