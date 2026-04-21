local instagram_graphql_request = require("lib.graphql").request
local helpers = require("lib.helpers")
local queries = require("lib.graphql").queries
local errors = require("lib.helpers").create_error
local json = require("cjson")
local config = require("lapis.config").get()
local get_redis = require("lapis.redis").get_redis
local get_user_id = require("lib.get_user_id_web")
local user_id_db = require("models.user_ids")
local format_post = require("lib.formatters").format_post

local USER_INFO_EXPIRE_TIME = config.cache.expire_times.user_info.positive
local LATEST_USER_TIMELINE_EXPIRE_TIME = config.cache.expire_times.user_timelines.latest
local CURSORED_USER_TIMELINE_EXPIRE_TIME = config.cache.expire_times.user_timelines.with_cursor
local NEGATIVE_USER_TIMELINE_EXPIRE_TIME = config.cache.expire_times.user_timelines.negative

local function get_user_posts(username, cursor)
    local redis = get_redis()
    if redis then
        if not cursor then
            local timeline_query = redis:get("ig:timeline:" .. username .. ":latest")
            if timeline_query ~= ngx.null then
                return json.decode(timeline_query)
            end
        elseif cursor then
            local timeline_query = redis:get("ig:timeline:" .. username .. ":" .. cursor)
            if timeline_query ~= ngx.null then
                return json.decode(timeline_query)
            end
        end
    else
        ngx.log(ngx.ERR, "Redis connection failed")
    end

    local payload, doc_id = queries.user_posts(username, 20, cursor)
    local posts_request = instagram_graphql_request(payload, doc_id, "user_posts")
    -- Check if there is posts in the response.
    if not posts_request.errors and helpers.check_nested_field(posts_request, "data", "xdt_api__v1__feed__user_timeline_graphql_connection", "edges") then
        local posts = posts_request.data.xdt_api__v1__feed__user_timeline_graphql_connection.edges
        local end_cursor = posts_request.data.xdt_api__v1__feed__user_timeline_graphql_connection.page_info.end_cursor
        if redis then
            if not cursor then
                redis:set("ig:timeline:" .. username .. ":latest", json.encode({
                    posts = posts,
                    end_cursor = end_cursor,
                }), "EX", LATEST_USER_TIMELINE_EXPIRE_TIME)
            elseif cursor then
                redis:set("ig:timeline:" .. username .. ":" .. cursor, json.encode({
                    posts = posts,
                    end_cursor = end_cursor,
                }), "EX", CURSORED_USER_TIMELINE_EXPIRE_TIME)
            end
        end
        return { posts = posts, end_cursor = end_cursor }

    elseif posts_request.errors and posts_request.errors[1].code == 4630001 then
        local timeline_error = errors.not_found{
            message = "User not found.",
            blob = posts_request
        }

        if redis then
            local key
            if cursor then
                key = "ig:timeline:" .. username .. ":" .. cursor
            else
               key = "ig:timeline:" .. username .. ":latest"
            end
            redis:set(key, json.encode(timeline_error), "EX", NEGATIVE_USER_TIMELINE_EXPIRE_TIME)
        end
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
    local redis = get_redis()
    local user_query

    if not redis then
        ngx.log(ngx.ERR, "Redis connection failed: ")
    else
        user_query = redis:get("ig:user:" .. user_id)
    end

    if redis and user_query ~= ngx.null then
        local user_info = json.decode(user_query)
        return user_info
    else
        local payload, doc_id = queries.user_info(user_id)
        local user_info = instagram_graphql_request(payload, doc_id, "user_info")
        if redis then
            redis:set("ig:user:" .. user_id, json.encode(user_info.data.user), "EX", USER_INFO_EXPIRE_TIME)
        end
        return user_info.data.user
    end
end





-- Instagram fetches user info based on ids,
-- fetching posts also returns the user's id. I can then fetch the user info based on that.
-- this method is pretty naive. Like the rest of this project :P
-- If a user has no posts (or is private), then their userid is retrieved from their user page.
-- All user ids are stored for later use, as profile pages are ratelimited heavily.

local function arrange_user_data(username, after_cursor)
    local user_posts = {}
    local user_id = false
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
        if not helpers.check_nested_field(user_posts.posts[1], "node", "coauthor_producers", 1) then
            user_id = user_posts.posts[1].node.owner.id
            user_id_db.save_user_id(user_posts.posts[1].node.user.username, user_id)
        elseif helpers.check_nested_field(user_posts.posts[1], "node", "coauthor_producers", 1) then
            -- I'm not entirely sure if this is always accurate, so user ids found here aren't saved.
            user_id = user_posts.posts[1].node.coauthor_producers[1].id
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
