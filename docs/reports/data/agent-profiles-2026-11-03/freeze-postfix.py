"""Freeze checked release artifacts before the separate capacity experiment."""
import hashlib, json, pathlib, shutil, subprocess

root = pathlib.Path.cwd()
out = root / 'build/chat-benchmarks/agent-profiles-2026-11-03'
binary = root / '.build/out/Products/Release'
app = pathlib.Path('/tmp/sillies-agent-profile-release-v3/Sillies.app')
variants = json.loads((out / 'variants.json').read_text())

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def freeze(name, destination, tokens):
    destination.mkdir(parents=True, exist_ok=False)
    shutil.copy2(binary / 'ChatModelBenchmark', destination)
    shutil.copytree(app / 'Contents/Helpers/SilliesTextInference.app', destination / 'SilliesTextInference.app')
    shutil.copytree(binary / 'Sillies_SilliesModelStore.bundle', destination / 'Sillies_SilliesModelStore.bundle')
    catalog = destination / 'Sillies_SilliesModelStore.bundle/Contents/Resources/Resources/text-models.json'
    document = json.loads(catalog.read_text())
    for item in document['manifests']:
        profile = item['model']['profile']
        profile['context']['workingTokens'] = tokens
        if tokens != 4096:
            profile['evidence']['rationale'] += ' Experimental 8192-token working context; no other execution setting changes.'
    catalog.write_text(json.dumps(document, indent=2) + '\n')
    variants[name] = {
        'worker': str(destination / 'ChatModelBenchmark'),
        'helper': str(destination / 'SilliesTextInference.app/Contents/MacOS/SilliesTextInference'),
        'hashes': {str(p.relative_to(destination)): digest(p) for p in destination.rglob('*') if p.is_file()},
    }

freeze('postfix', pathlib.Path('/tmp/sillies-agent-profiles-postfix'), 4096)
variants['capacity-8k-unused-core'] = variants['capacity-8k']
freeze('capacity-8k', pathlib.Path('/tmp/sillies-agent-profiles-postfix-8k'), 8192)
(out / 'variants.json').write_text(json.dumps(variants, indent=2) + '\n')
tracked = subprocess.check_output(['git', 'diff', '--', 'Sources', 'Tests', 'Tools', 'scripts', 'ModelProfiles'])
untracked = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '--', 'Sources', 'Tests', 'Tools', 'ModelProfiles']).decode().splitlines()
for path in untracked:
    tracked += subprocess.run(['git', 'diff', '--no-index', '--', '/dev/null', path], capture_output=True).stdout
(out / 'postfix.patch').write_bytes(tracked)
files = [p for directory in ['Sources', 'Tests', 'Tools/ChatModelBenchmark', 'ModelProfiles']
         for p in (root / directory).rglob('*') if p.is_file()]
(out / 'source-files-postfix.json').write_text(json.dumps({str(p.relative_to(root)): digest(p) for p in files}, indent=2) + '\n')
print('Post-review executables and both capacity catalogs frozen.')
