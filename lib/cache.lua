local get_redis = require("lapis.redis").get_redis
local json = require("cjson")
local config = require("lapis.config").get()

local POSITIVE_POST_EXPIRE_TIME = config.cache.expire_times.posts.positive
local NEGATIVE_POST_EXPIRE_TIME = config.cache.expire_times.posts.negative
local USER_INFO_EXPIRE_TIME = config.cache.expire_times.user_info.positive
local LATEST_USER_TIMELINE_EXPIRE_TIME = config.cache.expire_times.user_timelines.latest
local CURSORED_USER_TIMELINE_EXPIRE_TIME = config.cache.expire_times.user_timelines.with_cursor
local NEGATIVE_USER_TIMELINE_EXPIRE_TIME = config.cache.expire_times.user_timelines.negative
local EXPLORE_PAGE_EXPIRE_TIME =  config.cache.expire_times.explore

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
    elseif expire_type == "positive_post" or expire_type == "comments" then
        ttl = POSITIVE_POST_EXPIRE_TIME
    elseif expire_type == "negative_post" then
        ttl = NEGATIVE_POST_EXPIRE_TIME
    elseif expire_type == "user_info" then
        ttl = USER_INFO_EXPIRE_TIME
    elseif expire_type == "explore" then
        ttl = EXPLORE_PAGE_EXPIRE_TIME
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
        return json.decode(query)
    else
        return query
    end
end

return { cache_item = cache_item, query_item = query_item }
