local instagram_graphql_request = require("lib.instagram.web.graphql").request
local helpers = require("lib.helpers")
local queries = require("lib.instagram.web.graphql").queries
local ig_api = require("lib.instagram.web.api")
local errors = require("lib.helpers").create_error
local json = require("cjson")
local config = require("lapis.config").get()
local cache = require("lib.cache")
local get_user_id = require("lib.instagram.web.get_user_id_web")
local user_id_db = require("models.user_ids")
local format_post = require("lib.formatters").format_post

local USER_INFO_EXPIRE_TIME = config.cache.expire_times.user_info.positive
local LATEST_USER_TIMELINE_EXPIRE_TIME = config.cache.expire_times.user_timelines.latest
local CURSORED_USER_TIMELINE_EXPIRE_TIME = config.cache.expire_times.user_timelines.with_cursor
local NEGATIVE_USER_TIMELINE_EXPIRE_TIME = config.cache.expire_times.user_timelines.negative

local function get_user_posts(username, cursor)
    if not cursor then
        local timeline_query = cache.query_item("ig:timeline:" .. username .. ":latest")
        if timeline_query ~= ngx.null then
            return timeline_query
        end
    elseif cursor then
        local timeline_query = cache.query_item("ig:timeline:" .. username .. ":" .. cursor)
        if timeline_query ~= ngx.null then
            return timeline_query
        end
    end


    local payload, doc_id = queries.user_posts(username, 20, cursor)
    local posts_request = instagram_graphql_request(payload, doc_id, "user_posts")

    if posts_request.has_errors then
        if posts_request.error_type == "not_found" then
            local key
            if cursor then
                key = "ig:timeline:" .. username .. ":" .. cursor
            else
                key = "ig:timeline:" .. username .. ":latest"
            end
            cache.cache_item(key, posts_request, "negative_timeline")
        end
        return posts_request
    end
    -- Check if there is posts in the response.
    if not posts_request.errors and helpers.check_nested_field(posts_request, "data", "xdt_api__v1__feed__user_timeline_graphql_connection", "edges") then
        local posts = posts_request.data.xdt_api__v1__feed__user_timeline_graphql_connection.edges
        local end_cursor = posts_request.data.xdt_api__v1__feed__user_timeline_graphql_connection.page_info.end_cursor

        if not cursor then
            cache.cache_item("ig:timeline:" .. username .. ":latest", {
                posts = posts,
                end_cursor = end_cursor
            }, "latest_timeline")
        elseif cursor then
            cache.cache_item("ig:timeline:" .. username .. ":" .. cursor, {
                posts = posts,
                end_cursor = end_cursor,
            }, "cursored_timeline")
        end
        cache.cache_timeline(posts)
        return { posts = posts, end_cursor = end_cursor }
    end

    return errors.unknown{
        blob = posts_request
    }
end

local function get_user_reels(user_id, cursor)
    local key = "ig:reel_timeline:" .. user_id .. ":" .. (cursor or "latest")

    local query = cache.query_item(key)
    if query ~= ngx.null then
        return query.posts, query.end_cursor
    end

    local endpoint, params = ig_api.endpoints.user_reels, ig_api.construct_params.user_reels(user_id, cursor)
    local request = ig_api.request(endpoint, params, "user_posts")
    if request.has_errors then
        return request
    else
        local reels_formatted = {}
        for _, reel in ipairs(request.items) do
            local formatted_reel = format_post.from_reel_timeline(reel)
            table.insert(reels_formatted, formatted_reel)
        end
        local posts_with_cursor = {
            posts = reels_formatted,
            end_cursor = request.paging_info.max_id
        }
        local cache_time_type
        if cursor then
            cache_time_type = "cursored_timeline"
        else
            cache_time_type = "latest_timeline"
        end
        cache.cache_item(key, posts_with_cursor, cache_time_type)
        return reels_formatted, request.paging_info.max_id
    end
end

