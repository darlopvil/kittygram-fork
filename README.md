# kittygram-fork

An independent fork of [Kittygram](https://codeberg.org/irelephant/kittygram) by
[irelephant](https://codeberg.org/irelephant), an anonymous, lightweight
Instagram frontend inspired by [Nitter](https://github.com/zedeus/nitter).

This is a fork in its own right, not a fork for contributing back: it follows
its own direction and changes are not sent upstream. It powers a personal
instance, but issues and pull requests are welcome here. For the original
project, its public instances and its community, see the
[upstream repository](https://codeberg.org/irelephant/kittygram).

## What this fork changes

- **Working authenticated search.** With an optional web session, search queries
  Instagram live through `PolarisSearchBoxRefetchableQuery`. The session tokens
  (`fb_dtsg`, `lsd`, actor id, build tokens) are read from an authenticated page,
  cached in Redis and refreshed automatically when Instagram rejects them. See
  [`lib/instagram/web/session.lua`](lib/instagram/web/session.lua).
- **Local search fallback.** If live search fails or no session is configured,
  results come from the local index of users the instance has already seen.
  Profiles are indexed from every view, and queries are normalized, so
  `tomb raider`, `@TombRaider` and 1-2 character prefixes all match.
- **No leaks on error pages.** Raw Instagram responses are no longer shown on
  error pages, API errors or logs, unless `show_error_details` is enabled.
- **GraphQL overrides.** Rotated `doc_id`s can be fixed from `config.lua`
  (`graphql_overrides`) without rebuilding the image.
- **Persistent database and automatic migrations.** SQLite lives in the `data/`
  volume and pending migrations run on every container start.
- **No public instance list.** No runtime download of `instances.json` and no
  random-instance links.
- **Profiles that work again.** List and tile views and full-media Atom feeds
  go through the web session (`use_for.user_posts`), since Instagram now
  requires login for them; without it, profiles are shown as a grid. Private
  profiles show a notice instead of an error. The post count, now hidden from
  anonymous visitors, comes from the session too (`use_for.user_info`).
- **Atom feeds** (`/<user>/atom.xml`) for any feed reader, served from the
  cache, newest post first.
- **Stories and highlights** (`use_for.stories`): a stories and highlights
  tray on profiles, `/stories/<user>` and `/stories/highlights/<id>`. Only the
  media is requested: stories are never marked as seen, so the session account
  does not show up in their viewers list.
- **Tagged posts** (`use_for.tagged`): a Tagged tab on profiles,
  `/<user>/tagged`, with the posts other accounts tagged the profile in, as a
  grid with pagination.
- **Embeds** for iframes on Instagram's own paths, so an embed URL only needs
  its host replaced: `/p/<code>/embed` and `/reel/<code>/embed` show the post
  alone (author, media, date and a link to the full post), and
  `/embed/captioned` adds the caption. No navbar, no JavaScript, no comments,
  media through the proxy, and `?theme=dark` for a dark variant. The view
  fills whatever frame it gets: the media takes the space left by the author,
  caption and footer, a long caption scrolls in its own area, and carousels
  show one item at a time in a row that scrolls sideways.
- **Gentler with Instagram's limits.** A 429 from GraphQL counts as a rate
  limit, so profiles fall back to the web session instead of failing. When
  Instagram redirects anonymous profile pages to its login page, the instance
  stops requesting them for a pause that doubles while the redirect continues,
  up to `ratelimits.login_wall_max_cooldown` (2 hours by default), instead of
  retrying every 11 minutes.
- **Quieter, more useful logs.** Database queries are only logged with
  `LOG_QUERIES=true`. A profile shown without its highlights tray logs the
  reason. Pages answer `OPTIONS` requests, sent by some feed readers, instead
  of failing with a 500.

## Deployment

Requires Docker with Compose, plus Git LFS for the static assets.

```bash
git clone https://github.com/darlopvil/kittygram-fork.git kittygram && cd kittygram
git lfs pull
cp config.example.lua config.lua
cp compose.example.yaml docker-compose.yml
mkdir -p data
sudo chown 65534:65534 data
sudo chown 1000:65534 config.lua && sudo chmod 640 config.lua
docker compose up -d --build
```

- Change `secret` in `config.lua`, and write your own `about_message`: it is
  shown at the top of the home page.
- The container serves as `nobody` (65534): `config.lua` must be readable by
  that group and `data/` writable by it.
- Edit `config.lua` in place (e.g. with `nano`). `sed -i` recreates the file and
  resets its owner and permissions.
- To update: `git pull && docker compose up -d --build`. Migrations run on start.

### Monitoring

Every check of a page that shows Instagram content (profiles, posts, search,
stories, tagged posts) sends requests to Instagram. Frequent checks, or checks
that run at the same moment, look like automation to Instagram and end up
rate limited, often more than real visitors would ever be. Check the instance
itself often (`/`, and `/api/status`, which only reports the instance's own
rate-limit state), and pages with Instagram content every few hours, with
intervals that are not multiples of each other so they never run together.

### Atom feeds (optional)

Set `enable_atom = true` and `base_atom_path` (the instance's public URL, with
a trailing slash) in `config.lua`, or the `ENABLE_ATOM=true` and
`BASE_ATOM_PATH` environment variables in the docker environment. With the web
session enabled for `user_posts`, entries carry the full media and the real
date; without it, they are built from the anonymous grid (thumbnail, caption
and the date decoded from the media id). All media goes through `/mediaproxy`.

### Web session (optional)

Live search needs a logged-in Instagram session. Use a dedicated account:
Instagram may restrict or ban accounts used this way.

1. Log in with that account in a private window and copy these cookies:
   `sessionid`, `csrftoken`, `ds_user_id`, `mid`, `ig_did`.
2. In `config.lua`, set `web_session.cookies` to
   `"sessionid=...; csrftoken=...; ds_user_id=...; mid=...; ig_did=..."`.
3. Optionally set `web_session.user_agent` to the user agent of that browser.
4. Enable `web_session.use_for` only where it is needed: `search` for live
   search, `user_posts` for list and tile views and full-media feeds,
   `user_info` for the post count on profiles, `stories` for stories and
   highlights, and `tagged` for the Tagged tab.
   Grids, posts and comments work anonymously, and routing more through the
   account only increases the risk of losing it.

Keep `show_error_details = false` when a session is configured: raw responses
can reveal the account.

## License

[AGPL-3.0](LICENSE), as the original project. Kittygram is © irelephant and its
contributors; the changes in this fork are © darlopvil. Anyone running a
modified version as a network service must offer its source to the service's
users: the home page links to this repository.

Icon by [nulla](https://codeberg.org/nulla).
