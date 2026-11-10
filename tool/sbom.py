"""Software bill of materials (SBOM) for Busclear, CycloneDX 1.5 JSON.

Call: python3 tool/sbom.py [out-dir]   (default build/sbom)

One file per product: the app (`pubspec.lock`) and the add-on/box server
(`ha-addon/knx_monitor/server/pubspec.lock`). Each lists the Dart packages with
version, source, SHA-256 and package URL (`pkg:pub/…`), direct dependencies as
required and dev dependencies as optional. Only the standard library, so it runs
anywhere the repository does. For the Cyber Resilience Act and for users who ask
what is inside.
"""
import datetime
import hashlib
import json
import os
import re
import sys
import uuid

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..'))
PRODUCTS = [
    ('busclear-app', 'pubspec.yaml', 'pubspec.lock'),
    ('busclear-server', 'ha-addon/knx_monitor/server/pubspec.yaml', 'ha-addon/knx_monitor/server/pubspec.lock'),
]


def read_lock(path):
    """Packages of a pubspec.lock: {name: {dependency, source, version, sha256, url, git}}."""
    packages = {}
    current = None
    section = None
    for line in open(path, encoding='utf-8'):
        if re.match(r'^\S', line):
            section = line.strip().rstrip(':')
            current = None
            continue
        if section != 'packages':
            continue
        m = re.match(r'^  (\S+):\s*$', line)
        if m:
            current = packages.setdefault(m.group(1), {})
            continue
        m = re.match(r'^\s{4,}([\w-]+):\s*"?([^"\n]*?)"?\s*$', line.rstrip('\n'))
        if m and current is not None:
            key, value = m.group(1), m.group(2)
            # "url" of a git package is its repository, "resolved-ref" its commit.
            if key in ('dependency', 'source', 'version', 'sha256', 'url', 'resolved-ref', 'path'):
                current.setdefault(key, value)
    return packages


def read_version(pubspec):
    for line in open(pubspec, encoding='utf-8'):
        m = re.match(r'^version:\s*([^\s#]+)', line)
        if m:
            return m.group(1)
    return '0.0.0'


def component(name, p):
    c = {
        'type': 'library',
        'bom-ref': f'pkg:pub/{name}@{p.get("version", "")}',
        'name': name,
        'version': p.get('version', ''),
        'purl': f'pkg:pub/{name}@{p.get("version", "")}',
        'scope': 'optional' if p.get('dependency', '').startswith('direct dev') else 'required',
        'properties': [{'name': 'pub:dependency', 'value': p.get('dependency', '')},
                       {'name': 'pub:source', 'value': p.get('source', '')}],
    }
    if p.get('sha256'):
        c['hashes'] = [{'alg': 'SHA-256', 'content': p['sha256']}]
    if p.get('source') == 'git':
        c['externalReferences'] = [{'type': 'vcs', 'url': p.get('url', '')}]
        if p.get('resolved-ref'):
            c['properties'].append({'name': 'git:commit', 'value': p['resolved-ref']})
    elif p.get('source') == 'hosted':
        c['externalReferences'] = [{'type': 'distribution', 'url': f'https://pub.dev/packages/{name}/versions/{p.get("version", "")}'}]
    return c


def sbom(product, pubspec, lock):
    packages = read_lock(os.path.join(ROOT, lock))
    version = read_version(os.path.join(ROOT, pubspec))
    lock_bytes = open(os.path.join(ROOT, lock), 'rb').read()
    # Same lock file, same serial number: a rebuild yields the same document apart from the time.
    serial = uuid.UUID(hashlib.sha256(product.encode() + lock_bytes).hexdigest()[:32])
    return {
        'bomFormat': 'CycloneDX',
        'specVersion': '1.5',
        'serialNumber': f'urn:uuid:{serial}',
        'version': 1,
        'metadata': {
            'timestamp': datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat(),
            'component': {'type': 'application', 'bom-ref': product, 'name': product, 'version': version,
                          'supplier': {'name': 'Kalkar IT Solutions', 'url': ['https://busclear.de']}},
            'tools': {'components': [{'type': 'application', 'name': 'tool/sbom.py'}]},
        },
        'components': [component(n, p) for n, p in sorted(packages.items()) if p.get('source') != 'sdk'],
        'dependencies': [{'ref': product, 'dependsOn': [f'pkg:pub/{n}@{p.get("version", "")}'
                                                        for n, p in sorted(packages.items())
                                                        if p.get('dependency', '').startswith('direct')
                                                        and p.get('source') != 'sdk']}],
    }


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'build', 'sbom')
    os.makedirs(out, exist_ok=True)
    for product, pubspec, lock in PRODUCTS:
        doc = sbom(product, pubspec, lock)
        path = os.path.join(out, f'{product}.cdx.json')
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(doc, f, indent=2)
            f.write('\n')
        print(f'{path}: {len(doc["components"])} components')


if __name__ == '__main__':
    main()
