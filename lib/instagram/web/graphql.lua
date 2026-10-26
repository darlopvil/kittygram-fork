local encoding = require("lapis.util.encoding")
local helpers = require("lib.helpers")
local http_request = require("lib.http")
local json = require("cjson")
local util = require("lapis.util")
local errors = helpers.create_error
local config = require("lapis.config").get()
local ngx_resp = require("ngx.resp")
local web_state = ngx.shared.web_state
local session = require("lib.instagram.web.session")

local WINDOW_LENGTH = config.ratelimits.window_length
local REQUEST_LIMIT = config.ratelimits.request_limit

local function create_headers(lsd, csrftoken, friendly_name, cookie)
    local headers = {
        { "accept", "*/*" },
        { "content-type", "application/x-www-form-urlencoded" },
        { "cookie", cookie },
        {
            "user-agent",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36",
        },
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
        { "x-csrftoken", csrftoken or "exampletexthere" },
        { "x-fb-friendly_name", friendly_name },
        { "x-fb-lsd", lsd },
        { "x-ig-app-id", "936619743392459" },
        { "x-ig-max-touch-points", "0" },
    }

    return headers
end

local gql_endpoints = {
    query = "https://www.instagram.com/graphql/query",
    api = "https://www.instagram.com/api/graphql",
}

