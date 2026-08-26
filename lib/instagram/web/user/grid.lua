local cache = require("lib.cache")
local formatters = require("lib.formatters")
local graphql = require("lib.instagram.web.graphql")
local helpers = require("lib.helpers")
local json = require("cjson")
local errors = helpers.create_error
local encoding = require("lapis.util.encoding")
local html_request = require("lib.instagram.web.html").request

local function paginate_grid(username, user_id, cursor, page_data, feed_type)
    local grid_key = string.format("ig:grid:%s:%s:%s", feed_type, username, cursor)
    local user_key = string.format("ig:user:%s", username)

    local user, grid

    local grid_cache_query = cache.query_item(grid_key)
    local user_cache_query = cache.query_item(user_key)

    if user_cache_query ~= ngx.null then
        user = user_cache_query
    else
        local query, doc_id = graphql.queries.anon_user_info(username)
        user = graphql.query_and_format(query, doc_id, formatters.format_user_info.from_anon_web_graphql, {
            purpose = "user_info",
            page_data = page_data,
            extra_formatter_options = { page_data },
        })
    end

    if grid_cache_query ~= ngx.null then
        grid = grid_cache_query
    else
        if feed_type == "reels" then
            local query, doc_id = graphql.queries.anon_reel_paginated_grid(cursor, user_id)
            grid = graphql.query_and_format(query, doc_id, formatters.format_grid.from_anon_reel_web_graphql, {
                purpose = "user_posts",
                page_data = page_data,
                extra_formatter_options = { page_data },
            })
        else
            local query, doc_id = graphql.queries.anon_paginated_grid(cursor, user_id)
            grid = graphql.query_and_format(query, doc_id, formatters.format_grid.from_anon_web_graphql, {
                purpose = "user_posts",
                page_data = page_data,
                extra_formatter_options = { page_data },
            })
        end
    end

    if grid.has_errors then
        return grid
    end

    if user.has_errors then
        return user
    end

    cache.cache_item(grid_key, grid, "cursored_timeline")
    cache.cache_item(user_key, user, "user_info")

    return { info = user, grid = grid }
end

local function get_user_grid(username, cursor, feed_type)
    local decoded_cursor, grid, user
    if cursor then
        decoded_cursor = json.decode(encoding.decode_base64(cursor))
        return paginate_grid(username, decoded_cursor.id, decoded_cursor.cursor, decoded_cursor.page_data, feed_type)
    end

    local grid_key = string.format("ig:grid:%s:%s:latest", feed_type, username)
    local user_key = string.format("ig:user:%s", username)

    local grid_cache_query = cache.query_item(grid_key)
    local user_cache_query = cache.query_item(user_key)

    if grid_cache_query ~= ngx.null and user_cache_query ~= ngx.null then
        return { grid = grid_cache_query, info = user_cache_query }
    end

    local request_url = "https://www.instagram.com/" .. username .. "/"
    local pattern = "/%s/"
    if feed_type == "reels" then
        pattern = pattern + "reels/"
        request_url = request_url .. "reels/"
    end

    local request = html_request(request_url, pattern)

    if request.data then
        local page_data = {}

        for k, v in pairs(request.data) do
            if k ~= "preloaders" then
                page_data[k] = v
            end
        end

        -- I can't see any better way of detecting a 404. Instagram uses 200 on almost every request.
        -- Ratelimits almost always use 302.
        if
            request.data.canonical_route_name
            and request.data.canonical_route_name == "comet.igweb.PolarisErrorRoute"
        then
            return errors.not_found {
                message = "Initial html indicated 404. Open an issue if this user really exists.",
                blob = page_data,
            }
        end

        if feed_type == "all" then
            local grid_preloader_result = helpers.check_nested_field(
                request,
                "data",
                "preloaders",
                "PolarisLoggedOutDesktopWWWProfilePostsTabContentQuery",
                "result"
            )
            if grid_preloader_result and grid_preloader_result ~= ngx.null then
                grid = formatters.format_grid.from_anon_web_graphql(grid_preloader_result.data, page_data)
            else
                local query, doc_id = graphql.queries.anon_initial_grid(username)
                grid = graphql.query_and_format(query, doc_id, formatters.format_grid.from_anon_web_graphql, {
                    purpose = "user_posts",
                    page_data = page_data,
                    extra_formatter_options = { page_data },
                })
            end
        elseif feed_type == "reels" then
            local grid_preloader_result = helpers.check_nested_field(
                request,
                "data",
                "preloaders",
                "PolarisLoggedOutDesktopWWWProfileReelsTabContentQuery",
                "result"
            )
            if grid_preloader_result and grid_preloader_result ~= ngx.null then
                grid = formatters.format_grid.from_anon_reel_web_graphql(grid_preloader_result.data, page_data)
            else
                local query, doc_id = graphql.queries.anon_reel_initial_grid(username)
                grid = graphql.query_and_format(query, doc_id, formatters.format_grid.from_anon_reel_web_graphql, {
                    purpose = "user_posts",
                    page_data = page_data,
                    extra_formatter_options = { page_data },
                })
            end
        end

        local user_preloader_result = helpers.check_nested_field(
            request,
            "data",
            "preloaders",
            "PolarisLoggedOutDesktopWWWProfileRootContentQuery",
            "result"
        )
        if user_preloader_result and user_preloader_result ~= ngx.null then
            user = formatters.format_user_info.from_anon_web_graphql(user_preloader_result.data)
        else
            local query, doc_id = graphql.queries.anon_user_info(username)
            user = graphql.query_and_format(query, doc_id, formatters.format_user_info.from_anon_web_graphql, {
                purpose = "user_info",
                page_data = page_data,
                extra_formatter_options = { page_data },
            })
        end
    end

    if not user then
        local query, doc_id = graphql.queries.anon_user_info(username)
        user = graphql.query_and_format(query, doc_id, formatters.format_user_info.from_anon_web_graphql, {
            purpose = "user_info",
        })
    end

    if not grid then
        if feed_type == "all" then
            local query, doc_id = graphql.queries.anon_initial_grid(username)
            grid = graphql.query_and_format(query, doc_id, formatters.format_grid.from_anon_web_graphql, {
                purpose = "user_posts",
            })
        else
            local query, doc_id = graphql.queries.anon_reel_initial_grid(username)
            grid = graphql.query_and_format(query, doc_id, formatters.format_grid.from_anon_reel_web_graphql, {
                purpose = "user_posts",
            })
        end
    end

    if not grid.has_errors then
        grid.is_grid = true
        cache.cache_item(grid_key, grid, "latest_timeline")
    end

    if not user.has_errors then
        cache.cache_item(user_key, user, "user_info")
    end

    return { grid = grid, info = user }
end

return get_user_grid
