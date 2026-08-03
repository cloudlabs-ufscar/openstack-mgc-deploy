
# Documenting issues that we ran into during deploy attempts

## 1: eth0 is unreachable
Solution: Check what network interfaces are available on MGC VMs:
```
ssh -o StrictHostKeyChecking=no ubuntu@$(tofu output -json cluster_ips | jq -r '.controller') "ip -br a"
lo               UNKNOWN        127.0.0.1/8 ::1/128 
ens3             UP             172.18.0.132/20 metric 100 2801:80:3ea0:d345::210/128 fe80::f816:3eff:fef3:25bb/64 
```
Available interface is `ens3`. Edit `globals.yml` to point to the correct interface.

## 2: 
[ERROR]: Task failed: Error while evaluating conditional: object of type 'dict' has no attribute 'baremetal'
Solution: Add `[baremetal]` to generated multinode file

## 3:
```
TASK [prechecks : Checking empty passwords in passwords.yml. Run kolla-genpwd if this task fails] ************
[ERROR]: Task failed: Action failed.
Origin: /home/lucas/kolla-venv/share/kolla-ansible/ansible/roles/prechecks/tasks/service_checks.yml:24:3
```
Solution: Run `kolla-genpwd`

## 4:
```
TASK [loadbalancer : Get container facts] **********************************************************************************
[ERROR]: Task failed: Module failed: 'Traceback (most recent call last):\n  File "/tmp/ansible_kolla_container_facts_payload_s3a6ccg5/ansible_kolla_container_facts_payload.zip/ansible/legacy/kolla_container_facts.py", line 224, in __init__\n    import docker\nModuleNotFoundError: No module named \'docker\'\n\nDuring handling of the above exception, another exception occurred:\n\nTraceback (most recent call last):\n  File "/tmp/ansible_kolla_container_facts_payload_s3a6ccg5/ansible_kolla_container_facts_payload.zip/ansible/legacy/kolla_container_facts.py", line 286, in main\n    cfw = DockerFactsWorker(module)\n          ^^^^^^^^^^^^^^^^^^^^^^^^^\n  File "/tmp/ansible_kolla_container_facts_payload_s3a6ccg5/ansible_kolla_container_facts_payload.zip/ansible/legacy/kolla_container_facts.py", line 227, in __init__\n    self.module.fail_json(\n    ^^^^^^^^^^^\nAttributeError: \'DockerFactsWorker\' object has no attribute \'module\'\n'
Origin: /home/lucas/kolla-venv/share/kolla-ansible/ansible/roles/loadbalancer/tasks/precheck.yml:9:3

7     service_name: "{{ project_name }}"
8
9 - name: Get container facts
    ^ column 3

fal: [201.54.21.140]: FAILED! => {"changed": true, "msg": "'Traceback (most recent call last):\\n  File \"/tmp/ansible_kolla_container_facts_payload_s3a6ccg5/ansible_kolla_container_facts_payload.zip/ansible/legacy/kolla_container_facts.py\", line 224, in __init__\\n    import docker\\nModuleNotFoundError: No module named \\'docker\\'\\n\\nDuring handling of the above exception, another exception occurred:\\n\\nTraceback (most recent call last):\\n  File \"/tmp/ansible_kolla_container_facts_payload_s3a6ccg5/ansible_kolla_container_facts_payload.zip/ansible/legacy/kolla_container_facts.py\", line 286, in main\\n    cfw = DockerFactsWorker(module)\\n          ^^^^^^^^^^^^^^^^^^^^^^^^^\\n  File \"/tmp/ansible_kolla_container_facts_payload_s3a6ccg5/ansible_kolla_container_facts_payload.zip/ansible/legacy/kolla_container_facts.py\", line 227, in __init__\\n    self.module.fail_json(\\n    ^^^^^^^^^^^\\nAttributeError: \\'DockerFactsWorker\\' object has no attribute \\'module\\'\\n'"}`
```
Solution: modify deploy script to make sure the Docker Engine and the Docker Python SDK is installed in all the VMs. Updated `deploy.sh` to do so.

## 5:
```
TASK [service-precheck : Validate inventory groups for nova] *************************************************
skipping: [201.54.21.114] => (item=nova-libvirt) 
skipping: [201.54.21.114] => (item=nova-ssh) 
skipping: [201.54.21.167] => (item=nova-libvirt) 
skipping: [201.54.21.167] => (item=nova-ssh) 
[ERROR]: Task failed: Action failed: Ansible inventory does not contain the expected group nova-novncproxy for service nova-novncproxy in nova.
Origin: /home/lucas/kolla-venv/share/kolla-ansible/ansible/roles/service-precheck/tasks/main.yml:2:3

