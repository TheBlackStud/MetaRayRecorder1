#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
rm -rf build/RecorderTests.xcresult
xcrun simctl list devices available -j > build/simulators.json
SDK_VERSION=$(xcrun --sdk iphonesimulator --show-sdk-version)
export SDK_VERSION
UDID=$(python3 - <<'PY'
import json, os, re
with open('build/simulators.json') as f: data=json.load(f)
sdk=tuple(int(x) for x in os.environ['SDK_VERSION'].split('.')[:2])
def version(runtime):
    match=re.search(r'iOS-(\d+)-(\d+)',runtime)
    return tuple(map(int,match.groups())) if match else (0,0)
for runtime, devices in sorted(data['devices'].items(), key=lambda item: version(item[0]), reverse=True):
    current=version(runtime)
    if current == (0,0) or current > sdk: continue
    for device in devices:
        if device.get('isAvailable', False) and 'iPhone' in device.get('name', ''):
            print(device['udid']); raise SystemExit(0)
raise SystemExit('No available iPhone simulator on this macOS runner.')
PY
)
xcodebuild -project MetaRayRecorder.xcodeproj -scheme MetaRayRecorder -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -destination-timeout 180 \
  -derivedDataPath build/TestDerivedData -clonedSourcePackagesDirPath build/Packages \
  -resultBundlePath build/RecorderTests.xcresult CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' test 2>&1 | tee build/tests.log
