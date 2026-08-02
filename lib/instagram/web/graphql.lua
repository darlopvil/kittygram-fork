local http_request = require("lib.http")
local util = require("lapis.util")
local encoding = require("lapis.util.encoding")
local json = require("cjson")
local helpers = require("lib.helpers")
local errors = helpers.create_error
local ngx_resp = require("ngx.resp")
local config = require("lapis.config").get()
local web_state = ngx.shared.web_state

local WINDOW_LENGTH = config.ratelimits.window_length
local REQUEST_LIMIT = config.ratelimits.request_limit

local function create_headers(lsd, cookie)
    local headers =  {
        { "accept", "*/*"},
        { "content-type", "application/x-www-form-urlencoded" },
        { "cookie", cookie},
        { "sec-ch-prefers-color-scheme", "dark" },
        { "sec-ch-ua", "\"Chromium\";v=\"135\", \"Not)A;Brand\";v=\"24\"" },
        { "sec-ch-ua-full-version-list", "\"Google Chrome\";v=\"135.0.0.0\", \"Chromium\";v=\"135.0.0.0\", \"Not.A/Brand\";v=\"24\"" },
        { "sec-ch-ua-mobile", "?0"},
        { "sec-ch-ua-model", "\"\"" },
        { "sec-ch-ua-platform-version", "\"10.0.19045\""},
        { "sec-fetch-dest", "empty" },
        { "sec-fetch-mode", "cors" },
        { "sec-fetch-site", "same-origin" },
        { "x-ig-app-id", "936619743392459" },
        { "x-csrftoken", "exampletexthere" }, -- this can be anything. I could get valid CSRF tokens, but this works for now.
        { "x-ig-max-touch-points", "0" },
        { "x-fb-lsd", lsd}
    }

    return headers
end

local gql_endpoints = {
    query = "https://www.instagram.com/graphql/query",
    api = "https://www.instagram.com/api/graphql"
}

local doc_ids = {
    user_info = {
        doc_id = "37095153540132433",
        endpoint = "api",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = true
    },
    -- Friendly name: PolarisLoggedOutDesktopWWWPostCommentsPaginationQuery
    anon_comments_pagination = {
        doc_id = "27261273046856309",
        endpoint = "api",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = true,
    },
    search = {
        doc_id = "24146980661639222",
        endpoint = "query",
        method = "POST",
        requires_auth = true,
        requires_anonymous_session = false
    },
    user_posts = {
        doc_id = "27414153238279961",
        endpoint = "query",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = false
    },
    user_reels = {
        doc_id = "26909206778772295",
        endpoint = "query",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = false,
    },
    explore_search = {
        doc_id = "27319959457629526",
        endpoint = "api",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = true,
    },
    -- friendly_name: PolarisPostRootQuery
    shortcode_post_info = {
        doc_id = "26713194205046842",
        endpoint = "api",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = true,
    },
    -- friendly_name: PolarisLoggedOutDesktopWWWPostRootContentQuery
    media_id_post_info = {
        doc_id = "27130156389949648",
        endpoint = "api",
        method = "POST",
        requires_auth = false,
        -- Not too sure if it _actually_ requires an anon session, but it's a part of the logged-out stuff.
        requires_anonymous_session = true,
    },
    -- Equivalent of https://instagram.com/popular.
    popular_page = {
        doc_id = "36780798938170941",
        endpoint = "api",
        method = "POST",
        requires_auth = false,
        -- unsure of this
        requires_anonymous_session = false
    },
    -- Query used to get user info from hover cards. Doesn't include a bio/links, has almost everything else.
    user_hover_info = {
        doc_id = "26785645987802781",
        endpoint = "api",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = true
    },
}

local queries = {
    anon_comments_pagination = function(media_id, cursor)
        return {
            after = cursor,
            first = 10,
            media_id = media_id
        }, doc_ids.anon_comments_pagination
    end,
    user_info = function(user_id)
        return {
            enable_integrity_filters = true,
            id = user_id,
            __relay_internal__pv__PolarisCannesGuardianExperienceEnabledrelayprovider = true,
            __relay_internal__pv__PolarisCASB976ProfileEnabledrelayprovider = false,
            __relay_internal__pv__PolarisWebSchoolsEnabledrelayprovider = false,
            __relay_internal__pv__PolarisRepostsConsumptionEnabledrelayprovider = true,
            __relay_internal__pv__PolarisShortDramaEnabledrelayprovider = false,
        }, doc_ids.user_info
    end,
    user_posts = function(username, count, after_cursor)
        return {
            after = after_cursor or json.null,
            before = json.null,
            data = {
                count = count,
                include_reel_media_seen_timestamp = true,
                include_relationship_info = true,
                latest_besties_reel_media = true,
                latest_reel_media = true
            },
            first = 12,
            include_multi_captions = false,
            last = json.null,
            username = username,
            __relay_internal__pv__PolarisMultiCaptionCarouselEnabledrelayprovider = false,
            __relay_internal__pv__PolarisShortDramaEnabledrelayprovider = false,
            __relay_internal__pv__PolarisAIGMAccountLabelEnabledrelayprovider = false,
            __relay_internal__pv__PolarisReelsRecoDebugOverlayEnabledrelayprovider = false,
        }, doc_ids.user_posts
    end,
    user_reels = function(user_id, after_cursor)
        local before
        if after_cursor then
            before = json.null
        end

        return {
            data = {
                include_feed_video = true,
                page_size = 12,
                target_user_id = user_id,
            },
            after = after_cursor,
            before = before
        }, doc_ids.user_reels
    end,
    search = function(query)
        return {
            hasQuery = true,
            data = {
                query = query
            }
        }, doc_ids.search
    end,
    explore_search = function(query, after)
        return {
            after = after or json.null,
            debug = json.null,
            keyword = query,
            media_count = 8
        }, doc_ids.explore_search
    end,
    shortcode_post_info = function(shortcode)
        return {
            shortcode = shortcode,
            __relay_internal__pv__PolarisAIGMMediaWebLabelEnabledrelayprovider = false
        }, doc_ids.shortcode_post_info
    end,
    media_id_post_info = function(media_id)
        return {
            media_id = media_id,
        }, doc_ids.media_id_post_info
    end,
    popular_page = function()
        return {}, doc_ids.popular_page
    end,
    user_hover_info = function(target_id)
        return {
            userID = target_id,
            __relay_internal__pv__PolarisAIGMAccountLabelEnabledrelayprovider = false
        }, doc_ids.user_hover_info
    end,
}


