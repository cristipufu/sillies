#!/usr/bin/env python3
"""Restore reviewed public meeting excerpts from the official headset mix and input manifest."""
import argparse
import hashlib
import json
from pathlib import Path
import wave

RATE = 16000


def restore(manifest, source_directory, destination):
    data = manifest.read_bytes()
    specification = json.loads(data)
    source_path = source_directory / Path(specification['source_url']).name
    annotations = source_directory / 'annotations.zip'
    for path, expected in [(source_path, specification['source_sha256']),
                           (annotations, specification['annotations_sha256'])]:
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Public corpus checksum mismatch')
    destination.mkdir(parents=True, exist_ok=False)
    with wave.open(str(source_path)) as source:
        parameters = source.getparams()
        if (parameters.nchannels, parameters.sampwidth, parameters.framerate) != (1, 2, RATE):
            raise ValueError('Expected mono PCM16 16kHz meeting source')
        for fixture in specification['fixtures']:
            start, end = fixture['source_start_seconds'], fixture['source_end_seconds']
            if not 0 <= start < end <= parameters.nframes / RATE or end - start > 90:
                raise ValueError('Meeting excerpt outside bounded source')
            target = (destination / fixture['file']).resolve()
            if not target.is_relative_to(destination.resolve()):
                raise ValueError('Excerpt path leaves destination')
            source.setpos(round(start * RATE))
            audio = source.readframes(round((end - start) * RATE))
            with wave.open(str(target), 'wb') as output:
                output.setparams(parameters)
                output.writeframes(audio)
            if hashlib.sha256(target.read_bytes()).hexdigest() != fixture['sha256']:
                raise ValueError('Restored excerpt checksum mismatch')
    (destination / 'manifest.json').write_bytes(data)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('source_directory', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    restore(args.manifest, args.source_directory, args.destination)
    print('Restored and verified reviewed meeting excerpts.')
