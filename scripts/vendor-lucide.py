#!/usr/bin/env python3
"""Vendor Lucide SVGs and search metadata. No network is used by app builds.
Run with a full upstream commit SHA; the recorded SHA is reused by default.
"""
import io
import json
from pathlib import Path
import re
import sys
import tarfile
import urllib.request

root = Path(__file__).resolve().parent.parent
resources = root / 'Sources/TasklistCore/Resources'
manifest = resources / 'lucide-source.json'
sha = sys.argv[1] if len(sys.argv) > 1 else json.loads(manifest.read_text())['commit']
if not re.fullmatch(r'[0-9a-f]{40}', sha):
    raise SystemExit('Pass a full 40-character Lucide commit SHA.')
url = f'https://codeload.github.com/lucide-icons/lucide/tar.gz/{sha}'
with urllib.request.urlopen(url) as response:
    archive = tarfile.open(fileobj=io.BytesIO(response.read()), mode='r:gz')
files = {m.name.split('/', 1)[1]: m for m in archive.getmembers() if m.isfile() and '/' in m.name}
def read(name):
    return archive.extractfile(files[name]).read()
assets = root / 'Sources/Tasklist/Assets.xcassets'
records = []
total = 0
for path in sorted(files):
    if not re.fullmatch(r'icons/[a-z0-9-]+\.svg', path):
        continue
    slug = Path(path).stem
    svg = read(path)
    total += len(svg)
    metadata = json.loads(read(f'icons/{slug}.json')) if f'icons/{slug}.json' in files else {}
    name = slug.replace('-', ' ').title()
    records.append({'id': slug, 'name': name, 'tags': metadata.get('tags', []), 'categories': metadata.get('categories', [])})
    directory = assets / f'Lucide-{slug}.imageset'
    directory.mkdir(parents=True, exist_ok=True)
    # Asset catalogs use template tint; resolve SVG currentColor for actool.
    (directory / f'{slug}.svg').write_bytes(svg.replace(b'currentColor', b'black'))
    (directory / 'Contents.json').write_text(json.dumps({'images': [{'filename': f'{slug}.svg', 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}, 'properties': {'preserves-vector-representation': True, 'template-rendering-intent': 'template'}}, indent=2) + '\n')
resources.mkdir(parents=True, exist_ok=True)
(resources / 'lucide-icons.json').write_text(json.dumps(records, ensure_ascii=False, separators=(',', ':')) + '\n')
(resources / 'Lucide-LICENSE.txt').write_bytes(read('LICENSE'))
manifest.write_text(json.dumps({'repository': 'https://github.com/lucide-icons/lucide', 'commit': sha, 'iconCount': len(records), 'upstreamSVGBytes': total, 'svgAdjustment': 'currentColor replaced with black for Xcode template asset compilation'}, indent=2) + '\n')
print(f'Vendored {len(records)} Lucide icons at {sha}; {total:,} raw SVG bytes.')
