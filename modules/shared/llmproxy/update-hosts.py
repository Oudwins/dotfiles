import argparse
import ipaddress
from pathlib import Path
import shutil

parser = argparse.ArgumentParser(description="Update a managed hosts-file entry.")
parser.add_argument("domain")
parser.add_argument("address")
parser.add_argument("--hosts-file", type=Path, default=Path("/etc/hosts"))
args = parser.parse_args()

address = args.address
ipaddress.ip_address(address)
path = args.hosts_file
hostname = args.domain.encode("ascii")
name = hostname.split(b".", 1)[0].decode("ascii")
begin = f"# BEGIN dotfiles {name}".encode("ascii")
end = f"# END dotfiles {name}".encode("ascii")
original = path.read_bytes()
retained = []
inside = False

for line in original.splitlines(keepends=True):
    if line.strip() == begin:
        if inside:
            raise SystemExit(f"Nested {name} hosts-file markers; refusing to modify hosts")
        inside = True
    elif line.strip() == end:
        if not inside:
            raise SystemExit(f"Unmatched {name} hosts-file marker; refusing to modify hosts")
        inside = False
    elif not inside:
        if hostname in line.split(b"#", 1)[0].split()[1:]:
            raise SystemExit(f"Unmanaged {name} hosts entry exists; refusing to overwrite it")
        retained.append(line)

if inside:
    raise SystemExit(f"Unclosed {name} hosts-file marker; refusing to modify hosts")

updated = b"".join(retained)
if updated and not updated.endswith(b"\n"):
    updated += b"\n"
updated += begin + b"\n" + address.encode("ascii") + b"\t" + hostname + b"\n" + end + b"\n"

if updated != original:
    backup = path.with_name(path.name + f".before-{name}")
    if not backup.exists():
        shutil.copy2(path, backup)
    path.write_bytes(updated)
