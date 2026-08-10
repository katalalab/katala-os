#!/usr/bin/env python3
"""Read-only preflight for a strictly verified fleet SSH host-key registration."""

import argparse
import base64
import csv
import hashlib
import ipaddress
import json
import os
import re
import stat
import subprocess
import sys
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional, Sequence


SCHEMA = "fleet_known_hosts_gate.v1"
KEY_TYPE = "ssh-ed25519"
DEFAULT_ROSTER = Path("$HOME/work/agent-context/scripts/fleet-hosts.tsv")
DEFAULT_KNOWN_HOSTS = Path.home() / ".ssh" / "known_hosts"
SSH_KEYSCAN = "/usr/bin/ssh-keyscan"
SSH_KEYGEN = "/usr/bin/ssh-keygen"
MAX_ROSTER_BYTES = 64_000
MAX_KNOWN_HOSTS_BYTES = 4_000_000
MAX_COMMAND_BYTES = 65_536
NODE_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}$")
DNS_RE = re.compile(r"^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$")
FINGERPRINT_RE = re.compile(r"^SHA256:[A-Za-z0-9+/]{43}$")


@dataclass(frozen=True)
class CommandResult:
    state: str
    stdout: bytes = b""
    returncode: Optional[int] = None
    stderr: bytes = b""


class SafeArgumentParser(argparse.ArgumentParser):
    def error(self, _message):
        self.print_usage(sys.stderr)
        self.exit(2, f"{self.prog}: error: invalid arguments\n")


def result(node_id, expected, verdict, scan_state, known_hosts_state, issue, surface_count=0):
    safe_node_id = node_id if isinstance(node_id, str) and NODE_ID_RE.fullmatch(node_id) else "invalid"
    safe_expected = expected if valid_fingerprint(expected) else "invalid"
    return {
        "schema": SCHEMA,
        "mode": "read-only",
        "verdict": verdict,
        "exitCode": {"pass": 0, "actionRequired": 2, "fail": 1}.get(verdict, 1),
        "nodeId": safe_node_id,
        "expectedEd25519Sha256": safe_expected,
        "keyType": KEY_TYPE,
        "scanSurfaceCount": surface_count,
        "scanState": scan_state,
        "knownHostsState": known_hosts_state,
        "issue": issue,
    }


def valid_fingerprint(value):
    if not isinstance(value, str) or not FINGERPRINT_RE.fullmatch(value):
        return False
    try:
        digest = base64.b64decode(value[7:] + "=", validate=True)
    except (ValueError, TypeError):
        return False
    return len(digest) == 32 and fingerprint_from_digest(digest) == value


def fingerprint_from_digest(digest):
    return "SHA256:" + base64.b64encode(digest).decode("ascii").rstrip("=")


def fingerprint_from_key_blob(blob):
    return fingerprint_from_digest(hashlib.sha256(blob).digest())


def valid_dns(value):
    return isinstance(value, str) and DNS_RE.fullmatch(value) is not None


def valid_ipv4(value):
    try:
        return isinstance(value, str) and ipaddress.ip_address(value).version == 4
    except ValueError:
        return False


