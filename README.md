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

#### `k8s_setup.sh`
**Kubernetes with GPU Support Setup**
- Complete Kubernetes cluster installation
- containerd container runtime configuration
- NVIDIA Container Toolkit integration
- NVIDIA GPU Operator deployment
- Flannel CNI networking
- Helm package manager
- Sample GPU workloads (TensorFlow, PyTorch)
- Automated GPU resource scheduling

**Generated Components:**
- `k8s_status.sh` - Cluster status monitoring
- `k8s_gpu_manage.sh` - GPU workload management
- Sample YAML manifests for GPU testing

**Usage:**
```bash
# Install Kubernetes with GPU support
./k8s_setup.sh

# Monitor cluster status
./k8s_status.sh

# Test GPU functionality
./k8s_gpu_manage.sh test-gpu

# Deploy TensorFlow GPU workload
./k8s_gpu_manage.sh test-tensorflow
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

### 5. Kubernetes Setup (Optional)
For containerized GPU workloads:
```bash
chmod +x k8s_setup.sh
./k8s_setup.sh
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

## 🎯 Use Cases & Deployment Scenarios

### AI/ML Development & Training
**Recommended Setup:** 2-4 VMs with vGPU instances
- **VM 1**: Development environment (4-8GB vGPU, 16GB RAM, 4 vCPUs)
- **VM 2**: Training workstation (8-16GB vGPU, 32GB RAM, 8 vCPUs)
- **VM 3**: Inference server (4-8GB vGPU, 16GB RAM, 4 vCPUs)
- **VM 4**: Jupyter/notebook server (2-4GB vGPU, 8GB RAM, 2 vCPUs)

**Use Cases:**
- TensorFlow/PyTorch model development
- Data preprocessing and analysis
- Model training and fine-tuning
- Inference API services
- Jupyter notebook environments

### Multi-User Research Environment
**Recommended Setup:** 6-12 VMs with smaller vGPU allocations
- **Per User VM**: 2-4GB vGPU, 8-16GB RAM, 2-4 vCPUs
- **Shared Storage**: NFS/CIFS for datasets
- **Load Balancer**: For web-based interfaces

**Use Cases:**
- University research labs
- Corporate R&D teams
- Multi-tenant GPU access
- Educational environments
- Collaborative development

### Production AI Services
**Recommended Setup:** 3-6 VMs with high availability
- **Load Balancer VM**: No GPU, 4GB RAM, 2 vCPUs
- **API Servers**: 4-8GB vGPU each, 16GB RAM, 4 vCPUs
- **Database VM**: No GPU, 16GB RAM, 4 vCPUs
- **Monitoring VM**: No GPU, 8GB RAM, 2 vCPUs

**Use Cases:**
- REST API inference services
- Real-time image/video processing
- Natural language processing APIs
- Computer vision applications
- Scalable ML microservices

### Container Orchestration (Kubernetes)
**Recommended Setup:** 3-5 VMs for K8s cluster
- **Master Node**: No GPU, 8GB RAM, 4 vCPUs
- **Worker Nodes**: 8-16GB vGPU each, 32GB RAM, 8 vCPUs
- **Storage Node**: No GPU, 16GB RAM, 4 vCPUs

**Use Cases:**
- Containerized ML workloads
- Auto-scaling GPU applications
- Multi-tenant container platform
- CI/CD with GPU testing
- Microservices architecture

### Development & Testing
**Recommended Setup:** 2-3 VMs for different environments
- **Development VM**: 4GB vGPU, 16GB RAM, 4 vCPUs
- **Staging VM**: 8GB vGPU, 24GB RAM, 6 vCPUs
- **Testing VM**: 2GB vGPU, 8GB RAM, 2 vCPUs

**Use Cases:**
- CUDA application development
- GPU driver testing
- Performance benchmarking
- Software validation
- Integration testing

## 📊 VM Configuration Guidelines

### GPU Memory Allocation Strategy

