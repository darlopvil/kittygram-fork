local lapis = require("lapis")
local app = lapis.Application()

local http = require("resty.http")
local util = require("lapis.util")

local DOWNLOAD_EXTENSIONS = {
    ["image/jpeg"] = ".jpg",
    ["image/png"] = ".png",
    ["image/webp"] = ".webp",
    ["image/heic"] = ".heic",
    ["image/avif"] = ".avif",
    ["video/mp4"] = ".mp4",
}

local WHITELIST = {
    "cdninstagram.com",
    "fbcdn.net",
    "fbsbx.com",
}

app:get("/mediaproxy", function(self)
    local image_uri = util.unescape(self.params.url)
    local httpc = http.new()
    local parsed_uri = httpc:parse_uri(image_uri)

    if not parsed_uri then
        return { status = 400, "Invalid URL" }
    end

    local scheme, host, port, path = unpack(parsed_uri)

    local allowed = false
    for _, domain in ipairs(WHITELIST) do
        if host == domain or ngx.re.find(host, [[\.]] .. domain .. "$", "jo") then
            allowed = true
            break
        end
    end

    if not allowed then
        return { status = 403, "Domain Not Allowed", layout = false, content_type = "text/plain" }
    end

    local ok, err, ssl_session = httpc:connect {
        scheme = scheme,
        host = host,
        port = 443,
    }

    if err then
        ngx.log(ngx.ERR, "[mediaproxy] Connecting failed: ", err)
        return { status = 502, "Request Failed" }
    end

    local res, err = httpc:request {
        path = path,
        headers = {
            ["Host"] = host,
            ["Range"] = self.req.headers["Range"],
        },
    }

    if not res then
        ngx.log(ngx.ERR, "[mediaproxy] Request Failed: ", err)
        return { status = 502, "Request Failed" }
    end

    ngx.status = res.status
    ngx.header.content_type = res.headers["Content-Type"]
    ngx.header.content_length = res.headers["Content-Length"]
    ngx.header.content_range = res.headers["Content-Range"]

    -- ?download=<name>: save the file instead of displaying it.
    local download = self.params.download
    if type(download) == "string" and download ~= "" then
        local stem = download:gsub("[^%w%._-]", "_"):sub(1, 100)
        local content_type = (res.headers["Content-Type"] or ""):match("^[^;%s]+") or ""
        local extension = DOWNLOAD_EXTENSIONS[content_type:lower()] or ""
        ngx.header["Content-Disposition"] = 'attachment; filename="' .. stem .. extension .. '"'
    end

    repeat
        local buffer, err = res.body_reader(8192)
        if err then
            ngx.log(ngx.ERR, err)
            break
        end

        if buffer then
            ngx.print(buffer)
        end
    until not buffer

    return {
        skip_render = true,
    }
end)

return app