local function cooldown(doc_id)
    if config.ratelimits.cooldown_on_ratelimit then
        -- Get the remaining ttl on the key
        local key_ttl = web_state:ttl("graphql:" .. doc_id)
        local count = web_state:get("graphql:" .. doc_id)
        ngx.log(ngx.WARN, "Rate limit hit on " .. tostring(doc_id) .. " after " .. tostring(count) .. " requests.")
        if key_ttl and key_ttl > 0 then
            web_state:replace("graphql:" .. doc_id, REQUEST_LIMIT + 999, key_ttl)
        else
            web_state:replace("graphql:" .. doc_id, REQUEST_LIMIT + 999, WINDOW_LENGTH)
        end
    end
end

local function graphql_request(request_payload, doc_id, request_type)
    -- count the total number of requests sent using that doc_id, in an 11 minute window.
    -- Instagram ratelimits each server to 200 requests/11 minute window for most doc_ids.
    -- some instances may have workarounds in place, so they can disable the cooldown in their config.
    -- Note that the 200 reqs / 11 minutes ratelimit does not apply to most server/datacenter ips, those are ratelimited much more aggressively, and in most cases entirely blocked.
    local request_count = web_state:incr("graphql:" .. doc_id.doc_id, 1, 0, WINDOW_LENGTH)
    if request_count > REQUEST_LIMIT and config.ratelimits.cooldown_on_ratelimit then
        return errors.ratelimited{
            message = "The server has blocked further requests to Instagram temporarily.",
        }
    end

    local cookie, lsd

    -- Add cookies to request if the request supports it.
    if config.web_session and config.web_session.cookies then
        if config.web_session.use_for and config.web_session.use_for[request_type] then
            if not doc_id.requires_anonymous_session then
                cookie = config.web_session.cookies
            end
        end
    end

    local request_body = ""
    local request_url = gql_endpoints[doc_id.endpoint]

    -- This endpoint requires extra information
    if doc_id.endpoint == "api" then
        lsd = encoding.encode_base64(math.random())
            :gsub("+", "-")
            :gsub("/", "_")
            :gsub("=", "")

        request_body = "av=0&__d=www&__user=0&__a=1&__comet_req=7&lsd=" .. lsd .. "&server_timestamps=true&"
    end
    -- some queries are sent through get requests.
    if doc_id.method == "GET" then
        request_body = "doc_id=" .. doc_id.doc_id .. "&variables=" .. util.escape(json.encode(request_payload))
        request_url = request_url .. "?" .. request_body
    else
        request_body = request_body .. "variables=" .. util.escape(json.encode(request_payload)) .. "&doc_id=" .. doc_id.doc_id
    end

    local headers = create_headers(lsd, cookie)
    local request_opts = {
        method = doc_id.method,
        headers = headers
    }

    if doc_id.method == "POST" then
        request_opts.body = request_body
    end

    -- check if there is a proxy url for the request type.
    if request_type and config.proxies[request_type] then
        request_opts.proxy_opts = { https_proxy = config.proxies[request_type] }
    end


    local request, err = http_request(request_url, request_opts)

    if config.include_debug_headers then
        ngx_resp.add_header("X-Kg-Debug-Endpoints", doc_id.doc_id)
    end

    if not request then
        ngx.log(ngx.ERR, "Network error: " .. err)
        return errors.network_error{
            blob = err
        }
    elseif request.status == 302 then
        -- Since a 302 usually indicates a ratelimit or block of some sort,
        cooldown(doc_id.doc_id)
        return errors.ratelimited{
            message = "Instagram returned 302 with location: " .. tostring(request.headers.location)
        }
    end

    local decode_status, decoded_body = helpers.safe_json_decode(request.body)

    if not decode_status then
        return errors.unknown{
            message = "Instagram returned invalid json. Status code: " .. request.status,
            blob = request.body
        }
    end

    if decoded_body.status == "fail" and decoded_body.require_login then
        cooldown(doc_id.doc_id)
        return errors.ratelimited{
            blob = decoded_body
        }
    elseif (decoded_body.data == json.null or not decoded_body.data) and decoded_body.errors then
        for _, gql_error in ipairs(decoded_body.errors) do
            if gql_error.code == 4630001 then
                return errors.not_found{
                    message = "Item (likely a user) not found.",
                    blob = decoded_body
                }
            elseif gql_error.code == 1675004 then
                cooldown(doc_id.doc_id)
                return errors.ratelimited{
                    blob = decoded_body
                }
            end
        end
        return errors.unknown{
            blob = decoded_body
        }
    elseif not decoded_body.data or decoded_body.data == json.null then
        return errors.unknown{
            message = "`data` field not present in response.",
            blob = decoded_body
        }
    else
        return decoded_body
    end
end

return { request = graphql_request, queries = queries, doc_ids = doc_ids }
