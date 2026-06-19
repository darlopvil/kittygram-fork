
local cache = {
    -- the time it takes for a cached item to expire, in seconds.
    -- Positive is for when an item is found, negative for if an item doesn't exist.
    expire_times = {
        posts = {
            negative = 1800,
            positive = 3600
        },
        user_info = {
            positive = 86400,
            negative = 0, -- this value isn't used currently. May be used in future.
        },
        user_timelines = {
            latest = 300, -- how long the latest batch of posts by a user are cached for. This is only a short amount of time as new posts wouldn't be fetched often enough otherwise.
            with_cursor = 3600, -- how long a batch of posts with a cursor (timeline continuation) are cached for.
            negative = 3600, -- if a user isn't found/doesn't exist
        },
        explore = 3600 * 3,
        comments = 3600,
        popular_index = 3600 * 6 -- This doesn't really include much dynamic content, so it can be cached for a long time.
    }
}

return cache
