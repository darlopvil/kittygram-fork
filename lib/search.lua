local instagram_graphql_request = require("lib.send_instagram_graphql_request")
local queries = require("lib.structures").queries
local helpers = require("lib.helpers")
local errors = require("lib.structures").errors
local config = require("lapis.config").get()
local json = require("cjson")
local get_redis = require("lapis.redis").get_redis

local EXPLORE_PAGE_EXPIRE_TIME =  config.cache.expire_times.explore

local function search(query)

    local payload, doc_id = queries.search(query)
    local search_request = instagram_graphql_request(payload, doc_id, "search")
    local search_results = search_request

    if search_results.errors then
        return errors.unknown{ blob = search_results }
    elseif helpers.check_nested_field(search_results, "data", "xdt_api__v1__fbsearch__topsearch_connection") then
        return search_results.data.xdt_api__v1__fbsearch__topsearch_connection
    end

    return errors.unknown{ blob = search_results }
end

local function explore(query, after)
    local redis = get_redis()
    if not redis then
        ngx.log("Redis connection failed!")
    else
        local key
        if after then
            key = "ig:explore:" .. query  .. ":" .. after
        else
            key = "ig:explore:" .. query .. ":latest"
        end
        local explore_query = redis:get(key)
        if explore_query ~= ngx.null then
            return json.decode(explore_query)
        end
    end
    local payload, doc_id = queries.explore_search(query, after)
    local search_request = instagram_graphql_request(payload, doc_id, "explore")
    if search_request.data ~= json.null then
        if redis then
            local key
            if after then
                key = "ig:explore:" .. query  .. ":" .. after
            else
                key = "ig:explore:" .. query .. ":latest"
            end
            redis:set(key, json.encode(search_request.data.xig_logged_out_popular_search_media_info), "EX", EXPLORE_PAGE_EXPIRE_TIME)
        end
        return search_request.data.xig_logged_out_popular_search_media_info
    elseif search_request.status == "fail" and search_request.require_login == true then
        return errors.ratelimited{ blob = search_request }
    else
        return errors.unknown{ blob = search_request }
    end
end
return { search = search, explore = explore }