1 ---
2 - name: "Validate inventory groups for {{ project_name }}"
    ^ column 3

failed: [201.54.21.114] (item=nova-novncproxy) => {"ansible_loop_var": "item", "changed": false, "item": {"key": "nova-novncproxy", "value": {"container_name": "nova_novncproxy", "dimensions": {"ulimits": {"nofile": {"hard": 1048576, "soft": 1048576}}}, "enabled": true, "group": "nova-novncproxy", "healthcheck": {"interval": 30, "retries": 3, "start_period": 5, "test": ["CMD-SHELL", "healthcheck_curl http://172.18.1.36:6080/vnc_lite.html"], "timeout": 30}, "image": "quay.io/openstack.kolla/nova-novncproxy:master-rocky-10", "volumes": ["/etc/kolla/nova-novncproxy/:/var/lib/kolla/config_files/:ro", "/etc/localtime:/etc/localtime:ro", "kolla_logs:/var/log/kolla/", "/dev/shm:/dev/shm", ""]}}, "msg": "Ansible inventory does not contain the expected group nova-novncproxy for service nova-novncproxy in nova."}
failed: [201.54.21.167] (item=nova-novncproxy) => {"ansible_loop_var": "item", "changed": false, "item": {"key": "nova-novncproxy", "value": {"container_name": "nova_novncproxy", "dimensions": {"ulimits": {"nofile": {"hard": 1048576, "soft": 1048576}}}, "enabled": true, "group": "nova-novncproxy", "healthcheck": {"interval": 30, "retries": 3, "start_period": 5, "test": ["CMD-SHELL", "healthcheck_curl http://172.18.1.46:6080/vnc_lite.html"], "timeout": 30}, "image": "quay.io/openstack.kolla/nova-novncproxy:master-rocky-10", "volumes": ["/etc/kolla/nova-novncproxy/:/var/lib/kolla/config_files/:ro", "/etc/localtime:/etc/localtime:ro", "kolla_logs:/var/log/kolla/", "/dev/shm:/dev/shm", ""]}}, "msg": "Ansible inventory does not contain the expected group nova-novncproxy for service nova-novncproxy in nova."}
[ERROR]: Task failed: Action failed: Ansible inventory does not contain the expected group nova-spicehtml5proxy for service nova-spicehtml5proxy in nova.
Origin: /home/lucas/kolla-venv/share/kolla-ansible/ansible/roles/service-precheck/tasks/main.yml:2:3

1 ---
2 - name: "Validate inventory groups for {{ project_name }}"
    ^ column 3

failed: [201.54.21.114] (item=nova-spicehtml5proxy) => {"ansible_loop_var": "item", "changed": false, "item": {"key": "nova-spicehtml5proxy", "value": {"container_name": "nova_spicehtml5proxy", "dimensions": {"ulimits": {"nofile": {"hard": 1048576, "soft": 1048576}}}, "enabled": false, "group": "nova-spicehtml5proxy", "healthcheck": {"interval": 30, "retries": 3, "start_period": 5, "test": ["CMD-SHELL", "healthcheck_curl http://172.18.1.36:6082/spice_auto.html"], "timeout": 30}, "image": "quay.io/openstack.kolla/nova-spicehtml5proxy:master-rocky-10", "volumes": ["/etc/kolla/nova-spicehtml5proxy/:/var/lib/kolla/config_files/:ro", "/etc/localtime:/etc/localtime:ro", "kolla_logs:/var/log/kolla/", "/dev/shm:/dev/shm", ""]}}, "msg": "Ansible inventory does not contain the expected group nova-spicehtml5proxy for service nova-spicehtml5proxy in nova."}
failed: [201.54.21.167] (item=nova-spicehtml5proxy) => {"ansible_loop_var": "item", "changed": false, "item": {"key": "nova-spicehtml5proxy", "value": {"container_name": "nova_spicehtml5proxy", "dimensions": {"ulimits": {"nofile": {"hard": 1048576, "soft": 1048576}}}, "enabled": false, "group": "nova-spicehtml5proxy", "healthcheck": {"interval": 30, "retries": 3, "start_period": 5, "test": ["CMD-SHELL", "healthcheck_curl http://172.18.1.46:6082/spice_auto.html"], "timeout": 30}, "image": "quay.io/openstack.kolla/nova-spicehtml5proxy:master-rocky-10", "volumes": ["/etc/kolla/nova-spicehtml5proxy/:/var/lib/kolla/config_files/:ro", "/etc/localtime:/etc/localtime:ro", "kolla_logs:/var/log/kolla/", "/dev/shm:/dev/shm", ""]}}, "msg": "Ansible inventory does not contain the expected group nova-spicehtml5proxy for service nova-spicehtml5proxy in nova."}
[ERROR]: Task failed: Action failed: Ansible inventory does not contain the expected group nova-serialproxy for service nova-serialproxy in nova.
Origin: /home/lucas/kolla-venv/share/kolla-ansible/ansible/roles/service-precheck/tasks/main.yml:2:3