def read_roster(path, node_id):
    try:
        metadata = os.stat(path, follow_symlinks=False)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > MAX_ROSTER_BYTES:
            return None, "ROSTER_INVALID"
        with open(path, "r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle, delimiter="\t")
            header = set(reader.fieldnames or [])
            rows = list(reader)
    except (OSError, UnicodeError, csv.Error):
        return None, "ROSTER_UNREADABLE"
    required = {"alias", "dns", "ipv4", "status", "role", "node_id"}
    if not required.issubset(header):
        return None, "ROSTER_INVALID"
    if not isinstance(node_id, str) or not NODE_ID_RE.fullmatch(node_id):
        return None, "ROSTER_NODE_INVALID"
    matches = [row for row in rows if row.get("node_id") == node_id]
    if len(matches) != 1:
        return None, "ROSTER_NODE_COUNT"
    row = matches[0]
    if row.get("status") != "online":
        return None, "ROSTER_NODE_UNAVAILABLE"
    role = row.get("role", "")
    if role == "archive-only" or role == "no-ssh-expected" or "no-ssh" in role or "archive" in role:
        return None, "ROSTER_ROLE_EXCLUDED"
    if not isinstance(row.get("alias"), str) or not NODE_ID_RE.fullmatch(row["alias"]):
        return None, "ROSTER_ALIAS_INVALID"
    if not valid_dns(row.get("dns")) or not valid_ipv4(row.get("ipv4")):
        return None, "ROSTER_ADDRESS_INVALID"
    return row, None


def trusted_binary(path):
    try:
        metadata = os.stat(path, follow_symlinks=True)
    except OSError:
        return False
    return stat.S_ISREG(metadata.st_mode) and bool(metadata.st_mode & stat.S_IXUSR)


def close_streams(proc):
    for stream in (proc.stdout, proc.stderr):
        if stream is not None:
            try:
                stream.close()
            except OSError:
                pass


def close_process(proc):
    try:
        proc.kill()
    except OSError:
        pass
    try:
        proc.wait(timeout=1)
    except (OSError, subprocess.TimeoutExpired):
        pass
    close_streams(proc)


def drain_stream(stream, sink):
    try:
        while True:
            chunk = stream.read(65_536)
            if not chunk:
                return
            sink.extend(chunk)
    except (OSError, ValueError):
        return


def run_bounded(argv: Sequence[str], timeout: int, output_cap=MAX_COMMAND_BYTES):
    """Run an absolute trusted binary without a shell and retain bounded output only.

    Pipes are drained by threads: selectors cannot poll pipes on Windows, and this
    gate runs on every fleet OS. The cap is checked after the streams close, so a
    runaway command is bounded by the timeout rather than cut mid-stream — at
    keyscan scale the difference does not matter.
    """
    try:
        proc = subprocess.Popen(
            list(argv),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            shell=False,
            close_fds=True,
        )
    except OSError:
        return CommandResult("COMMAND_START_FAILED")
    try:
        buffers = {"stdout": bytearray(), "stderr": bytearray()}
        readers = []
        for name, stream in (("stdout", proc.stdout), ("stderr", proc.stderr)):
            thread = threading.Thread(target=drain_stream, args=(stream, buffers[name]), daemon=True)
            thread.start()
            readers.append(thread)
        try:
            returncode = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            close_process(proc)
            return CommandResult("COMMAND_TIMEOUT")
        # The child exiting closes the write ends; readers hit EOF right after.
        for thread in readers:
            thread.join(timeout=1.0)
        if len(buffers["stdout"]) > output_cap or len(buffers["stderr"]) > output_cap:
            close_process(proc)
            return CommandResult("COMMAND_OUTPUT_LIMIT")
        if returncode != 0:
            return CommandResult(
                "COMMAND_NONZERO",
                bytes(buffers["stdout"]),
                returncode,
                bytes(buffers["stderr"]),
            )
        return CommandResult(
            "COMMAND_OK",
            bytes(buffers["stdout"]),
            returncode,
            bytes(buffers["stderr"]),
        )
    except (OSError, ValueError, RuntimeError):
        close_process(proc)
        return CommandResult("COMMAND_INTERNAL")
    finally:
        close_streams(proc)


def parse_ed25519_blob(encoded):
    try:
        blob = base64.b64decode(encoded, validate=True)
    except (ValueError, TypeError):
        return None
    if len(blob) > 8_192 or len(blob) < 4:
        return None
    first_length = int.from_bytes(blob[:4], "big")
    first_end = 4 + first_length
    if first_end + 4 > len(blob) or blob[4:first_end] != KEY_TYPE.encode("ascii"):
        return None
    second_length = int.from_bytes(blob[first_end:first_end + 4], "big")
    if second_length != 32 or first_end + 4 + second_length != len(blob):
        return None
    return blob


def parse_key_lines(output, reject_unexpected):
    fingerprints = set()
    for raw_line in output.splitlines():
        if not raw_line or raw_line.startswith(b"#"):
            continue
        fields = raw_line.split()
        if len(fields) < 3:
            return None, "KEY_FORMAT_INVALID"
        if fields[0].startswith(b"@"):
            return None, "KEY_MARKER_UNSUPPORTED"
        try:
            key_type = fields[1].decode("ascii")
            encoded = fields[2].decode("ascii")
        except UnicodeDecodeError:
            return None, "KEY_FORMAT_INVALID"
        if key_type != KEY_TYPE:
            if reject_unexpected:
                return None, "KEY_TYPE_UNEXPECTED"
            continue
        blob = parse_ed25519_blob(encoded)
        if blob is None:
            return None, "KEY_INVALID"
        fingerprints.add(fingerprint_from_key_blob(blob))
    return fingerprints, None


def scan_surface(target, expected, timeout, runner):
    command = [SSH_KEYSCAN, "-4", "-q", "-T", str(timeout), "-t", "ed25519", target]
    executed = runner(command, timeout)
    if executed.state != "COMMAND_OK":
        return None, "SCAN_" + executed.state
    fingerprints, error = parse_key_lines(executed.stdout, True)
    if error:
        return None, "SCAN_" + error
    if not fingerprints:
        return None, "SCAN_EMPTY"
    if len(fingerprints) != 1:
        return None, "SCAN_KEY_CONFLICT"
    if next(iter(fingerprints)) != expected:
        return None, "SCAN_FINGERPRINT_MISMATCH"
    return fingerprints, None


def inspect_known_hosts(known_hosts, aliases, expected, timeout, runner):
    try:
        metadata = os.stat(known_hosts, follow_symlinks=False)
    except FileNotFoundError:
        return "MISSING", None
    except OSError:
        return "FAILED", "KNOWN_HOSTS_UNREADABLE"
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > MAX_KNOWN_HOSTS_BYTES:
        return "FAILED", "KNOWN_HOSTS_INVALID"
    fingerprints = set()
    alias_expected_present = False
    for index, alias in enumerate(aliases):
        command = [SSH_KEYGEN, "-F", alias, "-f", str(known_hosts)]
        executed = runner(command, timeout)
        if executed.state == "COMMAND_NONZERO" and executed.returncode == 1:
            if not executed.stdout and not executed.stderr:
                continue
            return "FAILED", "KNOWN_HOSTS_LOOKUP_FAILED"
        if executed.state != "COMMAND_OK":
            return "FAILED", "KNOWN_HOSTS_LOOKUP_FAILED"
        found, error = parse_key_lines(executed.stdout, False)
        if error:
            return "FAILED", "KNOWN_HOSTS_KEY_INVALID"
        fingerprints.update(found)
        if index == 0 and expected in found:
            alias_expected_present = True
    if any(fingerprint != expected for fingerprint in fingerprints):
        return "FAILED", "KNOWN_HOSTS_CONFLICT"
    if alias_expected_present:
        return "PRESENT", None
    return "MISSING", None


def gate(node_id, expected, roster, known_hosts, timeout, runner=run_bounded):
    if not valid_fingerprint(expected):
        return result(node_id, expected, "fail", "NOT_STARTED", "NOT_CHECKED", "EXPECTED_FINGERPRINT_INVALID")
    if not trusted_binary(SSH_KEYSCAN) or not trusted_binary(SSH_KEYGEN):
        return result(node_id, expected, "fail", "NOT_STARTED", "NOT_CHECKED", "SYSTEM_BINARY_INVALID")
    row, roster_error = read_roster(roster, node_id)
    if roster_error:
        return result(node_id, expected, "fail", "NOT_STARTED", "NOT_CHECKED", roster_error)
    for target in (row["dns"], row["ipv4"]):
        _, scan_error = scan_surface(target, expected, timeout, runner)
        if scan_error:
            return result(node_id, expected, "fail", "FAILED", "NOT_CHECKED", scan_error)
    state, known_error = inspect_known_hosts(known_hosts, (row.get("alias", ""), row["dns"], row["ipv4"]), expected, timeout, runner)
    if known_error:
        return result(node_id, expected, "fail", "MATCHED", state, known_error, 2)
    if state == "PRESENT":
        return result(node_id, expected, "pass", "MATCHED", "PRESENT", "NONE", 2)
    return result(node_id, expected, "actionRequired", "MATCHED", "MISSING", "REGISTRATION_REQUIRED", 2)


def parse_args(argv):
    parser = SafeArgumentParser(
        prog="fleet-known-hosts-gate.py",
        description="Read-only fleet known-hosts verifier",
    )
    parser.add_argument("--node-id", required=True)
    parser.add_argument("--expected-ed25519-sha256", required=True)
    parser.add_argument("--roster", type=Path, default=DEFAULT_ROSTER)
    parser.add_argument("--known-hosts", type=Path, default=DEFAULT_KNOWN_HOSTS)
    parser.add_argument("--timeout", type=int, default=10)
    args = parser.parse_args(argv)
    if not 1 <= args.timeout <= 30:
        parser.error("--timeout must be between 1 and 30")
    return args


def main(argv=None):
    args = parse_args(argv)
    try:
        report = gate(args.node_id, args.expected_ed25519_sha256, args.roster, args.known_hosts, args.timeout)
    except Exception:
        report = result(args.node_id, args.expected_ed25519_sha256, "fail", "NOT_STARTED", "NOT_CHECKED", "UNEXPECTED_ERROR")
    print(json.dumps(report, separators=(",", ":"), sort_keys=True))
    return {"pass": 0, "actionRequired": 2, "fail": 1}[report["verdict"]]


if __name__ == "__main__":
    sys.exit(main())
