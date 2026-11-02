#!/usr/bin/env python3
"""Prepare a pinned, isolated native build without altering the source checkout."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

BRIDGE = Path(__file__).resolve().parent
PROJECT = BRIDGE.parents[2]
BUILD = PROJECT / 'work/gofly-ios'
PIN = json.loads((BRIDGE / 'upstream.json').read_text())


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def run(*args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


def fetch_pinned(repository):
    """Fetch only the pinned commit into the ignored default checkout."""
    if not (repository / '.git').exists():
        run('git', 'init', '--quiet', str(repository))
    run('git', '-C', str(repository), 'fetch', '--quiet', '--depth', '1', PIN['repository'], PIN['commit'])


def prepare():
    BUILD.mkdir(parents=True, exist_ok=True)
    override = os.environ.get('GOFLY_IDEVICE_REPOSITORY')
    repository = Path(override or str(PROJECT / 'work/mac-bootstrap-idevice'))
    has_pin = subprocess.run(['git', '-C', str(repository), 'cat-file', '-e', PIN['commit'] + '^{commit}'],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    if not has_pin:
        # An explicit clone is never modified; the default checkout is fetched on demand.
        if override:
            raise SystemExit('Pinned upstream commit is missing from GOFLY_IDEVICE_REPOSITORY')
        fetch_pinned(repository)
    commit = subprocess.check_output(['git', '-C', str(repository), 'rev-parse', PIN['commit'] + '^{commit}'], text=True).strip()
    if commit != PIN['commit']:
        raise SystemExit('Pinned upstream commit is unavailable')
    stage = Path(tempfile.mkdtemp(prefix='.native-source-', dir=BUILD))
    try:
        archive = subprocess.Popen(['git', '-C', str(repository), 'archive', commit], stdout=subprocess.PIPE)
        run('tar', '-x', '-C', str(stage), stdin=archive.stdout)
        archive.stdout.close()
        if archive.wait() != 0:
            raise SystemExit('Pinned upstream export failed')
        if sha256(stage / 'Cargo.lock') != PIN['cargoLockSHA256']:
            raise SystemExit('Upstream Cargo.lock differs from the pin')
        for patch in PIN['patches']:
            run('patch', '--batch', '-p1', '-i', str(BRIDGE / patch), cwd=stage)
        if sha256(stage / 'Cargo.lock') != PIN['cargoLockSHA256']:
            raise SystemExit('Patch unexpectedly changed dependency resolution')
        destination = BUILD / 'native-source'
        if destination.is_symlink() or (destination / '.git').exists():
            raise SystemExit('Refusing to replace a symlink or source checkout')
        if destination.exists():
            shutil.rmtree(destination)
        stage.rename(destination)
    finally:
        if stage.exists():
            shutil.rmtree(stage)

    downloads = BUILD / 'downloads'
    downloads.mkdir(exist_ok=True)
    toolchain = BUILD / 'toolchain'
    installed = toolchain / '.gofly-toolchain.json'
    if installed.exists() and json.loads(installed.read_text()) == PIN['components']:
        return
    for component in PIN['components']:
        destination = downloads / component['url'].rsplit('/', 1)[1]
        if not destination.exists() or sha256(destination) != component['sha256']:
            partial = destination.with_suffix(destination.suffix + '.partial')
            run('curl', '--fail', '--location', '--silent', '--show-error', '--retry', '3', component['url'], '-o', str(partial))
            if sha256(partial) != component['sha256']:
                raise SystemExit('Official Rust component SHA-256 mismatch')
            partial.replace(destination)
        print(destination.name + ': official SHA-256 verified', flush=True)
        with tempfile.TemporaryDirectory(prefix='.rust-install-', dir=BUILD) as unpacked:
            run('tar', '-xJf', str(destination), '-C', unpacked)
            installer = Path(unpacked) / destination.name.removesuffix('.tar.xz') / 'install.sh'
            run('sh', str(installer), '--prefix=' + str(toolchain), '--disable-ldconfig')
    installed.write_text(json.dumps(PIN['components'], indent=2) + '\n')


def record():
    output = BUILD / 'native'
    source = BUILD / 'native-source'
    metadata = {
        'upstreamRepository': PIN['repository'],
        'upstreamCommit': PIN['commit'],
        'rustVersion': subprocess.check_output([str(BUILD / 'toolchain/bin/rustc'), '-Vv'], text=True).strip(),
        'cargoVersion': subprocess.check_output([str(BUILD / 'toolchain/bin/cargo'), '-V'], text=True).strip(),
        'target': PIN['target'],
        'features': PIN['features'],
        'deploymentTarget': '26.0',
        'cargoLocked': True,
        'swiftShimABI': '30 declarations checked against generated C ABI and archive symbols',
        'nativeTests': 'not run (packaging-only build)',
        'xcodeVersion': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
        'sdkVersion': subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-version'], text=True).strip(),
        'sha256': {
            'Cargo.lock': sha256(source / 'Cargo.lock'),
            'verify-only.patch': sha256(BRIDGE / 'verify-only.patch'),
            'location-reply.patch': sha256(BRIDGE / 'location-reply.patch'),
            'upstream.json': sha256(BRIDGE / 'upstream.json'),
            'idevice-full.h': sha256(output / 'idevice-full.h'),
            'libidevice_ffi.a': sha256(output / 'libidevice_ffi.a'),
            'swiftShimHeader': sha256(BRIDGE / 'include/idevice.h'),
            'swiftModuleMap': sha256(BRIDGE / 'include/module.modulemap'),
        },
    }
    (output / 'manifest.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print('Wrote native build manifest', flush=True)


if __name__ == '__main__':
    import sys
    if sys.argv[1:] == ['--record']:
        record()
    elif not sys.argv[1:]:
        prepare()
    else:
        raise SystemExit('Usage: prepare-build.py [--record]')