1 ---
2 - name: "Validate inventory groups for {{ project_name }}"
    ^ column 3

failed: [201.54.21.114] (item=nova-serialproxy) => {"ansible_loop_var": "item", "changed": false, "item": {"key": "nova-serialproxy", "value": {"container_name": "nova_serialproxy", "dimensions": {"ulimits": {"nofile": {"hard": 1048576, "soft": 1048576}}}, "enabled": false, "group": "nova-serialproxy", "image": "quay.io/openstack.kolla/nova-serialproxy:master-rocky-10", "volumes": ["/etc/kolla/nova-serialproxy/:/var/lib/kolla/config_files/:ro", "/etc/localtime:/etc/localtime:ro", "kolla_logs:/var/log/kolla/", "/dev/shm:/dev/shm", ""]}}, "msg": "Ansible inventory does not contain the expected group nova-serialproxy for service nova-serialproxy in nova."}
failed: [201.54.21.167] (item=nova-serialproxy) => {"ansible_loop_var": "item", "changed": false, "item": {"key": "nova-serialproxy", "value": {"container_name": "nova_serialproxy", "dimensions": {"ulimits": {"nofile": {"hard": 1048576, "soft": 1048576}}}, "enabled": false, "group": "nova-serialproxy", "image": "quay.io/openstack.kolla/nova-serialproxy:master-rocky-10", "volumes": ["/etc/kolla/nova-serialproxy/:/var/lib/kolla/config_files/:ro", "/etc/localtime:/etc/localtime:ro", "kolla_logs:/var/log/kolla/", "/dev/shm:/dev/shm", ""]}}, "msg": "Ansible inventory does not contain the expected group nova-serialproxy for service nova-serialproxy in nova."}
[ERROR]: Task failed: Action failed: Ansible inventory does not contain the expected group nova-conductor for service nova-conductor in nova.
Origin: /home/lucas/kolla-venv/share/kolla-ansible/ansible/roles/service-precheck/tasks/main.yml:2:3

1 ---
2 - name: "Validate inventory groups for {{ project_name }}"
    ^ column 3

