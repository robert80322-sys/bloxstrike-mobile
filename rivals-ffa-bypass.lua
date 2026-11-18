--[[
  RIVALS BEST FFA FARM (#237069) · pasteblox 免 key 尝试 + 抓包/落盘
  用法：执行器里直接跑本文件。

  它做三件事：
    1. 拦下所有 pasteblox 的 HTTP（HttpGet / HttpPost / HttpService / request 族），
       回一个「验证通过」的宽字段 JSON
    2. 把被 loadstring 编译的脚本全部落盘成 pasteblox_dump_N.lua
    3. 跑原脚本；流量写 pasteblox_traffic.txt

  说明：pasteblox 的 `/k/<slug>` 走的是 Next Server Action，服务端查 work.ink 回跳，
  伪造 token 实测无效（见 README）。所以这里只能赌脚本自己的校验是吃客户端响应的。
  如果没生效：先用 10 秒做完那 1 个 checkpoint 拿真 key，再跑本文件，
  会把下发的载荷/请求全存下来，之后就能离线跑。
]]

local GENV = (typeof(getgenv) == "function" and getgenv()) or _G
local RAW  = "https://scriptblox.com/raw/RIVALS-BEST-FFA-FARM-237069"
local LOGF = "pasteblox_traffic.txt"

local function log(s)
    pcall(function() print("[PB] " .. tostring(s)) end)
    pcall(function() if appendfile then appendfile(LOGF, tostring(s) .. "\n") end end)
end

local FAKE = '{"ok":true,"success":true,"valid":true,"key":"PBBYPASS-0000-0000",'
    .. '"data":{"ok":true,"valid":true,"key":"PBBYPASS-0000-0000","step":1,"total":1,'
    .. '"state":{"step":1,"total":1,"key":"PBBYPASS-0000-0000","boundToDevice":false}},'
    .. '"state":{"step":1,"total":1,"key":"PBBYPASS-0000-0000"},"message":"ok"}'

local function isPB(u) return type(u) == "string" and u:find("pasteblox%.com") ~= nil end

-- loadstring 落盘
local dumped = 0
local realLoad = loadstring
loadstring = function(src, name, ...)
    if type(src) == "string" and #src > 400 then
        dumped = dumped + 1
        local f = "pasteblox_dump_" .. dumped .. ".lua"
        pcall(function() if writefile then writefile(f, src) end end)
        log("DUMP " .. f .. " (" .. #src .. "B) <- " .. tostring(name))
    end
    return realLoad(src, name, ...)
end

-- game:HttpGet / HttpPost
do
    local og, op = game.HttpGet, game.HttpPost
    game.HttpGet = function(self, url, ...)
        if type(self) == "string" then url, self = self, game end
        if isPB(url) then log("BLOCK GET " .. tostring(url)) return FAKE end
        local r = og(self, url, ...)
        log("GET " .. tostring(url) .. " -> " .. #tostring(r) .. "B")
        return r
    end
    game.HttpPost = function(self, url, body, ...)
        if isPB(url) then log("BLOCK POST " .. tostring(url) .. " | " .. tostring(body):sub(1, 200)) return FAKE end
        local r = op(self, url, body, ...)
        log("POST " .. tostring(url) .. " -> " .. #tostring(r) .. "B")
        return r
    end
end

-- HttpService
pcall(function()
    local HS = game:GetService("HttpService")
    local g, p = HS.GetAsync, HS.PostAsync
    HS.GetAsync = function(self, url, ...)
        if isPB(url) then log("BLOCK GetAsync " .. tostring(url)) return FAKE end
        return g(self, url, ...)
    end
    HS.PostAsync = function(self, url, body, ...)
        if isPB(url) then log("BLOCK PostAsync " .. tostring(url)) return FAKE end
        return p(self, url, body, ...)
    end
    if type(HS.RequestAsync) == "function" then
        local ra = HS.RequestAsync
        HS.RequestAsync = function(self, opts, ...)
            local url = type(opts) == "table" and opts.Url or nil
            if isPB(url) then
                log("BLOCK RequestAsync " .. tostring(url))
                return { StatusCode = 200, Status = 200, Success = true, Body = FAKE, Headers = {} }
            end
            return ra(self, opts, ...)
        end
    end
end)

-- request 族
local function wrap(fn, tag)
    return function(t)
        local url = type(t) == "table" and (t.Url or t.url) or nil
        if isPB(url) then
            log("BLOCK " .. tag .. " " .. tostring(t.Method or t.method or "GET") .. " " .. tostring(url))
            return { StatusCode = 200, Status = 200, Success = true, Body = FAKE, Headers = {} }
        end
        return fn(t)
    end
end
for _, n in ipairs({ "request", "http_request", "httpRequest" }) do
    if type(GENV[n]) == "function" then GENV[n] = wrap(GENV[n], n) end
end
for _, ns in ipairs({ "syn", "http" }) do
    local t = GENV[ns]
    if type(t) == "table" and type(t.request) == "function" then t.request = wrap(t.request, ns .. ".request") end
end

log("===== 开始执行原脚本 =====")
local ok, err = pcall(function()
    local src = game:HttpGet(RAW)
    local fn = loadstring(src, "=rivals_ffa")
    if not fn then error("compile failed") end
    return fn()
end)
log("exit ok=" .. tostring(ok) .. " err=" .. tostring(err))
