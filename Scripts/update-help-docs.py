#!/usr/bin/env python3
"""Export repository guides from the offline help articles, or check for drift."""
import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
HELP = ROOT / 'Resources' / 'Help'


def slug(text):
    return re.sub(r'\s+', '-', re.sub(r'[^\w\s-]', '', text.lower())).strip('-')


def outputs():
    index = json.loads((HELP / 'index.json').read_text())
    results = {}
    for code in ('en', 'de'):
        topics = {item['id']: (HELP / code / (item['id'] + '.md')).read_text().strip() for item in index}
        titles = {key: value.splitlines()[0][2:] for key, value in topics.items()}

        def links(text, standalone=False):
            def replace(match):
                label, key = match.groups()
                if key not in titles:
                    raise ValueError('Unknown help link: ' + key)
                target = ('USER_GUIDE_DE.md' if code == 'de' else 'USER_GUIDE.md') + '#' + slug(titles[key]) if standalone else '#' + slug(titles[key])
                return '[' + label + '](' + target + ')'
            return re.sub(r'\[([^\]]+)\]\(help://([a-z0-9-]+)\)', replace, text)

        title = 'Benutzerhandbuch' if code == 'de' else 'User guide'
        intro = ('Dieses Handbuch und die native Offline-Hilfe verwenden dieselben Quelldateien. Öffne **Hilfe → Coool PM Hilfe** oder **⌘?** in der App.' if code == 'de' else 'This guide and the native offline help use the same source articles. Open **Help → Coool PM Help** or **⌘?** inside the app.')
        content = '# ' + title + '\n\n' + intro + '\n\n'
        content += '\n'.join('- [' + titles[item['id']] + '](#' + slug(titles[item['id']]) + ')' for item in index) + '\n\n'
        for item in index:
            text = re.sub(r'^(#{1,5}) ', r'\1# ', topics[item['id']], flags=re.M)
            content += links(text) + '\n\n'
        filename = 'USER_GUIDE_DE.md' if code == 'de' else 'USER_GUIDE.md'
        results[ROOT / 'docs' / filename] = content.rstrip() + '\n'
        ai = links(topics['ai-prompting'], standalone=True)
        ai += '\n\n' + ('[Modellnutzung, Referenzpreise und Speicher](USER_GUIDE_DE.md#' if code == 'de' else '[Model usage, reference rates and memory](USER_GUIDE.md#') + slug(titles['local-ai']) + ').\n'
        results[ROOT / 'docs' / ('AI_GUIDE_DE.md' if code == 'de' else 'AI_GUIDE.md')] = ai
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true', help='Fail when committed guides differ from help sources')
    args = parser.parse_args()
    stale = []
    for path, text in outputs().items():
        if args.check:
            if not path.exists() or path.read_text() != text:
                stale.append(str(path.relative_to(ROOT)))
        else:
            path.write_text(text)
    if stale:
        print('Refresh generated guides with Scripts/update-help-docs.py:', ', '.join(stale))
        return 1
    print('Help guides are current.' if args.check else 'Exported English and German user and AI guides.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