local doc_ids = {
    user_info = {
        doc_id = "38611279431804694",
        query_name = "PolarisProfilePageContentQuery",
        endpoint = "api",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = false,
    },
    anon_comments_pagination = {
        doc_id = "27261273046856309",
        query_name = "PolarisLoggedOutDesktopWWWPostCommentsPaginationQuery",
        endpoint = "api",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = true,
    },
    search = {
        doc_id = "27706427925724183",
        query_name = "PolarisSearchBoxRefetchableQuery",
        endpoint = "api",
        method = "POST",
        requires_auth = true,
        requires_anonymous_session = false,
    },
    user_posts = {
        doc_id = "37691262543822084",
        query_name = "PolarisProfilePostsQuery",
        endpoint = "api",
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
    shortcode_post_info = {
        doc_id = "26713194205046842",
        query_name = "PolarisPostRootQuery",
        endpoint = "api",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = true,
    },
    media_id_post_info = {
        doc_id = "27130156389949648",
        query_name = "PolarisLoggedOutDesktopWWWPostRootContentQuery",
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
        requires_anonymous_session = false,
    },
    -- Query used to get user info from hover cards. Doesn't include a bio/links, has almost everything else.
    user_hover_info = {
        doc_id = "27756568060663620",
        query_name = "PolarisUserHoverCardContentV2Query",
        endpoint = "api",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = true,
    },
    anon_user_info = {
        doc_id = "27981003384861049",
        query_name = "PolarisLoggedOutDesktopWWWProfileRootContentQuery",
        endpoint = "api",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = true,
    },
    anon_initial_grid = {
        doc_id = "27553725110923321",
        query_name = "PolarisLoggedOutDesktopWWWProfilePostsTabContentQuery",
        endpoint = "api",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = true,
    },
    anon_paginated_grid = {
        doc_id = "27389614800735091",
        query_name = "PolarisLoggedOutDesktopWWWProfilePostsTabContentQuery_connection",
        endpoint = "api",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = true,
    },
    anon_reel_initial_grid = {
        doc_id = "27838951732404191",
        query_name = "PolarisLoggedOutDesktopWWWProfileReelsTabContentQuery",
        endpoint = "api",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = true,
    },
    anon_reel_paginated_grid = {
        doc_id = "27420265870989234",
        query_name = "PolarisLoggedOutDesktopWWWProfileReelsTabContentQuery_connection",
        endpoint = "api",
        method = "POST",
        requires_auth = false,
        requires_anonymous_session = true,
    },
    -- Stories and highlights, web session only. Only the media is requested:
    -- the "seen" mutations (PolarisAPIReelSeenMutation,
    -- PolarisAPIForceStorySeenMutation) are never sent.
    reels_media = {
        doc_id = "28449850404637481",
        query_name = "PolarisStoriesV3ReelPageStandaloneQuery",
        endpoint = "api",
        method = "POST",
        requires_auth = true,
        requires_anonymous_session = false,
    },
    highlights_tray = {
        doc_id = "26970053832668570",
        query_name = "PolarisProfileStoryHighlightsTrayContentQuery",
        endpoint = "api",
        method = "POST",
        requires_auth = true,
        requires_anonymous_session = false,
    },
    -- Posts a profile is tagged in, web session only.
    tagged_posts = {
        doc_id = "28512785875070926",
        query_name = "PolarisProfileTaggedTabContentQuery",
        endpoint = "api",
        method = "POST",
        requires_auth = true,
        requires_anonymous_session = false,
    },
    tagged_posts_paginated = {
        doc_id = "28555803087449153",
        query_name = "PolarisProfileTaggedTabContentQuery_connection",
        endpoint = "api",
        method = "POST",
        requires_auth = true,
        requires_anonymous_session = false,
    },
}

-- Instagram rotates doc_ids regularly. config.graphql_overrides lets an
-- instance replace doc_id / query_name / endpoint per query without a rebuild,
-- e.g. graphql_overrides = { search = { doc_id = "123" } }
for key, override in pairs(config.graphql_overrides or {}) do
    if doc_ids[key] and type(override) == "table" then
        for _, field in ipairs { "doc_id", "query_name", "endpoint" } do
            if override[field] then
                doc_ids[key][field] = tostring(override[field])
            end
        end
    else
        ngx.log(ngx.WARN, "[graphql] ignoring unknown override: ", tostring(key))
    end
end

local function uuid4()
    return (
        string.gsub("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx", "[xy]", function(c)
            local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
            return string.format("%x", v)
        end)
    )
end

local queries = {
    anon_comments_pagination = function(media_id, cursor)
        return {
            after = cursor,
            first = 10,
            media_id = media_id,
        },
            doc_ids.anon_comments_pagination
    end,
    user_info = function(user_id)
        return {
            enable_integrity_filters = true,
            id = user_id,
            render_surface = "PROFILE",
            __relay_internal__pv__PolarisCannesGuardianExperienceEnabledrelayprovider = true,
            __relay_internal__pv__PolarisCASB976ProfileEnabledrelayprovider = false,
            __relay_internal__pv__PolarisWebSchoolsEnabledrelayprovider = false,
            __relay_internal__pv__PolarisRepostsConsumptionEnabledrelayprovider = true,
            __relay_internal__pv__PolarisShortDramaEnabledrelayprovider = false,
            __relay_internal__pv__PolarisLongformEnabledrelayprovider = false,
        },
            doc_ids.user_info
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
                latest_reel_media = true,
            },
            first = 12,
            include_multi_captions = false,
            last = json.null,
            username = username,
            __relay_internal__pv__PolarisMultiCaptionCarouselEnabledrelayprovider = false,
            __relay_internal__pv__PolarisShortDramaEnabledrelayprovider = false,
            __relay_internal__pv__PolarisAIGMAccountLabelEnabledrelayprovider = false,
            __relay_internal__pv__PolarisReelsRecoDebugOverlayEnabledrelayprovider = false,
        },
            doc_ids.user_posts
    end,
    search = function(query)
        return {
            data = {
                context = "blended",
                include_reel = "true",
                query = query,
                rank_token = "",
                search_session_id = uuid4(),
                search_surface = "web_top_search",
            },
            hasQuery = true,
        }, doc_ids.search
    end,
    explore_search = function(query, after)
        return {
            after = after or json.null,
            debug = json.null,
            keyword = query,
            media_count = 8,
        },
            doc_ids.explore_search
    end,
    shortcode_post_info = function(shortcode)
        return {
            shortcode = shortcode,
            __relay_internal__pv__PolarisAIGMMediaWebLabelEnabledrelayprovider = false,
        },
            doc_ids.shortcode_post_info
    end,
    media_id_post_info = function(media_id)
        return {
            media_id = media_id,
        }, doc_ids.media_id_post_info
    end,
    reels_media = function(reel_ids)
        return {
            reel_ids_arr = reel_ids,
            __relay_internal__pv__PolarisCommunityNoteStoriesLabelEnabledrelayprovider = true,
        }, doc_ids.reels_media
    end,
    highlights_tray = function(user_id)
        return { user_id = user_id }, doc_ids.highlights_tray
    end,
    tagged_posts = function(user_id)
        return {
            count = 12,
            user_id = user_id,
            __relay_internal__pv__PolarisShortDramaEnabledrelayprovider = true,
            __relay_internal__pv__PolarisSEOIsCrawlerrelayprovider = false,
        }, doc_ids.tagged_posts
    end,
    tagged_posts_paginated = function(user_id, after)
        return {
            after = after,
            before = json.null,
            count = 12,
            first = 12,
            last = json.null,
            user_id = user_id,
            __relay_internal__pv__PolarisShortDramaEnabledrelayprovider = true,
            __relay_internal__pv__PolarisSEOIsCrawlerrelayprovider = false,
        }, doc_ids.tagged_posts_paginated
    end,
    popular_page = function()
        return {}, doc_ids.popular_page
    end,
    user_hover_info = function(target_id)
        return {
            userID = target_id,
            __relay_internal__pv__PolarisAIGMAccountLabelEnabledrelayprovider = false,
        },
            doc_ids.user_hover_info
    end,
    anon_user_info = function(username)
        return {
            username = username,
        }, doc_ids.anon_user_info
    end,
    anon_initial_grid = function(username)
        return {
            first = 12,
            username = username,
        }, doc_ids.anon_initial_grid
    end,
    anon_paginated_grid = function(cursor, id)
        return {
            after = cursor,
            first = 12,
            id = id,
        }, doc_ids.anon_paginated_grid
    end,
    anon_reel_initial_grid = function(username)
        return {
            first = 12,
            username = username,
        }, doc_ids.anon_reel_initial_grid
    end,
    anon_reel_paginated_grid = function(cursor, id)
        return {
            after = cursor,
            first = 12,
            id = id,
        }, doc_ids.anon_reel_paginated_grid
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

