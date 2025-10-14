# 🎬 DragTranscribe (macOS)

**Drag a video into the app and get a `.srt` subtitle and a subtitled `.mp4` automatically and offline.**  

---

## ✨ What it does

- ✅ Generates a standard `.srt` subtitle file  
- ✅ Creates `YourVideo_subbed.mp4` with **soft** subtitles (QuickTime-friendly)  
- 🧠 Auto language detection; translates to English when needed!  
- 🔒 100% local processing (privacy-friendly)  
- 🧰 Batch mode supported

---

## 🧩 Requirements

- macOS **12.0+** on **Apple Silicon** (M1/M2/M3)  
- ~**3 GB** free disk for the AI model download (first run only)  
- Internet connection for the one-time model download

---

## 📦 Install (DMG)

1. **Download** `DragTranscribe-1.0.0.dmg` from the Releases on the top-right side of this page.
2. **Open** the DMG.
3. **Drag the entire `DragTranscribe` folder** to the **Applications** shortcut in the DMG window.  
4. Eject the DragTranscribe DMG on your Desktop.

Your Applications folder should now contain:

```
/Applications/DragTranscribe/
├─ DragTranscribe.app
├─ 1-Allow-Run.command
├─ 2-Download-Model.command
├─ Transcribe.command
├─ bin/        (ffmpeg, whisper-cli, transcribe.sh)
└─ models/     (AI model is downloaded here on first run)
└─ video/     (test.mp4 for you to test with. Also for batch processing)
```

---

## ▶️ First-time setup (one-time)

1. Open **/Applications/DragTranscribe/**.
2. Double-click **`1-Allow-Run.command`**  
   - Clears macOS quarantine flags and sets execute permissions.
   - If macOS warns you, choose **Open** (or **System Settings → Privacy & Security → Open Anyway**).

> Gatekeeper tip: If the app is blocked, **Right-click → Open → Open** to approve it once.

---

## 🚀 Use the app

1. Launch **`DragTranscribe.app`**.  
   - The app will **auto-detect** its install folder. If it can’t, click **Set Install…** and choose the `DragTranscribe` folder in **Applications**.
2. **First model download** (one-time):
   - If the model isn’t present when transcribing, the app will prompt to download it (~3 GB) into `models/`. This will take a while so be patient.
   - Or run **`2-Download-Model.command`** manually to fetch it ahead of time.
3. **Transcribe a single file**:
   - Drag a video (`.mp4`, `.mov`, `.mkv`, `.webm`, `.avi`) into the app window.
   - **Transcribe starts automatically** and watch the log.
   - Subtitles file and subbed video appear next to your video:
     - `YourVideo.srt`
     - `YourVideo_subbed.mp4`

---

## 📁 Batch mode (multiple files)

1. Put videos into:  
   `/Applications/DragTranscribe/video/`
2. Double-click **`Transcribe.command`**.  
   The script:
   - Skips files already having `.srt` or named with `_subbed`
   - Produces `.srt` and `_subbed.mp4` next to each original

---

## 🔧 Troubleshooting

- **App says it can’t open**  
  → Right-click the app → **Open** → **Open** (one-time approval)

- **“Model not found”**  
  → Accept the in-app prompt for model download **or** run `2-Download-Model.command`

- **Nothing happens when running scripts**  
  → Make sure you ran **`1-Allow-Run.command`** once

---

## 🔒 Full Privacy

All audio/video/subtitles stays on your Mac. No data leaves your machine.

---
