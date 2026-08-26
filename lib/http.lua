local config = require("lapis.config").get()
local helpers = require("lib.helpers")
local http = require("resty.http")
local json = require("cjson")
local util = require("lapis.util")

local function sidecar_request(url, options)
    local httpc = http.new()

    local payload = {
        method = options.method,
        body = options.body,
        request_url = url,
    }

    if options.proxy_opts and options.proxy_opts.https_proxy then
        payload.proxy = options.proxy_opts.https_proxy
    elseif config.http_sidecar.proxy then
        payload.proxy = config.http_sidecar.proxy
    end

    if options.headers then
        local clean_headers = {}
        for _, header in ipairs(options.headers) do
            if header[2] ~= nil then
                table.insert(clean_headers, header)
            end
        end
        payload.headers = json.encode(clean_headers)
    end

    local request, err = httpc:request_uri(config.http_sidecar.url, {
        method = "POST",
        body = util.encode_query_string(payload),
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
        },
    })
    if err then
        return nil, err
    end

    local decode_ok, decoded = helpers.safe_json_decode(request.body)

    if not decode_ok then
        return nil, "Sidecar returned invalid json."
    end

    return decoded
end

local function resty_request(url, opts)
    local httpc = http.new()

    local headers
    if opts.headers and type(opts.headers) == "table" then
        headers = {}
        for _, header in ipairs(opts.headers) do
            headers[header[1]] = header[2]
        end
        opts.headers = headers
    end

    local request, err = httpc:request_uri(url, opts)

    return request, err
end

if config.http_sidecar and config.http_sidecar.enabled then
    return sidecar_request
else
    return resty_request
end
