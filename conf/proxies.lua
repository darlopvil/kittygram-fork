-- to configure proxies, replace "false" with the proxies url.
-- note: use 127.0.0.1 instead of localhost.
-- This only supports http proxies, not SOCKS.


local proxies = {
    posts = false, -- Posts/reels, anything with a shortcode.
    user_info = false,
    search = false,
    user_posts = false,
    comments = false,
    explore = false,
    -- A user's page (e.g., https://www.instagram.com/{username}). Requests are only sent to these pages if the user has no posts, and their ID hasn't been saved before.
    -- this page can be ratelimited heavily.
    user_page = false,
}

return proxies
