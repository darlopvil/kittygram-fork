local instagram_graphql_request = require("lib.instagram.web.graphql").request
local helpers = require("lib.helpers")
local queries = require("lib.instagram.web.graphql").queries
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

    elseif posts_request.errors and posts_request.errors[1].code == 4630001 then
        local timeline_error = errors.not_found{
            message = "User not found.",
            blob = posts_request
        }
        local key
        if cursor then
            key = "ig:timeline:" .. username .. ":" .. cursor
        else
            key = "ig:timeline:" .. username .. ":latest"
        end
        cache.cache_item(key, timeline_error, "negative_timeline")
        return timeline_error
    elseif posts_request.status == "fail" and posts_request.require_login == true then
        return errors.ratelimited{
            blob = posts_request
        }
    end

    return errors.unknown{
        blob = posts_request
    }
end

-- this could probably do with more error handling.
-- Since kittygram checks for posts first, that usually handles most errors
local function get_user_info(user_id)
    local user_query = cache.query_item("ig:user:" .. user_id)
    if user_query ~= ngx.null then
        return user_query
    end
    local payload, doc_id = queries.user_info(user_id)
    local user_info = instagram_graphql_request(payload, doc_id, "user_info")
    cache.cache_item("ig:user:" .. user_id, user_info.data.user, "user_info")

    return user_info.data.user
end





-- Instagram fetches user info based on ids,
-- fetching posts also returns the user's id. I can then fetch the user info based on that.
-- this method is pretty naive. Like the rest of this project :P
-- If a user has no posts (or is private), then their userid is retrieved from their user page.
-- All user ids are stored for later use, as profile pages are ratelimited heavily.

local function arrange_user_data(username, after_cursor)
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
    return {
        posts = user_posts.posts,
        user_info = user_info,
        end_cursor = user_posts.end_cursor
    }
end

return arrange_user_data