failed: [201.54.21.114] (item=nova-conductor) => {"ansible_loop_var": "item", "changed": false, "item": {"key": "nova-conductor", "value": {"container_name": "nova_conductor", "dimensions": {"ulimits": {"nofile": {"hard": 1048576, "soft": 1048576}}}, "enabled": true, "group": "nova-conductor", "healthcheck": {"interval": 30, "retries": 3, "start_period": 5, "test": ["CMD-SHELL", "healthcheck_port nova-conductor 5672"], "timeout": 30}, "image": "quay.io/openstack.kolla/nova-conductor:master-rocky-10", "volumes": ["/etc/kolla/nova-conductor/:/var/lib/kolla/config_files/:ro", "/etc/localtime:/etc/localtime:ro", "kolla_logs:/var/log/kolla/", "/dev/shm:/dev/shm", ""]}}, "msg": "Ansible inventory does not contain the expected group nova-conductor for service nova-conductor in nova."}
failed: [201.54.21.167] (item=nova-conductor) => {"ansible_loop_var": "item", "changed": false, "item": {"key": "nova-conductor", "value": {"container_name": "nova_conductor", "dimensions": {"ulimits": {"nofile": {"hard": 1048576, "soft": 1048576}}}, "enabled": true, "group": "nova-conductor", "healthcheck": {"interval": 30, "retries": 3, "start_period": 5, "test": ["CMD-SHELL", "healthcheck_port nova-conductor 5672"], "timeout": 30}, "image": "quay.io/openstack.kolla/nova-conductor:master-rocky-10", "volumes": ["/etc/kolla/nova-conductor/:/var/lib/kolla/config_files/:ro", "/etc/localtime:/etc/localtime:ro", "kolla_logs:/var/log/kolla/", "/dev/shm:/dev/shm", ""]}}, "msg": "Ansible inventory does not contain the expected group nova-conductor for service nova-conductor in nova."}
skipping: [201.54.21.114] => (item=nova-compute) 
skipping: [201.54.21.167] => (item=nova-compute) 
[ERROR]: Task failed: Action failed: Ansible inventory does not contain the expected group nova-compute-ironic for service nova-compute-ironic in nova.
Origin: /home/lucas/kolla-venv/share/kolla-ansible/ansible/roles/service-precheck/tasks/main.yml:2:3

1 ---
2 - name: "Validate inventory groups for {{ project_name }}"
    ^ column 3

failed: [201.54.21.114] (item=nova-compute-ironic) => {"ansible_loop_var": "item", "changed": false, "item": {"key": "nova-compute-ironic", "value": {"container_name": "nova_compute_ironic", "dimensions": {"ulimits": {"nofile": {"hard": 1048576, "soft": 1048576}}}, "enabled": false, "group": "nova-compute-ironic", "healthcheck": {"interval": 30, "retries": 3, "start_period": 5, "test": ["CMD-SHELL", "healthcheck_port nova-compute 5672"], "timeout": 30}, "image": "quay.io/openstack.kolla/nova-compute-ironic:master-rocky-10", "volumes": ["/etc/kolla/nova-compute-ironic/:/var/lib/kolla/config_files/:ro", "/etc/localtime:/etc/localtime:ro", "kolla_logs:/var/log/kolla/", "/dev/shm:/dev/shm", ""]}}, "msg": "Ansible inventory does not contain the expected group nova-compute-ironic for service nova-compute-ironic in nova."}
failed: [201.54.21.167] (item=nova-compute-ironic) => {"ansible_loop_var": "item", "changed": false, "item": {"key": "nova-compute-ironic", "value": {"container_name": "nova_compute_ironic", "dimensions": {"ulimits": {"nofile": {"hard": 1048576, "soft": 1048576}}}, "enabled": false, "group": "nova-compute-ironic", "healthcheck": {"interval": 30, "retries": 3, "start_period": 5, "test": ["CMD-SHELL", "healthcheck_port nova-compute 5672"], "timeout": 30}, "image": "quay.io/openstack.kolla/nova-compute-ironic:master-rocky-10", "volumes": ["/etc/kolla/nova-compute-ironic/:/var/lib/kolla/config_files/:ro", "/etc/localtime:/etc/localtime:ro", "kolla_logs:/var/log/kolla/", "/dev/shm:/dev/shm", ""]}}, "msg": "Ansible inventory does not contain the expected group nova-compute-ironic for service nova-compute-ironic in nova."}

PLAY RECAP ***************************************************************************************************
201.54.21.114              : ok=21   changed=0    unreachable=0    failed=1    skipped=12   rescued=0    ignored=0   
201.54.21.140              : ok=49   changed=0    unreachable=0    failed=0    skipped=88   rescued=0    ignored=0   
201.54.21.167              : ok=21   changed=0    unreachable=0    failed=1    skipped=12   rescued=0    ignored=0   

