#!/usr/bin/env python3
"""Helper boundary tests. Only invalid inputs: never contact a real CoPing receiver."""
import os
import subprocess
import sys
import time

helper = sys.argv[1]
env = dict(os.environ, COPING_DEBUG="1")
env.pop("COPING_SETUP", None)
for name, payload in [
    ("invalid-json", b"{"),
    ("unknown-hook", b'{"session_id":"session-A","hook_event_name":"Unknown"}'),
    ("over-limit", b"x" * (1_048_576 + 1)),
    ("wrong-types", b'{"session_id":42,"hook_event_name":"Stop"}'),
]:
    result = subprocess.run([helper], input=payload, capture_output=True, env=env, timeout=2)
    assert result.returncode == 0 and not result.stdout and not result.stderr, name
    print(f"Helper {name}: PASS")

# Leave the input pipe open; bounded input reading must exit without EOF.
start = time.monotonic()
process = subprocess.Popen([helper], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, env=env)
process.wait(timeout=2)
process.stdin.close()
assert process.returncode == 0
assert not process.stdout.read() and not process.stderr.read()
print(f"Helper stalled-input deadline: PASS ({time.monotonic() - start:.3f}s)")
