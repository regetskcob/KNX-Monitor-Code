"""Fügt Übersetzungen in lib/l10n/app_de.arb und app_en.arb ein.

Aufruf: python3 tool/arb_add.py keys.json
keys.json: {"schlüssel": {"de": "…", "en": "…", "desc": "…", "placeholders": {"n": "int"}}}
"""
import collections
import json
import sys

entries = json.load(open(sys.argv[1]), object_pairs_hook=collections.OrderedDict)
for lang in ('de', 'en'):
    path = f'lib/l10n/app_{lang}.arb'
    arb = json.load(open(path), object_pairs_hook=collections.OrderedDict)
    for key, e in entries.items():
        arb[key] = e[lang]
        if lang == 'de':
            meta = {'description': e['desc']}
            if 'placeholders' in e:
                meta['placeholders'] = {p: {'type': t} for p, t in e['placeholders'].items()}
            arb['@' + key] = meta
    with open(path, 'w') as f:
        json.dump(arb, f, ensure_ascii=False, indent=2)
        f.write('\n')
print(f'{len(entries)} Schlüssel ergänzt')
