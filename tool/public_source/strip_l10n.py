"""Removes the texts of the private parts from the public snapshot's ARB files.

A key goes if its prefix belongs to a private part (account, team, Betriebs-
lösung, Bauherren-Paket, GA assistant, device sync) and nothing left in the snapshot uses
it. Run from the snapshot root by tool/export_public_source.sh, which then
regenerates the localizations.

    python3 strip_l10n.py
"""
import collections
import json
import pathlib
import re

PREFIXES = ('account', 'team', 'biz', 'hp', 'ga', 'cloudSync')

root = pathlib.Path('.')
code = '\n'.join(
    p.read_text(encoding='utf-8')
    for folder in ('lib', 'test', 'integration_test')
    for p in (root / folder).rglob('*.dart')
    if 'l10n/app_localizations' not in str(p)
)
used = set(re.findall(r'\.([A-Za-z_][A-Za-z0-9_]*)\b', code))

removed = 0
for path in sorted((root / 'lib/l10n').glob('app_*.arb')):
    arb = json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=collections.OrderedDict)
    drop = {k for k in arb if not k.startswith('@') and k.startswith(PREFIXES) and k not in used}
    for k in drop:
        arb.pop(k)
        arb.pop('@' + k, None)
    removed = max(removed, len(drop))
    path.write_text(json.dumps(arb, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'{removed} texts of private parts removed')
