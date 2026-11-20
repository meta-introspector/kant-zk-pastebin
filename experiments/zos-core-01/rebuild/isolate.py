"""Run the rebuild with Landlock file-content writes confined to this handoff."""
import ctypes
import os
from pathlib import Path
import platform

if platform.system() != "Linux" or platform.machine() != "x86_64":
    raise SystemExit("The containment launcher requires Linux x86_64")
root = Path(__file__).resolve().parents[1]
for path in root.rglob("*"):
    if path.is_symlink() or (path.is_file() and path.stat().st_nlink != 1):
        raise SystemExit(f"Unexpected link in handoff: {path}")

libc = ctypes.CDLL(None, use_errno=True)


def checked(result):
    if result < 0:
        errno = ctypes.get_errno()
        raise OSError(errno, os.strerror(errno))
    return result


class PathRule(ctypes.Structure):
    _layout_ = "ms"
    _pack_ = 1
    _fields_ = [("rights", ctypes.c_uint64), ("parent", ctypes.c_int32)]


abi = checked(libc.syscall(444, 0, 0, 1))
if abi < 5:
    raise SystemExit("Landlock ABI 5 or later is required")
# Handle write-open, removal, creation, cross-directory links/renames,
# truncate, and device ioctl. Handle TCP bind/connect without granting either.
rights = (1 << 1) | sum(1 << bit for bit in range(4, 16))
attributes = (ctypes.c_uint64 * 2)(rights, 3)
ruleset = checked(libc.syscall(444, ctypes.byref(attributes), ctypes.sizeof(attributes), 0))
parent = os.open(root, os.O_PATH | os.O_DIRECTORY | os.O_CLOEXEC)
try:
    rule = PathRule(rights, parent)
    checked(libc.syscall(445, ruleset, 1, ctypes.byref(rule), 0))
    checked(libc.prctl(38, 1, 0, 0, 0))
    checked(libc.syscall(446, ruleset, 0))
finally:
    os.close(parent)
    os.close(ruleset)

probe = root / ".write-probe"
with probe.open("xb") as handle:
    handle.write(b"lab-local write succeeded\n")
probe.unlink()
print(f"Landlock ABI {abi}; write rule limited to the package root; in-root write/unlink succeeded; TCP bind/connect denied", flush=True)
for variable in ("CORE_LEAN", "CORE_RUSTC"):
    os.environ[variable] = str(Path(os.environ[variable]).resolve(strict=True))
os.chdir(root / "rebuild")
os.execve("/usr/bin/python3", ["/usr/bin/python3", "-B", "run.py"], {
    "CORE_LEAN": os.environ["CORE_LEAN"], "CORE_RUSTC": os.environ["CORE_RUSTC"],
    "PATH": "/usr/bin:/bin", "LC_ALL": "C", "HOME": str(root), "TMPDIR": str(root),
})
