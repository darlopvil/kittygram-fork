local json = require("cjson")


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
                        video_thumbnail = item.node.display_resources[1].src,
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

        if web_post.like_count then
            formatted_post.likes = web_post.like_count
        end

        if web_post.caption ~= json.null and web_post.caption.text ~= json.null then
            formatted_post.caption = web_post.caption.text
        end
        if web_post.carousel_media ~= json.null then
            formatted_post.images = {}
            for _, item in ipairs(web_post.carousel_media) do
                if item.video_versions ~= json.null then
                    table.insert(formatted_post.images, {
                        video_url = item.video_versions[1].url,
                        video_thumbnail = item.image_versions2.candidates[1].url,
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
    from_timeline = function(item)
        item = item.node
        local post = {
            shortcode = item.code,
            id = item.pk,
            timestamp = item.taken_at,
            likes = item.like_count,
            comment_count = item.comment_count,
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
        if item.video_versions ~= json.null then
            post.video_url = item.video_versions[1].url
            if item.image_versions2 ~= json.null then
                post.video_thumbnail = item.image_versions2.candidates[1].url
            else
                post.video_thumbnail = item.display_uri
            end
        elseif item.carousel_media ~= json.null then
            post.images = {}
            for _, media_item in ipairs(item.carousel_media) do
                if type(media_item.video_versions) == "table" and #media_item.video_versions > 0 then
                    table.insert(post.images, {
                        video_url = media_item.video_versions[1].url,
                        video_thumbnail = media_item.image_versions2.candidates[1].url,
                        alt_text = media_item.accessibility_caption
                    })
                else
                    table.insert(post.images, {
                        image_url = media_item.image_versions2.candidates[1].url,
                        alt_text = media_item.accessibility_caption
                    })
                end
            end
        elseif item.image_versions2 ~= json.null and item.video_versions == json.null and  item.carousel_media == json.null then
            post.image_url = item.image_versions2.candidates[1].url
        end

        if item.caption and item.caption ~= json.null and item.caption.text ~= json.null then
            post.caption = item.caption.text
        end
        return post
    end,
    -- This doesn't handle carousels.
    from_reel_timeline = function(reel)
        reel = reel.media
        local reel_formatted = {
            id = reel.id,
            comment_count = reel.comment_count,
            shortcode = reel.code,
            timestamp = reel.taken_at,
            likes = reel.like_count,
        }

        reel_formatted.user = {
            id = reel.user.id,
            username = reel.user.username,
            profile_picture = reel.user.profile_pic_url,
            is_verified = reel.is_verified,
        }
        if reel.caption and reel.caption ~= json.null and reel.caption.text ~= json.null then
            reel_formatted.caption = reel.caption.text
        end
        if reel.video_versions and reel.video_versions ~= json.null then
            reel_formatted.video_url = reel.video_versions[1].url
            if reel.image_versions2 then
                reel_formatted.video_thumbnail = reel.image_versions2.candidates[1].url
            else
                reel_formatted.video_thumbnail = reel.display_uri
            end
        end
        return reel_formatted
    end,
}

local format_user_info = {
    from_graphql = function(info)
        return {
            follower_count = info.follower_count,
            pronouns = info.pronouns,
            display_name = info.full_name,
            following_count = info.following_count,
            media_count = info.media_count,
            -- not exposed on web_profile_info.
            is_cannes = info.is_cannes,
            profile_pic_url = info.profile_pic_url,
            bio_links = info.bio_links,
            is_private = info.is_private,
            id = info.id,
            username = info.username,
            biography = info.biography,
            is_verified = info.is_verified,
            is_business = info.is_business,
            -- don't know what this is. Keeping it in case it's useful in future.
            -- not exposed on the web_profile_info api though.
            account_type = info.account_type
        }
    end,
    from_web_api = function(info)
        local info_formatted = {
            username = info.username,
            display_name = info.full_name,
            biography = info.biography,
            profile_pic_url = info.profile_pic_url,
            id = info.id,
            is_verified = info.is_verified,
            is_private = info.is_private,
            is_business = info.is_business_account,
            bio_links = info.bio_links,
            pronouns = info.pronouns
        }

        if info.edge_follow and info.edge_follow ~= json.null and info.edge_follow.count and info.edge_follow.count ~= json.null then
            info_formatted.following_count = info.edge_follow.count
        end
        if info.edge_followed_by and info.edge_followed_by ~= json.null and info.edge_followed_by.count and info.edge_followed_by.count ~= json.null then
            info_formatted.follower_count = info.edge_followed_by.count
        end
        if info.edge_owner_to_timeline_media and info.edge_owner_to_timeline_media ~= json.null and info.edge_owner_to_timeline_media.count and info.edge_owner_to_timeline_media.count ~= json.null then
            info_formatted.media_count = info.edge_owner_to_timeline_media.count
        end
        return info_formatted
    end,
}

local format_search = {
    from_web_topsearch = function(results)
        local formatted_results = {
            search_source = "instagram_topsearch",
            users = {},
            hashtags = {},
        }
        for _, user in ipairs(results.users) do
            user = user.user
            table.insert(formatted_results.users, {
                username = user.username,
                profile_picture = user.profile_pic_url,
                id = user.id,
                is_verified = user.is_verified
            })
        end

        for _, hashtag in ipairs(results.hashtags) do
            hashtag = hashtag.hashtag
            table.insert(formatted_results.hashtags, {
                name = hashtag.name,
                search_result_subtitle = hashtag.search_result_subtitle
            })
        end
        return formatted_results
    end,
    from_database = function(results)
        local formatted_results = {
            search_source = "database",
            users = {},
            hashtags = {}
        }
        -- database backed search only finds users
        for _, user in ipairs(results) do
            table.insert(formatted_results.users, user)
        end

        return formatted_results
    end
}
return { format_post = format_post, format_user_info = format_user_info, format_search = format_search }
