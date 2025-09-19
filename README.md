# KVM vGPU Configuration Repository

This repository contains comprehensive documentation and automation scripts for setting up KVM hypervisor with NVIDIA vGPU support. The setup enables virtual machines to share GPU resources through SR-IOV virtual functions and mediated devices.

## 📁 Repository Contents

### 📖 Documentation

#### `config.md`
**Comprehensive KVM vGPU Setup Guide**
- Complete step-by-step installation instructions
- Hardware prerequisites and BIOS configuration
- System setup and driver installation procedures  
- vGPU configuration and VM management
- Troubleshooting guide with common issues
- Reference tables for vGPU profiles and settings

### 🛠️ Scripts

#### `pre_reqs.sh`
**Prerequisites Checker Script**
- Validates system hardware compatibility
- Checks CPU virtualization support (Intel VT-x / AMD SVM)
- Verifies NVIDIA GPU detection and compatibility
- Tests IOMMU configuration
- Validates memory and system requirements
- Checks required packages and services
- Color-coded pass/fail/warning output
- Provides specific fix commands for issues

**Usage:**
```bash
./pre_reqs.sh
```

#### `config_install.sh`
**Automated Installation Script**
- Complete KVM vGPU installation automation
- System package updates and essential tools
- KVM and libvirt installation and configuration
- Cockpit web interface setup
- GRUB configuration for IOMMU support
- Nouveau driver blacklisting
- Build dependency installation
- Creates helper scripts for post-installation
- Handles reboot requirements automatically

**Usage:**
```bash
./config_install.sh
```

**Generated Helper Scripts:**
- `install_drivers.sh` - Post-reboot driver installation
- `create_vm.sh` - VM creation helper
- `manage_vgpu.sh` - vGPU management utilities

#### `monitor_status.sh`
**Comprehensive System Status Monitor**
- Real-time system overview (CPU, memory, uptime)
- KVM service and module status
- Virtual network configuration
- VM status and resource allocation
- GPU detection and driver status
- SR-IOV Virtual Function enumeration
- vGPU mediated device management
- IOMMU group information
- Storage usage and VM disk images
- **Automatic issue detection and troubleshooting**
- **Kernel rollback instructions**
- **Driver recovery procedures**
- **Emergency recovery guidance**

**Usage:**
```bash
# Single status check
./monitor_status.sh

# Detailed information
./monitor_status.sh -d

# Continuous monitoring
./monitor_status.sh -w

# Custom refresh interval
./monitor_status.sh -w -r 10
```

## 🚀 Quick Start

### 1. Prerequisites Check
First, verify your system meets all requirements:
```bash
chmod +x pre_reqs.sh
./pre_reqs.sh
```

### 2. Automated Installation
Run the main installation script:
```bash
chmod +x config_install.sh
./config_install.sh
```

### 3. Post-Installation Setup
After reboot, complete driver installation:
```bash
./install_drivers.sh
```

### 4. System Monitoring
Monitor your KVM vGPU environment:
```bash
chmod +x monitor_status.sh
./monitor_status.sh
```

## 📋 System Requirements

### Hardware
- **GPU**: NVIDIA RTX 6000/8000, RTX A6000, or compatible vGPU-capable card
- **CPU**: Intel with VT-x or AMD with SVM support
- **Memory**: 16GB+ recommended (32GB+ for multiple VMs)
- **Storage**: Sufficient space for VM disk images

### Software
- **OS**: Ubuntu 24.04 LTS (primary target)
- **BIOS**: Virtualization and IOMMU enabled
- **Network**: Static IP recommended for stability

## 🔧 Key Features

### Automated Setup
- **One-command installation** of complete KVM vGPU stack
- **Prerequisite validation** before installation
- **Intelligent error detection** and recovery guidance
- **Helper script generation** for ongoing management

### Comprehensive Monitoring
- **Real-time status** of all system components
- **Automatic issue detection** with fix suggestions
- **VM resource tracking** and utilization
- **vGPU instance management** and assignment

### Recovery & Troubleshooting
- **Kernel rollback procedures** for driver compatibility
- **Emergency recovery instructions** for boot failures
- **Driver reinstallation guides** for various scenarios
- **Log file locations** for detailed debugging

## 📊 Supported vGPU Profiles

### RTX A6000
| Profile | Memory | Resolution | Max Instances |
|---------|--------|------------|---------------|
| A6000-16Q | 16GB | 7680x4320 | 3 |
| A6000-8Q | 8GB | 7680x4320 | 6 |
| A6000-4Q | 4GB | 5120x2880 | 12 |

### RTX 8000
| Profile | Memory | Use Case |
|---------|--------|----------|
| RTX8000-8Q | 8GB | Heavy workloads |
| RTX8000-4Q | 4GB | Medium workloads |
| RTX8000-2Q | 2GB | Light workloads |

## 🆘 Troubleshooting

### Common Issues
The `monitor_status.sh` script automatically detects and provides fixes for:
- CPU virtualization not enabled
- IOMMU configuration problems
- Nouveau driver conflicts
- Service startup failures
- Permission issues
- Driver compatibility problems

### Emergency Recovery
If your system won't boot after configuration changes:
1. **Boot into recovery mode** from GRUB menu
2. **Use live USB** to mount and chroot into system
3. **Restore configuration backups** created by installation script
4. **Roll back to previous kernel** if driver incompatible

### Getting Help
1. Run `./monitor_status.sh -d` for detailed system analysis
2. Check the **Issues & Troubleshooting** section output
3. Review log files mentioned in the troubleshooting guide
4. Consult the comprehensive `config.md` documentation

## 📚 Additional Resources

- [NVIDIA vGPU Deployment Guide](https://docs.nvidia.com/vgpu/deployment/ubuntu-with-kvm/latest/install.html)
- [NVIDIA vGPU Product Support Matrix](https://docs.nvidia.com/vgpu/latest/product-support-matrix/)
- [Ubuntu KVM Installation Guide](https://help.ubuntu.com/community/KVM/Installation)
- [Cockpit Project Documentation](https://cockpit-project.org/documentation.html)

## ⚠️ Important Notes

- **Lab Environment**: Scripts assume development/lab environment with relaxed security
- **Production Use**: Implement proper security measures for production deployments
- **Driver Licensing**: Ensure proper NVIDIA vGPU licensing for production use
- **Backup**: Always backup system before making configuration changes

---

**Repository Structure:**
```
kvm_mig_config/
├── README.md              # This file
├── config.md              # Comprehensive setup guide
├── pre_reqs.sh           # Prerequisites checker
├── config_install.sh     # Main installation script
└── monitor_status.sh     # System status monitor
```