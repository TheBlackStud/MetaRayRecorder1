#!/usr/bin/env python3
"""Package a real ARM64 iOS build; refuse source folders and simulator builds."""
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def package(app: Path, output: Path) -> None:
    info_path = app / 'Info.plist'
    if not app.is_dir() or not info_path.is_file():
        raise RuntimeError('Expected a compiled .app containing Info.plist, not a source folder.')
    with info_path.open('rb') as fp:
        info = plistlib.load(fp)
    if info.get('DTPlatformName') != 'iphoneos':
        raise RuntimeError('This is not an iPhone-device build (iphoneos). Simulator builds cannot be installed.')
    executable_name = info.get('CFBundleExecutable', '')
    if not executable_name or '/' in executable_name or '$(' in executable_name:
        raise RuntimeError('Unresolved or invalid executable name.')
    executable = app / executable_name
    with executable.open('rb') as fp:
        magic = fp.read(4)
    if magic not in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf'):
        raise RuntimeError('The application does not contain a Mach-O executable. Refusing to create a fake IPA.')
    if sys.platform != 'darwin':
        raise RuntimeError('Packaging is restricted to the macOS build job with architecture verification.')
    subprocess.run(['xcrun', 'lipo', str(executable), '-verify_arch', 'arm64'], check=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='metaray-ipa-') as temporary:
        root = Path(temporary)
        dest = root / 'Payload' / app.name
        shutil.copytree(app, dest, symlinks=True)
        for path in sorted(dest.rglob('*'), key=lambda p: len(p.parts), reverse=True):
            if path.name == '_CodeSignature' and path.is_dir():
                shutil.rmtree(path)
            elif path.name == 'embedded.mobileprovision' and path.is_file():
                path.unlink()
            elif path.is_file() and not path.is_symlink():
                with path.open('rb') as fp:
                    header = fp.read(4)
                if header in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf'):
                    subprocess.run(['codesign', '--remove-signature', str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path in sorted(root.rglob('*')):
                if path.is_symlink():
                    zi = zipfile.ZipInfo(path.relative_to(root).as_posix())
                    zi.create_system = 3
                    zi.external_attr = (0o120777 << 16)
                    archive.writestr(zi, os.readlink(path))
                elif path.is_file():
                    archive.write(path, path.relative_to(root).as_posix())
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise RuntimeError('IPA integrity check failed.')
    print(f'Unsigned IPA packaged: {output}')

if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: package_ipa.py /path/App.app /path/output.ipa')
    try:
        package(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f'Packaging failed: {error}')
