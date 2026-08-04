#!/usr/bin/env python3
"""Read-only metadata gate for one local tailscaled log file."""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
from typing import Any, Dict, List, Optional


SCHEMA = "tailscaled_log_size_gate.v1"
OUTPUT_MAX_BYTES = 4_096
EMPTY_FILE = {"exists": False, "regular": False, "symlink": False, "sizeBytes": 0, "inode": 0}


class QuietParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise ValueError("ARGUMENT_INVALID")


def fixed_result(issue: str) -> Dict[str, Any]:
    return {"schema": SCHEMA, "state": "failed", "issues": [issue], "file": dict(EMPTY_FILE)}


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = QuietParser(add_help=False)
    parser.add_argument("--path", required=True)
    parser.add_argument("--warn-bytes", required=True, type=int)
    parser.add_argument("--critical-bytes", required=True, type=int)
    parser.add_argument("--expected-inode", type=int)
    args, unknown = parser.parse_known_args(argv)
    if unknown or not os.path.isabs(args.path) or "\0" in args.path:
        raise ValueError("ARGUMENT_INVALID")
    if args.warn_bytes < 0 or args.critical_bytes <= args.warn_bytes:
        raise ValueError("ARGUMENT_INVALID")
    if args.expected_inode is not None and args.expected_inode <= 0:
        raise ValueError("ARGUMENT_INVALID")
    return args


def file_metadata(path: str) -> Dict[str, Any]:
    metadata = dict(EMPTY_FILE)
    try:
        detail = os.lstat(path)
    except FileNotFoundError:
        return dict(metadata, issues=["LOG_MISSING"])
    except PermissionError:
        return dict(metadata, issues=["LOG_STAT_PERMISSION_DENIED"])
    except OSError:
        return dict(metadata, issues=["LOG_STAT_UNREADABLE"])
    except Exception:
        return dict(metadata, issues=["LOG_STAT_INTERNAL_ERROR"])
    metadata.update({
        "exists": True,
        "regular": stat.S_ISREG(detail.st_mode),
        "symlink": stat.S_ISLNK(detail.st_mode),
        "sizeBytes": int(detail.st_size),
        "inode": int(detail.st_ino),
    })
    return dict(metadata, issues=[])


def inspect_path(path: str, warn_bytes: int, critical_bytes: int, expected_inode: Optional[int] = None) -> Dict[str, Any]:
    metadata_and_issues = file_metadata(path)
    issues = list(metadata_and_issues.pop("issues"))
    if metadata_and_issues["exists"]:
        if metadata_and_issues["symlink"]:
            issues.append("LOG_SYMLINK")
        elif not metadata_and_issues["regular"]:
            issues.append("LOG_NONREGULAR")
        elif metadata_and_issues["sizeBytes"] >= critical_bytes:
            issues.append("SIZE_CRITICAL")
        elif metadata_and_issues["sizeBytes"] >= warn_bytes:
            issues.append("SIZE_WARNING")
        if metadata_and_issues["regular"] and not metadata_and_issues["symlink"] and expected_inode is not None and metadata_and_issues["inode"] != expected_inode:
            issues.append("INODE_CHANGED")
    issues = sorted(set(issues))
    failed = {"LOG_MISSING", "LOG_STAT_PERMISSION_DENIED", "LOG_STAT_UNREADABLE", "LOG_STAT_INTERNAL_ERROR", "LOG_NONREGULAR", "LOG_SYMLINK", "SIZE_CRITICAL"}
    state = "failed" if any(issue in failed for issue in issues) else "degraded" if issues else "ok"
    return {"schema": SCHEMA, "state": state, "issues": issues, "file": metadata_and_issues}


def render(result: Dict[str, Any]) -> str:
    encoded = json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    if len(encoded) > OUTPUT_MAX_BYTES:
        encoded = json.dumps(fixed_result("OUTPUT_TOO_LARGE"), sort_keys=True, separators=(",", ":")).encode("utf-8")
    return encoded.decode("utf-8")


def exit_code(result: Dict[str, Any]) -> int:
    return {"ok": 0, "degraded": 2, "failed": 1}[result["state"]]


def main(argv: Optional[List[str]] = None) -> int:
    try:
        args = parse_args(argv)
        result = inspect_path(args.path, args.warn_bytes, args.critical_bytes, args.expected_inode)
    except (ValueError, SystemExit):
        result = fixed_result("ARGUMENT_INVALID")
    except Exception:
        result = fixed_result("GATE_INTERNAL_ERROR")
    sys.stdout.write(render(result) + "\n")
    return exit_code(result)


if __name__ == "__main__":
    raise SystemExit(main())
