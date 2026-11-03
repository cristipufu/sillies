"""Replay the observed synthetic native request, unchanged, through the checked Swift helper."""
import fcntl, hashlib, json, os, pathlib, select, struct, subprocess, time

root = pathlib.Path.cwd()
out = root / 'build/chat-benchmarks/agent-profiles-2026-11-03'
source = out / 'baseline/nemotron-3.5-bolt-e4b/cases/heldout-memory-new-name--app--r1.json'
original = json.loads(source.read_text())['turns'][0]['generations'][1]['request']
assert original['messages'][-1]['role'] == 'tool'
variant = json.loads((out / 'variants.json').read_text())['postfix']
manifest = next(item for item in json.loads((root / 'Sources/SilliesModelStore/Resources/text-models.json').read_text())['manifests']
                if item['model']['id'] == 'nemotron-3.5-bolt-e4b')
model = manifest['model']
weights = sum(item['byteCount'] for item in manifest['artifacts'])
directory = pathlib.Path('/private/tmp/sillies-extra-models') / model['id'] / model['revision']
request = {'configuration': {'directory': directory.as_uri(), 'profile': model['profile'],
                            'reasoning': model.get('reasoning'),
                            'memoryLimitBytes': weights + max(2 * 1024**3, weights // 4)},
           'generation': original}

def write_frame(stream, value):
    data = json.dumps(value, separators=(',', ':')).encode()
    assert 0 < len(data) <= 128 * 1024
    stream.write(struct.pack('>I', len(data)) + data)
    stream.flush()

def read_exact(descriptor, count, deadline):
    data = bytearray()
    while len(data) < count:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([descriptor], [], [], remaining)[0]:
            raise TimeoutError('Native replay deadline exceeded')
        chunk = os.read(descriptor, count - len(data))
        if not chunk:
            raise EOFError('Native helper closed its response stream')
        data.extend(chunk)
    return data

def read_frame(stream, deadline):
    descriptor = stream.fileno()
    length = struct.unpack('>I', read_exact(descriptor, 4, deadline))[0]
    assert 0 < length <= 128 * 1024
    return json.loads(read_exact(descriptor, length, deadline))

result = {'source': str(source.relative_to(root)), 'sourceHash': hashlib.sha256(source.read_bytes()).hexdigest(),
          'helperHash': hashlib.sha256(pathlib.Path(variant['helper']).read_bytes()).hexdigest(),
          'request': request, 'replays': []}
with (out / 'run.lock').open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    with (out / 'controls/tool-completion-stderr.log').open('w') as log:
        worker = subprocess.Popen([variant['helper']], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log)
        try:
            for number in range(3):
                start = time.monotonic()
                write_frame(worker.stdin, request)
                events = []
                while True:
                    event = read_frame(worker.stdout, start + 60)
                    events.append(event)
                    if 'delta' in event:
                        write_frame(worker.stdin, {})
                    elif 'finished' in event:
                        break
                    else:
                        raise ValueError('Unknown native event')
                result['replays'].append({'seconds': time.monotonic() - start, 'events': events})
                response = event['finished']['_0']
                print(number + 1, 'text bytes', len(response.get('text', '').encode()),
                      'native metrics', bool(response.get('metrics')), 'failure', response.get('failure'), flush=True)
        finally:
            worker.terminate()
            try:
                worker.wait(timeout=5)
            except subprocess.TimeoutExpired:
                worker.kill()
                worker.wait()
            (out / 'controls/tool-completion-replay.json').write_text(json.dumps(result, indent=2) + '\n')
