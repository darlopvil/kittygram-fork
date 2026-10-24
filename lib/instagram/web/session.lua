-- Token bootstrap for the optional web session (config.web_session).
-- Instagram's authenticated GraphQL calls need tokens bound to the session
-- (fb_dtsg, lsd, actor id...). They are read from an authenticated HTML page,
-- cached in Redis and refreshed when Instagram rejects them.
local config = require("lapis.config").get()
local get_redis = require("lapis.redis").get_redis
local http_request = require("lib.http")
local json = require("cjson")

local CACHE_KEY = "kg:web_session:tokens"
local BOOTSTRAP_URL = "https://www.instagram.com/explore/"
local BOOTSTRAP_ROUTE = "comet.igweb.PolarisExploreRoute"
local DEFAULT_USER_AGENT =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"

-- The page is ~2.5 MB, so values are extracted with regexes instead of a full HTML parse.
local PATTERNS = {
    fb_dtsg = [["DTSGInitialData",\[\],\{"token":"([^"]+)"]],
    lsd = [["LSD",\[\],\{"token":"([^"]+)"]],
    actor_id = [["actorID":"([1-9][0-9]*)"]],
    haste_session = [["haste_session":"([^"]+)"]],
    hsi = [["hsi":"([0-9]+)"]],
    revision = [["client_revision":([0-9]+)]],
    spin_r = [["__spin_r":([0-9]+)]],
    spin_b = [["__spin_b":"([^"]+)"]],
    spin_t = [["__spin_t":([0-9]+)]],
    comet_env = [["comet_env":([0-9]+)]],
    connection_class = [["connectionClass":"([^"]+)"]],
}
local REQUIRED = { "fb_dtsg", "lsd", "actor_id", "haste_session", "hsi", "revision", "spin_r", "spin_b", "spin_t" }

-- Instagram error codes returned when the session tokens are not accepted.
local REJECTION_CODES = { ["1357001"] = true, ["1357004"] = true, ["1357054"] = true }

local function settings()
    return config.web_session or {}
end

local function user_agent()
    return settings().user_agent or DEFAULT_USER_AGENT
end

local function cookie_value(name)
    local cookies = settings().cookies
    if type(cookies) ~= "string" then
        return nil
    end
    return ("; " .. cookies):match("[;%s]" .. name .. "=([^;%s]+)")
end

-- jazoest is a checksum of fb_dtsg: "2" followed by the sum of its bytes.
local function jazoest(fb_dtsg)
    local sum = 0
    for i = 1, #fb_dtsg do
        sum = sum + fb_dtsg:byte(i)
    end
    return "2" .. sum
end

local function bootstrap()
    local cookies = settings().cookies
    if type(cookies) ~= "string" or cookies == "" then
        return nil, "web_session.cookies is not set"
    end

    local request, err = http_request(BOOTSTRAP_URL, {
        method = "GET",
        headers = {
            { "accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" },
            { "accept-language", "en-GB,en;q=0.9" },
            { "cookie", cookies },
            { "user-agent", user_agent() },
            { "sec-fetch-dest", "document" },
            { "sec-fetch-mode", "navigate" },
            { "sec-fetch-site", "none" },
            { "upgrade-insecure-requests", "1" },
        },
    })

    if not request then
        return nil, "network error: " .. tostring(err)
    end
    if request.status ~= 200 then
        return nil, "bootstrap page returned HTTP " .. tostring(request.status)
    end

    local html = request.body or ""
    local tokens = {}
    for key, pattern in pairs(PATTERNS) do
        local match = ngx.re.match(html, pattern, "jo")
        if match then
            tokens[key] = match[1]
        end
    end

    for _, key in ipairs(REQUIRED) do
        if not tokens[key] then
            return nil, "token not found in bootstrap page: " .. key
        end
    end

    tokens.jazoest = jazoest(tokens.fb_dtsg)
    tokens.csrf_token = cookie_value("csrftoken")
    tokens.comet_env = tokens.comet_env or "7"
    tokens.connection_class = tokens.connection_class or "EXCELLENT"
    tokens.canonical_route_name = BOOTSTRAP_ROUTE

    return tokens
end

local function get_tokens()
    local redis = get_redis()
    if redis then
        local cached = redis:get(CACHE_KEY)
        if cached and cached ~= ngx.null then
            local ok, tokens = pcall(json.decode, cached)
            if ok and type(tokens) == "table" then
                return tokens
            end
        end
    end

    local tokens, err = bootstrap()
    if not tokens then
        ngx.log(ngx.WARN, "[web_session] bootstrap failed: ", err)
        return nil, err
    end

    if redis then
        redis:set(CACHE_KEY, json.encode(tokens), "EX", settings().token_ttl or 3600)
    end
    return tokens
end

local function invalidate()
    local redis = get_redis()
    if redis then
        redis:del(CACHE_KEY)
    end
end

-- Whether Instagram refused the request because of the session tokens.
local function is_rejection(request)
    if request.status == 302 or request.status == 403 then
        return true
    end
    local body = request.body or ""
    if body:find('"require_login":true', 1, true) then
        return true
    end
    local code = body:match('^for %(;;%);{"__ar":1,"error":(%d+)')
    return code ~= nil and REJECTION_CODES[code] == true
end

-- Make an authenticated request look like the browser that owns the session.
local function apply_headers(headers)
    for _, header in ipairs(headers) do
        if header[1] == "user-agent" then
            header[2] = user_agent()
        elseif header[1]:sub(1, 9) == "sec-ch-ua" then
            header[2] = nil
        end
    end
    table.insert(headers, { "x-asbd-id", settings().asbd_id or "359341" })
    table.insert(headers, { "origin", "https://www.instagram.com" })
    table.insert(headers, { "referer", BOOTSTRAP_URL })
end

return {
    get_tokens = get_tokens,
    invalidate = invalidate,
    is_rejection = is_rejection,
    apply_headers = apply_headers,
}