local function get_user_hover_info(user_id)
    local key = "ig:user_hover_info:" .. user_id
    local cache_query = cache.query_item(key)
    if cache_query ~= ngx.null then
        return cache_query
    end

    local payload, doc_id = queries.user_hover_info(user_id)
    local info_request = instagram_graphql_request(payload, doc_id, "user_info")

    if info_request.has_errors then
        return info_request
    end

    if info_request.data and info_request.data.xig_user_by_igid_v2 then
        if info_request.data.xig_user_by_igid_v2 == json.null then
            return errors.not_found{ message = "Hover card info is null.", blob = info_request }
        else
            cache.cache_item(key, info_request.data.xig_user_by_igid_v2.user_dict, "user_info")
            return info_request.data.xig_user_by_igid_v2.user_dict
        end
    end

    return errors.unknown{ message = "Unknown error occured."}
end

-- Function to get user info from an id.
local function get_user_info(user_id)
    local user_query = cache.query_item("ig:user:" .. user_id)

    if user_query ~= ngx.null then
        return user_query
    end

    local payload, doc_id = queries.user_info(user_id)
    local user_info = instagram_graphql_request(payload, doc_id, "user_info")

    if user_info.has_errors then
        -- try getting info from hover cards, they contain less information, so they're used as a fallback.
        if user_info.error_type == "ratelimited" then
            return get_user_hover_info(user_id)
        else
            return user_info
        end
    end

    cache.cache_item("ig:user:" .. user_id, user_info.data.user, "user_info")

    return user_info.data.user
end


-- Instagram fetches user info based on ids,
-- fetching posts also returns the user's id. I can then fetch the user info based on that.
-- If a user has no posts (or is private), then their userid is retrieved from their user page.
-- All user ids are stored for later use, as profile pages are ratelimited heavily.

local function arrange_user_data(username, after_cursor, timeline_type)
    if timeline_type == "reel" then
        local user_id = user_id_db.get_user_id(username)
        if not user_id then
            user_id = get_user_id(username)
        end

        if type(user_id) == "table" and user_id.has_errors then
            return user_id
        elseif not user_id then
            return errors.not_found{
                message = "User's id couldn't be found from page.",
                blob = user_id
            }
        end
        local user_info = get_user_info(user_id)
        local user_posts, cursor = get_user_reels(user_id, after_cursor)
        if user_posts.has_errors then
            return user_posts
        end
        return { user_info = user_info, posts = user_posts, end_cursor = cursor}
    end

    local user_posts = {}
    local user_id
    -- check if a cursor is present (for pagination)
    if after_cursor then
        user_posts = get_user_posts(username, after_cursor)
    else
        user_posts = get_user_posts(username)
    end

    if user_posts.has_errors then
        return user_posts
    end

    if #user_posts.posts < 1 then
        if user_id_db.get_user_id(username) then
            user_id = user_id_db.get_user_id(username)
        else
            user_id = get_user_id(username)
            if user_id.has_errors then
                return user_id
            else
                -- save id for later.
                user_id_db.save_user_id(username, user_id)
            end
        end
    else
        -- Check if a post has coauthors. Usually an indication they are a repost.
        if helpers.check_nested_field(user_posts.posts[1], "node", "coauthor_producers") and user_posts.posts[1].node.coauthor_producers ~= json.null and #user_posts.posts[1].node.coauthor_producers >= 1 then
            -- Iterate over the coauthors to see if one of them has a username which matches the provided username.
            for _, coauthor in ipairs(user_posts.posts[1].node.coauthor_producers) do
                if string.lower(coauthor.username) == string.lower(username) then
                    user_id = coauthor.id
                end
            end
            -- if a user id is not set, then use the id of the user who owns the post itself.
            if not user_id then
                user_id = user_posts.posts[1].node.user.id
            end
        else
            user_id = user_posts.posts[1].node.user.id
            -- check that the username instagram returns matches the provided username to avoid saving an incorrect id.
            if string.lower(username) == string.lower(user_posts.posts[1].node.user.username) then
                 user_id_db.save_user_id(user_posts.posts[1].node.user.username, user_id)
            end
        end
    end


    local user_info = get_user_info(user_id)

    local formatted_posts = {}
    for _, post in ipairs(user_posts.posts) do
        table.insert(formatted_posts, format_post.from_timeline(post))
    end

    user_posts.posts = formatted_posts

    return {
        posts = user_posts.posts,
        user_info = user_info,
        end_cursor = user_posts.end_cursor
    }
end

return arrange_user_data
