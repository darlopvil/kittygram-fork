local get_redis = require("lapis.redis").get_redis
local json = require("cjson")
local save_user = require("models.users").save_user
local config = require("lapis.config").get()
local formatters = require("lib.formatters")
local ngx_resp = require("ngx.resp")

local POSITIVE_POST_EXPIRE_TIME = config.cache.expire_times.posts.positive
local NEGATIVE_POST_EXPIRE_TIME = config.cache.expire_times.posts.negative
local USER_INFO_EXPIRE_TIME = config.cache.expire_times.user_info.positive
local LATEST_USER_TIMELINE_EXPIRE_TIME = config.cache.expire_times.user_timelines.latest
local CURSORED_USER_TIMELINE_EXPIRE_TIME = config.cache.expire_times.user_timelines.with_cursor
local NEGATIVE_USER_TIMELINE_EXPIRE_TIME = config.cache.expire_times.user_timelines.negative
local EXPLORE_PAGE_EXPIRE_TIME = config.cache.expire_times.explore
local COMMENTS_EXPIRE_TIME = config.cache.expire_times.comments
local POPULAR_PAGE_EXPIRE_TIME = config.cache.expire_times.popular_index

-- function to test that redis is operational
local function test_redis()
    local redis = get_redis()
    return not not redis
end

local function cache_item(key, data, expire_type)
    local redis = get_redis()
    if not redis then
        ngx.log(ngx.ERR, "Redis connection failed!")
        return ngx.null
    end
    local ttl
    if expire_type == "cursored_timeline" then
        ttl = CURSORED_USER_TIMELINE_EXPIRE_TIME
    elseif expire_type == "latest_timeline" then
        ttl = LATEST_USER_TIMELINE_EXPIRE_TIME
    elseif expire_type == "negative_timeline" then
        ttl = NEGATIVE_USER_TIMELINE_EXPIRE_TIME
    elseif expire_type == "positive_post" then
        ttl = POSITIVE_POST_EXPIRE_TIME
    elseif expire_type == "negative_post" then
        ttl = NEGATIVE_POST_EXPIRE_TIME
    elseif expire_type == "user_info" then
        ttl = USER_INFO_EXPIRE_TIME
    elseif expire_type == "comments" then
        ttl = COMMENTS_EXPIRE_TIME
    elseif expire_type == "explore" then
        ttl = EXPLORE_PAGE_EXPIRE_TIME
    elseif expire_type == "popular_index" then
        ttl = POPULAR_PAGE_EXPIRE_TIME
    else
        ngx.log(ngx.WARN, "Unknown expire type " .. tostring(expire_type) .. "Falling back to five minutes.")
        ttl = 360
    end

    redis:set(key, json.encode(data), "EX", ttl)
end
local function query_item(key)
    local redis = get_redis()
    if not redis then
        ngx.log(ngx.ERR, "Redis connection failed!")
        return ngx.null
    end
    local query = redis:get(key)
    if query ~= ngx.null then
        ngx_resp.add_header("X-KG-Debug-Cache", key)
        return json.decode(query)
    else
        return query
    end
end

-- cache individual posts from a users timeline
local function cache_timeline(posts)
    for _, post in ipairs(posts) do
        cache_item("ig:shortcode:" .. post.shortcode, post, "positive_post")
    end
end

-- functions to cache all the user Ids from different objects.
local bulk_save_users = {
    from_comments = function(comments)
        for _, comment in ipairs(comments.edges or {}) do
            comment = comment.node

            if comment.user and comment.user ~= ngx.null then
                save_user(comment.user)
            end
        end
    end,
    from_explore = function(items)
        for _, item in ipairs(items.edges or {}) do
            item = item.node

            if item.user and item.user ~= ngx.null then
                save_user(item.user)
            end
        end
    end,
    from_topsearch = function(results)
        for _, user in ipairs(results.users) do
            if user.user then
                save_user(user.user)
            end
        end
    end,
}

return {
    test_redis = test_redis,
    cache_item = cache_item,
    query_item = query_item,
    cache_timeline = cache_timeline,
    bulk_save_users = bulk_save_users,
}
