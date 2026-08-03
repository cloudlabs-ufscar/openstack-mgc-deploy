#!/usr/bin/env python3
import sys, json

d = json.load(sys.stdin)
c = d['controller']
t = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

print(f"[control]")
print(f"{c} ansible_user=ubuntu ansible_ssh_common_args='{t}'")
print(f"\n[network]")
print(f"{c} ansible_user=ubuntu ansible_ssh_common_args='{t}'")
print(f"\n[loadbalancer]")
print(f"{c} ansible_user=ubuntu ansible_ssh_common_args='{t}'")
print(f"\n[compute]")
print(f"{d['compute-01']} ansible_user=ubuntu ansible_ssh_common_args='{t}'")
print(f"{d['compute-02']} ansible_user=ubuntu ansible_ssh_common_args='{t}'")
print(f"\n[monitoring]")
print(f"{c} ansible_user=ubuntu ansible_ssh_common_args='{t}'")
print(f"\n[storage]")
print(f"{c} ansible_user=ubuntu ansible_ssh_common_args='{t}'")
print(f"\n[baremetal]")
