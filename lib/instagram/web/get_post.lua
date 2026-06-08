local json = require("cjson")
local cache = require("lib.cache")
local errors = require("lib.helpers").create_error
local queries = require("lib.instagram.web.graphql").queries
local format_post = require("lib.formatters").format_post
local graphql_request = require("lib.instagram.web.graphql").request
local get_comments = require("lib.instagram.web.get_comments")
local http = require("resty.http")
local html = require("htmlparser")
local helpers = require("lib.helpers")
local config = require("lapis.config").get()
local web_state = ngx.shared.web_state

local WINDOW_LENGTH = config.ratelimits.window_length
local REQUEST_LIMIT = config.ratelimits.request_limit

local function get_post_graphql(shortcode)
    local post_query = cache.query_item("ig:shortcode:" .. shortcode)
    if post_query ~= ngx.null then
        return post_query
    end

    local payload, doc_id = queries.shortcode(shortcode)
    local post = graphql_request(payload, doc_id, "posts")

    -- Check if an error was caught in the graphql function, if so, return that.
    if post.has_errors then
        return post
    end
    if post.data and post.data.xdt_shortcode_media == json.null then
        -- cache a post if its not found
        local post_error = errors.not_found {
            message = "Post not found. (Note: this result was cached.)",
            blob = post
        }
        cache.cache_item("ig:shortcode:" .. shortcode, post_error, "negative_post")
        return post_error
    end

    local formatted_post = format_post.from_shortcode(post.data
                                                              .xdt_shortcode_media)
    cache.cache_item("ig:shortcode:" .. shortcode, formatted_post, "positive_post")
    return formatted_post
end



local totally_human_headers = {
    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ["Sec-Fetch-Mode"] = "navigate",
}


local function cooldown()
    if config.ratelimits.cooldown_on_ratelimit then
        -- Get the remaining ttl on the key
        local key_ttl = web_state:ttl("post_html")
        if key_ttl and key_ttl > 0 then
            web_state:replace("post_html", REQUEST_LIMIT + 999, key_ttl)
        else
            web_state:replace("post_html", REQUEST_LIMIT + 999, WINDOW_LENGTH)
        end
    end
end

-- fetch posts through a json blob embedded in a post's html.
local function get_post_web(shortcode)
    local post_query = cache.query_item("ig:shortcode:" .. shortcode)
    if post_query and post_query ~= ngx.null then
        if not post_query.has_errors then
            local comments_query = cache.query_item("ig:comments:" .. post_query.id)
            local comments
            if comments_query == ngx.null then
                comments = get_comments(post_query.id)
            else
                comments = comments_query
            end
            return post_query, comments
        else
            return post_query
        end
    end
    -- I'm not sure if ratelimits are the same for post pages.
    local request_count = web_state:incr("post_html", 1, 0, WINDOW_LENGTH)
    if request_count > REQUEST_LIMIT and config.ratelimits.cooldown_on_ratelimit then
        return errors.ratelimited{
            message = "The server has blocked further requests to Instagram temporarily.",
        }
    end

    local httpc = http.new()
    local request_opts = {
        headers = totally_human_headers
    }

    if config.proxies["posts"] then
        request_opts.proxy_opts = {
            https_proxy = config.proxies["posts"]
        }
    end

    local post_request, err = httpc:request_uri(
                                  "https://www.instagram.com/p/" .. shortcode ..
                                      "/", request_opts)

    if not post_request then
        ngx.log(ngx.ERR, "Request failed: " .. err)

        return errors.network_error{
            message = "Request failed.",
            blob = err
        }
    elseif post_request.status == 302 or post_request.status == 429 then
        cooldown()
        return errors.ratelimited{
            message = "Instagram returned " .. post_request.status .. " on post page.",
            blob = post_request.body
        }
    end

    local html_root = html.parse(post_request.body)
    local script_elements = html_root:select("[type='application/json']")

    local post_info
    local post_comments

    for _, element in pairs(script_elements) do
        local element_json = json.decode(element:getcontent())

        if helpers.check_nested_field(element_json, "require", 1, 4, 1, "__bbox", "require", 1, 4, 2, "__bbox", "result", "data", "xdt_api__v1__media__shortcode__web_info") then
            -- instagram's json structure is fucked.

            local post_data = element_json.require[1][4][1].__bbox.require[1][4][2].__bbox.result.data
            -- if the shortcode_web_info field is null, it usually means the post exists, but is otherwise unavailable.
            if post_data.xdt_api__v1__media__shortcode__web_info == json.null then
                local post_error = errors.null_content{
                    message = "This post is unavailable. It could be age-gated or otherwise restricted.",
                    blob = post_data
                }
                cache.cache_item("ig:shortcode:" .. shortcode, post_error, "negative_post")
                return post_error
            end
            post_info = post_data.xdt_api__v1__media__shortcode__web_info.items[1]
        end

        if helpers.check_nested_field(element_json, "require", 1, 4, 1,
                                      "__bbox", "require", 1, 4, 2, "__bbox",
                                      "result", "data",
                                      "xdt_api__v1__media__media_id__comments__connection",
                                      "edges") then
            post_comments =
                element_json.require[1][4][1].__bbox.require[1][4][2].__bbox
                    .result.data
                    .xdt_api__v1__media__media_id__comments__connection.edges
        end

    end
    if not post_info then
        local post_error = errors.not_found {
            message = "No post info was found in the post's HTML. This means that the post either doesn't exist, or something broke.",
            blob = post_info
        }
        cache.cache_item("ig:shortcode:" .. shortcode, post_error, "negative_post")
        return post_error
    end


    if not post_comments then
        post_comments = errors.not_found {
            message = "Comments not found in post HTML.",
            blob = post_comments
        }
    end

    local formatted_post = format_post.from_web(post_info)

    cache.cache_item("ig:shortcode:" .. shortcode, formatted_post, "positive_post")
    cache.cache_item("ig:comments:" .. formatted_post.id, post_comments, "comments")

    return formatted_post, post_comments
end

if config.post_fetch_mode == "web" then
    return get_post_web
elseif config.post_fetch_mode == "graphql" then
    return get_post_graphql
else
    ngx.log(ngx.WARN, "post_fetch_mode not set! Falling back to web.")
    return get_post_web
end

