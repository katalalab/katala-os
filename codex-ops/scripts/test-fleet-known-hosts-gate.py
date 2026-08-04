#!/usr/bin/env python3
import base64
import contextlib
import importlib.util
import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).with_name("fleet-known-hosts-gate.py")
SPEC = importlib.util.spec_from_file_location("fleet_known_hosts_gate", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


HEADER = "alias\tdns\tipv4\tos\tstatus\trole\tnode_id\texpected_hostname\tdev_session_kind\n"
GOOD_ROW = "node-a\tnode-a.example.test\t100.1.2.3\tmacOS\tonline\tprimary\tnode-a\thost\tmacos\n"
CANARY = "RAW_PRIVATE_CANARY_/Users/secret/known_hosts_stderr"


def key_blob(fill=b"A"):
    key_type = b"ssh-ed25519"
    return len(key_type).to_bytes(4, "big") + key_type + (32).to_bytes(4, "big") + fill * 32


def key_line(host="host", fill=b"A"):
    return (host + " ssh-ed25519 " + base64.b64encode(key_blob(fill)).decode("ascii") + "\n").encode("ascii")


def fingerprint(fill=b"A"):
    return MODULE.fingerprint_from_key_blob(key_blob(fill))


class GateTest(unittest.TestCase):
    def roster(self, directory, content=GOOD_ROW):
        path = Path(directory) / "fleet.tsv"
        path.write_text(HEADER + content, encoding="utf-8")
        return path

    def known_hosts(self, directory):
        path = Path(directory) / "known_hosts"
        path.write_text("# synthetic\n", encoding="utf-8")
        return path

    def runner(self, scan=b"", lookups=None, states=None):
        calls = []
        lookups = lookups or {}
        states = states or {}
        def invoke(argv, timeout):
            calls.append((argv, timeout))
            if argv[0] == MODULE.SSH_KEYSCAN:
                target = argv[-1]
                return states.get(target, MODULE.CommandResult("COMMAND_OK", scan, 0))
            target = argv[2]
            return states.get(target, MODULE.CommandResult("COMMAND_OK", lookups.get(target, b""), 0))
        return invoke, calls

    def invoke(self, roster, known, expected, runner):
        with mock.patch.object(MODULE, "trusted_binary", return_value=True):
            return MODULE.gate("node-a", expected, roster, known, 7, runner)

    def test_exact_keyscan_argv_serial_no_shell_or_network(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, calls = self.runner(scan=key_line())
            report = self.invoke(self.roster(directory), self.known_hosts(directory), fingerprint(), runner)
        self.assertEqual("actionRequired", report["verdict"])
        self.assertEqual([
            [MODULE.SSH_KEYSCAN, "-4", "-q", "-T", "7", "-t", "ed25519", "node-a.example.test"],
            [MODULE.SSH_KEYSCAN, "-4", "-q", "-T", "7", "-t", "ed25519", "100.1.2.3"],
        ], [call[0] for call in calls[:2]])
        self.assertFalse(any("ssh" in call[0][0] and "shell" in call[0] for call in calls))

    def test_fqdn_ipv4_match_and_registration_required(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, _ = self.runner(scan=key_line())
            report = self.invoke(self.roster(directory), self.known_hosts(directory), fingerprint(), runner)
        self.assertEqual(("MATCHED", "MISSING", "REGISTRATION_REQUIRED", 2), (report["scanState"], report["knownHostsState"], report["issue"], report["scanSurfaceCount"]))
        self.assertEqual(("read-only", 2), (report["mode"], report["exitCode"]))

    def test_expected_already_present_is_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, _ = self.runner(scan=key_line(), lookups={"node-a": key_line("node-a")})
            report = self.invoke(self.roster(directory), self.known_hosts(directory), fingerprint(), runner)
        self.assertEqual(("pass", "PRESENT", "NONE"), (report["verdict"], report["knownHostsState"], report["issue"]))
        self.assertEqual(0, report["exitCode"])

    def test_dns_only_registration_does_not_pass_alias_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, _ = self.runner(scan=key_line(), lookups={"node-a.example.test": key_line("node-a.example.test")})
            report = self.invoke(self.roster(directory), self.known_hosts(directory), fingerprint(), runner)
        self.assertEqual(("actionRequired", "MISSING", "REGISTRATION_REQUIRED"), (report["verdict"], report["knownHostsState"], report["issue"]))

    def test_scan_mismatch_and_multiple_keys_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, _ = self.runner(scan=key_line(fill=b"B"))
            mismatch = self.invoke(self.roster(directory), self.known_hosts(directory), fingerprint(), runner)
            runner, _ = self.runner(scan=key_line(fill=b"A") + key_line(fill=b"B"))
            multiple = self.invoke(self.roster(directory), self.known_hosts(directory), fingerprint(), runner)
        self.assertEqual("SCAN_FINGERPRINT_MISMATCH", mismatch["issue"])
        self.assertEqual("SCAN_KEY_CONFLICT", multiple["issue"])

    def test_invalid_base64_and_invalid_key_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, _ = self.runner(scan=b"host ssh-ed25519 !!!\n")
            bad_base64 = self.invoke(self.roster(directory), self.known_hosts(directory), fingerprint(), runner)
            runner, _ = self.runner(scan=b"host ssh-ed25519 YQ==\n")
            bad_key = self.invoke(self.roster(directory), self.known_hosts(directory), fingerprint(), runner)
        self.assertEqual("SCAN_KEY_INVALID", bad_base64["issue"])
        self.assertEqual("SCAN_KEY_INVALID", bad_key["issue"])

    def test_output_cap_timeout_and_nonzero_are_stable(self):
        with tempfile.TemporaryDirectory() as directory:
            for state, issue in (("COMMAND_OUTPUT_LIMIT", "SCAN_COMMAND_OUTPUT_LIMIT"), ("COMMAND_TIMEOUT", "SCAN_COMMAND_TIMEOUT"), ("COMMAND_NONZERO", "SCAN_COMMAND_NONZERO")):
                runner, _ = self.runner(states={"node-a.example.test": MODULE.CommandResult(state, b"partial", 255)})
                report = self.invoke(self.roster(directory), self.known_hosts(directory), fingerprint(), runner)
                self.assertEqual(issue, report["issue"])

    def test_known_hosts_conflict_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, _ = self.runner(scan=key_line(), lookups={"100.1.2.3": key_line(fill=b"B")})
            report = self.invoke(self.roster(directory), self.known_hosts(directory), fingerprint(), runner)
        self.assertEqual(("fail", "FAILED", "KNOWN_HOSTS_CONFLICT"), (report["verdict"], report["knownHostsState"], report["issue"]))

    def test_known_hosts_markers_fail_closed(self):
        marked = b"@revoked node-a ssh-ed25519 " + base64.b64encode(key_blob()) + b"\n"
        with tempfile.TemporaryDirectory() as directory:
            runner, _ = self.runner(
                scan=key_line(),
                lookups={"node-a": key_line("node-a") + marked},
            )
            report = self.invoke(self.roster(directory), self.known_hosts(directory), fingerprint(), runner)
        self.assertEqual(("fail", "FAILED", "KNOWN_HOSTS_KEY_INVALID"), (report["verdict"], report["knownHostsState"], report["issue"]))

    def test_hashed_lookup_uses_exact_ssh_keygen_argv(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, calls = self.runner(scan=key_line(), lookups={"node-a": b"# Host hashed found\n" + key_line("|1|hash")})
            report = self.invoke(self.roster(directory), self.known_hosts(directory), fingerprint(), runner)
            known = self.known_hosts(directory)
            # Re-run while the file exists for exact argv validation.
            report = self.invoke(self.roster(directory), known, fingerprint(), runner)
        self.assertEqual("pass", report["verdict"])
        keygen = [call[0] for call in calls if call[0][0] == MODULE.SSH_KEYGEN]
        self.assertIn([MODULE.SSH_KEYGEN, "-F", "node-a.example.test", "-f", str(known)], keygen)
        self.assertTrue(all("-h" not in argv for argv in keygen))

    def test_known_hosts_rc1_with_stderr_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            state = MODULE.CommandResult("COMMAND_NONZERO", b"", 1, CANARY.encode())
            runner, _ = self.runner(scan=key_line(), states={"node-a": state})
            report = self.invoke(self.roster(directory), self.known_hosts(directory), fingerprint(), runner)
        self.assertEqual(("fail", "FAILED", "KNOWN_HOSTS_LOOKUP_FAILED"), (report["verdict"], report["knownHostsState"], report["issue"]))
        self.assertNotIn(CANARY, str(report))

    def test_roster_failures_are_closed(self):
        cases = [
            ("", "ROSTER_NODE_COUNT"),
            (GOOD_ROW.replace("online", "retired"), "ROSTER_NODE_UNAVAILABLE"),
            (GOOD_ROW.replace("primary", "no-ssh-expected"), "ROSTER_ROLE_EXCLUDED"),
            (GOOD_ROW.replace("node-a.example.test", "bad dns"), "ROSTER_ADDRESS_INVALID"),
            (GOOD_ROW + GOOD_ROW, "ROSTER_NODE_COUNT"),
        ]
        with tempfile.TemporaryDirectory() as directory:
            for content, issue in cases:
                runner, _ = self.runner(scan=key_line())
                report = self.invoke(self.roster(directory, content), self.known_hosts(directory), fingerprint(), runner)
                self.assertEqual(issue, report["issue"])

    def test_roster_requires_and_validates_alias(self):
        with tempfile.TemporaryDirectory() as directory:
            missing_alias = Path(directory) / "missing-alias.tsv"
            missing_alias.write_text(HEADER.replace("alias\t", "") + GOOD_ROW.split("\t", 1)[1], encoding="utf-8")
            runner, _ = self.runner(scan=key_line())
            missing_report = self.invoke(missing_alias, self.known_hosts(directory), fingerprint(), runner)
            invalid_report = self.invoke(
                self.roster(directory, GOOD_ROW.replace("node-a\t", "bad alias\t", 1)),
                self.known_hosts(directory),
                fingerprint(),
                runner,
            )
        self.assertEqual("ROSTER_INVALID", missing_report["issue"])
        self.assertEqual("ROSTER_ALIAS_INVALID", invalid_report["issue"])

    def test_privacy_is_deterministic_and_no_apply_option(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, _ = self.runner(states={"node-a.example.test": MODULE.CommandResult("COMMAND_NONZERO", CANARY.encode(), 255)})
            first = self.invoke(self.roster(directory), self.known_hosts(directory), fingerprint(), runner)
            second = self.invoke(self.roster(directory), self.known_hosts(directory), fingerprint(), runner)
        self.assertEqual(first, second)
        rendered = str(first)
        self.assertNotIn(CANARY, rendered)
        self.assertNotIn("/Users/", rendered)
        self.assertNotIn("apply", MODULE.parse_args.__code__.co_consts)
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            MODULE.parse_args(["--node-id", "node-a", "--expected-ed25519-sha256", fingerprint(), "--apply"])

    def test_invalid_cli_values_are_fixed_before_reporting(self):
        with tempfile.TemporaryDirectory() as directory:
            roster = self.roster(directory)
            known = self.known_hosts(directory)
            runner, _ = self.runner(scan=key_line())
            with mock.patch.object(MODULE, "trusted_binary", return_value=True):
                bad_node = MODULE.gate(CANARY, fingerprint(), roster, known, 7, runner)
                bad_expected = MODULE.gate("node-a", CANARY, roster, known, 7, runner)
        self.assertEqual("invalid", bad_node["nodeId"])
        self.assertEqual("invalid", bad_expected["expectedEd25519Sha256"])
        self.assertNotIn(CANARY, str(bad_node) + str(bad_expected))
        self.assertNotIn("/Users/", str(bad_node) + str(bad_expected))

    def test_run_bounded_closes_pipes_and_retains_bounded_stderr(self):
        stdout_read, stdout_write = os.pipe()
        stderr_read, stderr_write = os.pipe()
        os.write(stdout_write, b"out")
        os.write(stderr_write, b"diagnostic")
        os.close(stdout_write)
        os.close(stderr_write)
        proc = mock.Mock()
        proc.stdout = os.fdopen(stdout_read, "rb", buffering=0)
        proc.stderr = os.fdopen(stderr_read, "rb", buffering=0)
        proc.wait.return_value = 0
        with mock.patch.object(MODULE.subprocess, "Popen", return_value=proc):
            executed = MODULE.run_bounded([MODULE.SSH_KEYSCAN], 1)
        self.assertEqual(("COMMAND_OK", b"out", b"diagnostic"), (executed.state, executed.stdout, executed.stderr))
        self.assertTrue(proc.stdout.closed)
        self.assertTrue(proc.stderr.closed)

    def test_run_bounded_enforces_per_stream_output_cap(self):
        stdout_read, stdout_write = os.pipe()
        stderr_read, stderr_write = os.pipe()
        os.write(stdout_write, b"12345")
        os.close(stdout_write)
        os.close(stderr_write)
        proc = mock.Mock()
        proc.stdout = os.fdopen(stdout_read, "rb", buffering=0)
        proc.stderr = os.fdopen(stderr_read, "rb", buffering=0)
        proc.wait.return_value = 0
        with mock.patch.object(MODULE.subprocess, "Popen", return_value=proc):
            executed = MODULE.run_bounded([MODULE.SSH_KEYSCAN], 1, output_cap=4)
        self.assertEqual("COMMAND_OUTPUT_LIMIT", executed.state)
        self.assertTrue(proc.stdout.closed)
        self.assertTrue(proc.stderr.closed)

    def test_expected_fingerprint_and_timeout_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, _ = self.runner(scan=key_line())
            report = self.invoke(self.roster(directory), self.known_hosts(directory), "SHA256:not-a-fingerprint", runner)
        self.assertEqual("EXPECTED_FINGERPRINT_INVALID", report["issue"])
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            MODULE.parse_args(["--node-id", "node-a", "--expected-ed25519-sha256", fingerprint(), "--timeout", "31"])
        stderr = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()) as stdout, contextlib.redirect_stderr(stderr), self.assertRaises(SystemExit):
            MODULE.parse_args([
                "--node-id", "node-a",
                "--expected-ed25519-sha256", fingerprint(),
                "--timeout", CANARY,
            ])
        rendered = stdout.getvalue() + stderr.getvalue()
        self.assertNotIn(CANARY, rendered)
        self.assertNotIn("/Users/", rendered)
        self.assertIn("invalid arguments", rendered)


if __name__ == "__main__":
    unittest.main()
