local instagram_graphql_request = require("lib.instagram.web.graphql").request
local queries = require("lib.instagram.web.graphql").queries
local helpers = require("lib.helpers")
local errors = require("lib.helpers").create_error
local util = require("lapis.util")
local formatters = require("lib.formatters")
local config = require("lapis.config").get()
local cache = require("lib.cache")
local json = require("cjson")

local db_search = require("models.user_search")


local function web_search(query)
    local payload, doc_id = queries.search(query)
    local search_request = instagram_graphql_request(payload, doc_id, "search")
    local search_results = search_request

    -- Check if an error was caught in the graphql function, if so, return that.
    if search_results.has_errors then
        return search_request
    end
    if search_results.errors then
        return errors.unknown{ blob = search_results }
    elseif helpers.check_nested_field(search_results, "data", "xdt_api__v1__fbsearch__topsearch_connection") then
        local formatted_results = formatters.format_search.from_web_topsearch(search_results.data.xdt_api__v1__fbsearch__topsearch_connection)
        cache.bulk_save_users.from_topsearch(search_results.data.xdt_api__v1__fbsearch__topsearch_connection)
        return  formatted_results
    end

    return errors.unknown{ blob = search_results }
end

local function database_search(query)
    local search = db_search(query)
    local formatted_results = formatters.format_search.from_database(search)
    return formatted_results
end

local function search(query)
    if config.web_session and config.web_session.cookies and config.web_session.use_for and config.web_session.use_for.search then
        return web_search(query)
    else
        return database_search(query)
    end
end

local function get_popular_page()
    local cache_query = cache.query_item("ig:popular")
    if cache_query ~= ngx.null then
        return cache_query
    end

    local payload, doc_id = queries.popular_page()
    local request = instagram_graphql_request(payload, doc_id, "popular_page")

    if request.has_errors then
        return request
    end

    if request.data and request.data.popular_search_home_sections then
        local formatted = formatters.format_popular_index(request.data)
        cache.cache_item("ig:popular", formatted, "popular_index")
        return formatted
    else
        return errors.unknown{ blob = request }
    end
end

local function explore(query, after)
    local key = "ig:explore:" .. query .. ":" .. (after or "latest")

    local explore_query = cache.query_item(key)
    if explore_query ~= ngx.null then
        return explore_query
    end

    local decoded_query = util.unescape(tostring(query))

    local payload, doc_id = queries.explore_search(decoded_query, after)
    local search_request = instagram_graphql_request(payload, doc_id, "explore")

    -- Check if an error was caught in the graphql function, if so, return that.
    if search_request.has_errors then
        return search_request
    end
    if search_request.data.xig_logged_out_popular_search_media_info and search_request.data.xig_logged_out_popular_search_media_info ~= ngx.null then
        cache.bulk_save_users.from_explore(search_request.data.xig_logged_out_popular_search_media_info)
        local formatted = formatters.format_explore_results.from_anon_web(search_request.data.xig_logged_out_popular_search_media_info)
        cache.cache_item(key, formatted, "explore")
        return formatted
    else
        return errors.unknown{ blob = search_request }
    end
end
return { search = search, explore = explore, popular_page = get_popular_page }
