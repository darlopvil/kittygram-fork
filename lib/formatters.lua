local json = require("cjson")
local construct_error = require("lib.helpers").create_error
local encoding = require("lapis.util.encoding")

-- all of instagram's apis return posts in a different format.
-- this takes  posts from different formats and turns them into a universal format
local format_post = {
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
            thumbnail = item.display_uri,
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

        if item.product_type == "feed" then
            post.kind = "post"
        elseif item.product_type == "clips" then
            post.kind = "reel"
        elseif item.product_type == "carousel_container" then
            post.kind = "carousel"
        else
            post.kind = "unknown"
        end

        if item.coauthor_producers and item.coauthor_producers ~= json.null then
            post.coauthors = {}
            for _, coauthor in ipairs(item.coauthor_producers) do
                table.insert(post.coauthors, {
                    username = coauthor.username,
                    id = coauthor.id,
                    profile_picture = coauthor.profile_pic_url,
                    is_verified = coauthor.id_verified
                })
            end
        end

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
            thumbnail = reel.display_uri,
            -- considering its a reel timeline, everything should be a reel
            kind = "reel",
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
    from_media_id_anon = function(post)
        local formatted_post = {
            id = post.pk,
            alt_text = post.accessibility_caption,
            shortcode = post.code,
            thumbnail = post.display_uri,
            likes = post.like_count,
            timestamp = post.taken_at,
            comment_count = post.comment_count
        }

        formatted_post.user = {
            username = post.user.username,
            id = post.user.pk,
            profile_picture = post.user.profile_pic_url,
            is_verified = post.user.is_verified
        }

        if post.caption and post.caption ~= ngx.null then
            formatted_post.caption = post.caption.text
        end

        if post.carousel_media and post.carousel_media ~= json.null then
            formatted_post.images = {}
            for _, media in ipairs(post.carousel_media) do
                if media.video_versions and media.video_versions ~= ngx.null then
                    table.insert(formatted_post.images, {
                        video_url = media.video_versions[1].url,
                        video_thumbnail = media.image_versions2.candidates[1].url,
                        alt_text = media.accessibility_caption
                    })
                else
                    table.insert(formatted_post.images, {
                        image_url = media.image_versions2.candidates[1].url,
                        alt_text = media.accessibility_caption
                    })
                end
            end
        elseif post.video_versions and post.video_versions ~= ngx.null then
            formatted_post.video_url = post.video_versions[1].url
            if post.image_versions2 and post.image_versions2 ~= ngx.null then
                formatted_post.video_thumbnail = post.image_versions2.candidates[1].url
            else
                formatted_post.video_thumbnail = post.display_uri
            end
        elseif post.image_versions2 and post.image_versions2 ~= ngx.null then
            formatted_post.image_url = post.image_versions2.candidates[1].url
        end

        return formatted_post
    end
}

