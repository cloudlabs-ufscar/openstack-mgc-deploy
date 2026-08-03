#!/usr/bin/env python3
import sys, json

d = json.load(sys.stdin)
c = d['controller']
t = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

lines = [
    f"[control]",
    f"{c} ansible_user=ubuntu ansible_ssh_common_args='{t}'",
    f"\n[network]",
    f"{c} ansible_user=ubuntu ansible_ssh_common_args='{t}'",
    f"\n[loadbalancer]",
    f"{c} ansible_user=ubuntu ansible_ssh_common_args='{t}'",
    f"\n[compute]",
]
for k in sorted(d.keys()):
    if k.startswith("compute"):
        lines.append(f"{d[k]} ansible_user=ubuntu ansible_ssh_common_args='{t}'")
lines += [
    f"\n[monitoring]",
    f"{c} ansible_user=ubuntu ansible_ssh_common_args='{t}'",
    f"\n[storage]",
    f"{c} ansible_user=ubuntu ansible_ssh_common_args='{t}'",
    f"\n[baremetal]",
]
print("\n".join(lines))
