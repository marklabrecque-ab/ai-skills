---
name: playlist-builder
description: "Build a YouTube music playlist from a mood/likes/dislikes descriptor. Use whenever the user wants a custom playlist, mixtape, or set of songs assembled on YouTube — e.g. 'make me a playlist of moody synthwave for late-night coding', 'build a 2-hour upbeat workout mix', 'mixtape for a rainy Sunday, no country'. Curates the tracklist from training knowledge first, then searches each track on YouTube and assembles the playlist."
---

# YouTube Playlist Builder

Assemble a YouTube music playlist from a free-form descriptor that may include moods, genres, eras, reference artists, and dislikes.

## Required tools

This skill relies on the `youtube` MCP server. The user must have these tools available:

- `mcp__youtube__search_videos`
- `mcp__youtube__create_playlist`
- `mcp__youtube__add_to_playlist`

If any are missing, stop and tell the user to install/authenticate the youtube MCP before retrying.

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

## Step 3 — Resolve each track on YouTube

After the user confirms, for each track:

1. Call `mcp__youtube__search_videos` with a query like `"<Artist> <Title>"`. Ask for ~3 results so you can pick the best.
2. Choose the best match using this priority:
   - Official artist channel / "VEVO" upload
   - Official audio / "Topic" channel auto-uploads (these are official)
   - Highest-view canonical upload from a reputable source
   - Avoid: covers, karaoke, slowed/reverb edits, fan-made lyric videos, "8D audio" remixes — unless the descriptor specifically asked for that style
3. Record the video ID. If no acceptable match exists, note it as **unresolved** and continue; do not substitute a random track silently.

Run searches in parallel where possible (multiple tool calls in one assistant turn) to keep things fast.

## Step 4 — Create the playlist and add tracks

1. Call `mcp__youtube__create_playlist` with:
   - A descriptive title derived from the descriptor (e.g. "Late-night synthwave — moody coding mix")
   - A short description that summarizes the mood and notes it was Claude-curated
   - Default to **private** privacy unless the user explicitly asked for public/unlisted
2. For each resolved video, call `mcp__youtube__add_to_playlist` with the playlist ID and video ID, preserving the curated order.

## Step 5 — Report back

Give the user:

- The playlist URL (or title + ID if URL isn't returned by the MCP)
- Total tracks added vs. requested
- A list of any **unresolved** tracks with a one-line reason each
- An offer to find replacements for the unresolved ones, or to swap any tracks the user wants changed

## Notes on judgment

- "Likes" are inspiration, not a hard menu — feel free to pull in adjacent artists the user didn't name if they fit the mood.
- "Dislikes" are absolute — never override them.
- If the descriptor is contradictory (e.g. "upbeat melancholy") lean into the tension rather than averaging it out, and call out the interpretation in your reply.
