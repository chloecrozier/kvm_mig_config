# KVM vGPU Setup Guide

Complete setup for KVM with NVIDIA vGPU support on Ubuntu 24.04.

## Prerequisites

### Hardware
- NVIDIA RTX 6000/8000/A6000 GPU
- CPU with Intel VT-x or AMD SVM
- 32GB+ RAM recommended
- Ubuntu 24.04 LTS

### BIOS Settings
Enable these in BIOS:
- **Virtualization** (VT-x/SVM)
- **IOMMU**
- **4G Decoding**
- **Fast Boot**
- Disable **CSM Support**

## Quick Setup

### System Preparation
```bash
# Update and install basics
sudo apt update && sudo apt upgrade -y
sudo apt install -y net-tools openssh-server cpu-checker

# Verify prerequisites
egrep -c '(vmx|svm)' /proc/cpuinfo  # Should be > 0
lspci | grep -i nvidia              # Should show GPU
kvm-ok                              # Should pass
```

### KVM Installation
```bash
# Install KVM
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager

# Add user to groups
sudo adduser $USER kvm libvirt

# Start services
sudo systemctl enable --now libvirtd
sudo virsh net-autostart default
```

### Web Interface (Optional)
```bash
# Install Cockpit for web management
sudo apt install -y cockpit cockpit-machines
sudo systemctl enable --now cockpit.socket

# Access at: https://HOST_IP:9090
```

## GPU Setup

### Prepare System
```bash
# Blacklist nouveau
echo -e "blacklist nouveau\noptions nouveau modeset=0" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
sudo update-initramfs -u

# Add IOMMU to GRUB
sudo nano /etc/default/grub
# Add: intel_iommu=on (or amd_iommu=on)
sudo update-grub

sudo reboot
```

### Install vGPU Driver
```bash
# Install dependencies
sudo apt install -y dkms gcc make

# Install vGPU host driver (download from NVIDIA)
sudo dpkg -i nvidia-vgpu-ubuntu-*.deb
sudo reboot

# Verify
nvidia-smi
```

### Enable Virtual Functions
```bash
# Find GPU address
lspci | grep -i nvidia

# Enable VFs (replace with your GPU address)
sudo /usr/lib/nvidia/sriov-manage -e 0000:0a:00.0

# Verify
lspci | grep -i nvidia
```

### Create vGPU Instances
```bash
# List available profiles
ls /sys/bus/pci/devices/0000:0a:00.4/mdev_supported_types
cat /sys/bus/pci/devices/0000:0a:00.4/mdev_supported_types/*/name

# Create vGPU (example for nvidia-531 profile)
UUID=$(uuidgen)
echo "$UUID" | sudo tee /sys/class/mdev_bus/0000:0a:00.4/mdev_supported_types/nvidia-531/create

# Verify
ls /sys/bus/mdev/devices/
```

## VM Setup

### Create VM
```bash
# Use Cockpit web interface at https://HOST_IP:9090
# Or use command line:
virt-install --name myvm --ram 16384 --vcpus 4 \
  --disk size=50 --cdrom /path/to/os.iso \
  --network bridge=virbr0
```

### Assign vGPU to VM
Edit VM config and add:
```xml
<hostdev mode='subsystem' type='mdev' managed='no' model='vfio-pci'>
  <source>
    <address uuid='your-vgpu-uuid'/>
  </source>
</hostdev>
```

### Install Guest Driver
In the VM:
```bash
# Ubuntu/Debian
sudo apt install -y dkms gcc make linux-headers-$(uname -r)

# RHEL/Rocky
sudo dnf install -y dkms gcc kernel-devel kernel-headers

# Install NVIDIA guest driver
sudo ./NVIDIA-Linux-x86_64-*-grid.run

# Verify
nvidia-smi
```

## vGPU Profiles

### RTX A6000 (48GB)
- **A6000-16Q**: 16GB (3 max)
- **A6000-8Q**: 8GB (6 max)  
- **A6000-4Q**: 4GB (12 max)

### RTX 8000 (48GB)
- **RTX8000-8Q**: 8GB (6 max)
- **RTX8000-4Q**: 4GB (12 max)
- **RTX8000-2Q**: 2GB (24 max)

## Troubleshooting

Use the monitoring script: `./monitor_status.sh`

Common fixes:
- **No virtualization**: Enable VT-x/SVM in BIOS
- **No IOMMU**: Add `intel_iommu=on` to GRUB
- **Driver issues**: Check `dmesg | grep nvidia`
- **VM won't start**: Verify vGPU UUID assignment

---

**Tip:** Use the automated scripts instead of manual setup: `./config_install.sh`