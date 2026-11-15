"""Drop root and its environment before executing the proxy (also works on macOS)."""

import os
import pwd
import resource
import sys

user, home, executable, *args = sys.argv[1:]
account = pwd.getpwnam(user)
if account.pw_uid == 0:
    raise SystemExit("Refusing to run the proxy as root")

path = os.path.dirname(executable)
if sys.platform == "darwin":
    path += os.pathsep + "/usr/bin"

resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
os.setgroups([])
os.setgid(account.pw_gid)
os.setuid(account.pw_uid)
os.execve(
    executable,
    [executable, *args],
    {
        "HOME": home,
        "USER": user,
        "LOGNAME": user,
        "WRITABLE_PATH": home,
        "PATH": path,
    },
)
