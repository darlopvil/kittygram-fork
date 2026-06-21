local json = require("cjson")
local http = require("resty.http")
local web_state = ngx.shared.web_state
local ngx_resp = require("ngx.resp")
local config = require("lapis.config").get()
local util = require("lapis.util")
local helpers = require("lib.helpers")
local errors = helpers.create_error

local BASE_PATH = "https://www.instagram.com/api/v1/"
local WINDOW_LENGTH = config.ratelimits.window_length
local REQUEST_LIMIT = config.ratelimits.request_limit

local function create_headers()
    return {
        ["X-Ig-App-Id"] = "936619743392459",
        ["X-CSRFToken"] = "exampletexthere",
        ["Accept"] = "*/*",
        ["Content-Type"] = "application/x-www-form-urlencoded"
    }
end

local endpoints = {
    user_reels = {
        path = "clips/user/",
        method = "POST",
        requires_auth = false
    },
    -- found this endpoint embedded in a profile page. Seems to be forgotten about or unused.
    user_posts = {
        path = "feed/user/%s/username/",
        method = "GET",
        requires_auth = false
    }
}

local construct_params = {
    user_reels = function(user_id, cursor)
        return {
            body = {
                include_feed_video = "true",
                page_size = "12",
                target_user_id = user_id,
                max_id = cursor
            },
            path = {},
            query = {}
        }
    end,
    user_posts = function(username, count)
        return {
            body = {},
            path = {
                username
            },
            query = {
                count = count
            },
        }
    end,
}


local function cooldown(endpoint)
    local key = "api:" .. endpoint.path
    if config.ratelimits.cooldown_on_ratelimit then
        -- Get the remaining ttl on the key
        local key_ttl = web_state:ttl(key)
        if key_ttl and key_ttl > 0 then
            web_state:replace(key, REQUEST_LIMIT + 999, key_ttl)
        else
            web_state:replace(key, REQUEST_LIMIT + 999, WINDOW_LENGTH)
        end
    end
end
-- This assumes the same ratelimits as graphql.
local function request(endpoint, params, purpose)
    local httpc = http:new()
    --See comments at graphql.lua on ratelimits.
    local request_count = web_state:incr("api:" .. endpoint.path, 1, 0, WINDOW_LENGTH)
    if request_count > REQUEST_LIMIT and config.ratelimits.cooldown_on_ratelimit then
        return errors.ratelimited{
            message = "The server has blocked further requests to Instagram temporarily.",
        }
    end

    local headers = create_headers()
    local request_opts = {
        headers = headers
    }

    if purpose and config.proxies[purpose] then
        request_opts.proxy_opts = { https_proxy = config.proxies[purpose] }
    end

    local request_uri = BASE_PATH .. string.format(endpoint.path, table.unpack(params.path))

    local encoded_query_string = util.encode_query_string(params.query)
    if encoded_query_string ~= "" then
        request_uri = request_uri .. "?" .. encoded_query_string
    end

    if endpoint.method == "POST" then
        request_opts.method = "POST"
        local encoded_body = util.encode_query_string(params.body)
        request_opts.body = encoded_body
    elseif endpoint.method == "GET" then
        request_opts.method = "GET"
    end

    local request = httpc:request_uri(request_uri, request_opts)

    if config.include_debug_headers then
        ngx_resp.add_header("X-Kg-Debug-Endpoints", endpoint.path)
    end

    local decode_status, decoded_body = helpers.safe_json_decode(request.body)

    if request.status == 429 then
        cooldown(endpoint)
        return errors.ratelimited{
            blob = request.body,
            message = "Instagram returned 429."
        }
    elseif request.status == 302 then
        cooldown(endpoint)
        return errors.ratelimited{
            blob = request.body,
            message = "Instagram returned 302 with location " .. tostring(request.headers.location)
        }
    end
    if not decode_status then
        return errors.unknown{
            message = "Instagram returned invalid json. Status code: " .. request.status,
            blob = request.body
        }
    else
        if decoded_body.status == "fail" then
            if decoded_body.require_login then
                cooldown(endpoint)
                return errors.ratelimited{
                    message = "Instagram is temporarily blocking requests sent by the server.",
                    blob = decoded_body
                }
            else
                return errors.unknown{
                    message = "An unknown error occurred (instagram indicated failure)",
                    blob = decoded_body
                }
            end
        else
            return decoded_body
        end
    end
end

return {
    endpoints = endpoints,
    construct_params = construct_params,
    request = request
}



