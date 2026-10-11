"""Stands in for the dbt CLI in test_dbt.py.

It prints its arguments and working directory, then acts on the first argument
and exits with the second.
"""

import os
import sys
import time

action, code = sys.argv[1:3]
print("args:", *sys.argv[1:], flush=True)
print("cwd:", os.path.basename(os.getcwd()), flush=True)

if action == "advance":
    print("03:12:00  CDC positions updated to pending", flush=True)
elif action == "hold":
    print("03:12:00  CDC positions not updated: 2 models didn't succeed", flush=True)
elif action == "wait":
    # Until it's stopped, which dbt does on SIGINT.
    print("ready", flush=True)
    try:
        time.sleep(30)
    except KeyboardInterrupt:
        sys.exit(2)
sys.exit(int(code))