#### RTX A6000 (48GB Total)
```
Scenario 1: High-Performance (3 VMs)
├── VM1: 16GB vGPU (A6000-16Q) - Heavy training
├── VM2: 16GB vGPU (A6000-16Q) - Model development  
└── VM3: 16GB vGPU (A6000-16Q) - Inference server

Scenario 2: Multi-User (6 VMs)
├── VM1-4: 8GB vGPU each (A6000-8Q) - User workstations
├── VM5: 8GB vGPU (A6000-8Q) - Shared services
└── VM6: 8GB vGPU (A6000-8Q) - Testing environment

Scenario 3: Mixed Workload (12 VMs)
├── VM1-2: 8GB vGPU each (A6000-8Q) - Primary users
├── VM3-8: 4GB vGPU each (A6000-4Q) - Development
└── VM9-12: 4GB vGPU each (A6000-4Q) - Testing/CI
```

#### RTX 8000 (48GB Total)
```
Scenario 1: Research Lab (8 VMs)
├── VM1-2: 8GB vGPU each (RTX8000-8Q) - Senior researchers
├── VM3-6: 4GB vGPU each (RTX8000-4Q) - Graduate students
└── VM7-8: 8GB vGPU each (RTX8000-8Q) - Shared compute

Scenario 2: Production (4 VMs)
├── VM1-2: 12GB vGPU each (RTX8000-12Q) - Primary services
├── VM3: 12GB vGPU (RTX8000-12Q) - Backup/failover
└── VM4: 12GB vGPU (RTX8000-12Q) - Development
```

### System Resource Recommendations

#### Memory Allocation (Host RAM)
- **64GB Host**: Support 4-6 VMs (8-16GB each)
- **128GB Host**: Support 6-10 VMs (8-24GB each)
- **256GB Host**: Support 10-16 VMs (8-32GB each)

#### CPU Allocation
- **16 Cores**: 2-4 VMs (4-8 vCPUs each)
- **32 Cores**: 4-8 VMs (4-8 vCPUs each)
- **64 Cores**: 8-16 VMs (4-8 vCPUs each)

#### Storage Planning
- **OS Disk**: 50-100GB per VM
- **Data Storage**: 500GB-2TB per VM (depending on datasets)
- **Shared Storage**: NFS/CIFS for common datasets
- **Backup Storage**: 2x total VM storage

### Network Configuration

#### Single Host Setup
```
Host: 10.110.20.180/24
├── VM1: 10.110.20.181 (Static)
├── VM2: 10.110.20.182 (Static)
├── VM3: 10.110.20.183 (Static)
└── VM4: 10.110.20.184 (Static)
```

#### Multi-Host Setup
```
Management Network: 10.110.20.0/24
├── Host1: 10.110.20.180
├── Host2: 10.110.20.181
└── Storage: 10.110.20.190

VM Network: 192.168.100.0/24
├── VM Pool: 192.168.100.10-100
└── Services: 192.168.100.200-250
```

## 🔧 Scaling Recommendations

### Small Environment (1-5 Users)
- **1 Host**: RTX A6000, 64GB RAM, 16 cores
- **2-4 VMs**: 8-16GB vGPU each
- **Use Case**: Small team development, research

### Medium Environment (5-20 Users)
- **1-2 Hosts**: RTX A6000 each, 128GB RAM, 32 cores
- **6-12 VMs**: 4-8GB vGPU each
- **Shared Storage**: NFS server
- **Use Case**: Department, research lab

### Large Environment (20+ Users)
- **2-4 Hosts**: RTX A6000 each, 256GB RAM, 64 cores
- **12-24 VMs**: 2-8GB vGPU each
- **Infrastructure**: Load balancers, monitoring
- **Use Case**: Enterprise, university

### Container Platform
- **3-5 Hosts**: Kubernetes cluster
- **Worker Nodes**: 8-16GB vGPU each
- **Master Nodes**: No GPU required
- **Use Case**: Scalable containerized workloads

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
├── monitor_status.sh     # System status monitor
└── k8s_setup.sh          # Kubernetes with GPU support
```