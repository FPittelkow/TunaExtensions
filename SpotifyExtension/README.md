# Spotify

Control the Spotify desktop app, search Spotify, and browse your saved music and playlists from Tuna.

## Setup

1. Install the extension and restart Tuna.
2. Open Tuna’s extension settings and connect Spotify.
3. Allow Tuna to control Spotify when macOS asks. Local playback controls use Spotify’s AppleScript support.

Spotify Web API access is used for search, library browsing, saves, queueing, and playlist writes. Spotify Premium is required for Web API playback features; local desktop controls may still work without Premium.

Spotify development-mode apps only expose playlist contents for playlists the connected user owns or collaborates on. Search can still find other playlists for playback or opening in Spotify, but Tuna only browses owned and collaborative playlists from Your Library.

The shared Spotify application is currently limited to five explicitly allowlisted users. Public distribution requires Spotify Extended Quota approval.