Kolla Ansible playbook(s) /home/lucas/kolla-venv/share/kolla-ansible/ansible/site.yml exited 2
```
Solution: append data from original kolla-ansible inventory `multinode` file, added to `deploy.sh`

## 6:
Stuck on
`TASK [openvswitch : Ensuring OVS ports are properly setup]`
In the end, it seems we couldn't make it work out with only one NIC per VM. OpenStack usually asks for your deployment environment to have two NICs, one for external and another for internal communications. During our initial research, it seemed as if it would work regardless with only one NIC, but we were running into a lot of issues during deployment, so we decided to try and deploy the VMs with two NICs.
We added mgc_network_vpcs_interfaces to the terraform file, to make sure the VMs have two network interfaces, and also added a cloud-init bash script to the VMs so this second interface is UP. Now we can edit globals.yml and test if everything works as intended.

## 7:
Stuck on 
`TASK [openstack.kolla.docker : Update the apt cache]`
After adding new NIC to VMs.
Magalu Cloud VMs are assigned both an IPv4 and IPv6 address automatically. When the Kolla Ansible bootstrap-servers command hits the apt update task, Ubuntu's package manager natively attempts to communicate with archive.ubuntu.com via IPv6 first.
The IPv6 routes (or peering to the specific Canonical IPs) frequently time out in this region, which forces apt to wait multiple minutes falling back slowly to other addresses. Because the connection is silent for several minutes while trying to resolve these slow mirrors, the intermediate NAT firewall drops the idle TCP SSH session. The local Ansible SSH multiplexing socket ([mux]) completely hangs because it never receives the final dropped exit status packet, locking your deploy terminal indefinitely.
Changed `deploy.sh` to force APT to utilize IPv4 and switch the Ubuntu repositories to the Brazilian mirrors.

## 8:
The deploy failed due to a RabbitMQ connection timeout which prevented Nova service registration, and a MariaDB verification timeout directly from Kolla, despite the MariaDB GALERA cluster actually being in a healthy and Synced state (wsrep_cluster_status Primary, wsrep_local_state_comment Synced) on the controller (`172.18.1.33`).
Kolla-Ansible natively uses HAProxy and Keepalived to establish a high-availability Virtual IP (VIP), which defaults to an unassigned IP in your subnet (`172.18.15.250` in this case).
Because Magalu Cloud (like most cloud providers) runs a strict Software-Defined Network underneath, it will drop/block any ARP packets or IP traffic referencing an IP address that isn't formally assigned to your VM's network interface by the cloud platform itself. Because of this boundary, your compute nodes hit a No route to host block whenever they attempted to reach OpenStack core services at `172.18.15.250`.
Since we are running a single-node controller setup, there's no need for these High-Availability failovers (Keepalived and HAProxy), so we can just turn them off on `globals.yml`. Automated in `deploy.sh`

## 9:
RUNNING HANDLER [mariadb : Wait for first MariaDB service port liveness] 
```
[ERROR]: Task failed: Module failed: Timeout when waiting for search string MariaDB in 172.18.3.206:3306
Origin: /home/lucas/kolla-venv/share/kolla-ansible/ansible/roles/mariadb/handlers/main.yml:23:3

21
22 # NOTE(yoctozepto): We have to loop this to avoid breaking on connection resets
23 - name: Wait for first MariaDB service port liveness
     ^ column 3

fatal: [201.54.23.251]: FAILED! => {
    "attempts": 10,
    "changed": false,
    "elapsed": 61,
    "invocation": {
        "module_args": {
            "active_connection_states": [
                "ESTABLISHED",
                "FIN_WAIT1",
                "FIN_WAIT2",
                "SYN_RECV",
                "SYN_SENT",
                "TIME_WAIT"
            ],
            "connect_timeout": 1,
            "delay": 0,
            "exclude_hosts": null,
            "host": "172.18.3.206",
            "msg": null,
            "path": null,
            "port": 3306,
            "search_regex": "MariaDB",
            "sleep": 1,
            "state": "started",
            "timeout": 60
        }
    },
    "msg": "Timeout when waiting for search string MariaDB in 172.18.3.206:3306"
}

PLAY RECAP ****************************************************************************************************************
201.54.20.210              : ok=34   changed=23   unreachable=0    failed=0    skipped=7    rescued=0    ignored=0   
201.54.23.248              : ok=34   changed=23   unreachable=0    failed=0    skipped=7    rescued=0    ignored=0   
201.54.23.251              : ok=82   changed=47   unreachable=0    failed=1    skipped=96   rescued=0    ignored=1   

