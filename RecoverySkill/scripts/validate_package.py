#!/usr/bin/env python3
"""Validate portable recovery package structure without executing skill scripts."""
import json
import re
import sys
from pathlib import Path


def validate(folder):
    base = Path(folder).resolve()
    package = json.loads((base / 'package.json').read_text())
    if package.get('schemaVersion') != 1 or not isinstance(package.get('packageID'), str):
        raise ValueError('schemaVersion must be 1 and packageID must be a string')
    if not isinstance(package.get('skills'), list) or not isinstance(package.get('coverage'), list):
        raise ValueError('skills and coverage must be arrays')
    for item in package['skills']:
        path = Path(item['folder'])
        if path.is_absolute() or '..' in path.parts or '\\' in str(path):
            raise ValueError('Unsafe skill folder path')
        root = (base / path).resolve()
        if not root.is_relative_to(base):
            raise ValueError('Skill folder escapes the package')
        if item['origin'] not in ['Personal', 'Project-specific', 'Third-party', 'Unknown']:
            raise ValueError('Unknown origin')
        if not isinstance(item['category'], str) or not all(isinstance(x, str) for x in item['dependencies']):
            raise ValueError('Invalid category or dependencies')
        if not item['sources']:
            raise ValueError('Every skill needs evidence sources')
        for source in item['sources']:
            if not isinstance(source['location'], str) or not isinstance(source['notes'], str):
                raise ValueError('Evidence location and notes must be text')
        text = (root / 'SKILL.md').read_text()
        header = re.match(r'^---\n(.*?)\n---(?:\n|$)', text, re.S)
        if not header or not re.search(r'^name: .+', header[1], re.M) or not re.search(r'^description: .+', header[1], re.M):
            raise ValueError(f'{path}: SKILL.md needs name and description frontmatter')
        for entry in root.rglob('*'):
            if not entry.resolve().is_relative_to(root):
                raise ValueError(f'External symbolic link: {entry}')
    for coverage in package['coverage']:
        if not all(isinstance(coverage[k], str) for k in ['source', 'status', 'detail']):
            raise ValueError('Coverage values must be strings')
    return len(package['skills'])


if __name__ == '__main__':
    try:
        count = validate(sys.argv[1])
        print(f'Valid version-1 package: {count} skills')
    except (IndexError, OSError, ValueError, KeyError, TypeError) as exc:
        sys.exit(f'Invalid package: {exc}')
