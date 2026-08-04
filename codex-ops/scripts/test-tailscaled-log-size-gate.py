#!/usr/bin/env python3
import builtins
import importlib.util
import io
import json
import os
import socket
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).with_name("tailscaled-log-size-gate.py")
SPEC = importlib.util.spec_from_file_location("tailscaled_log_size_gate", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class TailscaledLogSizeGateTest(unittest.TestCase):
    def test_exact_size_thresholds_and_exit_codes(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "log"
            target.write_bytes(b"x" * 10)
            warning = MODULE.inspect_path(str(target), 10, 20)
            target.write_bytes(b"x" * 20)
            critical = MODULE.inspect_path(str(target), 10, 20)
        self.assertEqual(("degraded", ["SIZE_WARNING"], 2), (warning["state"], warning["issues"], MODULE.exit_code(warning)))
        self.assertEqual(("failed", ["SIZE_CRITICAL"], 1), (critical["state"], critical["issues"], MODULE.exit_code(critical)))

    def test_inode_change_is_degraded_and_combines_sorted_issues(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "log"
            target.write_bytes(b"x" * 10)
            actual_inode = os.lstat(target).st_ino
            result = MODULE.inspect_path(str(target), 10, 20, actual_inode + 1)
        self.assertEqual("degraded", result["state"])
        self.assertEqual(["INODE_CHANGED", "SIZE_WARNING"], result["issues"])
        self.assertEqual(2, MODULE.exit_code(result))

    def test_missing_directory_and_symlink_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            missing = MODULE.inspect_path(str(base / "missing"), 1, 2)
            directory_result = MODULE.inspect_path(str(base), 1, 2)
            target = base / "target"
            target.write_text("x", encoding="utf-8")
            link = base / "link"
            link.symlink_to(target)
            symlink_result = MODULE.inspect_path(str(link), 1, 2)
        self.assertEqual(("failed", ["LOG_MISSING"]), (missing["state"], missing["issues"]))
        self.assertEqual(("failed", ["LOG_NONREGULAR"]), (directory_result["state"], directory_result["issues"]))
        self.assertEqual(("failed", ["LOG_SYMLINK"]), (symlink_result["state"], symlink_result["issues"]))
        self.assertTrue(symlink_result["file"]["symlink"])

    def test_permission_and_internal_errors_do_not_leak_path_or_exception(self):
        path = "/Users/private/FLEET_E2E_SECRET_CANARY"
        with mock.patch.object(MODULE.os, "lstat", side_effect=PermissionError("FLEET_E2E_SECRET_CANARY")):
            denied = MODULE.inspect_path(path, 1, 2)
        with mock.patch.object(MODULE.os, "lstat", side_effect=RuntimeError("FLEET_E2E_SECRET_CANARY")):
            internal = MODULE.inspect_path(path, 1, 2)
        for result, issue in ((denied, "LOG_STAT_PERMISSION_DENIED"), (internal, "LOG_STAT_INTERNAL_ERROR")):
            rendered = MODULE.render(result)
            self.assertEqual(("failed", [issue]), (result["state"], result["issues"]))
            self.assertNotIn(path, rendered)
            self.assertNotIn("FLEET_E2E_SECRET_CANARY", rendered)

    def test_argument_validation_happens_before_stat_and_hides_input(self):
        bad = ["--path", "relative/FLEET_E2E_SECRET_CANARY", "--warn-bytes", "2", "--critical-bytes", "1"]
        with mock.patch.object(MODULE.os, "lstat", side_effect=AssertionError("stat called")), mock.patch("sys.stdout", new_callable=io.StringIO) as stdout:
            code = MODULE.main(bad)
        result = json.loads(stdout.getvalue())
        self.assertEqual(1, code)
        self.assertEqual(["ARGUMENT_INVALID"], result["issues"])
        self.assertNotIn("FLEET_E2E_SECRET_CANARY", stdout.getvalue())

    def test_metadata_output_is_limited_to_allowed_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "log"
            target.write_bytes(b"x")
            result = MODULE.inspect_path(str(target), 2, 3)
        self.assertEqual({"schema", "state", "issues", "file"}, set(result))
        self.assertEqual({"exists", "regular", "symlink", "sizeBytes", "inode"}, set(result["file"]))
        self.assertEqual("ok", result["state"])
        self.assertEqual(0, MODULE.exit_code(result))

    def test_gate_uses_lstat_without_reads_or_external_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "log"
            target.write_bytes(b"x")
            reject = AssertionError("FLEET_E2E_SECRET_CANARY")
            with mock.patch.object(builtins, "open", side_effect=reject), \
                 mock.patch.object(MODULE.os, "open", side_effect=reject), \
                 mock.patch.object(subprocess, "run", side_effect=reject), \
                 mock.patch.object(subprocess, "Popen", side_effect=reject), \
                 mock.patch.object(socket, "create_connection", side_effect=reject):
                result = MODULE.inspect_path(str(target), 2, 3)
        self.assertEqual("ok", result["state"])
        self.assertFalse(result["issues"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