Kolla Ansible playbook(s) /home/lucas/kolla-venv/share/kolla-ansible/ansible/site.yml exited 2
clean_up Deploy
```

When we set kolla_internal_vip_address equal to the node's local IP (which we did to bypass the cloud routing issue), we caused an internal port collision between two Kolla database components:

ProxySQL: A load balancer that defaults to being deployed (enable_proxysql: true natively). It bound to the "VIP" address on port 3306.
MariaDB: The actual database, which tries to bind to the "local" node address on port 3306.
Since the VIP and the local node IP are now completely identical in our setup (172.18.3.206), ProxySQL grabbed port 3306 a fraction of a second earlier. When MariaDB attempted to start right behind it, it hit an Address already in use error and crashed, causing Ansible to wait forever for MariaDB to report readiness.

Again, we only have a single controller and disabled HAProxy, so ProxySQL is also completely unnecessary.

## 10: OVS fail_mode: secure breaks overlay network connectivity on MGC VPC

**Symptom:** After deploying OpenStack, floating IPs cannot be reached from the controller node. Tenant VMs are reachable from within the Neutron router namespace but not from the host. ARP requests from namespaces reach the external bridge but no responses return.

**Root cause:** Neutron's OVS agent creates all bridges (`br-ex`, `br-int`, `br-tun`) with `fail_mode: secure`. In secure mode, OVS enforces strict OpenFlow rules. On MGC's VPC, the secondary interfaces (ens8) carry provider network traffic, but the OVS flow rules in secure mode drop untagged return traffic from `br-int` to `br-ex` on flat networks. The `priority=2,in_port=2 actions=drop` rule on br-ex silently discards return packets from br-int (port 2 = patch port), since the `priority=4` rule only matches VLAN 1 tagged traffic (which flat networks don't use).

The issue also affects `br-int` and `br-tun` on all nodes, potentially disrupting VXLAN tunnel traffic and inter-node communication.

**Fix:** Change the fail_mode on all OVS bridges from `secure` to `standalone`:

```bash
for bridge in br-ex br-int br-tun; do
    sudo docker exec openvswitch_vswitchd ovs-vsctl set-fail-mode $bridge standalone
done
```

This is now applied automatically by `deploy.sh` on all cluster nodes after the kolla-ansible deploy step.

**Note:** This setting persists in the OVS database across reboots but may be reset if Neutron's OVS agent recreates a bridge. If connectivity breaks after agent restart, re-apply.

## 11: MariaDB bind-address causes bootstrap check failure

**Symptom:** `kolla-ansible deploy` fails at the MariaDB service check with "Can't connect to MySQL server on 'localhost' (Connection refused)".

**Root cause:** The `kolla_internal_vip_address` variable in `/etc/kolla/globals.yml` is on the same line as a commented-out config due to a missing trailing newline, causing it to be unparseable. The check uses `database_address` (which defaults to `kolla_internal_vip_address`) → empty string → defaults to localhost. MariaDB is configured to bind only to the API interface IP, not localhost.

**Fix:** Ensure `/etc/kolla/globals.yml` ends with a newline before appending config. The `deploy.sh` now ensures this with `echo "" >> /etc/kolla/globals.yml` before appending the VIP/haproxy configuration.

## 13: MGC-specific apt mirror URLs are unresolvable

**Symptom:** `kolla-ansible bootstrap-servers` fails with apt cache update errors. Hosts like `br-ne-1c.clouds.br.archive.ubuntu.com` cannot be resolved.

**Root cause:** MGC's Ubuntu cloud images generate AZ-specific mirror URLs (e.g., `br-ne-1c.clouds.br.archive.ubuntu.com`) in `/etc/apt/sources.list.d/ubuntu.sources` that don't actually resolve in all MGC regions.

**Fix:** Replace the broken MGC-specific URLs with working mirrors. The `deploy.sh` now applies:
```bash
sed -i 's|http://br-ne-1[a-z]\.clouds\.br\.archive\.ubuntu\.com/ubuntu/|http://archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources
```

## 14. VM OOM with small flavors

**Symptom:** Tenant VMs with 2GB RAM become unresponsive during package installations. SSH connections are killed.

**Root cause:** Ubuntu 24.04 cloud images require significant memory for cloud-init, apt updates, and package installation. A 2GB VM runs out of memory and the OOM killer terminates sshd or other processes.

**Fix:** Use at least 4GB RAM for tenant VMs that will run services:
```bash
openstack flavor create --ram 4096 --disk 20 --vcpus 2 web.flavor
```