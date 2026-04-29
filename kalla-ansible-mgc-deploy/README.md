# openstack-mgc-deploy
Automation scripts for deploying OpenStack in Magalu Cloud
Single-node deployment in the `microstack-mgc-deploy` folder

For multi-node deployment:
```
# Install Python dependencies
sudo apt update
sudo apt install python3-venv python3-dev libffi-dev gcc libssl-dev

# Create and activate a virtual environment
python3 -m venv ~/kolla-venv
source ~/kolla-venv/bin/activate

# Install Ansible and Kolla-Ansible
pip install -U pip
pip install ansible
pip install git+https://opendev.org/openstack/kolla-ansible@master
kolla-ansible install-deps

# Create Kolla-Ansible configuration
sudo mkdir -p /etc/kolla
sudo chown $USER:$USER /etc/kolla
cp -r ~/kolla-venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
```

Create and populate your .env file, then:

```
tofu init
source .env
tofu plan
tofu apply
```

This creates the VMs and the `multinode` Ansible file

To find out the network interfaces available in the VMs:
```
sh -o StrictHostKeyChecking=no ubuntu@$(tofu output -json cluster_ips | jq -r '.controller') "ip -br a"
```
For MGC, we have `ens3` available. Access `/etc/kolla/globals.yml` and edit the `network_interface` and `neutron_external_interface` property to `ens3`

Finally, you can run:

```
kolla-genpwd
kolla-ansible bootstrap-servers -i ./multinode 
kolla-ansible prechecks -i ./multinode 
kolla-ansible pull -i ./multinode 
kolla-ansible deploy -i ./multinode 
```

To get the credentials:
```
kolla-ansible post-deploy
cat /etc/kolla/admin-openrc.sh
```

# Documenting Hardships on Kolla-Ansible deployment
First error: eth0 is unreachable
Solution: Check what network interfaces are available on MGC VMs:
```
ssh -o StrictHostKeyChecking=no ubuntu@$(tofu output -json cluster_ips | jq -r '.controller') "ip -br a"
lo               UNKNOWN        127.0.0.1/8 ::1/128 
ens3             UP             172.18.0.132/20 metric 100 2801:80:3ea0:d345::210/128 fe80::f816:3eff:fef3:25bb/64 
```
Available interface is `ens3`. Edit `globals.yml` to point to the correct interface.

Second error: 
[ERROR]: Task failed: Error while evaluating conditional: object of type 'dict' has no attribute 'baremetal'
Solution: Add `[baremetal]` to generated multinode file

Third error:
```
TASK [prechecks : Checking empty passwords in passwords.yml. Run kolla-genpwd if this task fails] ************
[ERROR]: Task failed: Action failed.
Origin: /home/lucas/kolla-venv/share/kolla-ansible/ansible/roles/prechecks/tasks/service_checks.yml:24:3
```
Solution: Run `kolla-genpwd`

Fourth error:
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

Fifth error:
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