local default_tokens = {
    haste_session = "20681.HYP:instagram_web_pkg.2.1...0",
    spin_b = "trunk",
    spin_r = "1045311908",
    revision = "1045311908",
    connection_class = "EXCELLENT",
    actor_id = "0",
    lsd = encoding.encode_base64(math.random()):gsub("+", "-"):gsub("/", "_"):gsub("=", ""),
    csrf_token = encoding.encode_base64(math.random()):gsub("+", "-"):gsub("/", "_"):gsub("=", ""),
    hsi = "7674722996112187910",
    comet_env = "7",
}

local function graphql_request(request_payload, doc_id, request_type, page_info, retried)
    -- count the total number of requests sent using that doc_id, in an 11 minute window.
    -- Instagram ratelimits each server to 200 requests/11 minute window for most doc_ids.
    -- some instances may have workarounds in place, so they can disable the cooldown in their config.
    -- Note that the 200 reqs / 11 minutes ratelimit does not apply to most server/datacenter ips, those are ratelimited much more aggressively, and in most cases entirely blocked.
    local request_count = web_state:incr("graphql:" .. doc_id.doc_id, 1, 0, WINDOW_LENGTH)
    if request_count > REQUEST_LIMIT and config.ratelimits.cooldown_on_ratelimit then
        return errors.ratelimited {
            message = "The server has blocked further requests to Instagram temporarily.",
        }
    end

    local cookie
    -- Add cookies to request if the request supports it.
    if config.web_session and config.web_session.cookies then
        if config.web_session.use_for and config.web_session.use_for[request_type] then
            if not doc_id.requires_anonymous_session then
                cookie = config.web_session.cookies
            end
        end
    end

    local request_url = gql_endpoints[doc_id.endpoint]
    if cookie then
        -- Authenticated requests must use tokens bound to the session.
        local tokens, session_err = session.get_tokens()
        if not tokens then
            return errors.unknown {
                message = "Could not start the web session: " .. tostring(session_err),
            }
        end
        page_info = tokens
    elseif not page_info or page_info == {} then
        page_info = default_tokens
    end

    local unencoded_body = {
        { "av", page_info.actor_id },
        { "__d", "www" },
        { "__user", "0" },
        { "__a", "1" },
        { "__hs", page_info.haste_session },
        -- TODO: Don't hardcode this.
        { "dpr", "1" },
        { "__ccg", page_info.connection_class },
        { "__rev", page_info.revision },
        { "__hsi", page_info.hsi },
        { "__comet_req", page_info.comet_env },
        { "lsd", page_info.lsd },
        { "fb_dtsg", page_info.fb_dtsg },
        { "jazoest", page_info.jazoest },
        { "__spin_r", page_info.spin_r },
        { "__spin_b", page_info.spin_b },
        { "__spin_t", page_info.spin_t },
        { "__crn", page_info.canonical_route_name },
        { "fb_api_caller_class", "RelayModern" },
        { "fb_api_req_friendly_name", doc_id.query_name },
        { "server_timestamps", "true" },
        { "variables", json.encode(request_payload) },
        { "doc_id", doc_id.doc_id },
    }

    local request_body
    -- some queries are sent through get requests.
    if doc_id.method == "GET" then
        request_body = "doc_id=" .. doc_id.doc_id .. "&variables=" .. util.escape(json.encode(request_payload))
        request_url = request_url .. "?" .. request_body
    else
        request_body = helpers.encode_query_string(unencoded_body)
    end

    local headers = create_headers(page_info.lsd, page_info.csrf_token, doc_id.query_name, cookie)
    if cookie then
        session.apply_headers(headers)
    end
    local request_opts = {
        method = doc_id.method,
        headers = headers,
    }

    if doc_id.method == "POST" then
        request_opts.body = request_body
    end

    -- check if there is a proxy url for the request type.
    if request_type and config.proxies[request_type] then
        request_opts.proxy_opts = { https_proxy = config.proxies[request_type] }
    end

    local request, err = http_request(request_url, request_opts)

    -- Stale session tokens: drop them and retry once with fresh ones.
    if request and cookie and not retried and session.is_rejection(request) then
        session.invalidate()
        return graphql_request(request_payload, doc_id, request_type, nil, true)
    end

    if config.include_debug_headers then
        ngx_resp.add_header("X-Kg-Debug-Endpoints", doc_id.doc_id)
    end

    if not request then
        ngx.log(ngx.ERR, "Network error: " .. err)
        return errors.network_error {
            blob = err,
        }
    elseif request.status == 302 then
        -- Since a 302 usually indicates a ratelimit or block of some sort,
        cooldown(doc_id.doc_id)
        return errors.ratelimited {
            message = "Instagram returned 302 with location: " .. tostring(request.headers.location),
        }
    end

    -- Instagram prefixes some error responses with an anti-JSON-hijacking guard.
    local body = (request.body or ""):gsub("^for %(;;%);", "")
    local decode_status, decoded_body = helpers.safe_json_decode(body)

    if not decode_status then
        return errors.unknown {
            message = "Instagram returned invalid json. Status code: " .. request.status,
            blob = request.body,
        }
    end

    if decoded_body.status == "fail" and decoded_body.require_login then
        cooldown(doc_id.doc_id)
        return errors.ratelimited {
            blob = decoded_body,
        }
    elseif (decoded_body.data == json.null or not decoded_body.data) and decoded_body.errors then
        for _, gql_error in ipairs(decoded_body.errors) do
            if gql_error.code == 4630001 then
                return errors.not_found {
                    message = "Item (likely a user) not found.",
                    blob = decoded_body,
                }
            elseif gql_error.code == 1675004 then
                cooldown(doc_id.doc_id)
                return errors.ratelimited {
                    blob = decoded_body,
                }
            end
        end
        return errors.unknown {
            blob = decoded_body,
        }
    elseif not decoded_body.data or decoded_body.data == json.null then
        return errors.unknown {
            message = "`data` field not present in response.",
            blob = decoded_body,
        }
    else
        return decoded_body
    end
end

local function query_and_format(query, doc_id, formatter, options)
    options = options or {}
    local request = graphql_request(query, doc_id, options.purpose, options.page_data)
    if request.has_errors then
        return request
    end

    local formatted = formatter(request.data, table.unpack(options.extra_formatter_options or {}))

    return formatted
end

return {
    request = graphql_request,
    queries = queries,
    doc_ids = doc_ids,
    query_and_format = query_and_format,
}
