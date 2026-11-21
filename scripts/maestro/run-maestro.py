#!/usr/bin/env python3
"""Bound Maestro teardown after its final summary and successful JUnit report."""
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import time
import xml.etree.ElementTree as ET


def report_passed(report):
    try:
        root = ET.parse(report).getroot()
        cases = list(root.iter('testcase'))
        return bool(cases) and not any(
            list(root.iter(tag)) for tag in ('failure', 'error', 'skipped')
        ) and all(
            int(suite.get('failures', '0')) == 0 and int(suite.get('errors', '0')) == 0
            for suite in root.iter('testsuite')
        )
    except (OSError, ET.ParseError, ValueError):
        return False


ROOT = Path(__file__).resolve().parents[2]
FLOWS = {
    'foreground-complete': ROOT / '.maestro/flows/foreground-complete.yaml',
    'background-complete': ROOT / '.maestro/flows/background-complete.yaml',
    'kill-relaunch-resume': ROOT / '.maestro/flows/kill-relaunch-resume.yaml',
    'low-memory-kill': ROOT / '.maestro/flows/low-memory-kill.yaml',
    'network-drop-resume': ROOT / '.maestro/flows/network-drop-resume.yaml',
    'error-bad-url': ROOT / '.maestro/flows/error-bad-url.yaml',
    'error-404': ROOT / '.maestro/flows/error-404.yaml',
    'error-5xx': ROOT / '.maestro/flows/error-5xx.yaml',
    'error-unwritable-destination': ROOT / '.maestro/flows/error-unwritable-destination.yaml',
    'cancel-cleanup': ROOT / '.maestro/flows/cancel-cleanup.yaml',
    'parallel-downloads': ROOT / '.maestro/flows/parallel-downloads.yaml',
    'completion-once': ROOT / '.maestro/flows/completion-once.yaml',
    'batch-error-404': ROOT / '.maestro/flows/batch-error-404.yaml',
    'batch-error-5xx': ROOT / '.maestro/flows/batch-error-5xx.yaml',
    'batch-kill-mid': ROOT / '.maestro/flows/batch-kill-mid.yaml',
}


def run(timeout, scenarios, device, platform='android', results_dir=None):
    if not 0 < timeout <= 600:
        raise ValueError('Maestro timeout must be between 0 and 600 seconds')
    if isinstance(scenarios, str):
        scenario_list = [scenarios]
    else:
        scenario_list = list(scenarios)
    for scenario in scenario_list:
        if scenario not in FLOWS:
            raise ValueError(f'Unknown Maestro E2E flow: {scenario}')
    if platform not in {'android', 'ios'}:
        raise ValueError('Maestro platform must be android or ios')
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,127}', device):
        raise ValueError('Invalid device identifier')
    results = Path(results_dir) if results_dir else ROOT / (
        'maestro-results-ios' if platform == 'ios' else 'maestro-results'
    )
    results.mkdir(exist_ok=True)
    report = results / 'junit.xml'
    flow_paths = [str(FLOWS[scenario]) for scenario in scenario_list]
    command = [
        'maestro', 'test', '--config', str(ROOT / '.maestro/config.yaml'), *flow_paths,
        '--platform', platform, '--udid', device,
        '--format', 'junit', '--output', str(report),
        '--debug-output', str(results / 'debug'), '--flatten-debug-output',
        '--test-output-dir', str(results / 'artifacts'),
    ]
    try:
        os.remove(report)
    except FileNotFoundError:
        pass
    return run_command(command, report, timeout)


def run_command(command, report, timeout):
    process = None
    termination_signal = 0

    def request_termination(signum, _frame):
        nonlocal termination_signal
        termination_signal = signum

    previous_handler = signal.signal(signal.SIGTERM, request_termination)
    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            status = monitor_process(process, selector, report, timeout, lambda: termination_signal)
    finally:
        try:
            if process is not None:
                stop_process(process)
        finally:
            signal.signal(signal.SIGTERM, previous_handler)
    return 128 + termination_signal if termination_signal else status


def read_output(selector, output):
    for key, _ in selector.select(0.2):
        chunk = os.read(key.fileobj.fileno(), 65536)
        if not chunk:
            selector.unregister(key.fileobj)
            continue
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()
        output = (output + chunk.decode('utf-8', errors='replace'))[-8192:]
    return output


def monitor_process(process, selector, report, timeout, termination_signal):
    deadline = time.monotonic() + timeout
    passed_at = None
    output = ''
    while process.poll() is None:
        if termination_signal():
            return 128 + termination_signal()
        output = read_output(selector, output)
        summary_passed = bool(re.search(r'\b(\d+)/\1 Flow Passed\b', output))
        if summary_passed and report_passed(report):
            passed_at = passed_at or time.monotonic()
            if time.monotonic() - passed_at >= 0.5:
                print('Maestro flow and JUnit report passed; stopping stalled CLI teardown.', flush=True)
                return 0
        else:
            passed_at = None
        if time.monotonic() >= deadline:
            return 124
    return process.returncode


def signal_process_group(process, signum):
    try:
        os.killpg(process.pid, signum)
    except ProcessLookupError:
        pass


def stop_process(process):
    signal_process_group(process, signal.SIGTERM)
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass
    signal_process_group(process, signal.SIGKILL)
    process.wait()
    os.set_blocking(process.stdout.fileno(), False)
    remaining = process.stdout.read()
    if remaining:
        sys.stdout.buffer.write(remaining)
    process.stdout.close()


if __name__ == '__main__':
    if len(sys.argv) < 5:
        raise SystemExit(
            'Usage: run-maestro.py <timeout> <flow> [more-flows...] <device> <platform> [results_dir]'
        )
    timeout = float(sys.argv[1])
    if sys.argv[-1] in {'android', 'ios'}:
        platform = sys.argv[-1]
        device = sys.argv[-2]
        flow_args = sys.argv[2:-2]
        results_dir_arg = None
    else:
        platform = sys.argv[-2]
        device = sys.argv[-3]
        flow_args = sys.argv[2:-3]
        results_dir_arg = sys.argv[-1]
    if not flow_args:
        raise SystemExit('At least one flow id is required')
    sys.exit(run(timeout, flow_args, device, platform, results_dir_arg))