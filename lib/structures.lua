local json = require("cjson")
local check_nested_field = require("lib.helpers").check_nested_field

local doc_ids = {
    shortcode = "8845758582119845",
    user_info = "33257018913889225",
    comments = "25060748103519434",
    search = "24146980661639222",
    user_posts = "23893796620241262",
}

local queries = {
    shortcode = function(shortcode)
        return {
            shortcode = shortcode,
            fetch_tagged_user_count = json.null,
            hoisted_comment_id = json.null,
            hoisted_reply_id = json.null
        }, doc_ids.shortcode
    end,
    comments = function(post_id, sort_order)
        return {
            after = json.null, -- while an after_cursor _is_ exposed while logged out, this endpoint will only ever return the same page of comments when logged out.
            before = json.null,
            first = 30, -- I'm pretty sure this is the amount of comments to fetch at a time.
            last = json.null,
            media_id = post_id,
            sort_order = sort_order, -- leaving this at the default. would be cool to make this controllable.
            __relay_internal__pv__PolarisIsLoggedInrelayprovider = true
        }, doc_ids.comments
    end,
    user_info = function(user_id)
        return {
            enable_integrity_filters = true,
            id = user_id,
            render_surface = "PROFILE",
            __relay_internal__pv__PolarisProjectCannesLoggedInEnabledrelayprovider = true,
            __relay_internal__pv__PolarisCannesGuardianExperienceEnabledrelayprovider = true,
            __relay_internal__pv__PolarisCASB976ProfileEnabledrelayprovider = false,
            __relay_internal__pv__PolarisRepostsConsumptionEnabledrelayprovider = false
        }, doc_ids.user_info
    end,
    user_posts = function(username, count, after_cursor)
        if not after_cursor then
            after_cursor = json.null
        end
        return {
            after = after_cursor,
            before = json.null,
            data = {
                count = count,
                include_reel_media_seen_timestamp = true, -- no idea what this stuff does, but the requests fail without them ¯\_(ツ)_/¯
                include_relationship_info = true,
                latest_besties_reel_media = true,
                latest_reel_media = true
            },
            first = 12,
            last = json.null,
            username = username,
            __relay_internal__pv__PolarisIsLoggedInrelayprovider = true, -- no idea what this does either
            __relay_internal__pv__PolarisShareSheetV3relayprovider = true
        }, doc_ids.user_posts
    end,
    search = function(query)
        return {
            hasQuery = true,
            data = {
                query = query
            }
        }, doc_ids.search
    end,
}





local errors = {
    not_found = function(args)
        return {
            has_errors = true,
            error_type = "not_found",
            error_info = {
                message = args.message or "The requested content was not found.",
                blob = json.encode(args.blob)
            }
        }
    end,
    ratelimited = function(args)
        return {
            has_errors = true,
            error_type = "ratelimited",
            error_info = {
                message = args.message or "This instance may be rate-limited. Try again in a minute.",
                blob = json.encode(args.blob)
            }
        }
    end,
    blocked = function(args)
        return {
            has_errors = true,
            error_type = "blocked",
            error_info = {
                message = args.message or "This instance has been blocked from accessing that content. This may be permanent",
                blob = json.encode(args.blob)
            }
        }
    end,
    unknown = function(args)
        return {
            has_errors = true,
            error_type = "unknown",
            error_info = {
                message = args.message or "An unknown error occurred.",
                blob = json.encode(args.blob)
            }
        }
    end
}

