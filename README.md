# KVM vGPU Setup

Automated setup for KVM hypervisor with NVIDIA vGPU support. Share GPU resources across multiple virtual machines.

## 🚀 Quick Start

```bash
# 1. Check prerequisites
./pre_reqs.sh

# 2. Install KVM + vGPU
./config_install.sh

# 3. Monitor system
./monitor_status.sh

# 4. Optional: Add Kubernetes
./k8s_setup.sh
```

## 📁 Files

| Script | Purpose |
|--------|---------|
| `config.md` | Complete setup guide |
| `pre_reqs.sh` | Check system compatibility |
| `config_install.sh` | Install KVM + vGPU stack |
| `monitor_status.sh` | System status & troubleshooting |
| `k8s_setup.sh` | Kubernetes with GPU support |

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

Run `./monitor_status.sh` for automatic issue detection and fixes.

Common issues:
- **No GPU**: Check BIOS virtualization settings
- **Driver fails**: Use kernel rollback instructions
- **VMs won't start**: Check vGPU allocation

## 📚 Resources

- [NVIDIA vGPU Guide](https://docs.nvidia.com/vgpu/deployment/ubuntu-with-kvm/latest/install.html)
- [Ubuntu KVM Setup](https://help.ubuntu.com/community/KVM/Installation)

---

**Need help?** Check `config.md` for detailed instructions or run `./monitor_status.sh` for system diagnostics.