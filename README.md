# DragTranscribe

DragTranscribe creates subtitle files and embeds them into videos. Drop a video file, and it will generate accurate subtitle file (`.srt`) and create a new, subtitled version of your video (`_subbed.mp4`).  

Powered by OpenAI’s Whisper AI model, the app not only transcribes English audio into English subtitles but can also translate speech from 100 languages into English subtitles.

It's designed to be simple, private, and work entirely on your computer. This is especially for deaf people who need subtitled videos to understand what's being said.

## How to Install and Use

Follow these steps carefully to get the app working on Mac computers with Apple Silicon (M1, M2, M3, M4, or M5 chips).

### Step 1: Download the App

1.  Go to the [**Releases page**](https://github.com/jaredevans/DragTranscribe/releases/tag/1.0) on GitHub.
2.  Download the `DragTranscribe-1.0.0.dmg` file.

### Step 2: Install the App

1.  Open the `DragTranscribe-1.0.0.dmg` file you downloaded.
2.  A new window will appear. Drag the **DragTranscribe** folder into your **Applications** folder.

### Step 3: Give the App Permission to Run (Very Important!)

macOS has security features that you need to approve manually for the app to work. You only need to do this once.

1.  Go to your **Applications** folder and open the **DragTranscribe** folder.
2.  Double-click the `1-Allow-Run.command` file.
3.  You will likely see a warning that says the file cannot be opened. Click **OK**.
4.  Open **System Settings** > **Privacy & Security**.
5.  Scroll down to the "Security" section. You will see a message that "`1-Allow-Run.command` was blocked." Click the **Open Anyway** button.
6.  A terminal window will open and run a quick setup. It will close automatically.

### Step 4: Start Transcribing!

1.  In the **DragTranscribe** folder, double-click the **DragTranscribe.app** to open it.
2.  The first time you open it, you may see another security warning. Just like before, go to **System Settings** > **Privacy & Security** and click **Open Anyway**.
3.  Drag any video file from your computer and drop it onto the app window.

### Step 5: Download the AI Model (First Time Only)

1.  The first time you drop a file, the app will ask if you want to download the AI model. This is a large file (about 3 GB), so it may take some time.
2.  Click **Download**. The app will show the download progress in its window. Please be patient.
3.  Once the download is complete, the transcription will start automatically.

### What Happens Next

The app can handle multiple video files dragged and dropped at once. It will batch process them, one at a time.

For each file you drop on the app, it will:

1.  **Create a subtitle file:** A file named `YourFileName.srt` will be saved in the same folder as the original file. This is a standard subtitle file you can use with media players like VLC.
2.  **Create a subtitled video:** A new video file named `YourFileName_subbed.mp4` will also be created. This new video has the subtitles embedded in it, so you can see them when you play it in QuickTime or other players.

The app is smart: if it sees that a video already has a `.srt` file or a `_subbed.mp4` version, it will skip it. There is a `test.mp4` about Lincoln in the `/video` directory you can drag and drop to test out the subtitles.

## License

This software is available under the [MIT License](LICENSE).
