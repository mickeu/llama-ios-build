#!/usr/bin/env python3
"""Merge CI-built SpotifyGlass components into a local decrypted Spotify IPA."""
import argparse
import pathlib
import shutil
import subprocess
import tempfile
import zipfile
import sys

parser = argparse.ArgumentParser()
parser.add_argument('input_ipa', type=pathlib.Path)
parser.add_argument('components_dir', type=pathlib.Path)
parser.add_argument('output_ipa', type=pathlib.Path)
args = parser.parse_args()

host = args.components_dir / 'spotifyglass.dylib'
appex = args.components_dir / 'extension' / 'SpotifyGlassLiveActivity.appex'
metadata = args.components_dir / 'extension' / 'app' / 'Metadata.appintents'
for path in (args.input_ipa, host, appex / 'SpotifyGlassLiveActivity', metadata / 'extract.actionsdata'):
    if not path.exists():
        raise SystemExit(f'missing required input: {path}')

with tempfile.TemporaryDirectory() as temp:
    root = pathlib.Path(temp)
    with zipfile.ZipFile(args.input_ipa) as ipa:
        ipa.extractall(root)
    apps = list((root / 'Payload').glob('*.app'))
    if len(apps) != 1:
        raise SystemExit(f'expected one app, got {apps}')
    app = apps[0]
    frameworks = app / 'Frameworks'
    dylibs = list(frameworks.glob('spotifyglass*.dylib'))
    if len(dylibs) != 1:
        raise SystemExit(f'expected one existing spotifyglass dylib, got {dylibs}')
    shutil.copy2(host, dylibs[0])
    target = app / 'PlugIns' / 'SpotifyGlassLiveActivity.appex'
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(appex, target)
    staged = root / 'staged.ipa'
    with zipfile.ZipFile(staged, 'w', zipfile.ZIP_DEFLATED) as ipa:
        for path in root.rglob('*'):
            if path.is_file() and path != staged:
                ipa.write(path, path.relative_to(root))
    subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name('merge-appintents.py')), str(staged), f'Payload/{app.name}/', str(metadata)], check=True)
    shutil.move(staged, args.output_ipa)

subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name('verify_phase2_ipa.py')), str(args.input_ipa), str(args.output_ipa)], check=True)
print(args.output_ipa)
