# Deck Video Fixer

[中文](README.md) | English


A tool for Steam Deck / Linux users to fix Proton video codec issues.

Its goal is not to "compress videos" or "optimize quality", but to fix common problems with game cutscenes under Proton/Wine—such as color bars, black screen, skipped videos, or no audio—with minimal invasiveness.

Typical targets include early KOEI TECMO games, retro Japanese PC games, old galgames, early Windows ports, and their common video formats: WMV, ASF, MPG/MPEG, legacy AVI, legacy MOV/QuickTime.

---

## Features

- Requires nothing besides [FFMPEG](https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz);
- Can be run directly in Steam Deck Desktop Mode;
- Uses `ffprobe` to scan video info, `ffmpeg` to transcode;
- By default only processes formats known to be problematic; leaves normal MP4/WebM/OGV untouched;
- Backs up original files before transcoding;
- Preserves original paths and filenames to reduce the chance of games failing to locate files;
- Supports restoring from backup;
- Supports multiple transcode strategies, selectable at startup;
- Supports slow download regions for FFMPEG: retry, resume, caching, manual offline package placement, and custom mirror URLs;

---

## Dependencies

- [FFMPEG](https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz)

---

## What Problems Does It Solve?

**Suitable for:**

- Game cutscenes displaying color bars, like an old TV with no signal.
- Game videos showing black screen, being skipped, or failing to play.
- External video files visible in the game directory, such as `.wmv`, `.asf`, `.mpg`, `.mpeg`, `.avi`, `.mov`.
- Issues under Proton / Wine / Steam Deck that don't occur on Windows.

**Not suitable for:**

- Game videos packed inside resource archives like `.cpk`, `.pac`, `.dat`.
- Game middleware videos (Bink/CRI), e.g. `.bik`, `.bk2`, `.usm`.
- Game crashes, save files, GPU drivers, anti-cheat, or launcher issues.
- General-purpose video compression needs (e.g., re-encoding all game videos to smaller sizes).

---

## Default Scan Scope

The tool focuses on legacy commercial/proprietary video formats common in old Windows and retro Japanese PC games.

**Formats known to be problematic (processed by default):**

```text
WMV / ASF / WMA:
.wmv .asf .wm
wmv1 wmv2 wmv3 vc1
wmav1 wmav2 wmapro wmavoice

MPG / MPEG:
.mpg .mpeg .m1v .m2v .vob
mpeg1video mpeg2video
mp1 mp2

Old AVI / Windows codec:
.avi
msvideo1 msrle msmpeg4v1 msmpeg4v2 msmpeg4v3
cinepak / cvid
indeo2 indeo3 indeo4 indeo5

Old MOV / QuickTime:
.mov .qt
svq1 svq3 qtrle rpza
```

**Skipped by default:**

```text
.bik .bk2 .smk .usm .cpk .acb .awb .pac
```

**Modern normal videos are left untouched by default, e.g.:**

```text
MP4 with H.264 + AAC
WebM with VP8/VP9 + Opus/Vorbis
OGV with Theora + Vorbis
```

---

## File Structure

After extraction, the layout looks like this:

```text
deck-video-fixer/
  deck-video-fixer.sh        # Main script
  get-ffmpeg-for-deck.sh     # Helper script to fetch static ffmpeg/ffprobe
  README.md
  LICENSE
```

Running `get-ffmpeg-for-deck.sh` will generate:

```text
bin/
  ffmpeg
  ffprobe

cache/
  ffmpeg-static.tar.xz  or other downloaded archives
```

---

## Quick Start on Steam Deck

Enter Desktop Mode, extract the tool, and open Konsole in the tool's directory:

```bash
chmod +x get-ffmpeg-for-deck.sh deck-video-fixer.sh
./get-ffmpeg-for-deck.sh
./deck-video-fixer.sh
```

The first run of `get-ffmpeg-for-deck.sh` will download the Linux x86_64 static build of `ffmpeg` and `ffprobe` into the tool's `bin/` directory. It does not modify the SteamOS system partition.

Afterwards, run the main tool:

```bash
./deck-video-fixer.sh
```

---

## Getting ffmpeg / ffprobe

This tool does not bundle ffmpeg. It is recommended to use the helper script to download a static build:

```bash
./get-ffmpeg-for-deck.sh
```

The tested URL is [this one](https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz), which downloads the latest build by default.

