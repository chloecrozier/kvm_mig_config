# KVM vGPU Configuration Guide

**Date:** August 2025  
**Target OS:** Ubuntu 24.04 LTS

## Overview

This guide covers the complete setup of KVM hypervisor with vGPU support using NVIDIA drivers, including host configuration, guest VM creation, and vGPU device management.

## Prerequisites

### Hardware Requirements
- NVIDIA RTX 6000/8000 or RTX A6000 GPU
- CPU with virtualization support (Intel VT-x or AMD SVM)
- Sufficient RAM for host and guest VMs
- Ubuntu 24.04 LTS installed

### BIOS Configuration
Access BIOS and configure the following settings:

| Setting | Location | Value |
|---------|----------|-------|
| SVM Mode | M.I.T → Adv. Freq. → Adv. CPU Core | **Enabled** |
| Fast Boot | BIOS → Fast Boot | **Enabled** |
| 4G Decoding | Peripherals → Above 4G Encoding | **Enabled** |
| IOMMU Mode | Chipset → IOMMU | **Enabled** |
| CSM Support | BIOS → CSM Support | **Disabled** |

### Network Configuration
Set up static IP addressing:
- **IP Address:** 10.110.20.180
- **Netmask:** 255.255.255.0  
- **Gateway:** 10.110.20.1
- **DNS:** 10.10.10.53, 10.10.10.54

Optional: Disable Bluetooth and WiFi if using Ethernet only.

## Initial System Setup

### Basic System Configuration

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install essential tools
sudo apt install -y net-tools openssh-server cpu-checker

# Enable SSH service
sudo systemctl enable --now ssh

# Disable firewall (optional, for lab environments)
sudo systemctl disable ufw
```

### SSH Key Setup (Optional)
From your client machine:
```bash
ssh-copy-id -i ~/.ssh/your_public_key.pub nvadmin@10.110.20.180
```

## Hardware Verification

### Check CPU Virtualization Support
```bash
# Verify CPU supports virtualization (result should be > 0)
egrep -c '(vmx|svm)' /proc/cpuinfo

# Check KVM readiness
kvm-ok
```

### Verify GPU Detection
```bash
# Confirm NVIDIA GPU is detected
lspci | grep -i nvidia

# Check OS version
hostnamectl
```

## KVM Installation

### Install KVM Components
```bash
# Install KVM and related packages
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager

# Add user to required groups
sudo adduser $USER kvm
sudo adduser $USER libvirt

# Start and enable libvirt service
sudo systemctl enable --now libvirtd
systemctl status libvirtd

# Configure default network
sudo virsh net-autostart default
virsh net-list --all
```

### Verify KVM Installation
```bash
# List VMs (should be empty initially)
virsh list --all

# Check KVM modules
lsmod | grep kvm
```

## Cockpit Web Interface

### Install Cockpit
```bash
# Install Cockpit and VM management plugin
sudo apt install -y cockpit cockpit-machines

# Enable Cockpit service
sudo systemctl enable --now cockpit.socket
systemctl status cockpit
```

**Access:** Navigate to `https://{host_ip}:9090` and login with your system credentials.

## GPU Driver Installation

### Disable Nouveau Driver
```bash
# Check if nouveau is loaded
lsmod | grep nouveau

# Blacklist nouveau driver
echo -e "blacklist nouveau\noptions nouveau modeset=0" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf

# Update initramfs and reboot
sudo update-initramfs -u
sudo reboot
```

### Install NVIDIA vGPU Host Driver
```bash
# Install build dependencies
sudo apt install -y dkms gcc make

# Install the vGPU host driver package
# Note: Replace with your actual driver package
sudo dpkg -i nvidia-vgpu-ubuntu-580_580.65.05_amd64.deb

sudo reboot
```

### Verify Driver Installation
```bash
# Check VFIO modules
lsmod | grep vfio

# Verify NVIDIA driver
nvidia-smi
```

## vGPU Configuration

### Enable SR-IOV Virtual Functions
```bash
# List PCI devices
virsh nodedev-list --cap pci | grep nvidia

# Enable VFs on your GPU (replace with your GPU's BDF)
# Example for RTX A6000: 0000:0a:00.0
sudo /usr/lib/nvidia/sriov-manage -e 0000:0a:00.0

# Verify VFs are created
lspci | grep -i nvidia
```

### Create vGPU Mediated Devices

#### List Available vGPU Profiles
```bash
# Check supported vGPU types (replace with your GPU's BDF)
ls /sys/bus/pci/devices/0000:0a:00.4/mdev_supported_types

# View profile details
cat /sys/bus/pci/devices/0000:0a:00.4/mdev_supported_types/*/name
cat /sys/bus/pci/devices/0000:0a:00.4/mdev_supported_types/*/description
```

