local config = require("lapis.config").get()
local encoding = require("lapis.util.encoding")
local instagram_graphql_request = require("lib.instagram.web.graphql").request
local ig_api = require("lib.instagram.web.api")
local queries = require("lib.instagram.web.graphql").queries
local helpers = require("lib.helpers")
local format_comments = require("lib.formatters").format_comments
local cache = require("lib.cache")
local json = require("cjson")

local function get_comments_anon(post_id, encoded_cursor)
    local key = "ig:comments:" .. post_id .. ":" .. (encoded_cursor or "initial")
    local query = cache.query_item(key)
    if query ~= ngx.null then
        return query
    end

    local decoded_cursor
    if encoded_cursor then
        decoded_cursor = encoding.decode_base64(encoded_cursor)
    else
        decoded_cursor = json.null
    end

    local payload, doc_id = queries.anon_comments_pagination(post_id, decoded_cursor)
    local request = instagram_graphql_request(payload, doc_id, "comments")

    if request.has_errors then
        return request
    end

    if request.data and request.data.xig_polaris_media and request.data.xig_polaris_media.comments_connection then
        cache.bulk_save_users.from_comments(request.data.xig_polaris_media.comments_connection)
        local formatted_comments = format_comments.from_web_graphql(request.data.xig_polaris_media.comments_connection)
        cache.cache_item(key, formatted_comments, "comments")

        return formatted_comments
    end
end

local function get_comments_auth(post_id, encoded_cursor)
    local key = "ig:comments:" .. post_id .. ":" .. (encoded_cursor or "initial")
    local cache_query = cache.query_item(key)
    if cache_query ~= ngx.null then
        return cache_query
    end

    local cursor
    if encoded_cursor then
        cursor = encoding.decode_base64(encoded_cursor)
    end

    local endpoint, params = ig_api.endpoints.comments, ig_api.construct_params.comments(post_id, cursor)
    local request = ig_api.request(endpoint, params, "comments")

    if request.has_errors then
        return request
    end

    local formatted_comments = format_comments.from_web_api(request)
    cache.cache_item(key, formatted_comments, "comments")

    return formatted_comments
end

local function get_comments(post_id, cursor)
    if
        config.web_session
        and config.web_session.cookies
        and config.web_session.use_for
        and config.web_session.use_for.comments
    then
        return get_comments_auth(post_id, cursor)
    else
        return get_comments_anon(post_id, cursor)
    end
end

return get_comments