The script will prefer to reuse files in `cache/`, and will attempt to download from the network. It supports either `curl` or `wget`, whichever is available.

### If You're in a Region with Slow Downloads

If the default download source is slow, you can specify a mirror URL:

```bash
FFMPEG_STATIC_URL="https://your-mirror-url/ffmpeg-master-latest-linux64-gpl.tar.xz" ./get-ffmpeg-for-deck.sh
```

If you have a proxy set up:

```bash
HTTPS_PROXY="http://127.0.0.1:7890" ./get-ffmpeg-for-deck.sh
```

If downloading on Steam Deck is inconvenient, you can download the Linux x86_64 static FFmpeg archive on another machine (link above, GitHub download link), then copy it to:

```text
cache/
```

The script will recognize these common names:

```text
cache/ffmpeg-static.tar.xz
cache/ffmpeg-release-amd64-static.tar.xz
cache/ffmpeg-master-latest-linux64-gpl.tar.xz
cache/ffmpeg-master-latest-linux64-lgpl.tar.xz
```

It will also attempt to recognize other `.tar.xz` files in `cache/`, as long as they actually contain `ffmpeg` and `ffprobe`.

---

## How to Select a Game Directory

**Recommended method:**

1. Select the game in Steam.
2. Gear/Right-click → Manage → Browse local files.
3. In the Dolphin file manager that opens, copy the path from the address bar.
4. Run the tool and paste the path into the input prompt.

You can also pass the directory directly to the script:

```bash
./deck-video-fixer.sh "/path/to/game"
```

Or:

```bash
PVF_GAME_DIR="/path/to/game" ./deck-video-fixer.sh
```

The folder picker mode can be manually specified:

```bash
PVF_PICKER=input ./deck-video-fixer.sh      # Path input box
PVF_PICKER=native ./deck-video-fixer.sh     # System folder picker
PVF_PICKER=kdialog ./deck-video-fixer.sh    # KDE/kdialog
PVF_PICKER=zenity ./deck-video-fixer.sh     # zenity
PVF_PICKER=terminal ./deck-video-fixer.sh   # Terminal path input
```

The default mode first asks you to paste a path; if left blank, it opens the system folder picker.

---

## Usage Flow

0. Click the green `Code` button at the top-right of this page, then click `Download ZIP` at the bottom to download the project files.
1. Extract the downloaded ZIP, then:
   ```bash
   ./deck-video-fixer.sh
   ```
   Right-click on this file, select `Properties`, then choose `Permissions`, and check `Allow executing file as program (E)`, then click "OK". After that, double-click the script to run it.
2. Choose an action:
   ```text
   Scan & transcode to fix Proton compatibility issues
   Restore from backup
   Exit
   ```
3. Select the game directory.
4. Review the scan report.
5. Choose a transcode strategy.
6. Confirm to start backup and transcoding.
7. Review the log after transcoding finishes.
8. If everything succeeds, the tool will ask whether to delete the backup. It's recommended to keep it until you've confirmed the videos work in-game.

---

## Transcode Strategy Reference

Before transcoding starts, you'll be asked to choose a strategy.

```text
recommended     Use scan recommendation
h264_quality   H.264/AAC high quality, CRF 18
h264_balanced  H.264/AAC balanced, CRF 22
h264_fast      H.264/AAC fast, CRF 20 + veryfast
h264_small     H.264/AAC small size, CRF 27
h264_baseline  H.264 Baseline, old decoder compatibility
webm_vp9       WebM VP9/Opus fallback mode
mpeg_mci       MPEG-1/MP2, legacy MPG/MCI mode
mpeg2_mpg      MPEG-2/MP2, DVD-era MPG fallback
```

### Recommended Choices

For most cases, start with:

```text
recommended
```

For WMV/ASF/legacy AVI/legacy MOV:

```text
h264_quality or h264_balanced
```

For `.mpg/.mpeg` in retro Japanese PC games (if not working, try h264):

```text
mpeg_mci
```

If H.264 still shows color bars, try:

```text
webm_vp9
```

If disk space is tight:

```text
h264_small
```

If you suspect the game's player is very old:

```text
h264_baseline
```

You can also specify the strategy via environment variable, skipping the selection prompt:

```bash
PVF_TRANSCODE_MODE=recommended ./deck-video-fixer.sh
PVF_TRANSCODE_MODE=h264_balanced ./deck-video-fixer.sh
PVF_TRANSCODE_MODE=webm_vp9 ./deck-video-fixer.sh
PVF_TRANSCODE_MODE=mpeg_mci ./deck-video-fixer.sh
```

