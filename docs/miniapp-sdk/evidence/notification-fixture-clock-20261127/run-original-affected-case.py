from pathlib import Path
import importlib.util
import json
import sys
import time
import unittest

root = Path('/mnt/development/projects/worktrees/hanlin-notification-fixture-clock-20261127')
path = root / 'Scripts/CI/Tests/test_notification_os_scope.py'
spec = importlib.util.spec_from_file_location('test_notification_os_scope', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
original_time = module.runner.time
global_clock_functions = (time.time, time.monotonic, time.sleep)
assert original_time is time
name = 'test_worker_starts_only_after_actual_fresh_ui_exchange_and_uses_original_budgets'
case = module.NotificationScopeTests(name)
result = unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite([case]))
restored = module.runner.time is original_time
global_unchanged = global_clock_functions == (time.time, time.monotonic, time.sleep)
print(json.dumps({'selected': name, 'testsRun': result.testsRun,
                  'failures': len(result.failures), 'errors': len(result.errors),
                  'skipped': len(result.skipped), 'runnerTimeRestored': restored,
                  'globalTimeFunctionsUnchanged': global_unchanged,
                  'fixtureWallClockAfterCase': getattr(case, 'wall_clock', None)}))
assert restored, 'runner.time was not restored after the original case'
assert global_unchanged, 'fixture changed the global time module'
sys.exit(0 if result.wasSuccessful() and result.testsRun == 1 else 1)
