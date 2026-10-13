"""The mock dbt invocation for tests."""

import sys
import time

action, code = sys.argv[1:3]
print("args:", *sys.argv[1:], flush=True)

if action == "wait":
    try:
        time.sleep(30)
    except KeyboardInterrupt:
        sys.exit(2)

sys.exit(int(code))
