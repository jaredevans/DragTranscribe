# app.py — simplified install detection without persisting preferences
import os, sys, unicodedata, subprocess, threading, objc, pathlib
from AppKit import (
    NSApplication, NSApp, NSWindow, NSView, NSButton, NSTextField, NSTextView,
    NSScrollView, NSFont, NSAlert,
    NSMakeRect, NSBackingStoreBuffered,
    NSWindowStyleMaskTitled, NSWindowStyleMaskClosable, NSWindowStyleMaskResizable,
    NSViewWidthSizable, NSViewHeightSizable, NSViewMinYMargin,
    NSDragOperationCopy, NSSmallSquareBezelStyle
)
from Foundation import NSURL, NSBundle

APP_ID = "com.example.dragtranscribe"

def _normalize(p: str) -> str:
    return unicodedata.normalize("NFC", p)

def _run_transcribe_stream(cmd_argv, on_line, on_done):
    try:
        env = os.environ.copy()
        env.setdefault("LC_ALL", "en_US.UTF-8")
        env.setdefault("LANG", "en_US.UTF-8")
        env.setdefault("PYTHONIOENCODING", "utf-8")

        p = subprocess.Popen(
            cmd_argv,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            env=env,
        )
        assert p.stdout is not None
        for line in p.stdout:
            on_line(line.rstrip("\n"))
        rc = p.wait()
    except Exception as e:
        on_line(f"[exception] {e!r}")
        rc = 1
    finally:
        on_done(rc)

def _app_parent_dir() -> str | None:
    try:
        mb = NSBundle.mainBundle()
        if mb is not None:
            bundle_path = str(mb.bundlePath())
            if bundle_path.endswith(".app"):
                return os.path.dirname(bundle_path)
    except Exception:
        pass
    return None

def _detect_install_dir() -> str | None:
    parent = _app_parent_dir()
    if parent and os.path.isfile(os.path.join(parent, "bin", "transcribe.sh")):
        return parent
    env_override = os.environ.get("DRAGTRANSCRIBE_INSTALL_DIR")
    if env_override and os.path.isfile(os.path.join(env_override, "bin", "transcribe.sh")):
        return env_override
    return None

class AppState:
    def __init__(self):
        self.install_dir = _detect_install_dir()

    def transcribe_cmd(self):
        if not self.install_dir:
            return None
        return os.path.join(self.install_dir, "bin", "transcribe.sh")

    def model_dir(self):
        return os.path.join(self.install_dir, "models") if self.install_dir else None

    def model_file(self):
        d = self.model_dir()
        return os.path.join(d, "ggml-large-v2.bin") if d else None

    def download_script(self):
        return os.path.join(self.install_dir, "bin", "download_model.sh") if self.install_dir else None