#### Create vGPU Instance
```bash
# Navigate to desired profile directory (example: nvidia-531 for RTX A6000-16Q)
cd /sys/class/mdev_bus/0000:0a:00.4/mdev_supported_types/nvidia-531

# Generate UUID for the vGPU instance
UUID=$(uuidgen)
echo "Generated UUID: $UUID"

# Create the vGPU device
echo "$UUID" | sudo tee ./create

# Verify creation
ls /sys/bus/mdev/devices/
```

## Guest VM Configuration

### VM Creation
Use Cockpit web interface:
1. Navigate to **Virtual Machines** section
2. Create new VM with desired OS (Rocky Linux, Ubuntu, etc.)
3. Allocate appropriate resources (CPU, RAM, storage)

### Transfer Guest OS ISO
```bash
# Example: Transfer Rocky Linux ISO to host
scp /path/to/Rocky-10.0-x86_64-dvd1.iso nvadmin@10.110.20.180:/home/nvadmin/
```

### Assign vGPU to VM
1. Edit VM configuration in Cockpit or via `virsh edit <vm_name>`
2. Add hostdev section for the mdev device:
```xml
<hostdev mode='subsystem' type='mdev' managed='no' model='vfio-pci'>
  <source>
    <address uuid='your-uuid-here'/>
  </source>
</hostdev>
```

## Guest VM Driver Installation

### For Rocky Linux/RHEL-based Systems
```bash
# Update system
sudo dnf update -y

# Install build dependencies
sudo dnf install -y dkms gcc kernel-devel kernel-headers pkgconfig

# Verify kernel version matches headers
uname -r
sudo dnf install -y kernel-devel-$(uname -r) kernel-headers-$(uname -r)

# Reboot to ensure kernel/headers match
sudo reboot

# Install NVIDIA guest driver (transfer from host first)
chmod +x NVIDIA-Linux-x86_64-580.65.06-grid.run
sudo ./NVIDIA-Linux-x86_64-580.65.06-grid.run

# Verify installation
nvidia-smi
```

### For Ubuntu-based Systems
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install build dependencies
sudo apt install -y dkms gcc make linux-headers-$(uname -r)

# Install NVIDIA guest driver
chmod +x NVIDIA-Linux-x86_64-580.65.06-grid.run
sudo ./NVIDIA-Linux-x86_64-580.65.06-grid.run

# Verify installation
nvidia-smi
```

## Verification and Testing

### Host Verification
```bash
# Check vGPU devices
ls -l /sys/bus/mdev/devices/

# List VM status
virsh list --all
virsh domstate <vm_name>
virsh domstats <vm_name>
```

### Guest Verification
```bash
# Verify GPU detection in guest
lspci | grep -i nvidia

# Check vGPU resources
nvidia-smi
```

## Common vGPU Profiles

### RTX A6000 Profiles
| Profile | Name | Memory | Max Resolution | Max Instances |
|---------|------|---------|----------------|---------------|
| nvidia-531 | RTX A6000-16Q | 16GB | 7680x4320 | 3 |
| nvidia-530 | RTX A6000-8Q | 8GB | 7680x4320 | 6 |
| nvidia-529 | RTX A6000-4Q | 4GB | 5120x2880 | 12 |

### RTX 8000 Profiles
| Profile | Memory | Description |
|---------|---------|-------------|
| RTX8000-1Q | 1GB | Basic compute |
| RTX8000-2Q | 2GB | Light workloads |
| RTX8000-4Q | 4GB | Medium workloads |
| RTX8000-8Q | 8GB | Heavy workloads |

## Troubleshooting

### Common Issues
1. **KVM not ready:** Ensure SVM/VT-x is enabled in BIOS
2. **GPU not detected:** Verify PCIe slot and power connections
3. **Driver conflicts:** Ensure nouveau is properly blacklisted
4. **VF creation fails:** Check IOMMU configuration and GPU support

### Useful Commands
```bash
# Check IOMMU groups
find /sys/kernel/iommu_groups/ -type l

# View GRUB configuration for IOMMU
grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub

# Monitor system logs
journalctl -f
```

## Additional Resources

- [NVIDIA vGPU Deployment Guide](https://docs.nvidia.com/vgpu/deployment/ubuntu-with-kvm/latest/install.html)
- [NVIDIA vGPU Product Support Matrix](https://docs.nvidia.com/vgpu/latest/product-support-matrix/)
- [Ubuntu KVM Installation Guide](https://help.ubuntu.com/community/KVM/Installation)
- [Cockpit Project Documentation](https://cockpit-project.org/documentation.html)

---

**Note:** This guide assumes lab/development environment. For production deployments, implement appropriate security measures including firewall configuration, access controls, and monitoring.