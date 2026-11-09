import errno
import os
from pathlib import Path
import tempfile


assert os.getuid() == 10001, "Unexpected UID"
assert os.getgid() == 10001, "Unexpected GID"
print("NON_ROOT_OK", flush=True)

root_probe = Path("/task1-rootfs-check")
try:
    with root_probe.open("x") as probe:
        probe.write("check")
except OSError as error:
    assert error.errno == errno.EROFS, f"Expected EROFS, got errno={error.errno}"
else:
    root_probe.unlink()
    raise AssertionError("Root filesystem is writable")
print("ROOTFS_READ_ONLY_OK", flush=True)

with tempfile.NamedTemporaryFile(dir="/tmp") as probe:
    probe.write(b"check")
    probe.flush()
print("TMP_WRITE_OK", flush=True)

token_path = Path("/var/run/secrets/kubernetes.io/serviceaccount/token")
assert not token_path.exists(), "Unexpected Kubernetes API token"
print("NO_API_TOKEN_OK", flush=True)

status = {}
for line in Path("/proc/self/status").read_text().splitlines():
    key, separator, value = line.partition(":")
    if separator:
        status[key] = value.strip()

assert status["NoNewPrivs"] == "1", "Privilege escalation is not blocked"
assert status["Seccomp"] == "2", "Seccomp filter is not active"
assert int(status["CapEff"], 16) == 0, "Effective capabilities are not empty"
print("PRIVILEGES_SECCOMP_CAPABILITIES_OK", flush=True)
