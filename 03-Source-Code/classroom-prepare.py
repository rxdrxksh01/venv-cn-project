#!/usr/bin/env python3
"""Prepare role-specific config files after DHCP changes; no service/system changes.

Default is a read-only preview. --apply backs up changed files before writing.
The CLI verifies this Mac's current interface IP matches its chosen role.
Standard library only. Run the same three current IPs on all three Macs.
"""
import argparse
from datetime import datetime
import ipaddress
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def ipv4(value):
    try:
        address = ipaddress.IPv4Address(value)
    except ipaddress.AddressValueError as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc
    if address.is_loopback or address.is_unspecified or address.is_multicast:
        raise argparse.ArgumentTypeError('Use the actual unicast LAN IPv4 address.')
    return str(address)


def replace_settings(text, settings):
    for name, value in settings.items():
        pattern = rf'(?m)^{re.escape(name)}=.*$'
        line = f'{name}={value}'
        if re.search(pattern, text):
            text = re.sub(pattern, lambda match: line, text)
        else:
            text = text.rstrip() + '\n' + line + '\n'
    return text


def update_upstreams(text, a_ip, b_ip):
    for port, address in [(3001, a_ip), (3002, b_ip)]:
        pattern = rf'(?m)^(\s*server\s+)(?:[0-9]{{1,3}}\.){{3}}[0-9]{{1,3}}:{port}(\s[^\n]*;[^\n]*)$'
        text, count = re.subn(pattern, lambda m: f'{m[1]}{address}:{port}{m[2]}', text)
        if count != 1:
            raise ValueError(f'Expected exactly one IPv4 upstream on port {port}; found {count}. Inspect config manually.')
    return text


def make_plan(repo, home, brew_prefix, role, edge_ip, a_ip, b_ip, interface, upstream=None):
    source = repo / '03-Source-Code'
    team = source / 'team.env'
    plans = [(team, replace_settings(team.read_text(), {
        'MAC1_IP': edge_ip, 'MAC2_IP': edge_ip, 'MAC3_IP': a_ip, 'MAC4_IP': b_ip,
    }), 'team.env')]
    if role in ('edge', 'backend-b'):
        env = source / 'docker-dns/.env'
        initial = env.read_text() if env.exists() else (source / 'docker-dns/.env.example').read_text()
        settings = {'DNS_BIND_IP': edge_ip if role == 'edge' else b_ip,
                    'DNS_PORT': '53', 'EDGE_IP': edge_ip, 'DNS_TTL': '30', 'TTL_TARGET_IP': ''}
        if upstream is not None:
            settings['UPSTREAM_DNS'] = upstream
        plans.append((env, replace_settings(initial, settings), 'docker-dns.env'))
    for ident, address, port in [('a', a_ip, 3001), ('b', b_ip, 3002)]:
        rule = (f'# Classroom IPv4 isolation template; interface {interface}. Load only in the scoped project anchor.\n'
                f'pass in quick on {interface} inet proto tcp from {edge_ip} to {address} port {port} flags S/SA keep state label "cn-{ident}-edge-allow"\n'
                f'block return in quick on {interface} inet proto tcp from any to {address} port {port} label "cn-{ident}-client-block"\n')
        plans.append((source / f'firewall/backend-{ident}.pf', rule, f'backend-{ident}.pf'))
    template = source / 'standby-edge/nginx.conf'
    if template.exists():
        plans.append((template, update_upstreams(template.read_text(), a_ip, b_ip), 'standby-template.conf'))
    if role == 'edge':
        native = brew_prefix / 'etc/nginx/servers/team1.conf'
        if not native.exists():
            raise ValueError(f'Installed primary nginx config not found: {native}. Do not regenerate the CA; locate the existing config.')
        plans.append((native, update_upstreams(native.read_text(), a_ip, b_ip), 'installed-primary-nginx.conf'))
    if role == 'backend-b':
        standby = home / 'cn-standby/nginx.conf'
        if standby.exists():
            plans.append((standby, update_upstreams(standby.read_text(), a_ip, b_ip), 'installed-standby-nginx.conf'))
    return plans


