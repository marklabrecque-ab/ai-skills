---
name: playlist-builder
description: "Build a YouTube music playlist from a mood/likes/dislikes descriptor. Use whenever the user wants a custom playlist, mixtape, or set of songs assembled on YouTube — e.g. 'make me a playlist of moody synthwave for late-night coding', 'build a 2-hour upbeat workout mix', 'mixtape for a rainy Sunday, no country'. Curates the tracklist from training knowledge first, then searches each track on YouTube and assembles the playlist."
---

# YouTube Playlist Builder

Assemble a YouTube music playlist from a free-form descriptor that may include moods, genres, eras, reference artists, and dislikes.

## Required tools

This skill relies on the `youtube-playlist-url` MCP server (a minimal read-only server bundled with this plugin at `mcp-server/index.js`). The user must have these tools available:

- `mcp__youtube-playlist-url__search_video`
- `mcp__youtube-playlist-url__build_playlist_url`

If they're missing, the MCP probably failed to start because `yt-dlp` is not installed. Tell the user to run the setup script:

```bash
bash <plugin-dir>/mcp-server/setup.sh
```

The script checks for Homebrew, installs `yt-dlp` if missing, and runs `npm install`. Then they restart Claude Code.

This skill does **not** create the playlist via the YouTube write API (which would require OAuth and a verified app for the restricted `youtube` scope). Instead, the MCP uses `yt-dlp` to resolve track names to video IDs (no API key, no quota), and the user installs a one-time bookmarklet that adds the videos to a playlist using their existing logged-in YouTube session via the same internal Innertube API the **Save** button uses.

## Inputs

The descriptor may arrive as `$ARGUMENTS` (from the `/youtube-playlist-builder:playlist` command) or as conversational text. Parse it into:

- **Moods / vibes** (e.g. "moody", "upbeat", "melancholic")
- **Likes**: genres, reference artists, eras
- **Dislikes**: genres, artists, or styles to exclude
- **Duration**: target playlist length (e.g. "1 hour", "90 minutes", "an album-length set")

## Step 1 — Confirm duration

If the descriptor does **not** include a duration or track count, ask the user how long they want the playlist to be before proceeding. Do not guess a default. Accept either a time period ("about an hour", "2 hours") or an explicit track count ("15 songs").

Once a duration is known, convert to a track target using **~4 minutes/track** as the average:

- 30 min → 7–8 tracks
- 1 hour → 15 tracks
- 90 min → 22 tracks
- 2 hours → 30 tracks

If the user gave an explicit track count, use that number directly.

## Step 2 — Curate the tracklist

Generate the tracklist yourself from your training knowledge — do **not** search YouTube to discover tracks. For each slot, pick a specific `Artist — Title` pair that fits the descriptor.

Guidelines:

- Honor every dislike. If the user said "no country", do not include country tracks even if they fit other criteria.
- Mix well-known anchors with deeper cuts; avoid having every track be from the same artist (cap any single artist at ~2 tracks unless the user asked for an artist-focused mix).
- Sequence the list with intent (e.g. open strong, build energy, land softer if "late-night" / "wind-down" is implied).
- Prefer canonical studio recordings over live versions or covers unless the descriptor asks otherwise.

Present the proposed tracklist to the user as a numbered list of `Artist — Title` and ask for confirmation (or edits) **before** searching YouTube. This avoids wasted API calls if the curation is off.

## Step 3 — Resolve tracks to video IDs

After the user confirms the tracklist, call `mcp__youtube-playlist-url__build_playlist_url` **once** with the full ordered list of track query strings (e.g. `"Chemical Brothers Galvanize"`). The MCP resolves each track to the top YouTube search result and returns:

```json
{
  "url": "https://www.youtube.com/watch_videos?video_ids=...",
  "resolved": [{ "track": "...", "videoId": "...", "title": "...", "channel": "..." }],
  "unresolved": [{ "track": "...", "videoId": null }]
}
```

The `url` field is included by the MCP but **ignored by this skill** — the `watch_videos` endpoint is unreliable (YouTube progressively broke it; it often redirects to a single video). The skill uses the `resolved[].videoId` list instead, paired with a bookmarklet on the user's side.

Use `mcp__youtube-playlist-url__search_video` per track if a top match looks suspect (cover, karaoke, slowed/reverb, lyric-only video) and refine the query.

Also watch for **duplicate `videoId`s in `resolved`** — that means two different track queries collapsed to the same YouTube video (e.g. a generic title matching a more popular release). Re-search the offending track with a more specific query.

## Step 4 — Hand off to the bookmarklet

The user installs the bundled bookmarklet (`bookmarklet/add-to-playlist.bookmarklet.txt`) once. It adds a batch of videos to one of their YouTube playlists using their existing signed-in session, via YouTube's internal Innertube API. No OAuth, no API key for the write step.

Push the comma-separated video IDs to the user's clipboard with `pbcopy` so terminal wrap artifacts can't corrupt them:

```bash
printf '%s' 'Xu3FTEmN-eg,ub747pprmJ8,...' | pbcopy
```

Then tell the user:

1. **"IDs are on your clipboard."** (Do not also paste the long ID string into the chat — that re-introduces the wrap-and-copy problem the clipboard hand-off was meant to solve. If you want to show them, list 2–3 IDs as a sanity check, not all 30.)
2. **A reminder of the per-playlist steps** (compressed if the user has done this before):
   - Open YouTube Studio → **Content → Playlists → New playlist** → name → Create. Open it and copy the `PL...` part from the URL (or just the whole URL — the bookmarklet parses both).
   - On any youtube.com tab, click the **YT: Add to Playlist** bookmarklet.
   - Paste the playlist ID/URL at the first prompt. The bookmarklet reads the video IDs directly from the clipboard, shows a confirm dialog with the count + preview, and adds them.
3. **Total tracks resolved vs. requested**, and any **unresolved** tracks with a one-line reason each.
4. **An offer to swap any tracks** the user wants changed (which would re-run `pbcopy` with a new list).

If the user has not yet installed the bookmarklet, link them to `bookmarklet/README.md` and walk them through it.

## Notes on judgment

- "Likes" are inspiration, not a hard menu — feel free to pull in adjacent artists the user didn't name if they fit the mood.
- "Dislikes" are absolute — never override them.
- If the descriptor is contradictory (e.g. "upbeat melancholy") lean into the tension rather than averaging it out, and call out the interpretation in your reply.
