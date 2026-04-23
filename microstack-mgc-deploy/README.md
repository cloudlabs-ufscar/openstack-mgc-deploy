# MicroStack MGC deploy

Terraform code for MicroStack deployment in Magalu Cloud (MGC). MicroStack allows for a quick and easy single-node OpenStack deployment, great for test environments and experiments. Here, we deploy MicroStack on top of a MGC VM using Terraform, so that the VM can be quickly created and destroyed when needed.

1. Export your MGC API key:
   `export MGC_API_KEY="<your-api-key>"`
2. Create `terraform.tfvars` with your SSH key name:
   `ssh_key_name = "<your-mgc-ssh-key-name>"`
3. (Optional) Set custom values for `region`, `vm_name` or `microstack_keypair_name` in `terraform.tfvars`.
4. Run `tofu init`
5. Run `./run.sh`
6. After MicroStack is done installing, use `get-credentials.sh` to get the default keystone password

To access the web interface, use the VM's public ip on your web browser, it should work by default. If not, tunnel into your VM using `ssh -L 8080:localhost:80 ubuntu@<VM_PUBLIC_IP>` and then access it via http://localhost:8080.
To interact with the cluster directly, SSH into your VM and use the `microstack.openstack` prefix to run OpenStack CLI commands.


Launching an instance:
```
    microstack.openstack server create \
    --image cirros \
    --flavor m1.tiny \
    --key-name my-local-key \
    --security-group lab-secgroup \
    --net test \
    my-first-vm
```

Getting allocated IP address:
`microstack.openstack server list`

Since the MGC VM has a public IP, and the OpenStack instances are sitting on an internal virtual network managed by Neutron, the VM acts as a Jump Host or Bastion server.
We can use SSH's ProxyJump feature to route our connection through the VM, going straight from our host computer straight to the OpenStack instance.
Say we have an instance with a floating IP `10.20.20.15`, using the default CirrOS image, we can SSH into it via:
`ssh -J ubuntu@<VM_PUBLIC_IP> cirros@10.20.20.15`
