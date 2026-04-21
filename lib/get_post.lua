local json = require("cjson")
local get_redis = require("lapis.redis").get_redis
local errors = require("lib.structures").errors
local queries = require("lib.structures").queries
local format_post = require("lib.structures").format_post
local graphql_request = require("lib.graphql").request
local http = require("resty.http")
local html = require("htmlparser")
local helpers = require("lib.helpers")
local config = require("lapis.config").get()

local POSITIVE_EXPIRE_TIME = config.cache.expire_times.posts.positive
local NEGATIVE_EXPIRE_TIME = config.cache.expire_times.posts.negative

local function get_post_graphql(shortcode)
    local redis = get_redis()
    local post_query
    if not redis then
        ngx.log(ngx.ERR, "Redis connection failed: ", err)
    else
        post_query = redis:get("ig:shortcode:" .. shortcode)
    end

    -- check if redis returned anything.
    if redis and post_query ~= ngx.null then
        local post = json.decode(post_query)
        -- shortcodes that return no posts are cached.
        if post.has_errors and post.error_type == "not_found" then
            return errors.not_found {
                message = "Post not found. (note: result was cached.)",
                blob = json.decode(post.error_info.blob)
            }
        end

        return post
    else
        local payload, doc_id = queries.shortcode(shortcode)
        local post = graphql_request(payload, doc_id, "posts")

        if post.data and post.data.xdt_shortcode_media == json.null then
            -- cache a post if its not found
            local post_error = errors.not_found {
                message = "Post not found. (Note: this result was cached.)",
                blob = post
            }
            if redis then
                redis:set("ig:shortcode:" .. shortcode, json.encode(post_error),
                          "EX", NEGATIVE_EXPIRE_TIME)
            end
            return post_error
        elseif post.status == "fail" and post.require_login == true then
            return errors.ratelimited {blob = post}
        end

        local formatted_post = format_post.from_shortcode(post.data
                                                              .xdt_shortcode_media)
        if redis then
            redis:set("ig:shortcode:" .. shortcode, json.encode(formatted_post),
                      "EX", POSITIVE_EXPIRE_TIME)
        end
        return formatted_post
    end
end



local totally_human_headers = {
    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ["Sec-Fetch-Mode"] = "navigate"
}

-- fetch posts through a json blob embedded in a post's html.
local function get_post_web(shortcode)
    local redis = get_redis()

    if redis then
        local post_query = redis:get("ig:shortcode:" .. shortcode)
        if post_query ~= ngx.null then
            local post_info = json.decode(post_query)
            -- if the post has errors, return them immediately.
            if post_info.has_errors then
                return post_info
            end

            local comments
            local comments_query = redis:get("ig:comments:" .. post_info.id)

            if comments_query ~= ngx.null then
                comments = json.decode(comments_query)
            end
            return post_info, comments
        end
    else
        ngx.log(ngx.ERR, "Redis connection failed.")
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
                if redis then
                    redis:set("ig:shortcode:" .. shortcode, json.encode(post_error), "EX", NEGATIVE_EXPIRE_TIME)
                end
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
        if redis then
            redis:set("ig:shortcode:" .. shortcode, json.encode(post_error),
                      "EX", NEGATIVE_EXPIRE_TIME)
        end
        return post_error
    end


    if not post_comments then
        post_comments = errors.not_found {
            message = "Comments not found in post HTML.",
            blob = post_comments
        }
    end

    local formatted_post = format_post.from_web(post_info)
    if redis then
        redis:set("ig:shortcode:" .. shortcode, json.encode(formatted_post), "EX", POSITIVE_EXPIRE_TIME)
        redis:set("ig:comments:" .. formatted_post.id, json.encode(post_comments), "EX", POSITIVE_EXPIRE_TIME)
    end
    return formatted_post, post_comments
end


return { web = get_post_web, graphql = get_post_graphql }
