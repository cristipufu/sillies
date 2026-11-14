#!/usr/bin/env python3
"""Create deterministic recognition conditions from a checksum-pinned human-speech manifest."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import struct
import wave

RATE = 16000
LEADING_SECONDS = 0.5
TRAILING_SECONDS = 1.2
QUIET_RMS = 0.0012
NOISE_SNR_DB = 10
MAX_FIXTURES = 128


def samples(path):
    with wave.open(str(path)) as source:
        if (source.getframerate(), source.getnchannels(), source.getsampwidth()) != (RATE, 1, 2):
            raise ValueError(f"Unsupported canonical fixture: {path.name}")
        data = source.readframes(source.getnframes())
    return [value / 32768 for value in struct.unpack('<' + str(len(data) // 2) + 'h', data)]


def write_audio(path, values):
    pcm = struct.pack('<' + str(len(values)) + 'h', *(round(max(-1, min(1, value)) * 32767) for value in values))
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm)


def transformed(values, condition, seed):
    rms = math.sqrt(sum(value * value for value in values) / max(1, len(values)))
    if condition == 'quiet':
        gain = QUIET_RMS / max(rms, 1e-9)
        return [value * gain for value in values]
    if condition == 'noise':
        randomizer = random.Random(seed)
        noise = [randomizer.gauss(0, 1) for _ in values]
        noise_rms = math.sqrt(sum(value * value for value in noise) / len(noise))
        scale = rms / (10 ** (NOISE_SNR_DB / 20)) / noise_rms
        return [voice + background * scale for voice, background in zip(values, noise)]
    return values


def prepare(manifest, destination):
    source_bytes = manifest.read_bytes()
    source = json.loads(source_bytes)
    if not source['fixtures'] or len(source['fixtures']) > MAX_FIXTURES:
        raise ValueError('Fixture count outside preparation bound')
    destination.mkdir(parents=True, exist_ok=False)
    fixtures = []
    for fixture in source['fixtures']:
        path = manifest.parent / fixture['file']
        if hashlib.sha256(path.read_bytes()).hexdigest() != fixture['sha256']:
            raise ValueError('Source checksum mismatch')
        values = samples(path)
        seed = int(hashlib.sha256(fixture['id'].encode()).hexdigest()[:16], 16)
        for condition in ['clean', 'quiet', 'noise']:
            data = [0.0] * round(LEADING_SECONDS * RATE) + transformed(values, condition, seed)
            data += [0.0] * round(TRAILING_SECONDS * RATE)
            name = fixture['id'] + '::' + condition
            target = destination / (name.replace('::', '--') + '.wav')
            write_audio(target, data)
            fixtures.append({**fixture, 'id': name, 'condition': condition, 'file': target.name,
                             'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
    for split in ['dev', 'test']:
        for level in [0.0, 0.0018, 0.015]:
            randomizer = random.Random(1234)
            data = [0.0] * round(LEADING_SECONDS * RATE)
            data += [randomizer.gauss(0, level) for _ in range(6 * RATE)]
            data += [0.0] * round(TRAILING_SECONDS * RATE)
            name = f'no-speech-{split}-{level}'
            target = destination / (name + '.wav')
            write_audio(target, data)
            fixtures.append({'id': name, 'language': 'en', 'split': split, 'condition': 'no-speech',
                             'file': target.name, 'reference': '',
                             'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
    result = {'source_manifest_sha256': hashlib.sha256(source_bytes).hexdigest(),
              'conditions': {'leading_seconds': LEADING_SECONDS, 'trailing_seconds': TRAILING_SECONDS,
                             'quiet_rms': QUIET_RMS, 'noise_snr_db': NOISE_SNR_DB}, 'fixtures': fixtures}
    (destination / 'manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    return len(fixtures)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    arguments = parser.parse_args()
    print('Prepared', prepare(arguments.source, arguments.destination), 'pinned recognition fixtures.')