local format_timeline = {
    from_reel_api = function(reels, page_data)
        page_data = page_data or {}
        local formatted = {
            items = {},
        }

        for _, reel in ipairs(reels.items) do
            local formatted_reel = format_post.from_reel_timeline(reel)
            table.insert(formatted.items, formatted_reel)
        end

        if reels.paging_info and reels.paging_info ~= ngx.null then
            if reels.paging_info.more_available then
                local encoded_cursor = encoding.encode_base64(json.encode({
                    cursor = reels.paging_info.max_id,
                    page_data = page_data,
                    id = page_data.user_id,
                    kind = "timeline"
                }))

                formatted.cursor = encoded_cursor
            end
        end

        return formatted
    end,
    from_timeline_graphql = function(timeline, page_data)
        local formatted = {
            items = {},
        }

        if timeline.xdt_api__v1__feed__user_timeline_graphql_connection then
            for _, post in ipairs(timeline.xdt_api__v1__feed__user_timeline_graphql_connection.edges) do
                local formatted_post = format_post.from_timeline(post)
                table.insert(formatted.items, formatted_post)
            end

            if timeline.xdt_api__v1__feed__user_timeline_graphql_connection.page_info and timeline.xdt_api__v1__feed__user_timeline_graphql_connection.page_info ~= ngx.null then
                if timeline.xdt_api__v1__feed__user_timeline_graphql_connection.page_info.has_next_page then
                    local encoded_cursor = encoding.encode_base64(json.encode({
                        cursor = timeline.xdt_api__v1__feed__user_timeline_graphql_connection.page_info.end_cursor,
                        page_data = page_data,
                        kind = "timeline"
                    }))

                    formatted.cursor = encoded_cursor
                end
            end
        else
            return construct_error.unknown{ blob = timeline }
        end

        return formatted
    end,


}
local format_comments = {
    from_web_graphql = function(comments)
        local formatted_comments = {
            items = {},
        }

        for _, comment in ipairs(comments.edges) do
            comment = comment.node

            local formatted_comment = {
                text = comment.text,
                timestamp = comment.created_at,
                likes = comment.comment_like_count
            }

            if comment.giphy_media_info and comment.giphy_media_info ~= ngx.null and type(comment.giphy_media_info) == "table" then
                formatted_comment.gif_media = comment.giphy_media_info.first_party_cdn_proxied_images.fixed_height.url
            end

            formatted_comment.user = {
                username = comment.user.username,
                is_verified = comment.user.is_verified,
                id = comment.user.id,
                profile_picture = comment.user.profile_pic_url,
            }
            table.insert(formatted_comments.items, formatted_comment)
        end

        if comments.page_info and comments.page_info ~= json.null and  comments.page_info.has_next_page then
            formatted_comments.end_cursor = encoding.encode_base64(comments.page_info.end_cursor)
        end
        return formatted_comments
    end,
    from_web_api = function(comments)
        local formatted = {
            items = {}
        }

        for _, comment in ipairs(comments.comments) do
            local formatted_comment = {
                text = comment.text,
                timestamp = comment.created_at,
                likes = comment.comment_like_count,
            }

            formatted_comment.user = {
                username = comment.user.username,
                profile_picture = comment.user.profile_pic_url,
                id = comment.user.id,
                is_verified = comment.user.is_verified
            }

            if comment.giphy_media_info and comment.giphy_media_info ~= ngx.null then
                if comment.giphy_media_info.images and comment.giphy_media_info.images ~= json.null then
                    formatted_comment.gif_media = comment.giphy_media_info.images.fixed_height.url
                end
            end

            table.insert(formatted.items, formatted_comment)
        end

        if comments.next_min_id and comments.next_min_id ~= ngx.null then
            formatted.end_cursor = encoding.encode_base64(comments.next_min_id)
        end

        return formatted
    end
}
local format_user_info = {
    from_graphql = function(info)
        info = info.user or {}
        local formatted_info = {
            followers = info.follower_count,
            pronouns = info.pronouns,
            display_name = info.full_name,
            following = info.following_count,
            media_count = info.media_count,
            -- not exposed on web_profile_info.
            is_cannes = info.is_cannes,
            profile_picture = info.profile_pic_url,
            bio_links = info.bio_links,
            is_private = info.is_private,
            id = info.id,
            username = info.username,
            biography = info.biography,
            is_verified = info.is_verified,
            is_business = info.is_business,
        }

        if info.hd_profile_pic_url_info and info.hd_profile_pic_url_info ~= ngx.null then
            if info.hd_profile_pic_url_info.url and info.hd_profile_pic_url_info.url ~= ngx.null then
                formatted_info.hd_profile_picture = info.hd_profile_pic_url_info.url
            end
        end

        return formatted_info
    end,
    from_hover_graphql = function(user)
        if user.xig_user_by_igid_v2 then
            if user.xig_user_by_igid_v2 == ngx.null then
                return construct_error.not_found{ message = "Hover info is null", blob = user }
            end
            local info = user.xig_user_by_igid_v2.user_dict
            local formatted_info = {
                followers = info.follower_count,
                pronouns = info.pronouns,
                display_name = info.full_name,
                following = info.following_count,
                media_count = info.media_count,
                profile_picture = info.profile_pic_url,
                is_private = info.is_private,
                id = info.id,
                username = info.username,
                biography = info.biography,
                is_verified = info.is_verified,
            }

            if info.hd_profile_pic_url_info and info.hd_profile_pic_url_info ~= ngx.null then
                if info.hd_profile_pic_url_info.url and info.hd_profile_pic_url_info.url ~= ngx.null then
                    formatted_info.hd_profile_picture = info.hd_profile_pic_url_info.url
                end
            end

            return formatted_info
        else
            return construct_error.unknown{ blob = user }
        end
    end,
    from_anon_web_graphql = function(info)
        if info.xig_user_by_username  then
            if info.xig_user_by_username == ngx.null then
                return construct_error.not_found{
                    message = "xig_user_by_username is null.",
                    blob = info
                }
            end
            info = info.xig_user_by_username
            return {
                followers = info.follower_count,
                pronouns = info.pronouns,
                display_name = info.full_name,
                following = info.following_count,
                media_count = info.all_media_count,
                profile_picture = info.profile_pic_url,
                bio_links = info.bio_links,
                is_private = info.is_private,
                id = info.pk,
                username = info.username,
                biography = info.biography,
                is_verified = info.is_verified,
            }
        else
            return {}
        end
    end
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

local format_popular_index = function(results)
    local formatted_page = { }
    for _, section in ipairs(results.popular_search_home_sections) do
        local formatted_section = {
            title = section.display_title,
            entries = {}
        }
        for _, entry in ipairs(section.entries) do
            if entry.keyword and entry.keyword ~= ngx.null then
                local formatted_entry = {
                    count = entry.keyword.media_count,
                    text = entry.keyword.keyword_text,
                    thumbnail = entry.keyword.thumbnail_url
                }
                table.insert(formatted_section.entries, formatted_entry)
            end
        end

        if #formatted_section.entries >= 1 then
            table.insert(formatted_page, formatted_section)
        end

    end
    return formatted_page
end

local format_explore_results = {
    from_anon_web = function(results)
        local formatted_results = {
            items = {}
        }
        for _, item in ipairs(results.edges) do
            item = item.node
            local formatted_item = {
                shortcode = item.code,
                play_count = item.play_count,
                thumbnail = item.display_uri
            }
            formatted_item.user = {
                is_verified = item.user.is_verified,
                username = item.user.username,
                id = item.user.id,
                profile_picture = item.user.profile_pic_url
            }

            if item.caption and item.caption ~= ngx.null then
                formatted_item.caption = item.caption.text
            end

            if item.video_versions and item.video_versions ~= ngx.null then
                formatted_item.video_url = item.video_versions[1].url
            end
            table.insert(formatted_results.items, formatted_item)
        end

        if results.page_info and results.page_info ~= json.null and results.page_info.has_next_page == true then
            -- There's also a start cursor interestingly.
            formatted_results.end_cursor = results.page_info.end_cursor
        end

        return formatted_results
    end
}

local format_grid = {
    from_anon_web_graphql = function(grid, page_data)
        local formatted_grid = {
            items = {}
        }

        if grid.xig_user_by_username then
            if grid.xig_user_by_username == ngx.null then
                return construct_error.not_found{
                    message = "xig_user_by_username is null.",
                    blob = grid
                }
            end
            grid = grid.xig_user_by_username
        elseif grid.node and grid.node.polaris_ordered_timeline_connection then
            grid = grid.node
        else
            return formatted_grid
        end

        if grid.polaris_ordered_timeline_connection and grid.polaris_ordered_timeline_connection ~= json.null then
            for _, item in ipairs(grid.polaris_ordered_timeline_connection.edges) do
                item = item.node
                local formatted_item = {
                    id = item.pk,
                    shortcode = item.code,
                    alt_text = item.accessibility_caption,
                    thumbnail = item.display_uri,
                    likes = item.like_count,
                    views = item.view_count,
                    comment_count = item.comment_count
                }

                if item.user then
                    formatted_item.user = {
                        username = item.user.username,
                        id = item.user.pk
                    }
                end

                if item.caption and item.caption ~= ngx.null then
                    formatted_item.caption = item.caption.text
                end

                if item.product_type == "feed" then
                    formatted_item.kind = "post"
                elseif item.product_type == "clips" then
                    formatted_item.kind = "reel"
                elseif item.product_type == "carousel_container" then
                    formatted_item.kind = "carousel"
                else
                    formatted_item.kind = "unknown"
                end

                table.insert(formatted_grid.items, formatted_item)
            end
        end

        if grid.polaris_ordered_timeline_connection.page_info and grid.polaris_ordered_timeline_connection.page_info.has_next_page then
            local encoded_cursor = encoding.encode_base64(json.encode({
                cursor = grid.polaris_ordered_timeline_connection.page_info.end_cursor,
                page_data = page_data,
                id = grid.id,
                kind = "grid"
            }))


            formatted_grid.cursor = encoded_cursor
        end

        return formatted_grid
    end,
    from_anon_reel_web_graphql = function(grid, page_data)
        local formatted = {
            items = {}
        }

        if grid.xig_user_by_username then
            if grid.xig_user_by_username == ngx.null then
                return construct_error.not_found{
                    message = "(formatter) xig_user_by_username is null.",
                    blob = grid
                }
            else
                grid = grid.xig_user_by_username
            end
        elseif grid.node and grid.node ~= ngx.null then
            grid = grid.node
        end

        if grid.polaris_clips_connection and grid.polaris_clips_connection ~= json.null then
            for _, item in ipairs(grid.polaris_clips_connection.edges) do
                item = item.node
                local formatted_item = {
                    id = item.pk,
                    shortcode = item.code,
                    alt_text = item.accessibility_caption,
                    thumbnail = item.display_uri,
                    likes = item.like_count,
                    views = item.view_count,
                    comment_count = item.comment_count
                }

                if item.user then
                    formatted_item.user = {
                        username = item.user.username,
                        id = item.user.pk
                    }
                end

                if item.caption and item.caption ~= ngx.null then
                    formatted_item.caption = item.caption.text
                end

                if item.product_type == "feed" then
                    formatted_item.kind = "post"
                elseif item.product_type == "clips" then
                    formatted_item.kind = "reel"
                elseif item.product_type == "carousel_container" then
                    formatted_item.kind = "carousel"
                else
                    formatted_item.kind = "unknown"
                end

                table.insert(formatted.items, formatted_item)
            end
        end
        if grid.polaris_clips_connection.page_info and grid.polaris_clips_connection.page_info.has_next_page then
            local encoded_cursor = encoding.encode_base64(json.encode({
                cursor = grid.polaris_clips_connection.page_info.end_cursor,
                page_data = page_data,
                id = grid.id,
                kind = "grid"
            }))


            formatted.cursor = encoded_cursor
        end
        return formatted
    end
}


return {
    format_post = format_post,
    format_user_info = format_user_info,
    format_search = format_search,
    format_comments = format_comments,
    format_highlights = format_highlights,
    format_popular_index = format_popular_index,
    format_explore_results = format_explore_results,
    format_grid = format_grid,
    format_timeline = format_timeline
}
