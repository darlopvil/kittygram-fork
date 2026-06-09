local json = require("cjson")
local http = require("resty.http")
local web_state = ngx.shared.web_state
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
    --[[ currently unused, fairly sure it's blocked when kittygram tries to use it because of tls fingerprinting.
    web_profile_info = {
        path = "users/web_profile_info/",
        method = "GET",
        requires_auth = false,
    }]]
}

local construct_params = {
    user_reels = function(user_id, cursor)
        return {
            include_feed_video = "true",
            page_size = "12",
            target_user_id = user_id,
            max_id = cursor
        }
    end,
    web_profile_info = function(username)
        return {
            username = username
        }
    end
}

-- This assumes the same ratelimits as graphql.
-- GET requests aren't tested yet.
-- I haven't seen what a ratelimit looks like yet, so there's probably something I'm missing.
local function request(endpoint, params, purpose)
    local httpc = http:new()
    --See comments at graphql.lua on ratelimits.
    local request_count = web_state:incr("api:" .. endpoint.path .. ":", 1, 0, WINDOW_LENGTH)
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

    local request_uri = BASE_PATH .. endpoint.path
    local encoded_body = util.encode_query_string(params)

    if endpoint.method == "POST" then
        request_opts.method = "POST"
        request_opts.body = encoded_body
    elseif endpoint.method == "GET" then
        request_opts.method = "GET"
        request_uri = request_uri .. "?" .. encoded_body
    end
    local request = httpc:request_uri(request_uri, request_opts)

    local decode_status, decoded_body = helpers.safe_json_decode(request.body)

    if request.status == 429 then
        return errors.ratelimited{
            blob = request.body,
            message = "Instagram returned 429."
        }
    elseif request.status == 302 then
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



