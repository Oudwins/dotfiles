"""Create/reuse a macOS RAM disk, refusing to use a persistent mounted volume."""

import os
import plistlib
import subprocess
import sys

mountpoint = sys.argv[1]
os.makedirs(mountpoint, mode=0o700, exist_ok=True)
if os.path.islink(mountpoint):
    raise SystemExit("Refusing a symlinked runtime directory")

if os.path.ismount(mountpoint):
    info = plistlib.loads(
        subprocess.check_output(["/usr/bin/hdiutil", "info", "-plist"])
    )
    if not any(
        image.get("image-path", "").startswith("ram://")
        and any(
            os.path.realpath(entity.get("mount-point", "")) == mountpoint
            for entity in image.get("system-entities", [])
        )
        for image in info.get("images", [])
    ):
        raise SystemExit("Refusing a runtime volume that is not a RAM disk")
    # Ownership must be enforced; noowners would make private files readable by others.
    subprocess.run(
        ["/sbin/mount", "-u", "-o", "owners,nodev,nosuid,noexec,nobrowse", mountpoint],
        check=True,
    )
else:
    device = subprocess.check_output(
        ["/usr/bin/hdiutil", "attach", "-nomount", "ram://65536"], text=True
    ).split()[0]
    try:
        subprocess.run(
            ["/sbin/newfs_hfs", "-v", "CLIProxyAPI", device],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        subprocess.run(
            [
                "/sbin/mount",
                "-t",
                "hfs",
                "-o",
                "owners,nodev,nosuid,noexec,nobrowse",
                device,
                mountpoint,
            ],
            check=True,
        )
    except BaseException:
        subprocess.run(["/usr/bin/hdiutil", "detach", device], check=False)
        raise
