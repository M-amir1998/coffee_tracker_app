"""Lists every AppLocalizations key used in lib/ with its argument count.

Usage:
  python tool/l10n_keys.py                 # list used keys
  python tool/l10n_keys.py lib/l10n/app_en.arb lib/l10n/app_es.arb
                                           # report missing / unused keys
"""
import json
import pathlib
import re
import sys

# Not preceded by '/' or a word character, so import paths such as
# .../l10n/l10n.dart do not count as keys.
USE = re.compile(r'(?<![/\w])l10n\.([a-zA-Z][a-zA-Z0-9]*)')
BACKSLASH = chr(92)


def args_after(src: str, pos: int) -> int:
    """Counts the top-level arguments of the call starting at src[pos]."""
    if pos >= len(src) or src[pos] != '(':
        return 0
    depth, i, count, saw = 0, pos, 0, False
    while i < len(src):
        ch = src[i]
        if ch in '([{':
            depth += 1
            if depth == 1:
                i += 1
                continue
        elif ch in ')]}':
            depth -= 1
            if depth == 0:
                return count + (1 if saw else 0)
        elif ch == ',' and depth == 1:
            count += 1
            saw = False
            i += 1
            continue
        elif ch in ('"', "'"):
            quote = ch
            i += 1
            while i < len(src) and src[i] != quote:
                i += 2 if src[i] == BACKSLASH else 1
        if depth >= 1 and not ch.isspace():
            saw = True
        i += 1
    return count


def used_keys() -> dict:
    found = {}
    for path in sorted(pathlib.Path('lib').rglob('*.dart')):
        if 'generated' in path.parts:
            continue
        src = path.read_text(encoding='utf-8')
        for match in USE.finditer(src):
            found.setdefault(match.group(1), set()).add(args_after(src, match.end()))
    return found


def main() -> int:
    found = used_keys()
    if len(sys.argv) == 1:
        for key in sorted(found):
            print(key, sorted(found[key]))
        print(len(found), 'keys')
        return 0
    status = 0
    for arb_path in sys.argv[1:]:
        arb = json.loads(pathlib.Path(arb_path).read_text(encoding='utf-8'))
        defined = {k for k in arb if not k.startswith('@')}
        missing = sorted(set(found) - defined)
        unused = sorted(defined - set(found))
        for key in missing:
            print(f'{arb_path}: MISSING {key} args={sorted(found[key])}')
        for key in unused:
            print(f'{arb_path}: UNUSED  {key}')
        print(f'{arb_path}: {len(found)} used, {len(defined)} defined, {len(missing)} missing, {len(unused)} unused')
        status |= 1 if missing else 0
    return status


if __name__ == '__main__':
    sys.exit(main())
