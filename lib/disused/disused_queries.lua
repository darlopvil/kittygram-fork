local doc_ids = {
    logged_out_user_posts = {
        doc_id = "7950326061742207",
        endpoint = "query",
        method = "GET"
    },

}
-- queries that aren't used currently.
local unused_queries = {
    -- the logged_out posts query. This takes an id rather than a username. Probably doesn't work with cookies/auth.
    logged_out_user_posts = function(user_id, count, after_cursor)
        if not after_cursor then
            after_cursor = json.null
        end
        return {
            id = user_id,
            after = after_cursor,
            first = count
        }, doc_ids.logged_out_user_posts
    end,
}
