local cache = require("lib.cache")
local json = require("cjson")
local errors = require("lib.helpers").create_error
local queries = require("lib.instagram.web.graphql").queries
local format_post = require("lib.formatters").format_post
local format_comments = require("lib.formatters").format_comments
local graphql_request = require("lib.instagram.web.graphql").request
local config = require("lapis.config").get()
local get_comments = require("lib.instagram.web.get_comments")
local helpers = require("lib.helpers")
local users_db = require("models.users")

-- TODO: It's hard to detect if a post wasn't made, vs if an actual error occurred, so a post being missing will trigger a 500
local function get_post_graphql_shortcode(shortcode, comments_cursor)
    local post
    local post_query = cache.query_item("ig:shortcode:" .. shortcode)
    if post_query ~= ngx.null then
        post = post_query
    else
        local payload, doc_id = queries.shortcode_post_info(shortcode)
        local request = graphql_request(payload, doc_id, "posts")

        if request.has_errors then
            return request
        end
        if request.data.xdt_api__v1__media__shortcode__web_info == json.null then
            return errors.null_content { blob = request }
        end
        local formatted_post = format_post.from_web(request.data.xdt_api__v1__media__shortcode__web_info.items[1])
        cache.cache_item("ig:shortcode:" .. shortcode, formatted_post, "positive_post")
        users_db.save_user {
            id = formatted_post.user.id,
            username = formatted_post.user.username,
            profile_pic_url = formatted_post.user.profile_picture,
            is_verified = formatted_post.user.is_verified,
        }
        post = formatted_post
    end

    local comments = get_comments(post.id, comments_cursor)

    return post, comments
end

local function get_post_graphql_media_id(shortcode, comments_cursor)
    local post, initial_comments
    local post_query = cache.query_item("ig:shortcode:" .. shortcode)
    if post_query ~= ngx.null then
        post = post_query
    else
        local media_id = helpers.shortcode_to_id(shortcode)
        local payload, doc_id = queries.media_id_post_info(media_id)
        local request = graphql_request(payload, doc_id, "posts")
        if request.has_errors then
            return request
        end

        if request.data.xig_polaris_media == json.null then
            return errors.not_found { blob = request }
        end

        if request.data.xig_polaris_media.if_not_gated_logged_out == json.null then
            return errors.null_content { blob = request }
        end

        post = format_post.from_media_id_anon(request.data.xig_polaris_media.if_not_gated_logged_out)
        cache.bulk_save_users.from_comments(request.data.xig_polaris_media.comments_connection)
        users_db.save_user {
            id = post.user.id,
            username = post.user.username,
            profile_pic_url = post.user.profile_picture,
            is_verified = post.user.is_verified,
        }
        cache.cache_item("ig:shortcode:" .. shortcode, post, "positive_post")
        initial_comments = format_comments.from_web_graphql(request.data.xig_polaris_media.comments_connection)
        cache.cache_item("ig:comments:" .. post.id .. ":initial", initial_comments, "comments")
    end

    local comments
    if comments_cursor or not initial_comments then
        comments = get_comments(post.id, comments_cursor)
    elseif initial_comments then
        comments = initial_comments
    end

    return post, comments
end

local function fetch_post(shortcode, comments_cursor)
    local match = ngx.re.match(shortcode, "^[a-zA-Z0-9_-]+$", "jo")
    if not match then
        return errors.not_found {
            message = "Post shortcode is invalid. Open an issue if this post really exists.",
        }
    end

    if config.web_session and config.web_session.cookies and config.web_session.use_for and config.web_session.use_for.comments then
        return get_post_graphql_shortcode(shortcode, comments_cursor)
    else
        return get_post_graphql_media_id(shortcode, comments_cursor)
    end
end

return fetch_post
