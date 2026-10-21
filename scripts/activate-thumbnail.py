#!/usr/bin/env python3
"""Activate the built thumbnail app; --restore reverses this activation; --off stops it
and gives ⌘⇧3/4 back to macOS until the next activation."""
import os, pathlib, plistlib, shutil, subprocess, sys, time
home = pathlib.Path.home()
base = home / 'Library/Application Support/ScreenshotClipboard'
app = base / 'ScreenshotClipboard.app'
agent = home / 'Library/LaunchAgents/local.screenshot-clipboard.plist'
service = f'gui/{os.getuid()}/local.screenshot-clipboard'
domain = 'com.apple.symbolichotkeys'
backup = base / 'before-thumbnail'
def run(*args, check=True):
    return subprocess.run(list(map(str, args)), check=check, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
def keys():
    return plistlib.loads(run('/usr/bin/defaults', 'export', domain, '-').stdout).get('AppleSymbolicHotKeys', {})
def set_keys(values):
    for key, value in values.items():
        xml = plistlib.dumps(value).decode()
        run('/usr/bin/defaults', 'write', domain, 'AppleSymbolicHotKeys', '-dict-add', key, xml)
    run('/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings', '-u')
def stop():
    run('/bin/launchctl', 'bootout', service, check=False)
def restore():
    stop()
    if app.exists(): shutil.rmtree(app)
    if (backup / app.name).exists(): shutil.copytree(backup / app.name, app)
    if (backup / agent.name).exists():
        shutil.copy2(backup / agent.name, agent)
    elif agent.exists(): agent.unlink()
    set_keys(plistlib.loads((backup / 'shortcuts.plist').read_bytes()))
    if agent.exists(): run('/bin/launchctl', 'bootstrap', f'gui/{os.getuid()}', agent)
    print('Previous app and shortcuts restored.')
if '--restore' in sys.argv:
    restore(); sys.exit(0)
if '--off' in sys.argv:
    run('/bin/launchctl', 'disable', service)
    stop()
    current = keys()
    set_keys({k: dict(current[k], enabled=True) for k in ('28','30') if k in current})
    print('Off: app stopped and kept from starting at login; native screenshot shortcuts restored.')
    sys.exit(0)
source = pathlib.Path(__file__).resolve().parent.parent / 'build/active-app/ScreenshotClipboard.app'
assert (source / 'Contents/MacOS/capture').is_file(), 'Build the app first'
current = keys()
assert all(k in current for k in ('28', '30')), 'Expected screenshot shortcuts not found; no changes made'
base.mkdir(parents=True, exist_ok=True)
if not backup.exists():
    backup.mkdir()
    if app.exists(): shutil.copytree(app, backup / app.name)
    if agent.exists(): shutil.copy2(agent, backup / agent.name)
    (backup / 'shortcuts.plist').write_bytes(plistlib.dumps({k: current[k] for k in ('28','30')}))
ready = base / 'hotkeys-ready'
try:
    stop()
    if ready.exists(): ready.unlink()
    if app.exists(): shutil.rmtree(app)
    shutil.copytree(source, app)
    set_keys({k: dict(current[k], enabled=False) for k in ('28','30')})
    agent.parent.mkdir(parents=True, exist_ok=True)
    agent.write_bytes(plistlib.dumps({'Label':'local.screenshot-clipboard',
        'ProgramArguments':[str(app / 'Contents/MacOS/screenshot-clipboard'), '--ready-file', str(ready)],
        'RunAtLoad':True, 'KeepAlive':True, 'ThrottleInterval':10,
        'StandardOutPath':'/dev/null', 'StandardErrorPath':str(base / 'thumbnail-error.log')}))
    run('/bin/launchctl', 'enable', service)
    run('/bin/launchctl', 'bootstrap', f'gui/{os.getuid()}', agent)
    for _ in range(30):
        if ready.exists(): break
        time.sleep(.2)
    assert ready.exists(), 'Listener did not register shortcuts'
    state = run('/bin/launchctl', 'print', service).stdout.decode()
    assert 'state = running' in state, state
    assert all(not keys()[k]['enabled'] for k in ('28','30'))
    print('Activated: shortcut listener running, both hotkeys registered; launch at login enabled.')
    print('Backup:', backup)
except BaseException:
    restore()
    raise
