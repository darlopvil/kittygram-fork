local http = require("resty.http")
local util = require("lapis.util")
local encoding = require("lapis.util.encoding")
local json = require("cjson")
local helpers = require("lib.helpers")
local config = require("lapis.config").get()

local instagram_headers = {
    ["X-IG-App-ID"] = "936619743392459",
    ["X-CSRFToken"] = "exampletexthere", -- this can be anything. I could get valid CSRF tokens, but this works for now.
    ["Content-Type"] = "application/x-www-form-urlencoded",
    ["Accept"] = "*/*"
}

local gql_endpoints = {
    query = "https://www.instagram.com/graphql/query",
    api = "https://www.instagram.com/api/graphql"
}

local doc_ids = {
    shortcode = {
        doc_id = "8845758582119845",
        endpoint = "query",
        method = "POST"
    },
    user_info = {
        doc_id = "33257018913889225",
        endpoint = "query",
        method = "POST"
    },
    comments = {
        doc_id = "25060748103519434",
        endpoint = "query",
        method = "POST"
    },
    search = {
        doc_id = "24146980661639222",
        endpoint = "query",
        method = "POST"
    },
    user_posts = {
        doc_id = "25570792892598075",
        endpoint = "query",
        method = "POST"
    },
    logged_out_user_posts = {
        doc_id = "7950326061742207",
        endpoint = "query",
        method = "GET"
    },
    explore_search = {
        doc_id = "33897670563213924",
        endpoint = "api",
        method = "POST"
    }
}

local queries = {
    shortcode = function(shortcode)
        return {
            shortcode = shortcode,
            fetch_tagged_user_count = json.null,
            hoisted_comment_id = json.null,
            hoisted_reply_id = json.null
        }, doc_ids.shortcode
    end,
    comments = function(post_id, sort_order)
        return {
            after = json.null, -- while an after_cursor _is_ exposed while logged out, this endpoint will only ever return the same page of comments when logged out.
            before = json.null,
            first = 30, -- I'm pretty sure this is the amount of comments to fetch at a time.
            last = json.null,
            media_id = post_id,
            sort_order = sort_order, -- leaving this at the default. would be cool to make this controllable.
            __relay_internal__pv__PolarisIsLoggedInrelayprovider = true
        }, doc_ids.comments
    end,
    user_info = function(user_id)
        return {
            enable_integrity_filters = true,
            id = user_id,
            render_surface = "PROFILE",
            __relay_internal__pv__PolarisProjectCannesLoggedInEnabledrelayprovider = true,
            __relay_internal__pv__PolarisCannesGuardianExperienceEnabledrelayprovider = true,
            __relay_internal__pv__PolarisCASB976ProfileEnabledrelayprovider = false,
            __relay_internal__pv__PolarisRepostsConsumptionEnabledrelayprovider = false
        }, doc_ids.user_info
    end,
    user_posts = function(username, count, after_cursor)
        if not after_cursor then
            after_cursor = json.null
        end
        return {
            after = after_cursor,
            before = json.null,
            data = {
                count = count,
                include_reel_media_seen_timestamp = true, -- no idea what this stuff does, but the requests fail without them ¯\_(ツ)_/¯
                include_relationship_info = true,
                latest_besties_reel_media = true,
                latest_reel_media = true
            },
            first = 12,
            last = json.null,
            username = username,
            __relay_internal__pv__PolarisIsLoggedInrelayprovider = true, -- no idea what this does either
            __relay_internal__pv__PolarisShareSheetV3relayprovider = true
        }, doc_ids.user_posts
    end,
    logged_out_user_posts = function(user_id, count, after_cursor)
        if not after_cursor then
            after_cursor = json.null
        end
        return {
            id = user_id,
            after = after_cursor,
            first = count
        }, doc_ids.logged_out_user_posts
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
    end
}

local function graphql_request(request_payload, doc_id, request_type)
    local httpc = http.new()

    local headers = instagram_headers
    local request_body = ""
    local request_url = gql_endpoints[doc_id.endpoint]

    -- This endpoint requires extra information
    if doc_id.endpoint == "api" then
        local lsd = encoding.encode_base64(math.random())
            :gsub("+", "-")
            :gsub("/", "_")
            :gsub("=", "")

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
        headers = instagram_headers
    }

    if doc_id.method == "POST" then
        request_opts.body = request_body
    end

    -- check if there is a proxy url for the request type.
    if request_type and config.proxies[request_type] then
        request_opts.proxy_opts = { https_proxy = config.proxies[request_type] }
    end

    local request, err = httpc:request_uri(request_url, request_opts)

    if not request then
        ngx.log(ngx.ERR, err)
    end

    return json.decode(request.body)
end

return { request = graphql_request, queries = queries }