-- all of instagram's apis return posts in a different format.
-- this takes  posts from different formats and turns them into a universal format
local format_post = {
    -- posts from the graphql shortcode api.
    from_shortcode = function(shortcode)
        -- stuff that should be found across all posts
        local post = {
            shortcode = shortcode.shortcode,
            alt_text = shortcode.accessibility_caption,
            timestamp = shortcode.taken_at_timestamp,
            id = shortcode.id,
        }

        post.user = {
            username = shortcode.owner.username,
            display_name = shortcode.owner.full_name,
            id = shortcode.owner.id,
            profile_picture = shortcode.owner.profile_pic_url,
            is_verified = shortcode.owner.is_verified,
        }

        if shortcode.edge_media_preview_like and shortcode.edge_media_preview_like.count then
            post.likes = shortcode.edge_media_preview_like.count
        end
        if shortcode.edge_media_to_caption and #shortcode.edge_media_to_caption.edges > 0 then
            post.caption = shortcode.edge_media_to_caption.edges[1].node.text
        end
        if shortcode.video_url then
            post.video_url = shortcode.video_url
            post.video_thumbnail = shortcode.thumbnail_src
            post.view_count = shortcode.video_view_count
        end

        if shortcode.edge_sidecar_to_children then
            post.images = {}
            for _, item in ipairs(shortcode.edge_sidecar_to_children.edges) do
                if item.node.video_url then
                    table.insert(post.images, {
                        video_url = item.node.video_url,
                        alt_text = item.node.accessibility_caption
                    })
                else
                    table.insert(post.images, {
                        image_url = item.node.display_resources[1].src,
                        alt_text = item.node.accessibility_caption
                    })
                end
            end
        elseif shortcode.display_resources then
            post.image_url = shortcode.display_resources[1].src
        end

        return post
    end,
    -- posts from web post pages
    from_web = function(web_post)
        local formatted_post = {
            shortcode = web_post.code,
            alt_text = web_post.accessibility_caption,
            timestamp = web_post.taken_at,
            id = web_post.id,
        }

        formatted_post.user = {
            username = web_post.user.username,
            display_name = web_post.user.full_name,
            id = web_post.user.id,
            profile_picture = web_post.user.profile_pic_url,
            is_verified = web_post.user.is_verified,
        }

        if web_post.likes_count then
            formatted_post.likes = web_post.likes_count
        end

        if web_post.caption and web_post.caption.text then
            formatted_post.caption = web_post.caption.text
        end
        if web_post.carousel_media ~= json.null then
            formatted_post.images = {}
            for _, item in ipairs(web_post.carousel_media) do
                if item.video_versions ~= json.null then
                    table.insert(formatted_post.images, {
                        video_url = item.video_versions[1].url,
                        alt_text = item.accessibility_caption
                    })
                else
                    table.insert(formatted_post.images, {
                        image_url = item.image_versions2.candidates[1].url,
                        alt_text = item.accessibility_caption,
                    })
                end
            end
        elseif web_post.video_versions ~= json.null then
            formatted_post.video_url = web_post.video_versions[1].url
            formatted_post.video_thumbnail = web_post.display_uri

        elseif web_post.image_versions2 ~= json.null then
            formatted_post.image_url = web_post.image_versions2.candidates[1].url
        end


        return formatted_post
    end,
    -- this doesn't yet handle videos in an image carousel.
    -- not used _yet_
    from_timeline = function(item)
        local post = {
            shortcode = item.code,
            id = item.pk,
            timestamp = item.taken_at
        }

        post.user = {
            username = item.user.username,
            display_name = item.user.full_name,
            id = item.user.id,
            profile_picture = item.user.profile_pic_url,
            is_verified = item.user.is_verified,
        }
        if item.accessibility_caption then
            post.alt_text = item.accessibility_caption
        end
        if item.video_versions then
            post.video_url = item.video_versions[1].url
        elseif item.carousel_media then
            post.images = {}
            for _, item in ipairs(item.carousel_media) do
                if type(item.video_versions) == "table" and #item.video_versions > 0 then
                    table.insert(post.images, {
                        video_url = item.video_versions[1].url,
                        alt_text = item.accessibility_caption
                    })
                else
                    table.insert(post.images, {
                        image_url = item.image_version2.candidates[1].url,
                        alt_text = item.accessibility_caption
                    })
                end
            end
        elseif item.image_versions2 and not item.video_versions and not item.carousel_media then
            post.image_url = item.image_versions2.candidates[1].url
        end
        return post
    end
}


return { queries = queries, doc_ids = doc_ids, format_post = format_post, errors = errors }
