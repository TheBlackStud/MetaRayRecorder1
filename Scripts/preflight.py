#!/usr/bin/env python3
"""Preflight against common release regressions (not a real iOS device test)."""
from pathlib import Path
import plistlib

root=Path(__file__).resolve().parent.parent
model=(root/'MetaRayRecorder/RecorderModel.swift').read_text()
view=(root/'MetaRayRecorder/Views/RecorderView.swift').read_text()
app=(root/'MetaRayRecorder/MetaRayRecorderApp.swift').read_text()
writer=(root/'MetaRayRecorder/Services/MovieWriter.swift').read_text()
project=(root/'MetaRayRecorder.xcodeproj/project.pbxproj').read_text()
with (root/'MetaRayRecorder/Resources/Info.plist').open('rb') as f:
    info=plistlib.load(f)

modes=set(info.get('UIBackgroundModes',[]))
assert {'processing','bluetooth-central','bluetooth-peripheral','external-accessory','audio'}<=modes
assert 'com.meta.ar.wearable' in info.get('UISupportedExternalAccessoryProtocols',[])
assert 'let time = CACurrentMediaTime()' in model and 'clock.mark(time: time)' in model
assert 'writer.appendVideo(frame.sampleBuffer, hostTime: time)' in model
assert 'guard streaming, !captureBusy, !shuttingDown else' in model
assert 'preview != nil' not in model
assert 'func enteredBackground() {' in model and 'func enteredForeground() {' in model
bg=model.split('func enteredBackground() {',1)[1].split('func enteredForeground() {',1)[0]
assert 'stopAll' not in bg and 'stopRecording' not in bg and 'refreshPreviewMode()' in bg
assert 'streamClock.lastFrameTime()' in model
assert 'model.requestRecording()' in view
assert 'phase == .background || phase == .inactive' in app
assert 'output.movieFragmentInterval' in writer
assert '"MARKETING_VERSION" = "1.1.0"' in project
assert (root/'.github/workflows/build-ios.yml').is_file()
print('PASS: preflight background modes, frame pipeline, no preview prerequisite, lifecycle, workflow.')
