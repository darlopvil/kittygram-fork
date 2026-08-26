local http_request = require("lib.http")
local json = require("cjson")
local web_state = ngx.shared.web_state
local config = require("lapis.config").get()
local helpers = require("lib.helpers")
local ngx_resp = require("ngx.resp")
local util = require("lapis.util")
local errors = helpers.create_error

local BASE_PATH = "https://www.instagram.com/api/v1/"
local WINDOW_LENGTH = config.ratelimits.window_length
local REQUEST_LIMIT = config.ratelimits.request_limit

local function create_headers(content_type, cookie)
    local headers = {
        { "accept", "*/*" },
        { "content-type", content_type },
        { "cookie", cookie },
        { "sec-ch-prefers-color-scheme", "dark" },
        { "sec-ch-ua", '"Chromium";v="135", "Not)A;Brand";v="24"' },
        {
            "sec-ch-ua-full-version-list",
            '"Google Chrome";v="135.0.0.0", "Chromium";v="135.0.0.0", "Not.A/Brand";v="24"',
        },
        { "sec-ch-ua-mobile", "?0" },
        { "sec-ch-ua-model", '""' },
        { "sec-ch-ua-platform-version", '"10.0.19045"' },
        { "sec-fetch-dest", "empty" },
        { "sec-fetch-mode", "cors" },
        { "sec-fetch-site", "same-origin" },
        { "x-ig-app-id", "936619743392459" },
        { "x-csrftoken", "exampletexthere" }, -- this can be anything. I could get valid CSRF tokens, but this works for now.
        { "x-ig-max-touch-points", "0" },
        { "x-requested-with", "XMLHttpRequest" },
    }

    return headers
end

local endpoints = {
    user_reels = {
        path = "clips/user/",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = true, -- This doesn't _actually_ strictly required, but it isn't used anywhere with auth, so it's use could be suspicous.
    },
    -- found this endpoint embedded in a profile page. Seems to be forgotten about or unused.
    user_posts = {
        path = "feed/user/%s/username/",
        method = "GET",
        requires_auth = false,
    },
    comments = {
        path = "media/%s/comments/",
        method = "GET",
        requires_auth = true,
    },
}

local construct_params = {
    user_reels = function(user_id, cursor)
        return {
            body = {
                include_feed_video = "true",
                page_size = "12",
                target_user_id = user_id,
                max_id = cursor,
            },
            path = {},
            query = {},
        }
    end,
    user_posts = function(username, count)
        return {
            body = {},
            path = {
                username,
            },
            query = {
                count = count,
            },
        }
    end,
    web_profile_info = function(username)
        return {
            body = {},
            path = {},
            query = {
                username = username,
            },
        }
    end,
    comments = function(media_id, cursor)
        return {
            body = {},
            path = {
                media_id,
            },
            query = {
                can_support_threading = "true",
                min_id = cursor,
                sort_order = "popular",
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
    --See comments at graphql.lua on ratelimits.
    local request_count = web_state:incr("api:" .. endpoint.path, 1, 0, WINDOW_LENGTH)
    if request_count > REQUEST_LIMIT and config.ratelimits.cooldown_on_ratelimit then
        return errors.ratelimited {
            message = "The server has blocked further requests to Instagram temporarily.",
        }
    end

    local request_opts = {}

    if purpose and config.proxies[purpose] then
        request_opts.proxy_opts = { https_proxy = config.proxies[purpose] }
    end

    local cookie
    if purpose and config.web_session and config.web_session.cookies and config.web_session.use_for[purpose] then
        if not endpoint.requires_anonymous_session then
            cookie = config.web_session.cookies
        end
    end

    local request_uri = BASE_PATH .. string.format(endpoint.path, table.unpack(params.path))

    local encoded_query_string = util.encode_query_string(params.query)
    if encoded_query_string ~= "" then
        request_uri = request_uri .. "?" .. encoded_query_string
    end

    local content_type
    if endpoint.method == "POST" then
        request_opts.method = "POST"
        local encoded_body = util.encode_query_string(params.body)
        request_opts.body = encoded_body
        content_type = "application/x-www-form-urlencoded"
    elseif endpoint.method == "GET" then
        request_opts.method = "GET"
    end

    request_opts.headers = create_headers(content_type, cookie)
    local request, err = http_request(request_uri, request_opts)

    if not request then
        return errors.network_error { blob = err }
    end
    if config.include_debug_headers then
        ngx_resp.add_header("X-Kg-Debug-Endpoints", endpoint.path)
    end

    local decode_status, decoded_body = helpers.safe_json_decode(request.body)

    if request.status == 429 then
        cooldown(endpoint)
        return errors.ratelimited {
            blob = request.body,
            message = "Instagram returned 429.",
        }
    elseif request.status == 302 then
        cooldown(endpoint)
        return errors.ratelimited {
            blob = request.body,
            message = "Instagram returned 302 with location " .. tostring(request.headers.location),
        }
    end
    if not decode_status then
        return errors.unknown {
            message = "Instagram returned invalid json. Status code: " .. request.status,
            blob = request.body,
        }
    else
        if decoded_body.status == "fail" then
            if decoded_body.require_login then
                cooldown(endpoint)
                return errors.ratelimited {
                    message = "Instagram is temporarily blocking requests sent by the server.",
                    blob = decoded_body,
                }
            else
                return errors.unknown {
                    message = "An unknown error occurred (instagram indicated failure)",
                    blob = decoded_body,
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
    request = request,
}
