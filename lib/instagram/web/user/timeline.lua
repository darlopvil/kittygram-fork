local graphql = require("lib.instagram.web.graphql")
local ig_api = require("lib.instagram.web.api")
local user_db = require("models.users")
local cache = require("lib.cache")
local json = require("cjson")
local formatters = require("lib.formatters")
local encoding = require("lapis.util.encoding")

local function derive_id_from_timeline(posts, username)
    local user_id
    if posts[1] then
        local first_post = posts[1]
        -- Check if a post has coauthors. Usually an indication they are a repost.
        if first_post.coauthors then
            -- Iterate over the coauthors to see if one of them has a username which matches the provided username.
            for _, coauthor in ipairs(first_post.coauthors) do
                if string.lower(coauthor.username) == string.lower(username) then
                    user_id = coauthor.id
                end
                user_db.save_user(coauthor)
            end
                -- if a user id is not set, then use the id of the user who owns the post itself.
                if not user_id then
                    user_id = first_post.user.id
                end
        else
            user_id = first_post.user.id
            user_db.save_user(first_post.user)
        end
    end

    return user_id
end

local function get_timeline(username, cursor, page_data)

    local decoded_cursor
    if cursor then
        local decoded_cursor_table = json.decode(encoding.decode_base64(cursor))
        decoded_cursor = decoded_cursor_table.cursor
    end

    local key = "ig:timeline:" .. username .. ":" .. (decoded_cursor or "latest")

    local timeline_query = cache.query_item(key)
    if timeline_query ~= ngx.null then
        return timeline_query
    end

    local payload, doc_id = graphql.queries.user_posts(username, 20, decoded_cursor)
    local posts = graphql.query_and_format(payload, doc_id, formatters.format_timeline.from_timeline_graphql, {
        purpose = "user_posts",
        extra_formatter_data = { page_data },
        page_data = page_data
    })

    if posts.has_errors then
        if posts.error_type == "not_found" then
            cache.cache_item(key, posts, "negative_timeline")
        end
        return posts
    end

    local timeline_cache_type
    if not cursor then
        timeline_cache_type = "latest_timeline"
    elseif cursor then
        timeline_cache_type = "cursored_timeline"
    end

    cache.cache_item(key, posts, timeline_cache_type)
    cache.cache_timeline(posts)
    return posts, derive_id_from_timeline(posts.items, username)
end

local function get_reel_timeline(user_id, cursor, page_data)
    local decoded_cursor
    if cursor then
        local decoded_cursor_table = json.decode(encoding.decode_base64(cursor))
        decoded_cursor = decoded_cursor_table.cursor
    end

    local key = "ig:timeline:reels:" .. user_id .. ":" .. (decoded_cursor or "latest")

    local query = cache.query_item(key)
    if query ~= ngx.null then
        return query
    end

    local endpoint, params = ig_api.endpoints.user_reels, ig_api.construct_params.user_reels(user_id, decoded_cursor)
    local request = ig_api.request(endpoint, params, "user_posts")

    if request.has_errors then
        return request
    else
        local formatted = formatters.format_timeline.from_reel_api(request, page_data)

        local cache_time_type
        if cursor then
            cache_time_type = "cursored_timeline"
        else
            cache_time_type = "latest_timeline"
        end
        cache.cache_item(key, formatted, cache_time_type)
        cache.cache_timeline(formatted)
        return formatted
    end
end

return {
    derive_id_from_timeline = derive_id_from_timeline,
    get_reel_timeline = get_reel_timeline,
    get_timeline = get_timeline,
}
