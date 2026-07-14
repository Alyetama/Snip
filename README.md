# Snip

A small Mac app for trimming video. Drop in a file, drag the two handles to the part you want to keep, and export. It plays inline while you work, and when you need to land on an exact frame, you can.

![Snip screenshot](docs/mockup.png)

## Download

**[⬇︎ Download for macOS](https://github.com/Alyetama/Snip/releases/latest/download/Snip.dmg)**

That link always points at the newest release, because the DMG filename has no
version number in it — see [Releases](https://github.com/Alyetama/Snip/releases) for the changelog.

## Features

- Drag a video anywhere into the window to load it. ⌘O and Finder's "Open With" work too.
- Two handles on a thumbnail timeline mark where the clip starts and ends.
- Click anywhere on the timeline to jump there and play from that spot — handy for hunting down the exact cut.
- Need a precise edit? Press and hold a handle for about half a second. It switches to frame mode, where every 8 pixels of drag moves one frame.
- Keyboard: space plays, arrows step a frame, shift-arrows jump a second, I and O set the in and out points, L loops, M mutes, ⌘E exports.
- Export two ways: lossless (instant, but the cut lands on the nearest keyframe) or re-encode (slower, lands on the exact frame). Re-encode shows you an estimated file size before you commit.
- Exports go to a temp file and swap in only if they succeed, so a failed export can't clobber a file you already had. It also won't let you overwrite the original.

One caveat: frame *stepping* is always exact, but the frame numbers Snip shows assume a steady frame rate. On variable-frame-rate recordings (some screen captures, phone HDR) they'll be close, not perfect.

## First launch (opening an unsigned app)

**Snip isn't signed with an Apple Developer ID**, so macOS blocks it the
first time you open it. This is expected — you only need to do one of the
following once, and it opens normally afterward.

**1. Right-click to open.** In Finder, **Control-click** (or right-click)
`Snip`, choose **Open**, then click **Open** again in the dialog.

**2. If macOS still won't let you (newer versions):** open
**System Settings → Privacy & Security**, scroll down to the message about
`Snip` being blocked, and click **Open Anyway**. Confirm with
**Open Anyway** (and Touch ID or your password if asked).

**3. Terminal fallback.** If neither works, remove the quarantine flag and open
it normally:

```bash
/usr/bin/xattr -dr com.apple.quarantine /Applications/Snip.app
```

(Adjust the path if you keep the app somewhere other than `/Applications`.)

## Build from source

```bash
git clone https://github.com/Alyetama/Snip.git
cd Snip
./build_app.sh          # → build/Snip.app
```

Needs macOS 15+ and the Xcode command line tools. Pure SwiftUI and AVFoundation, no dependencies.

## License

[MIT](LICENSE) © 2026 Alyetama
