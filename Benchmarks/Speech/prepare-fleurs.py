#!/usr/bin/env python3
"""Restore exactly the checksum-pinned public speech inputs listed in a reviewed manifest."""
import argparse
from collections import defaultdict
import hashlib
import io
import json
import math
from pathlib import Path
import struct
import tarfile
import urllib.request
import wave

MAX_SOURCE_BYTES = 4_000_000
MAX_FIXTURES = 128


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical_pcm(source):
    position, format_bytes, samples = 12, None, None
    while position + 8 <= len(source):
        tag = source[position:position + 4]
        size = struct.unpack_from('<I', source, position + 4)[0]
        chunk = source[position + 8:position + 8 + size]
        if len(chunk) != size:
            raise ValueError('Truncated audio chunk')
        position += 8 + size + size % 2
        if tag == b'fmt ':
            format_bytes = chunk
        if tag == b'data':
            samples = chunk
    if format_bytes is None or len(format_bytes) < 16 or samples is None:
        raise ValueError('Missing audio format or data')
    encoding, channels, rate, _, block, bits = struct.unpack_from('<HHIIHH', format_bytes)
    if channels != 1 or rate != 16000 or block <= 0:
        raise ValueError('Expected mono 16kHz corpus source')
    if encoding == 3 and bits == 32:
        values = struct.unpack('<' + str(len(samples) // 4) + 'f', samples)
        if not all(math.isfinite(value) for value in values):
            raise ValueError('Non-finite corpus sample')
        samples = struct.pack('<' + str(len(values)) + 'h',
                              *(round(max(-1, min(1, value)) * 32767) for value in values))
    elif encoding != 1 or bits != 16:
        raise ValueError('Unsupported corpus encoding')
    output = io.BytesIO()
    with wave.open(output, 'wb') as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(rate)
        audio.writeframes(samples)
    return output.getvalue()


def restore_archive(url, fixtures, destination):
    pending = {fixture['source_member']: fixture for fixture in fixtures}
    with urllib.request.urlopen(url, timeout=60) as response:
        with tarfile.open(fileobj=response, mode='r|gz') as archive:
            for entry in archive:
                if entry.name not in pending:
                    continue
                if not entry.isfile() or not 0 < entry.size <= MAX_SOURCE_BYTES:
                    raise ValueError('Source member outside audio bound')
                fixture = pending.pop(entry.name)
                with archive.extractfile(entry) as member:
                    source = member.read(MAX_SOURCE_BYTES + 1)
                if digest(source) != fixture['source_sha256']:
                    raise ValueError('Original source checksum mismatch')
                audio = canonical_pcm(source)
                if digest(audio) != fixture['sha256']:
                    raise ValueError('Canonical source checksum mismatch')
                target = (destination / fixture['file']).resolve()
                if not target.is_relative_to(destination.resolve()):
                    raise ValueError('Fixture path leaves destination')
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(audio)
                if not pending:
                    break
    if pending:
        raise ValueError('Archive did not supply all reviewed members')


def restore(manifest, destination):
    data = manifest.read_bytes()
    fixtures = json.loads(data)['fixtures']
    if not 0 < len(fixtures) <= MAX_FIXTURES:
        raise ValueError('Fixture count outside bound')
    archives = defaultdict(list)
    for fixture in fixtures:
        archives[fixture['source_archive']].append(fixture)
    destination.mkdir(parents=True, exist_ok=False)
    for url, members in archives.items():
        restore_archive(url, members, destination)
    (destination / 'manifest.json').write_bytes(data)
    return len(fixtures)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    print('Restored', restore(args.manifest, args.destination), 'verified public speech files.')
