# OpenStack Deployment on Magalu Cloud (MGC)

This repository contains automation scripts and Infrastructure as Code (IaC) to deploy OpenStack environments on Magalu Cloud using OpenTofu (Terraform) and Ansible.

## Projects Overview

The repository is divided into two main deployment strategies:

### 1. Single-Node Deployment (MicroStack)
* **Directory:** `microstack-mgc-deploy/`
* **Description:** A quick and lightweight single-node OpenStack installation using MicroStack. Ideal for rapid testing, learning, or small-scale experiments.
* **Main Tools:** OpenTofu, Snap (MicroStack), Cloud-init.

### 2. Multi-Node Deployment (Kolla-Ansible)
* **Directory:** `kalla-ansible-mgc-deploy/`
* **Description:** A production-oriented, multi-node cluster deployment (Controller and Compute nodes) managed by Kolla-Ansible. Includes automated inventory generation and environment bootstrapping.
* **Main Tools:** OpenTofu, Ansible, Kolla-Ansible, Docker.

## How to Get Started

Each project contains its own specific instructions and requirements. To begin, navigate to the directory of the deployment type you wish to use and read the local `README.md` file:

* For **Single-Node, MicroStack installation**, see: [`microstack-mgc-deploy/README.md`](./microstack-mgc-deploy/README.md)
* For **Multi-Node, Kolla-Ansible installation**, see: [`kalla-ansible-mgc-deploy/README.md`](./kalla-ansible-mgc-deploy/README.md)

## Prerequisites

* A [Magalu Cloud](https://magalu.cloud/) account and API Key.
* [OpenTofu](https://opentofu.org/) or Terraform installed locally.
* SSH Key pair registered in your MGC dashboard.