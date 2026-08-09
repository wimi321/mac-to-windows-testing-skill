#!/usr/bin/env python3
"""Controller CLI for the Mac-to-Windows Testing agent skill.

The controller intentionally uses only the Python standard library. Windows UI
execution stays in PowerShell so the Windows target does not need Python.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import json
import os
import pathlib
import platform
import re
import secrets
import shutil
import subprocess
import sys
import time
from typing import Any, Iterable


SCHEMA_VERSION = 1
VERSION = "0.1.0"
RUN_DIR_NAME = ".mac-to-windows-testing"
DEFAULT_REMOTE_ROOT = r"$env:LOCALAPPDATA\MacToWindowsTesting"
FINAL_STATES = {"PASS", "FAIL", "BLOCKED"}
BLOCKED_VISION = "BLOCKED_VISION_UNAVAILABLE"


class CliError(RuntimeError):
    """Expected user-facing command failure."""

    def __init__(self, message: str, exit_code: int = 2) -> None:
        super().__init__(message)
        self.exit_code = exit_code


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def new_run_id() -> str:
    return f"{dt.datetime.now(dt.timezone.utc):%Y%m%dT%H%M%SZ}-{secrets.token_hex(4)}"


def dump_json(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_json(path: pathlib.Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError as exc:
        raise CliError(f"File not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise CliError(f"Invalid JSON in {path}: {exc}") from exc


def run_command(
    args: list[str],
    *,
    cwd: pathlib.Path | None = None,
    input_text: str | None = None,
    timeout: int = 30,
    check: bool = False,
) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            args,
            cwd=str(cwd) if cwd else None,
            input=input_text,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=check,
        )
    except FileNotFoundError as exc:
        raise CliError(f"Required command is not installed: {args[0]}") from exc
    except subprocess.TimeoutExpired as exc:
        raise CliError(f"Command timed out after {timeout}s: {' '.join(args)}") from exc


def parse_scalar(text: str) -> Any:
    value = text.strip()
    if value == "":
        return None
    if value.startswith(("\"", "'")):
        if value[0] == "\"":
            try:
                return json.loads(value)
            except json.JSONDecodeError as exc:
                raise CliError(f"Invalid quoted YAML scalar: {value}") from exc
        if len(value) < 2 or not value.endswith("'"):
            raise CliError(f"Invalid quoted YAML scalar: {value}")
        return value[1:-1].replace("''", "'")
    lowered = value.lower()
    if lowered in {"true", "false"}:
        return lowered == "true"
    if lowered in {"null", "~"}:
        return None
    if re.fullmatch(r"-?\d+", value):
        return int(value)
    if re.fullmatch(r"-?(?:\d+\.\d*|\d*\.\d+)", value):
        return float(value)
    return value


def yaml_tokens(text: str) -> list[tuple[int, str, int]]:
    tokens: list[tuple[int, str, int]] = []
    for line_number, raw in enumerate(text.splitlines(), start=1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if "\t" in raw[: len(raw) - len(raw.lstrip())]:
            raise CliError(f"Tabs are not allowed for YAML indentation (line {line_number})")
        indent = len(raw) - len(raw.lstrip(" "))
        if indent % 2:
            raise CliError(f"YAML indentation must use multiples of two spaces (line {line_number})")
        tokens.append((indent, raw.strip(), line_number))
    return tokens


def parse_simple_yaml(text: str) -> Any:
    """Parse the intentionally small profile subset without external packages."""

    stripped = text.lstrip()
    if stripped.startswith("{") or stripped.startswith("["):
        try:
            return json.loads(text)
        except json.JSONDecodeError as exc:
            raise CliError(f"Invalid JSON-compatible YAML: {exc}") from exc

    tokens = yaml_tokens(text)
    if not tokens:
        return {}

    def parse_block(index: int, indent: int) -> tuple[Any, int]:
        if index >= len(tokens) or tokens[index][0] != indent:
            raise CliError("Malformed YAML block")
        is_list = tokens[index][1].startswith("-")
        container: Any = [] if is_list else {}

        while index < len(tokens):
            current_indent, content, line_number = tokens[index]
            if current_indent < indent:
                break
            if current_indent > indent:
                raise CliError(f"Unexpected indentation on line {line_number}")
            if content.startswith("-") != is_list:
                raise CliError(f"Cannot mix mappings and lists on line {line_number}")

            if is_list:
                item_text = content[1:].strip()
                if not item_text:
                    if index + 1 >= len(tokens) or tokens[index + 1][0] <= indent:
                        container.append(None)
                        index += 1
                    else:
                        child, index = parse_block(index + 1, tokens[index + 1][0])
                        container.append(child)
                    continue

                if ":" in item_text:
                    key, raw_value = item_text.split(":", 1)
                    key = key.strip()
                    if not key:
                        raise CliError(f"Empty key on line {line_number}")
                    item: dict[str, Any] = {}
                    item[key] = parse_scalar(raw_value)
                    index += 1
                    if index < len(tokens) and tokens[index][0] > indent:
                        child, index = parse_block(index, tokens[index][0])
                        if not isinstance(child, dict):
                            if item[key] is None:
                                item[key] = child
                            else:
                                raise CliError(f"Expected mapping below list item on line {line_number}")
                        elif item[key] is None and len(child) == 1 and key in child:
                            item[key] = child[key]
                        else:
                            item.update(child)
                    container.append(item)
                    continue

                container.append(parse_scalar(item_text))
                index += 1
                continue

            if ":" not in content:
                raise CliError(f"Expected key: value on line {line_number}")
            key, raw_value = content.split(":", 1)
            key = key.strip()
            if not key:
                raise CliError(f"Empty key on line {line_number}")
            value = parse_scalar(raw_value)
            index += 1
            if value is None and index < len(tokens) and tokens[index][0] > indent:
                value, index = parse_block(index, tokens[index][0])
            container[key] = value

        return container, index

    result, end = parse_block(0, tokens[0][0])
    if end != len(tokens):
        raise CliError(f"Could not parse YAML near line {tokens[end][2]}")
    return result


def load_profile(path: pathlib.Path) -> dict[str, Any]:
    try:
        parsed = parse_simple_yaml(path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError as exc:
        raise CliError(f"Profile not found: {path}") from exc
    if not isinstance(parsed, dict):
        raise CliError("Profile root must be a mapping")
    return parsed


def validate_profile(profile: dict[str, Any]) -> None:
    if profile.get("version") != SCHEMA_VERSION:
        raise CliError(f"Unsupported profile version: {profile.get('version')!r}")
    for section in ("project", "commands", "automation", "scenarios"):
        if section not in profile:
            raise CliError(f"Missing profile section: {section}")
    if not isinstance(profile["project"], dict) or not isinstance(profile["commands"], dict):
        raise CliError("project and commands must be mappings")
    if not isinstance(profile["automation"], dict) or not isinstance(profile["scenarios"], list):
        raise CliError("automation must be a mapping and scenarios must be a list")
    for command_name in ("build", "test", "launch"):
        command = profile["commands"].get(command_name)
        if not isinstance(command, str) or not command.strip() or "replace with" in command.lower():
            raise CliError(f"commands.{command_name} must be a verified command")
    if profile["automation"].get("allowDestructiveActions") not in {True, False}:
        raise CliError("automation.allowDestructiveActions must be true or false")
    transport = profile["automation"].get("transport")
    if transport not in {"ssh", "winrm", "uu-computer-use", "windows-agent"}:
        raise CliError(f"Unsupported automation.transport: {transport!r}")
    repair_limit = profile["automation"].get("repairLimit")
    if not isinstance(repair_limit, int) or not 0 <= repair_limit <= 10:
        raise CliError("automation.repairLimit must be an integer from 0 to 10")
    threshold = profile["automation"].get("visualConfidenceThreshold")
    if not isinstance(threshold, (int, float)) or not 0.5 <= float(threshold) <= 1:
        raise CliError("automation.visualConfidenceThreshold must be from 0.5 to 1")
    if profile["automation"]["allowDestructiveActions"]:
        fixture = profile["automation"].get("destructiveFixture", {})
        if not isinstance(fixture, dict) or fixture.get("isolated") is not True or not fixture.get("label"):
            raise CliError("Destructive actions require destructiveFixture.isolated=true and a fixture label")
    serialized = json.dumps(profile, ensure_ascii=False)
    secret_patterns = [
        r"(?i)(?:password|passwd|api[_-]?key|bearer|secret)\s*[=:]\s*[A-Za-z0-9._-]{8,}",
        r"(?i)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
    ]
    if any(re.search(pattern, serialized) for pattern in secret_patterns):
        raise CliError("Profiles must not contain credentials or private keys")
    allowed_actions = {"wait", "discover", "screenshot", "assert", "click", "type", "shortcut", "close"}
    allowed_assertions = {"exists", "notExists", "enabled", "focusable", "focused", "visible", "textEquals", "withinWindow", "noOverlap"}
    seen_ids: set[str] = set()
    for scenario in profile["scenarios"]:
        if not isinstance(scenario, dict) or not scenario.get("id") or not isinstance(scenario.get("steps"), list):
            raise CliError("Every scenario needs an id and a steps list")
        if scenario["id"] in seen_ids:
            raise CliError(f"Duplicate scenario id: {scenario['id']}")
        seen_ids.add(scenario["id"])
        if not isinstance(scenario.get("window"), dict):
            raise CliError(f"Scenario {scenario['id']} needs a window selector")
        if not any(scenario["window"].get(key) for key in ("name", "automationId")):
            raise CliError(f"Scenario {scenario['id']} window needs name or automationId")
        for step in scenario["steps"]:
            if not isinstance(step, dict) or step.get("action") not in allowed_actions:
                raise CliError(f"Scenario {scenario['id']} has an unsupported action")
            action = step["action"]
            if action in {"click", "type", "assert"} and not isinstance(step.get("target"), dict):
                raise CliError(f"Scenario {scenario['id']} action {action} needs a target")
            if action == "assert" and step.get("condition", "exists") not in allowed_assertions:
                raise CliError(f"Scenario {scenario['id']} has an unsupported assertion")


def git_value(project_root: pathlib.Path, *args: str) -> str:
    completed = run_command(["git", *args], cwd=project_root)
    return completed.stdout.strip() if completed.returncode == 0 else ""


def git_metadata(project_root: pathlib.Path) -> dict[str, Any]:
    status = git_value(project_root, "status", "--short")
    remotes = git_value(project_root, "remote", "-v")
    return {
        "root": str(project_root.resolve()),
        "branch": git_value(project_root, "branch", "--show-current"),
        "commit": git_value(project_root, "rev-parse", "HEAD"),
        "dirty": bool(status),
        "status": status.splitlines(),
        "remotes": remotes.splitlines(),
    }


def profile_sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compile_manifest(config_path: pathlib.Path, project_root: pathlib.Path, output: pathlib.Path | None) -> pathlib.Path:
    profile = load_profile(config_path)
    validate_profile(profile)
    run_id = new_run_id()
    git = git_metadata(project_root)
    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "runId": run_id,
        "createdAt": utc_now(),
        "profileSha256": profile_sha(config_path),
        "controller": {
            "platform": platform.platform(),
            "python": platform.python_version(),
        },
        "source": git,
        "project": profile["project"],
        "commands": profile["commands"],
        "automation": profile["automation"],
        "scenarios": profile["scenarios"],
        "redaction": {
            "patterns": profile.get("redaction", {}).get("patterns", []),
            "defaultsEnabled": True,
        },
    }
    if output is None:
        output = project_root / RUN_DIR_NAME / "runs" / run_id / "manifest.json"
    dump_json(output, manifest)
    return output


def find_uu_cli() -> str | None:
    candidates = [
        "/Applications/UURemote.app/Contents/Helpers/uuyc-cli",
        "/Applications/UU远程.app/Contents/Helpers/uuyc-cli",
    ]
    for candidate in candidates:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return shutil.which("uuyc-cli")


def command_fact(name: str) -> dict[str, Any]:
    path = shutil.which(name)
    return {"available": bool(path), "path": path}


def uu_fact() -> dict[str, Any]:
    cli = find_uu_cli()
    result: dict[str, Any] = {"available": bool(cli), "path": cli, "success": False}
    if not cli:
        return result
    completed = run_command([cli, "status"], timeout=10)
    result["exitCode"] = completed.returncode
    try:
        payload = json.loads(completed.stdout or "{}")
        result["success"] = bool(payload.get("success"))
        if not result["success"]:
            result["error"] = payload.get("error") or payload.get("message") or "UU app unavailable"
    except json.JSONDecodeError:
        result["error"] = "UU CLI did not return JSON"
    return result


def ssh_probe(host: str) -> dict[str, Any]:
    completed = run_command(
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", host, "powershell.exe", "-NoProfile", "-Command", "$PSVersionTable.PSVersion.ToString()"],
        timeout=15,
    )
    return {
        "host": host,
        "success": completed.returncode == 0,
        "powerShell": completed.stdout.strip(),
        "error": completed.stderr.strip() if completed.returncode else None,
    }


def powershell_encoded_command(script: str) -> str:
    return base64.b64encode(script.encode("utf-16-le")).decode("ascii")


def winrm_powershell(host: str, script: str, *, timeout: int = 60) -> subprocess.CompletedProcess[str]:
    """Run PowerShell through an existing, secured WinRM configuration.

    The command deliberately does not modify TrustedHosts, firewall rules, TLS,
    or credentials. Those are one-time administrator concerns outside this tool.
    """

    payload = base64.b64encode(script.encode("utf-8")).decode("ascii")
    outer = (
        "$ErrorActionPreference='Stop';"
        f"$source=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{payload}'));"
        f"Invoke-Command -ComputerName {powershell_quote(host)} "
        "-ScriptBlock { param($code) & ([ScriptBlock]::Create($code)) } -ArgumentList $source"
    )
    return run_command(
        ["pwsh", "-NoProfile", "-NonInteractive", "-EncodedCommand", powershell_encoded_command(outer)],
        timeout=timeout,
    )


def winrm_probe(host: str) -> dict[str, Any]:
    try:
        completed = winrm_powershell(host, "$PSVersionTable.PSVersion.ToString()", timeout=20)
    except CliError as exc:
        return {"host": host, "success": False, "error": str(exc)}
    return {
        "host": host,
        "success": completed.returncode == 0,
        "powerShell": completed.stdout.strip(),
        "error": completed.stderr.strip() if completed.returncode else None,
    }


def doctor(args: argparse.Namespace) -> int:
    facts: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "checkedAt": utc_now(),
        "controller": {
            "platform": platform.platform(),
            "python": platform.python_version(),
            "git": command_fact("git"),
            "ssh": command_fact("ssh"),
            "scp": command_fact("scp"),
            "pwsh": command_fact("pwsh"),
            "uu": uu_fact(),
            "vision": os.environ.get("MAC2WIN_VISION_CAPABLE", "unknown"),
        },
    }
    if args.host:
        facts["windows"] = winrm_probe(args.host) if args.transport == "winrm" else ssh_probe(args.host)
    channels = [
        bool(args.host and facts.get("windows", {}).get("success")),
        bool(facts["controller"]["uu"].get("success") and facts["controller"]["vision"] == "true"),
    ]
    facts["status"] = "PASS" if any(channels) else "BLOCKED"
    if not any(channels):
        facts["blocker"] = "BLOCKED_AUTOMATION_CHANNEL"
    if args.json:
        print(json.dumps(facts, ensure_ascii=False, indent=2))
    else:
        print(f"Status: {facts['status']}")
        print(f"Controller: {facts['controller']['platform']}")
        print(f"UU: {'ready' if facts['controller']['uu'].get('success') else 'unavailable'}")
        if args.host:
            print(f"{args.transport.upper()} {args.host}: {'ready' if facts['windows']['success'] else 'unavailable'}")
        if facts.get("blocker"):
            print(f"Blocker: {facts['blocker']}")
    return 0 if facts["status"] == "PASS" else 2


def redact_text(text: str, custom_patterns: Iterable[str] = ()) -> str:
    home = str(pathlib.Path.home())
    replacements = [
        (re.escape(home), "<HOME>"),
        (r"(?i)(authorization\s*:\s*bearer\s+)[^\s\"']+", r"\1<REDACTED>"),
        (r"(?i)((?:api[_-]?key|token|password|passwd|secret)\s*[=:]\s*)[^\s,;\"']+", r"\1<REDACTED>"),
        (r"\b(?:\d{1,3}\.){3}\d{1,3}\b", "<IP>"),
        (r"(?i)C:\\Users\\[^\\\s]+", r"C:\\Users\\<USER>"),
        (r"(?<!\d)(?:\+?86[- ]?)?1[3-9]\d{9}(?!\d)", "<PHONE>"),
        (r"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", "<EMAIL>"),
    ]
    redacted = text
    for pattern, replacement in replacements:
        redacted = re.sub(pattern, replacement, redacted)
    for pattern in custom_patterns:
        redacted = re.sub(pattern, "<REDACTED_CUSTOM>", redacted)
    return redacted


def scenario_rows(result: dict[str, Any]) -> list[str]:
    rows = []
    for scenario in result.get("scenarios", []):
        rows.append(
            f"| {scenario.get('id', '')} | {scenario.get('status', 'UNKNOWN')} | {scenario.get('summary', '')} |"
        )
    return rows


def render_report(run_dir: pathlib.Path) -> pathlib.Path:
    result_path = run_dir / "result.json"
    result = load_json(result_path)
    review_path = run_dir / "ai-review.json"
    review = load_json(review_path) if review_path.exists() else None
    lines = [
        "# Mac-to-Windows Test Report",
        "",
        f"**Status:** `{result.get('status', 'UNKNOWN')}`  ",
        f"**Run:** `{result.get('runId', run_dir.name)}`  ",
        f"**Created:** `{result.get('finishedAt') or result.get('createdAt') or ''}`",
        "",
        "## Environment",
        "",
        "```json",
        json.dumps(result.get("environment", {}), ensure_ascii=False, indent=2),
        "```",
        "",
        "## Scenarios",
        "",
        "| Scenario | Status | Summary |",
        "|---|---|---|",
        *scenario_rows(result),
    ]
    if review:
        lines.extend(["", "## AI Visual Review", ""])
        lines.append(f"Confidence: `{review.get('confidence', 0):.2f}`")
        for finding in review.get("findings", []):
            lines.extend(
                [
                    "",
                    f"### {finding.get('severity', 'info').upper()}: {finding.get('summary', '')}",
                    "",
                    f"Evidence: {finding.get('evidence', '')}",
                    "",
                    f"Screenshot: `{finding.get('screenshot', '')}`",
                ]
            )
    if result.get("blocker"):
        lines.extend(["", "## Blocker", "", f"`{result['blocker']}`"])
    lines.extend(["", "## Evidence", "", f"Local directory: `{run_dir}`", ""])
    custom = result.get("redaction", {}).get("patterns", [])
    report = redact_text("\n".join(lines), custom)
    report_path = run_dir / "report.md"
    report_path.write_text(report, encoding="utf-8")
    return report_path


def finalize_result(result_path: pathlib.Path, review_path: pathlib.Path) -> dict[str, Any]:
    result = load_json(result_path)
    review = load_json(review_path)
    if review.get("runId") != result.get("runId"):
        raise CliError("AI review runId does not match result runId")
    review_status = review.get("status")
    if review_status not in FINAL_STATES:
        raise CliError(f"Invalid AI review status: {review_status!r}")
    threshold = float(result.get("visualConfidenceThreshold", 0.85))
    confidence = float(review.get("confidence", 0))
    runner_status = result.get("status")
    run_dir = result_path.resolve().parent
    screenshots = list((run_dir / "screenshots").glob("*.png")) if (run_dir / "screenshots").is_dir() else []
    ui_trees = list((run_dir / "ui-trees").glob("*.json")) if (run_dir / "ui-trees").is_dir() else []
    evidence_complete = bool(screenshots and ui_trees)
    invalid_findings = []
    for finding in review.get("findings", []):
        evidence_path = pathlib.Path(str(finding.get("screenshot", "")))
        if not evidence_path.is_absolute():
            evidence_path = run_dir / evidence_path
        if not evidence_path.is_file():
            invalid_findings.append(str(finding.get("screenshot", "")))
    if runner_status in {"FAIL", "BLOCKED"}:
        final_status = runner_status
    elif not evidence_complete or invalid_findings:
        final_status = "BLOCKED"
        result["blocker"] = "BLOCKED_EVIDENCE_MISSING"
    elif review_status == "PASS" and confidence >= threshold:
        final_status = "PASS"
    elif review_status == "FAIL":
        final_status = "FAIL"
    else:
        final_status = "BLOCKED"
        result["blocker"] = review.get("blocker") or "BLOCKED_VISUAL_UNCERTAIN"
    result["status"] = final_status
    result["finishedAt"] = utc_now()
    result["visualReview"] = {
        "status": review_status,
        "confidence": confidence,
        "findingCount": len(review.get("findings", [])),
        "evidenceComplete": evidence_complete,
        "invalidFindingScreenshots": invalid_findings,
    }
    dump_json(result_path, result)
    return result


def skill_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parents[1]


def runner_source() -> pathlib.Path:
    candidate = skill_root() / "scripts" / "windows-runner"
    if not candidate.is_dir():
        raise CliError(f"Bundled Windows runner is missing: {candidate}")
    return candidate


def powershell_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def ssh_powershell(host: str, script: str, *, timeout: int = 60) -> subprocess.CompletedProcess[str]:
    return run_command(
        ["ssh", "-o", "BatchMode=yes", host, "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "-"],
        input_text=script,
        timeout=timeout,
    )


def remote_powershell(transport: str, host: str, script: str, *, timeout: int = 60) -> subprocess.CompletedProcess[str]:
    if transport == "ssh":
        return ssh_powershell(host, script, timeout=timeout)
    if transport == "winrm":
        return winrm_powershell(host, script, timeout=timeout)
    raise CliError(f"Unsupported shell transport: {transport}")


def remote_root(host: str, transport: str = "ssh") -> str:
    script = "[Console]::Write([IO.Path]::Combine($env:LOCALAPPDATA,'MacToWindowsTesting'))"
    completed = remote_powershell(transport, host, script, timeout=20)
    if completed.returncode or not completed.stdout.strip():
        raise CliError(f"Unable to resolve Windows runner directory: {completed.stderr.strip()}")
    return completed.stdout.strip()


def send_file_remote(transport: str, host: str, local_path: pathlib.Path, remote_path: str) -> None:
    encoded = base64.b64encode(local_path.read_bytes()).decode("ascii")
    script = (
        f"$p={powershell_quote(remote_path)};"
        "$d=[IO.Path]::GetDirectoryName($p);[IO.Directory]::CreateDirectory($d)|Out-Null;"
        "$b=[Console]::In.ReadToEnd().Trim();"
        "[IO.File]::WriteAllBytes($p,[Convert]::FromBase64String($b))"
    )
    if transport == "ssh":
        completed = run_command(
            ["ssh", "-o", "BatchMode=yes", host, "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
            input_text=encoded,
            timeout=60,
        )
    else:
        payload_script = script.replace("[Console]::In.ReadToEnd().Trim()", powershell_quote(encoded))
        completed = remote_powershell(transport, host, payload_script, timeout=90)
    if completed.returncode:
        raise CliError(f"Could not transfer {local_path.name}: {completed.stderr.strip()}")


def install_runner_remote(transport: str, host: str) -> None:
    root = remote_root(host, transport)
    source = runner_source()
    for local_file in sorted(source.glob("*.ps1")) + sorted(source.glob("*.psm1")):
        send_file_remote(transport, host, local_file, root + "\\runner\\" + local_file.name)
    install_path = root + r"\runner\Install-Runner.ps1"
    script = f"& {powershell_quote(install_path)} -RunnerRoot {powershell_quote(root)}"
    completed = remote_powershell(transport, host, script, timeout=60)
    if completed.returncode:
        raise CliError(f"Runner installation failed: {completed.stderr.strip()}")
    print(completed.stdout.strip() or "Windows runner installed.")


def runner_status_remote(transport: str, host: str) -> int:
    root = remote_root(host, transport)
    status_path = root + r"\runner\Get-RunnerStatus.ps1"
    script = f"if(Test-Path -LiteralPath {powershell_quote(status_path)}){{& {powershell_quote(status_path)} -RunnerRoot {powershell_quote(root)}}}else{{Write-Output '{{\"status\":\"NOT_INSTALLED\"}}';exit 2}}"
    completed = remote_powershell(transport, host, script, timeout=30)
    print(completed.stdout.strip())
    if completed.stderr.strip():
        print(completed.stderr.strip(), file=sys.stderr)
    return completed.returncode


def uninstall_runner_remote(transport: str, host: str) -> None:
    root = remote_root(host, transport)
    uninstall_path = root + r"\runner\Uninstall-Runner.ps1"
    script = f"if(Test-Path -LiteralPath {powershell_quote(uninstall_path)}){{& {powershell_quote(uninstall_path)} -RunnerRoot {powershell_quote(root)}}}"
    completed = remote_powershell(transport, host, script, timeout=60)
    if completed.returncode:
        raise CliError(f"Runner uninstall failed: {completed.stderr.strip()}")
    print(completed.stdout.strip() or "Windows runner removed.")


def trust_profile_remote(transport: str, host: str, config_path: pathlib.Path) -> None:
    profile = load_profile(config_path)
    validate_profile(profile)
    root = remote_root(host, transport)
    trust_path = root + r"\runner\Trust-Profile.ps1"
    repository = str(profile.get("project", {}).get("repository", ""))
    script = (
        f"& {powershell_quote(trust_path)} -RunnerRoot {powershell_quote(root)} "
        f"-ProfileSha256 {powershell_quote(profile_sha(config_path))} -Repository {powershell_quote(repository)}"
    )
    completed = remote_powershell(transport, host, script, timeout=30)
    if completed.returncode:
        raise CliError(f"Could not trust profile: {completed.stderr.strip()}")
    print(completed.stdout.strip() or "Profile trusted.")


def run_over_remote(args: argparse.Namespace) -> int:
    project_root = pathlib.Path(args.project_root).resolve()
    manifest_path = compile_manifest(pathlib.Path(args.config).resolve(), project_root, None)
    manifest = load_json(manifest_path)
    run_id = manifest["runId"]
    root = remote_root(args.host, args.transport)
    status = runner_status_remote(args.transport, args.host)
    if status:
        result = {
            "schemaVersion": 1,
            "runId": run_id,
            "status": "BLOCKED",
            "blocker": "BLOCKED_RUNNER_NOT_INSTALLED",
            "createdAt": utc_now(),
            "scenarios": [],
        }
        dump_json(manifest_path.parent / "result.json", result)
        print("Runner is not installed. Run: mac2win-test runner install --host <host>")
        return 2
    remote_manifest = root + f"\\incoming\\{run_id}.json"
    send_file_remote(args.transport, args.host, manifest_path, remote_manifest)
    submit = root + r"\runner\Submit-Run.ps1"
    script = f"& {powershell_quote(submit)} -RunnerRoot {powershell_quote(root)} -ManifestPath {powershell_quote(remote_manifest)}"
    completed = remote_powershell(args.transport, args.host, script, timeout=30)
    if completed.returncode:
        raise CliError(f"Could not submit run: {completed.stderr.strip()}")

    remote_result = root + f"\\runs\\{run_id}\\result.json"
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        probe = remote_powershell(
            args.transport, args.host,
            f"if(Test-Path -LiteralPath {powershell_quote(remote_result)}){{[Console]::Write('READY')}}",
            timeout=20,
        )
        if probe.stdout.strip() == "READY":
            break
        time.sleep(3)
    else:
        raise CliError(f"Timed out waiting for Windows result after {args.timeout}s")

    collect_remote_run(args.transport, args.host, root, run_id, manifest_path.parent)
    result = load_json(manifest_path.parent / "result.json")
    print(f"Run {run_id}: {result.get('status', 'UNKNOWN')}")
    print(f"Evidence: {manifest_path.parent}")
    if result.get("status") == "PASS":
        return 0
    if result.get("status") == "PENDING_AI_REVIEW":
        return 3
    return 1


def collect_remote_run(transport: str, host: str, root: str, run_id: str, local_dir: pathlib.Path) -> None:
    remote_dir = root + f"\\runs\\{run_id}"
    list_script = (
        f"$root={powershell_quote(remote_dir)};"
        "Get-ChildItem -LiteralPath $root -Recurse -File|ForEach-Object{"
        "[pscustomobject]@{Relative=$_.FullName.Substring($root.Length).TrimStart('\\');Length=$_.Length}}|"
        "ConvertTo-Json -Compress"
    )
    completed = remote_powershell(transport, host, list_script, timeout=30)
    if completed.returncode or not completed.stdout.strip():
        raise CliError(f"Could not list remote evidence: {completed.stderr.strip()}")
    entries = json.loads(completed.stdout)
    if isinstance(entries, dict):
        entries = [entries]
    for entry in entries:
        relative = entry["Relative"]
        remote_file = remote_dir + "\\" + relative
        get_script = f"[Console]::Write([Convert]::ToBase64String([IO.File]::ReadAllBytes({powershell_quote(remote_file)})))"
        file_result = remote_powershell(transport, host, get_script, timeout=120)
        if file_result.returncode:
            raise CliError(f"Could not collect {relative}: {file_result.stderr.strip()}")
        destination = local_dir / pathlib.PureWindowsPath(relative).as_posix()
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(base64.b64decode(file_result.stdout.strip()))


def init_profile(args: argparse.Namespace) -> int:
    root = pathlib.Path(args.project_root).resolve()
    destination = root / "mac-to-windows-testing.yaml"
    if destination.exists() and not args.force:
        raise CliError(f"Profile already exists: {destination}. Use --force to replace it.")
    template = skill_root() / "assets" / "default-profile.yaml"
    destination.write_text(template.read_text(encoding="utf-8"), encoding="utf-8")
    print(destination)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="mac2win-test", description="Evidence-first real Windows UI validation from a Mac controller.")
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    sub = parser.add_subparsers(dest="command", required=True)

    init_cmd = sub.add_parser("init", help="Create a project profile")
    init_cmd.add_argument("--project-root", default=".")
    init_cmd.add_argument("--force", action="store_true")
    init_cmd.set_defaults(func=init_profile)

    doctor_cmd = sub.add_parser("doctor", help="Probe controller and Windows connectivity")
    doctor_cmd.add_argument("--host", help="SSH host alias for the Windows test PC")
    doctor_cmd.add_argument("--transport", choices=["ssh", "winrm"], default="ssh")
    doctor_cmd.add_argument("--json", action="store_true")
    doctor_cmd.set_defaults(func=doctor)

    compile_cmd = sub.add_parser("compile", help="Compile YAML profile into an immutable manifest")
    compile_cmd.add_argument("--config", default="mac-to-windows-testing.yaml")
    compile_cmd.add_argument("--project-root", default=".")
    compile_cmd.add_argument("--output")

    def do_compile(ns: argparse.Namespace) -> int:
        output = pathlib.Path(ns.output).resolve() if ns.output else None
        path = compile_manifest(pathlib.Path(ns.config).resolve(), pathlib.Path(ns.project_root).resolve(), output)
        print(path)
        return 0

    compile_cmd.set_defaults(func=do_compile)

    run_cmd = sub.add_parser("run", help="Run a trusted profile on Windows")
    run_cmd.add_argument("--transport", choices=["ssh", "winrm", "uu-computer-use", "windows-agent"], default="ssh")
    run_cmd.add_argument("--host", help="SSH host alias")
    run_cmd.add_argument("--config", default="mac-to-windows-testing.yaml")
    run_cmd.add_argument("--project-root", default=".")
    run_cmd.add_argument("--timeout", type=int, default=900)

    def do_run(ns: argparse.Namespace) -> int:
        if ns.transport in {"ssh", "winrm"}:
            if not ns.host:
                raise CliError(f"--host is required for the {ns.transport} transport")
            return run_over_remote(ns)
        manifest = compile_manifest(pathlib.Path(ns.config).resolve(), pathlib.Path(ns.project_root).resolve(), None)
        result = {
            "schemaVersion": 1,
            "runId": load_json(manifest)["runId"],
            "status": "BLOCKED",
            "blocker": "BLOCKED_AUTOMATION_CHANNEL",
            "createdAt": utc_now(),
            "scenarios": [],
        }
        dump_json(manifest.parent / "result.json", result)
        print(f"Prepared manifest: {manifest}")
        print("This transport must be continued by a vision-capable agent in the interactive Windows session.")
        return 2

    run_cmd.set_defaults(func=do_run)

    finalize_cmd = sub.add_parser("finalize", help="Merge deterministic and AI visual results")
    finalize_cmd.add_argument("--result", required=True)
    finalize_cmd.add_argument("--review", required=True)

    def do_finalize(ns: argparse.Namespace) -> int:
        result = finalize_result(pathlib.Path(ns.result), pathlib.Path(ns.review))
        print(result["status"])
        return 0 if result["status"] == "PASS" else 1

    finalize_cmd.set_defaults(func=do_finalize)

    report_cmd = sub.add_parser("report", help="Render a sanitized Markdown report")
    report_cmd.add_argument("--run-dir", required=True)

    def do_report(ns: argparse.Namespace) -> int:
        print(render_report(pathlib.Path(ns.run_dir).resolve()))
        return 0

    report_cmd.set_defaults(func=do_report)

    collect_cmd = sub.add_parser("collect", help="Collect a completed Windows evidence bundle")
    collect_cmd.add_argument("--transport", choices=["ssh", "winrm"], default="ssh")
    collect_cmd.add_argument("--host", required=True)
    collect_cmd.add_argument("--run-id", required=True)
    collect_cmd.add_argument("--output", default=None)

    def do_collect(ns: argparse.Namespace) -> int:
        root = remote_root(ns.host, ns.transport)
        output = pathlib.Path(ns.output).resolve() if ns.output else pathlib.Path.cwd() / RUN_DIR_NAME / "runs" / ns.run_id
        output.mkdir(parents=True, exist_ok=True)
        collect_remote_run(ns.transport, ns.host, root, ns.run_id, output)
        print(output)
        return 0

    collect_cmd.set_defaults(func=do_collect)

    runner_cmd = sub.add_parser("runner", help="Manage the Windows interactive runner")
    runner_sub = runner_cmd.add_subparsers(dest="runner_command", required=True)
    for name in ("install", "status", "uninstall", "trust"):
        command = runner_sub.add_parser(name)
        command.add_argument("--host", required=True)
        command.add_argument("--transport", choices=["ssh", "winrm"], default="ssh")
    runner_sub.choices["trust"].add_argument("--config", default="mac-to-windows-testing.yaml")
    runner_sub.choices["install"].set_defaults(func=lambda ns: (install_runner_remote(ns.transport, ns.host), 0)[1])
    runner_sub.choices["status"].set_defaults(func=lambda ns: runner_status_remote(ns.transport, ns.host))
    runner_sub.choices["uninstall"].set_defaults(func=lambda ns: (uninstall_runner_remote(ns.transport, ns.host), 0)[1])
    runner_sub.choices["trust"].set_defaults(
        func=lambda ns: (trust_profile_remote(ns.transport, ns.host, pathlib.Path(ns.config).resolve()), 0)[1]
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except CliError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return exc.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
