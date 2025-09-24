# Ubuntu 24.04 KVM vGPU + Kubernetes Setup

Automated setup for KVM hypervisor with NVIDIA vGPU support and Kubernetes GPU orchestration on Ubuntu 24.04.

## 🚀 Quick Start

```bash
# 1. Check prerequisites
./kvm-prereqs.sh

# 2. Install KVM + vGPU
./kvm-vgpu-install.sh

# 3. Monitor system
./kvm-monitor.sh

# 4. Optional: Add Kubernetes with GPU support
./k8s-gpu-setup.sh
```

## 📁 Files

| Script | Purpose |
|--------|---------|
| `kvm-vgpu-guide.md` | Complete setup guide |
| `kvm-prereqs.sh` | Check system compatibility |
| `kvm-vgpu-install.sh` | Install KVM + vGPU stack |
| `kvm-monitor.sh` | System status & troubleshooting |
| `k8s-gpu-setup.sh` | Kubernetes v1.30 with GPU support |

## 💻 Requirements

- **GPU**: NVIDIA RTX 6000/8000/A6000
- **CPU**: Intel VT-x or AMD SVM
- **RAM**: 32GB+ recommended
- **OS**: Ubuntu 24.04 LTS

## 🎯 Common Setups

### Small Team (2-4 VMs)
- **Development**: 8GB vGPU, 16GB RAM
- **Training**: 16GB vGPU, 32GB RAM
- **Testing**: 4GB vGPU, 8GB RAM

### Research Lab (6-8 VMs)
- **Per User**: 4-8GB vGPU, 16GB RAM
- **Shared**: 8GB vGPU, 24GB RAM

### Production (3-5 VMs)
- **API Servers**: 8GB vGPU, 16GB RAM
- **Database**: No GPU, 16GB RAM
- **Load Balancer**: No GPU, 8GB RAM

## 🔧 vGPU Profiles

### RTX A6000 (48GB)
- **A6000-16Q**: 16GB (3 instances max)
- **A6000-8Q**: 8GB (6 instances max)
- **A6000-4Q**: 4GB (12 instances max)

### RTX 8000 (48GB)
- **RTX8000-8Q**: 8GB (6 instances max)
- **RTX8000-4Q**: 4GB (12 instances max)

## 🆘 Troubleshooting

Run `./kvm-monitor.sh` for automatic issue detection and fixes.

Common issues:
- **No GPU**: Check BIOS virtualization settings
- **Driver fails**: Use kernel rollback instructions
- **VMs won't start**: Check vGPU allocation

## 📚 Resources

- [NVIDIA vGPU Guide](https://docs.nvidia.com/vgpu/deployment/ubuntu-with-kvm/latest/install.html)
- [Ubuntu KVM Setup](https://help.ubuntu.com/community/KVM/Installation)

---

**Need help?** Check `kvm-vgpu-guide.md` for detailed instructions or run `./kvm-monitor.sh` for system diagnostics.