def apply_plan(plans, backup_dir):
    changed = [(path, content, label) for path, content, label in plans
               if not path.exists() or path.read_text() != content]
    # Validate all destinations before writing any files.
    for path, content, label in changed:
        parent = path.parent
        while not parent.exists():
            parent = parent.parent
        if not os.access(parent, os.W_OK) or (path.exists() and not os.access(path, os.W_OK)):
            raise PermissionError(f'Not writable: {path}. Run as the normal Homebrew owner; inspect ownership instead of running this entire helper with sudo.')
    if changed:
        backup_dir.mkdir(parents=True, exist_ok=False, mode=0o700)
        for path, content, label in changed:
            if path.exists():
                saved = backup_dir / label
                shutil.copy2(path, saved)
                saved.chmod(0o600)
            else:
                (backup_dir / (label + '.was-absent')).write_text(str(path) + '\n')
        for path, content, label in changed:
            path.parent.mkdir(parents=True, exist_ok=True)
            mode = (path.stat().st_mode & 0o777) if path.exists() else 0o644
            if path.name == '.env':
                mode = 0o600
            fd, temp = tempfile.mkstemp(prefix='.cn-prepare-', dir=path.parent)
            try:
                with os.fdopen(fd, 'w') as stream:
                    stream.write(content)
                os.chmod(temp, mode)
                os.replace(temp, path)
            finally:
                if os.path.exists(temp):
                    os.unlink(temp)
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--role', choices=['edge', 'backend-a', 'backend-b'], required=True)
    parser.add_argument('--edge-ip', type=ipv4, required=True)
    parser.add_argument('--backend-a-ip', type=ipv4, required=True)
    parser.add_argument('--backend-b-ip', type=ipv4, required=True)
    parser.add_argument('--interface', default='en0')
    parser.add_argument('--upstream-dns', type=ipv4)
    parser.add_argument('--apply', action='store_true', help='Back up and write config files; otherwise preview only.')
    args = parser.parse_args()
    if len({args.edge_ip, args.backend_a_ip, args.backend_b_ip}) != 3:
        parser.error('The three physical Macs must have three distinct LAN IPs.')
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*', args.interface):
        parser.error('Invalid interface name.')
    repo = Path(__file__).resolve().parent.parent
    home = Path.home()
    result = subprocess.run(['ipconfig', 'getifaddr', args.interface], capture_output=True, text=True)
    local_ip = result.stdout.strip()
    expected = {'edge': args.edge_ip, 'backend-a': args.backend_a_ip, 'backend-b': args.backend_b_ip}[args.role]
    if result.returncode or local_ip != expected:
        parser.error(f'This Mac reports {local_ip or "no IPv4 address"} on {args.interface}, but role {args.role} expects {expected}. Recheck IP/interface/role; no files changed.')
    brew_prefix = Path('/opt/homebrew')
    if shutil.which('brew'):
        result = subprocess.run(['brew', '--prefix'], capture_output=True, text=True, check=True)
        brew_prefix = Path(result.stdout.strip())
    plans = make_plan(repo, home, brew_prefix, args.role, args.edge_ip,
                      args.backend_a_ip, args.backend_b_ip, args.interface, args.upstream_dns)
    print(f'Role {args.role}; current local IP verified: {local_ip}')
    changed = []
    for path, content, label in plans:
        different = not path.exists() or path.read_text() != content
        print(('UPDATE ' if different else 'KEEP   ') + str(path))
        if different:
            changed.append(path)
    if not args.apply:
        print('\nPreview only. Add --apply to write these files with backups.')
        return
    backup = home / '.cn-project-backups' / ('classroom-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    changed = apply_plan(plans, backup)
    print(f'\nUpdated {len(changed)} file(s).')
    if changed:
        print('Backups: ' + str(backup))
    print('No services started/reloaded. No system DNS or PF settings changed.')
    print('Next: follow CLASSROOM-RESTART.md to recreate DNS bindings, reload nginx, set client DNS and verify.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        sys.exit(1)
