local http = require("resty.http")
local util = require("lapis.util")
local encoding = require("lapis.util.encoding")
local json = require("cjson")
local helpers = require("lib.helpers")
local errors = helpers.create_error
local ngx_resp = require("ngx.resp")
local config = require("lapis.config").get()
local web_state = ngx.shared.web_state
local cache = require("lib.cache")
local graphql = require("lib.instagram.web.graphql")
local format_highlights = require("lib.formatters").format_highlights

local WINDOW_LENGTH = config.ratelimits.window_length
local REQUEST_LIMIT = config.ratelimits.request_limit

local HIGHLIGHTS_TRAY_QUERY_ID = "9957820854288654"

local function create_headers()
    return {
        ["X-IG-App-ID"] = "936619743392459",
        ["X-CSRFToken"] = "exampletexthere", -- this can be anything. I could get valid CSRF tokens, but this works for now.
        ["Content-Type"] = "application/x-www-form-urlencoded",
        ["Accept"] = "*/*",
    }
end

local function cooldown()
    if config.ratelimits.cooldown_on_ratelimit then
        -- Get the remaining ttl on the key
        local key_ttl = web_state:ttl("highlights_tray")
        if key_ttl and key_ttl > 0 then
            web_state:replace("highlights_tray", REQUEST_LIMIT + 999, key_ttl)
        else
            web_state:replace("highlights_tray", REQUEST_LIMIT + 999, WINDOW_LENGTH)
        end
    end
end

-- The query for highlights takes a completely different format to every other query I have seen.
local function get_highlights_tray(user_id)

    local request_count = web_state:incr("highlights_tray", 1, 0, WINDOW_LENGTH)
    if request_count > REQUEST_LIMIT and config.ratelimits.cooldown_on_ratelimit then
        return errors.ratelimited{
            message = "The server has blocked further requests to Instagram temporarily.",
        }
    end

    local httpc = http.new()
    local headers = create_headers()
    local url = string.format("https://www.instagram.com/graphql/query/?query_id=%s&user_id=%s&include_chaining=false&include_reel=true&include_suggested_users=false&include_logged_out_extras=true&include_live_status=false&include_highlight_reels=true",
                                    HIGHLIGHTS_TRAY_QUERY_ID,
                                    user_id)

    local request_opts = {
        headers = headers
    }

    if request_type and config.proxies["highlights"] then
        request_opts.proxy_opts = { https_proxy = config.proxies["highlights"] }
    end

    local request = httpc:request_uri(url, request_opts)

    if config.include_debug_headers then
        ngx_resp.add_header("X-Kg-Debug-Endpoints", "highlights_tray:" .. HIGHLIGHTS_TRAY_QUERY_ID)
    end

    if not request then
        ngx.log(ngx.ERR, "Network error: " .. err)
        return errors.network_error{
            blob = err
        }
    elseif request.status == 302 then
        -- Since a 302 usually indicates a ratelimit or block of some sort,
        cooldown()
        return errors.ratelimited{
            message = "Instagram returned 302 with location: " .. tostring(request.headers.location)
        }
    end

    local decode_ok, decoded_body = helpers.safe_json_decode(request.body)

    if not decode_ok then
        return errors.unknown{
            message = "Instagram returned invalid json. Status code: " .. request.status,
            blob = request.body
        }
    end

    if decoded_body.status == "fail" and decoded_body.require_login then
        cooldown()
        return errors.ratelimited{
            blob = decoded_body
        }
    elseif not decoded_body.data or decoded_body.data == json.null then
        return errors.unknown{
            message = "`data` field not present in response.",
            blob = decoded_body
        }
    else
        local formatted = format_highlights.from_anon_web(decoded_body.data)
        return formatted
    end
end



return {
    get_tray = get_highlights_tray,
}


