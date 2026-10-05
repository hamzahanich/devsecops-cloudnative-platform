#!/usr/bin/env python3
"""
Dynamic Quarantine Controller for Kubernetes Runtime Defense
Consumes Tetragon eBPF telemetry events and isolates compromised workloads.
"""

import argparse
import json
import logging
import os
import signal
import subprocess
import sys

LOG_FORMAT = "%(asctime)s [%(levelname)s] %(name)s: %(message)s"
logging.basicConfig(level=logging.INFO, format=LOG_FORMAT)
logger = logging.getLogger("quarantine-controller")

SUSPICIOUS_BINARIES = {
    "nmap", "nc", "netcat", "socat", "tcpdump", "wireshark", "tshark", "su"
}

SENSITIVE_TARGETS = {
    "/etc/shadow", "/etc/sudoers", "/root/.ssh"
}

IGNORABLE_NAMESPACES = {
    "kube-system", "kyverno", "monitoring"
}

running = True

def handle_shutdown(signum, frame):
    global running
    logger.info("Shutdown signal received (signal %s). Terminating controller.", signum)
    running = False

signal.signal(signal.SIGINT, handle_shutdown)
signal.signal(signal.SIGTERM, handle_shutdown)

def isolate_pod(namespace: str, pod_name: str, reason: str, dry_run: bool = False):
    logger.warning("Threat detected on %s/%s - Reason: %s", namespace, pod_name, reason)
    
    if dry_run:
        logger.info("[DRY-RUN] Would apply label 'security-status=quarantined' to pod %s/%s", namespace, pod_name)
        return

    cmd = [
        "kubectl", "label", "pod", pod_name,
        "-n", namespace,
        "security-status=quarantined",
        "--overwrite"
    ]
    try:
        subprocess.run(cmd, capture_output=True, text=True, check=True)
        logger.info("Network quarantine applied successfully: %s/%s [status=quarantined]", namespace, pod_name)
    except subprocess.CalledProcessError as err:
        logger.error("Failed to label pod %s/%s: %s", namespace, pod_name, err.stderr.strip())

def parse_and_evaluate(line: str, dry_run: bool = False):
    line = line.strip()
    if not line:
        return

    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        return

    exec_event = event.get("process_exec")
    kprobe_event = event.get("process_kprobe")

    pod_info = None
    binary = ""
    args = ""

    if exec_event:
        proc = exec_event.get("process", {})
        binary = proc.get("binary", "")
        args = proc.get("arguments", "")
        pod_info = proc.get("pod", {})
    elif kprobe_event:
        proc = kprobe_event.get("process", {})
        binary = proc.get("binary", "")
        pod_info = proc.get("pod", {})

    if not pod_info:
        return

    pod_name = pod_info.get("name")
    namespace = pod_info.get("namespace", "default")

    if not pod_name or namespace in IGNORABLE_NAMESPACES:
        return

    # Check for restricted binary executions
    bin_name = os.path.basename(binary)
    if bin_name in SUSPICIOUS_BINARIES:
        isolate_pod(namespace, pod_name, f"Restricted offensive binary execution: {binary} {args}", dry_run)
        return

    # Check for unauthorized file access attempts
    for sensitive in SENSITIVE_TARGETS:
        if sensitive in line:
            isolate_pod(namespace, pod_name, f"Unauthorized sensitive file access: {sensitive}", dry_run)
            return

def stream_events(dry_run: bool = False):
    logger.info("Starting Tetragon event listener stream...")
    cmd = [
        "kubectl", "logs", "-n", "kube-system",
        "-l", "app.kubernetes.io/name=tetragon",
        "-c", "export-stdout", "-f"
    ]

    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        while running:
            line = proc.stdout.readline()
            if not line:
                if proc.poll() is not None:
                    break
                continue
            parse_and_evaluate(line, dry_run)
    except Exception as exc:
        logger.error("Stream reader exception: %s", exc)
    finally:
        if proc.poll() is None:
            proc.terminate()
        logger.info("Event listener stopped.")

def main():
    parser = argparse.ArgumentParser(description="Kubernetes eBPF Dynamic Quarantine Controller")
    parser.add_argument("--dry-run", action="store_true", help="Log actions without modifying Kubernetes resources")
    parser.add_argument("--test-trigger", nargs=2, metavar=("POD", "NAMESPACE"), help="Simulate trigger against target pod")
    args = parser.parse_args()

    if args.test_trigger:
        pod, ns = args.test_trigger
        isolate_pod(ns, pod, "Manual validation trigger test", dry_run=args.dry_run)
    else:
        stream_events(dry_run=args.dry_run)

if __name__ == "__main__":
    main()