class DropView(NSView):
    DROP_TYPES = ["public.file-url", "public.url", "NSFilenamesPboardType"]

    def initWithFrame_textField_output_state_(self, frame, text_field, output_view, state):
        self = objc.super(DropView, self).initWithFrame_(frame)
        if self is None:
            return None
        self.text_field = text_field
        self.output_view = output_view
        self.state = state
        self.registerForDraggedTypes_(self.DROP_TYPES)
        return self

    def appendOutput_(self, s):
        existing = self.output_view.string() or ""
        if existing and not existing.endswith("\n"):
            existing += "\n"
        self.output_view.setString_(existing + s)
        self.output_view.scrollRangeToVisible_((len(self.output_view.string()), 0))

    def append_output_async(self, s: str):
        self.performSelectorOnMainThread_withObject_waitUntilDone_("appendOutput:", s, False)

    def clearOutput_(self, _):
        self.output_view.setString_("")

    def _show_reinstall_alert(self):
        alert = NSAlert.alloc().init()
        alert.setMessageText_("Install folder not found")
        alert.setInformativeText_(
            "DragTranscribe couldn’t locate its install folder.\n\n"
            "Make sure you installed the *entire* DragTranscribe folder into /Applications,\n"
            "then launch DragTranscribe.app from there."
        )
        alert.addButtonWithTitle_("OK")
        alert.runModal()

    def _ensure_model_then(self, cont_fn):
        model_path = self.state.model_file()
        if model_path and os.path.isfile(model_path):
            cont_fn()
            return

        alert = NSAlert.alloc().init()
        alert.setMessageText_("Whisper model missing")
        alert.setInformativeText_(
            "The AI model is not installed.\n\n"
            "Click Download to get it now (about 3 GB).\n"
            "Be patient — this only needs to be done once."
        )
        alert.addButtonWithTitle_("Download")
        alert.addButtonWithTitle_("Cancel")
        resp = alert.runModal()

        if resp != 1000:
            self.append_output_async("Download canceled.")
            return

        dl = self.state.download_script()
        if not (dl and os.path.isfile(dl) and os.access(dl, os.X_OK)):
            self.append_output_async(f"Error: download script not found or not executable:\n{dl}")
            return

        self.append_output_async(f"Starting model download (~3 GB) to:\n{self.state.model_dir()}\n$ {dl}\n")

        def bg_download():
            def on_line(line): self.append_output_async(line)
            def on_done(rc):
                if rc == 0 and os.path.isfile(self.state.model_file()):
                    self.append_output_async("✅ Model download complete.")
                    cont_fn()
                else:
                    self.append_output_async(
                        f"❌ Download failed (exit {rc}). "
                        "Try again later or run 2-Download-Model.command."
                    )
            _run_transcribe_stream([dl], on_line, on_done)

        threading.Thread(target=bg_download, daemon=True).start()

    def start_transcribe_for_path(self, path: str):
        self.performSelectorOnMainThread_withObject_waitUntilDone_("clearOutput:", "", False)

        script = self.state.transcribe_cmd()
        if not script or not os.path.isfile(script):
            self.append_output_async("Error: Install folder not found. Please reinstall DragTranscribe to /Applications.")
            self._show_reinstall_alert()
            return
        if not os.access(script, os.X_OK):
            self.append_output_async(
                f"Error: script is not executable:\n{script}\n"
                "Run 1-Allow-Run.command once, then try again."
            )
            return

        def run_transcribe():
            argv = [script, path]
            def bg():
                self.append_output_async(f"$ {' '.join(argv)}\n")
                def on_line(line): self.append_output_async(line)
                def on_done(rc):   self.append_output_async(f"\n[exit {rc}]")
                _run_transcribe_stream(argv, on_line, on_done)
            threading.Thread(target=bg, daemon=True).start()

        self._ensure_model_then(run_transcribe)

    def draggingEntered_(self, sender):
        return NSDragOperationCopy

    def draggingUpdated_(self, sender):
        return NSDragOperationCopy

    def prepareForDragOperation_(self, sender):
        return True

    def _path_from_url(self, u: NSURL):
        try:
            if hasattr(u, "isFileURL") and u.isFileURL():
                return u.path()
            if hasattr(u, "filePathURL"):
                fpu = u.filePathURL()
                if fpu is not None:
                    return fpu.path()
        except Exception as e:
            print(f"[path_from_url] error: {e}")
        return None

    def performDragOperation_(self, sender):
        pb = sender.draggingPasteboard()

        urls = pb.readObjectsForClasses_options_([NSURL], None)
        if urls:
            for u in urls:
                p = self._path_from_url(u)
                if p:
                    p = _normalize(p)
                    self.text_field.setStringValue_(p)
                    self.output_view.setString_("")
                    self.start_transcribe_for_path(p)
                    return True

        try:
            files = pb.propertyListForType_("NSFilenamesPboardType")
        except Exception:
            files = None
        if files and len(files) > 0:
            p = _normalize(files[0])
            self.text_field.setStringValue_(p)
            self.output_view.setString_("")
            self.start_transcribe_for_path(p)
            return True

        return False

    def concludeDragOperation_(self, sender):
        pass

def build_ui():
    app = NSApplication.sharedApplication()
    state = AppState()

    style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
    window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
        NSMakeRect(200, 200, 760, 420), style, NSBackingStoreBuffered, False
    )
    window.setTitle_("DragTranscribe")

    content = window.contentView()
    bounds = content.bounds()
    margin = 16.0

    path_field = NSTextField.alloc().initWithFrame_(NSMakeRect(
        margin,
        bounds.size.height - margin - 32,
        bounds.size.width - (margin * 2),
        28
    ))
    path_field.setEditable_(False)
    path_field.setBezeled_(True)
    path_field.setSelectable_(True)
    path_field.setStringValue_("Drop a file to start transcribing…")
    path_field.setAutoresizingMask_(NSViewWidthSizable | NSViewMinYMargin)
    path_field.unregisterDraggedTypes()

    quit_btn = NSButton.alloc().initWithFrame_(NSMakeRect(
        bounds.size.width - margin - 80.0,
        margin,
        80.0, 28.0
    ))
    quit_btn.setTitle_("Quit")
    quit_btn.setBezelStyle_(NSSmallSquareBezelStyle)
    quit_btn.setTarget_(NSApp())
    quit_btn.setAction_("terminate:")
    quit_btn.setAutoresizingMask_(NSViewMinYMargin)

    output_top = path_field.frame().origin.y - 12.0
    output_height = output_top - (margin + 32)
    scroll_frame = NSMakeRect(margin, margin + 36, bounds.size.width - (margin * 2), output_height)
    scroll = NSScrollView.alloc().initWithFrame_(scroll_frame)
    scroll.setHasVerticalScroller_(True)
    scroll.setHasHorizontalScroller_(False)
    scroll.setAutoresizingMask_(NSViewWidthSizable | NSViewHeightSizable)

    text_view = NSTextView.alloc().initWithFrame_(scroll.contentView().bounds())
    text_view.setEditable_(False)
    text_view.setSelectable_(True)
    try:
        text_view.setFont_(NSFont.userFixedPitchFontOfSize_(12))
    except Exception:
        pass
    scroll.setDocumentView_(text_view)

    drop_view = DropView.alloc().initWithFrame_textField_output_state_(
        bounds, path_field, text_view, state
    )
    drop_view.setAutoresizingMask_(NSViewWidthSizable | NSViewHeightSizable)

    content.registerForDraggedTypes_(DropView.DROP_TYPES)
    content.addSubview_(drop_view)
    content.addSubview_(path_field)
    content.addSubview_(quit_btn)
    content.addSubview_(scroll)

    window.makeKeyAndOrderFront_(None)
    return app

def main():
    app = build_ui()
    app.run()

if __name__ == "__main__":
    main()
