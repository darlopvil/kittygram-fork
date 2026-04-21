local http = require("resty.http")
local util = require("lapis.util")
local encoding = require("lapis.util.encoding")
local json = require("cjson")
local helpers = require("lib.helpers")
local config = require("lapis.config").get()

local instagram_headers = {
    ["X-IG-App-ID"] = "936619743392459", -- TODO: let this be configurable
    ["X-CSRFToken"] = "exampletexthere", -- this can be anything.  TODO: probably should make it configurable as well
    ["Content-Type"] =  "application/x-www-form-urlencoded",
    ["Accept"] =  "*/*"
}

local gql_endpoints = {
    query = "https://www.instagram.com/graphql/query",
    api = "https://www.instagram.com/api/graphql"
}


local function graphql_request(request_payload, doc_id, request_type)
    local httpc = http.new()

    local headers = instagram_headers
    local request_body = ""
    local request_url = gql_endpoints[doc_id.endpoint]

    -- This endpoint requires extra information
    if doc_id.endpoint == "api" then
        local lsd = encoding.encode_base64(math.random()):gsub("+", "-"):gsub("/", "_"):gsub("=", "")
        headers["X-Fb-Lsd"] = lsd
        request_body = "av=0&__d=www&__user=0&__a=1&__comet_req=7&lsd=" .. lsd .. "&server_timestamps=true&"
    end
    -- some queries are sent through get requests.
    if doc_id.method == "GET" then
        request_body = "doc_id=" .. doc_id.doc_id .. "&variables=" .. util.escape(json.encode(request_payload))
        request_url = request_url .. "?" .. request_body
    else
        request_body = request_body .. "variables=" .. util.escape(json.encode(request_payload)) .. "&doc_id=" .. doc_id.doc_id
    end
    local request_opts = {
        method = doc_id.method,
        headers = instagram_headers,
    }

    if doc_id.method == "POST" then
        request_opts.body = request_body
    end

    -- check if there is a proxy url for the request type.
    if request_type and config.proxies[request_type] then
        request_opts.proxy_opts = {
            https_proxy = config.proxies[request_type]
        }
    end

    local request, err = httpc:request_uri(request_url, request_opts)

    if not request then
        ngx.log(ngx.ERR, err)
    end


    return json.decode(request.body)
end

return { request = graphql_request }
