local lapis = require("lapis")
local app = lapis.Application()
local config = require("lapis.config").get()
local get_user = require("lib.instagram").get_user
local proxy_url = require("lib.helpers").proxy_url
local date = require("date")
local utf8 = require('lua-utf8')
local u8_gsub = utf8.gsub

local function xml_escape(string)
    local xml_replacements = {
        ["&"] = "&amp;",
        ["\""] = "&quot;",
        ["'"] = "&apos;",
        ["<"] = "&lt;",
        [">"] = "&gt;"
    }
    return u8_gsub(tostring(string), "[&\"'<>]", xml_replacements)
end

local function create_html_content(post)
    local base_url_path = config.base_atom_path
    if string.sub(tostring(base_url_path), #base_url_path, -1) == "/" then
        base_url_path = string.sub(base_url_path, 1, #base_url_path - 1)
    end

    local html_string = ""
    if post.images and #post.images >= 1 then

        for _, media in ipairs(post.images) do
            if media.image_url then
                html_string = html_string ..  string.format([[<img src="%s" />]], base_url_path .. proxy_url(media.image_url))
            elseif media.video_url then
                html_string = html_string .. string.format([[<video controls><source src="%s"></video>]], base_url_path .. proxy_url(media.video_url))
            end
        end
    else
        if post.image_url then
            html_string = html_string .. string.format([[<img src="%s"/>]], base_url_path .. proxy_url(post.image_url))
        elseif post.video_url then
            html_string = html_string .. string.format([[<video controls><source src="%s"></video>]], base_url_path .. proxy_url(post.video_url))
        end
    end
    if post.caption then
        html_string = html_string .. string.format([[<p>%s</p>]], u8_gsub(xml_escape(post.caption), "\n", "<br>"))
    end
    return html_string
end

local function create_feed_item(username, caption, link, timestamp, html_content)
    local title = xml_escape("Post by " .. username .. ": " .. utf8.sub(caption or "", 1, 100) .. "...")
    local iso_timestamp = date(timestamp):toutc():fmt("${iso}") .. "Z"
    local entry_xml = string.format([[
        <entry>
            <title>%s</title>
            <link rel="alternate" type="text/html" href="%s"/>
            <id>%s</id>
            <updated>%s</updated>
            <content type="html">%s</content>
        </entry>
    ]], xml_escape(title), xml_escape(link), xml_escape(link), xml_escape(iso_timestamp), xml_escape(html_content))
    return entry_xml
end

-- The base url path param is needed for generating urls.
local function create_feed_xml(username, posts)
    local base_url_path = config.base_atom_path
    local user_link = base_url_path .. username

    local self_link = user_link .. "/atom.xml"
    local first_timestamp
    if posts and #posts >= 1 then
        first_timestamp = posts[1].timestamp
    end
    local updated_timestamp = date(first_timestamp):toutc():fmt("${iso}") .. "Z"

    local feed_xml = string.format([[<?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom" xml:lang="en">
            <title>Posts by @%s</title>
            <link rel="alternate" type="text/html" href="%s" />
            <link rel="self" type="application/atom+xml" href="%s" />
            <id>%s</id>
            <updated>%s</updated>
            <author>
                <name>%s</name>
                <uri>%s</uri>
            </author>
    ]], xml_escape(username), xml_escape(user_link), xml_escape(self_link), xml_escape(user_link), updated_timestamp, xml_escape(username), xml_escape("https://www.instagram.com/" .. username))

    for _, post in ipairs(posts) do
        local html_content = create_html_content(post)
        local post_xml = create_feed_item(username, post.caption, base_url_path .. "p/" .. post.shortcode, post.timestamp, html_content)
        feed_xml = feed_xml .. post_xml
    end
    feed_xml = feed_xml .. "</feed>"
    return feed_xml
end

app:get("/:username/atom.xml(/)", function(self)
    if not config.enable_atom then
        return { "Atom is not enabled on this instance.", layout = false, content_type = "text/plain" }
    else
        local user = get_user(self.params.username, nil,  "all")
        if user.has_errors then
            return { "Error while fetching user.", layout = false, content_type = "text/plain" }
        else
            local feed_xml = create_feed_xml(self.params.username, user.posts)
            return { feed_xml, layout = false, content_type="application/atom+xml; charset=utf-8" }
        end
    end
end)
return app
