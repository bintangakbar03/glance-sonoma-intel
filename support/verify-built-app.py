#!/usr/bin/env python3
"""Check actual Mach-O deployment targets before a Sonoma DMG is produced.

This verifies the built package, not runtime behavior or biometric accuracy.
"""

import json
import plistlib
import struct
import sys
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def version_tuple(version):
    fields = tuple(int(part) for part in version.split('.'))
    require(1 <= len(fields) <= 3, 'Invalid macOS version')
    return fields + (0,) * (3 - len(fields))


def packed_version(value):
    return (value >> 16, (value >> 8) & 255, value & 255)


def slices(data, offset=0, nested=False):
    magic = data[offset:offset + 4]
    if magic in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        require(not nested, 'Nested fat binary')
        count = struct.unpack_from('>I', data, offset + 4)[0]
        require(0 < count < 32, 'Invalid architecture count')
        wide = magic == b'\xca\xfe\xba\xbf'
        records = []
        for index in range(count):
            row = offset + 8 + index * (32 if wide else 20)
            cpu = struct.unpack_from('>I', data, row)[0]
            start, length = struct.unpack_from('>QQ' if wide else '>II', data, row + 8)
            require(start + length <= len(data), 'Architecture outside file')
            child = slices(data[start:start + length], nested=True)
            require(len(child) == 1 and child[0]['cpu'] == cpu, 'Architecture header mismatch')
            records.extend(child)
        return records

    if magic not in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe'):
        return []
    cpu, _, _, commands, command_bytes, _ = struct.unpack_from('<6I', data, offset + 4)
    position = offset + (32 if magic[0] == 0xcf else 28)
    end = position + command_bytes
    require(end <= len(data), 'Load commands outside file')
    minimum = None
    for _ in range(commands):
        command, size = struct.unpack_from('<II', data, position)
        require(size >= 8 and position + size <= end, 'Invalid load command')
        if command == 0x32:  # LC_BUILD_VERSION
            platform, minimum_raw = struct.unpack_from('<II', data, position + 8)
            require(platform == 1, 'Expected a macOS binary')
            minimum = packed_version(minimum_raw)
        elif command == 0x24:  # LC_VERSION_MIN_MACOSX
            minimum = packed_version(struct.unpack_from('<I', data, position + 8)[0])
        position += size
    require(minimum is not None, 'Missing minimum macOS load command')
    return [{'cpu': cpu, 'minimum': minimum}]


def verify(app, target):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    minimum = version_tuple(info['LSMinimumSystemVersion'])
    require(minimum == target, f'Info.plist targets {minimum}, expected {target}')
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    main = slices(executable.read_bytes())
    require(len(main) == 1 and main[0]['cpu'] == 0x1000007, 'Main executable must be Intel x86_64')
    require(main[0]['minimum'] == target, 'Main executable target differs from Info.plist')

    checked = []
    for path in sorted(app.rglob('*')):
        if not path.is_file() or path.is_symlink():
            continue
        with path.open('rb') as handle:
            magic = handle.read(4)
        if magic not in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
            continue
        architectures = slices(path.read_bytes())
        intel = [row for row in architectures if row['cpu'] == 0x1000007]
        require(intel, f'Bundled binary has no Intel code: {path.name}')
        require(intel[0]['minimum'] <= target, f'Bundled binary needs newer macOS: {path.name}')
        checked.append({'path': str(path.relative_to(app)), 'intel_minimum_macos': '.'.join(map(str, intel[0]['minimum']))})

    require(any(app.rglob('ArcFace.mlmodelc')), 'Compiled ArcFace model is missing')
    require(not any(app.rglob('Sparkle.framework')), 'Upstream updater must not be bundled in this port')
    return {
        'package_checks': 'passed',
        'target_architecture': 'x86_64',
        'target_macos': '.'.join(map(str, target)),
        'binaries': checked,
        'runtime_test_on_sonoma': 'not performed by this script',
        'notarization': 'not performed',
    }


if __name__ == '__main__':
    require(len(sys.argv) == 3, 'Usage: verify-built-app.py APP_PATH MACOS_VERSION')
    print(json.dumps(verify(Path(sys.argv[1]).resolve(), version_tuple(sys.argv[2])), indent=2))