---

## Backup & Restore

Before transcoding, original files are backed up to a directory inside the game folder:

```text
.deck-video-fixer-backup/
  files/
  manifest.tsv
  last-run.log
```

For example:

```text
Game/Movie/opening.wmv
```

will be backed up to:

```text
Game/.deck-video-fixer-backup/files/Movie/opening.wmv
```

**To restore:**

```bash
./deck-video-fixer.sh
```

Then select:

```text
Restore from backup
```

The tool will copy files from `.deck-video-fixer-backup/files/` back to their original locations.

### Delete Backup After Transcoding?

The tool will ask by default. It is recommended to confirm in-game videos are working before deleting.

You can control this with an environment variable:

```bash
PVF_BACKUP_AFTER_SUCCESS=ask ./deck-video-fixer.sh     # Default, ask after completion
PVF_BACKUP_AFTER_SUCCESS=keep ./deck-video-fixer.sh    # Always keep
PVF_BACKUP_AFTER_SUCCESS=delete ./deck-video-fixer.sh  # Delete backup after full success
```

If any file fails to transcode, the backup is automatically retained.

---

## FAQ

### Will this break my game?

The tool backs up original files before replacing them. As long as the backup is not deleted, you can restore.

However, it does modify files in the game directory. It's recommended to process one game at a time, and test the opening cutscene or in-game videos first.

### Why keep the original filenames?

Many games look for resources at fixed paths, e.g. `Movie/opening.wmv`. If renamed to `opening.mp4`, the game may not find it. The tool places transcoded files back at the original path with the original filename.

### Why not process MP4 by default?

Normal H.264/AAC MP4 files should typically not need transcoding under Proton. If an MP4 has issues, it's more likely a problem with how the game calls Media Foundation rather than format incompatibility. To minimize unintended conversions, this tool only targets legacy commercial/proprietary codec formats by default.

### Why not handle `.bik` / `.bk2` / `.usm`?

These are typically game middleware or proprietary containers, not system codec issues. Converting them to MP4 and renaming back to the original extension will most likely result in the game being unable to read them.

### What happens after verifying game files?

Steam may restore replaced videos to their original versions. If the problem reappears, simply run the tool again.

### Can I scan multiple games at once?

It's not recommended. It's better to process one game directory at a time so that backup, logs, and restore are clear for each game.

---

## Quick Reference for Advanced Usage

```bash
# Specify game directory directly
./deck-video-fixer.sh "/path/to/game"

# Specify directory selection method
PVF_PICKER=input ./deck-video-fixer.sh
PVF_PICKER=terminal ./deck-video-fixer.sh

# Specify transcode strategy
PVF_TRANSCODE_MODE=h264_quality ./deck-video-fixer.sh
PVF_TRANSCODE_MODE=h264_balanced ./deck-video-fixer.sh
PVF_TRANSCODE_MODE=h264_small ./deck-video-fixer.sh
PVF_TRANSCODE_MODE=webm_vp9 ./deck-video-fixer.sh
PVF_TRANSCODE_MODE=mpeg_mci ./deck-video-fixer.sh

# Specify backup handling
PVF_BACKUP_AFTER_SUCCESS=keep ./deck-video-fixer.sh
PVF_BACKUP_AFTER_SUCCESS=delete ./deck-video-fixer.sh

# Use custom ffmpeg download URL
FFMPEG_STATIC_URL="https://example.com/ffmpeg-master-latest-linux64-gpl.tar.xz" ./get-ffmpeg-for-deck.sh

# Use a proxy
HTTPS_PROXY="http://127.0.0.1:7890" ./get-ffmpeg-for-deck.sh
```

---

## Design Principles

This tool follows three principles:

1. **Fix only problematic formats**: No blanket video optimization; don't touch normal videos by default.
2. **Backup first, then replace**: Save original files before any transcoding.
3. **User decides the strategy**: The scanner only gives recommendations; the final transcode preset is chosen by the user.

---

## Disclaimer

This tool is an unofficial community tool. It does not bypass DRM, modify game executables, or provide any game assets. It only processes external video files in the user's local game directory.

Before using, please confirm that you have the right to modify your local game files. Different games may read videos in different ways, so results cannot be guaranteed for every game.

---
