#!/bin/bash

# KVM vGPU Configuration Installation Script
# This script automates the installation steps from the KVM vGPU Configuration Guide
# Run with: bash config_install.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/install.log"
REBOOT_REQUIRED=false

print_header() {
    echo -e "${BLUE}=================================="
    echo "KVM vGPU Installation Script"
    echo -e "==================================${NC}"
    echo
}

print_section() {
    echo -e "${BLUE}--- $1 ---${NC}"
    echo "$(date): Starting $1" >> "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}✓ SUCCESS:${NC} $1"
    echo "$(date): SUCCESS - $1" >> "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}ℹ INFO:${NC} $1"
    echo "$(date): INFO - $1" >> "$LOG_FILE"
}

print_warn() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $1"
    echo "$(date): WARNING - $1" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}✗ ERROR:${NC} $1"
    echo "$(date): ERROR - $1" >> "$LOG_FILE"
}

# Check if running as root
check_sudo() {
    if [ "$EUID" -eq 0 ]; then
        print_error "Please run this script as a normal user with sudo privileges, not as root"
        exit 1
    fi
    
    if ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo privileges. You may be prompted for your password."
    fi
}

# Confirm before proceeding
confirm_installation() {
    echo -e "${YELLOW}This script will install and configure KVM with vGPU support.${NC}"
    echo "It will make system changes including:"
    echo "  - Update system packages"
    echo "  - Install KVM and related software"
    echo "  - Configure services"
    echo "  - Modify system configuration files"
    echo "  - May require system reboot"
    echo
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled by user"
        exit 0
    fi
}

# System update and basic packages
install_basic_packages() {
    print_section "Installing Basic Packages"
    
    print_info "Updating package repositories..."
    sudo apt update >> "$LOG_FILE" 2>&1
    
    print_info "Upgrading existing packages..."
    sudo apt upgrade -y >> "$LOG_FILE" 2>&1
    
    print_info "Installing essential tools..."
    sudo apt install -y \
        net-tools \
        openssh-server \
        cpu-checker \
        curl \
        wget \
        vim \
        htop \
        >> "$LOG_FILE" 2>&1
    
    print_success "Basic packages installed"
}

# Configure SSH
configure_ssh() {
    print_section "Configuring SSH"
    
    if systemctl is-enabled ssh >/dev/null 2>&1; then
        print_info "SSH service already enabled"
    else
        sudo systemctl enable --now ssh >> "$LOG_FILE" 2>&1
        print_success "SSH service enabled and started"
    fi
    
    # Optional: disable UFW for lab environments
    if systemctl is-enabled ufw >/dev/null 2>&1; then
        print_warn "Disabling UFW firewall (lab environment)"
        sudo systemctl disable ufw >> "$LOG_FILE" 2>&1
    fi
}

# Verify prerequisites
verify_prerequisites() {
    print_section "Verifying Prerequisites"
    
    # Check CPU virtualization
    virt_count=$(egrep -c '(vmx|svm)' /proc/cpuinfo 2>/dev/null || echo "0")
    if [ "$virt_count" -gt 0 ]; then
        print_success "CPU virtualization support detected"
    else
        print_error "CPU virtualization not supported or not enabled in BIOS"
        print_error "Enable Intel VT-x or AMD SVM in BIOS and rerun this script"
        exit 1
    fi
    
    # Check NVIDIA GPU
    if lspci | grep -qi nvidia; then
        print_success "NVIDIA GPU detected"
        lspci | grep -i nvidia | head -3
    else
        print_error "No NVIDIA GPU detected"
        exit 1
    fi
    
    # Check memory
    total_mem_gb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    if [ "$total_mem_gb" -ge 16 ]; then
        print_success "Sufficient memory: ${total_mem_gb}GB"
    else
        print_warn "Limited memory: ${total_mem_gb}GB (16GB+ recommended)"
    fi
}

# Install KVM
install_kvm() {
    print_section "Installing KVM"
    
    # Check if kvm-ok works
    if ! kvm-ok >> "$LOG_FILE" 2>&1; then
        print_error "KVM not supported or not enabled in BIOS"
        print_error "Enable virtualization in BIOS and rerun this script"
        exit 1
    fi
    
    print_info "Installing KVM packages..."
    sudo apt install -y \
        qemu-kvm \
        libvirt-daemon-system \
        libvirt-clients \
        bridge-utils \
        virt-manager \
        >> "$LOG_FILE" 2>&1
    
    print_success "KVM packages installed"
    
    # Add user to groups
    current_user=$(whoami)
    sudo adduser "$current_user" kvm >> "$LOG_FILE" 2>&1
    sudo adduser "$current_user" libvirt >> "$LOG_FILE" 2>&1
    print_success "User $current_user added to kvm and libvirt groups"
    
    # Start and enable libvirtd
    sudo systemctl enable --now libvirtd >> "$LOG_FILE" 2>&1
    print_success "libvirtd service enabled and started"
    
    # Configure default network
    if ! virsh net-list --all | grep -q "default.*active"; then
        virsh net-start default >> "$LOG_FILE" 2>&1 || true
    fi
    virsh net-autostart default >> "$LOG_FILE" 2>&1
    print_success "Default network configured"
}

# Install Cockpit
install_cockpit() {
    print_section "Installing Cockpit Web Interface"
    
    sudo apt install -y cockpit cockpit-machines >> "$LOG_FILE" 2>&1
    sudo systemctl enable --now cockpit.socket >> "$LOG_FILE" 2>&1
    
    print_success "Cockpit installed and enabled"
    
    # Get IP address for access info
    ip_addr=$(ip route get 8.8.8.8 | grep -oP 'src \K\S+' 2>/dev/null || echo "YOUR_IP")
    print_info "Access Cockpit at: https://$ip_addr:9090"
}

# Configure GRUB for IOMMU
configure_grub() {
    print_section "Configuring GRUB for IOMMU"
    
    # Detect CPU vendor
    if grep -q "Intel" /proc/cpuinfo; then
        iommu_param="intel_iommu=on"
        print_info "Intel CPU detected, using intel_iommu=on"
    elif grep -q "AMD" /proc/cpuinfo; then
        iommu_param="amd_iommu=on"
        print_info "AMD CPU detected, using amd_iommu=on"
    else
        print_warn "CPU vendor not detected, using generic iommu=on"
        iommu_param="iommu=on"
    fi
    
    # Backup GRUB config
    sudo cp /etc/default/grub /etc/default/grub.backup.$(date +%Y%m%d_%H%M%S)
    
    # Check if IOMMU is already configured
    if grep -q "$iommu_param" /etc/default/grub; then
        print_info "IOMMU already configured in GRUB"
    else
        print_info "Adding IOMMU configuration to GRUB..."
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $iommu_param\"/" /etc/default/grub
        sudo update-grub >> "$LOG_FILE" 2>&1
        print_success "GRUB updated with IOMMU support"
        REBOOT_REQUIRED=true
    fi
}

# Blacklist nouveau driver
blacklist_nouveau() {
    print_section "Blacklisting Nouveau Driver"
    
    if [ -f /etc/modprobe.d/blacklist-nouveau.conf ]; then
        print_info "Nouveau blacklist file already exists"
    else
        print_info "Creating nouveau blacklist configuration..."
        echo -e "blacklist nouveau\noptions nouveau modeset=0" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf >> "$LOG_FILE"
        sudo update-initramfs -u >> "$LOG_FILE" 2>&1
        print_success "Nouveau driver blacklisted"
        REBOOT_REQUIRED=true
    fi
    
    # Check if nouveau is currently loaded
    if lsmod | grep -q nouveau; then
        print_warn "Nouveau driver is currently loaded - reboot required"
        REBOOT_REQUIRED=true
    fi
}

# Install build dependencies for NVIDIA driver
install_build_deps() {
    print_section "Installing Build Dependencies"
    
    sudo apt install -y \
        dkms \
        gcc \
        make \
        linux-headers-$(uname -r) \
        >> "$LOG_FILE" 2>&1
    
    print_success "Build dependencies installed"
}

# Check for NVIDIA driver files
check_nvidia_drivers() {
    print_section "Checking for NVIDIA Driver Files"
    
    # Look for vGPU host driver
    host_driver=$(find "$SCRIPT_DIR" -name "nvidia-vgpu-ubuntu-*.deb" 2>/dev/null | head -1)
    guest_driver=$(find "$SCRIPT_DIR" -name "NVIDIA-Linux-x86_64-*-grid.run" 2>/dev/null | head -1)
    
    if [ -n "$host_driver" ]; then
        print_info "Found vGPU host driver: $(basename "$host_driver")"
        echo "HOST_DRIVER=$host_driver" >> "$SCRIPT_DIR/.driver_paths"
    else
        print_warn "vGPU host driver not found in script directory"
        print_info "Place nvidia-vgpu-ubuntu-*.deb file in $SCRIPT_DIR"
    fi
    
    if [ -n "$guest_driver" ]; then
        print_info "Found vGPU guest driver: $(basename "$guest_driver")"
        echo "GUEST_DRIVER=$guest_driver" >> "$SCRIPT_DIR/.driver_paths"
    else
        print_warn "vGPU guest driver not found in script directory"
        print_info "Place NVIDIA-Linux-x86_64-*-grid.run file in $SCRIPT_DIR"
    fi
}

# Create post-reboot script
create_post_reboot_script() {
    print_section "Creating Post-Reboot Script"
    
    cat > "$SCRIPT_DIR/install_drivers.sh" << 'EOF'
#!/bin/bash

# Post-reboot driver installation script
# This script runs after the initial system configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/install.log"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}ℹ INFO:${NC} $1"
    echo "$(date): INFO - $1" >> "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}✓ SUCCESS:${NC} $1"
    echo "$(date): SUCCESS - $1" >> "$LOG_FILE"
}

print_warn() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $1"
    echo "$(date): WARNING - $1" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}✗ ERROR:${NC} $1"
    echo "$(date): ERROR - $1" >> "$LOG_FILE"
}

echo -e "${BLUE}=== Post-Reboot Driver Installation ===${NC}"

# Check if nouveau is properly disabled
if lsmod | grep -q nouveau; then
    print_error "Nouveau driver is still loaded - blacklisting may have failed"
    exit 1
else
    print_success "Nouveau driver successfully disabled"
fi

# Check IOMMU
if [ -d "/sys/kernel/iommu_groups" ] && [ -n "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]; then
    iommu_groups=$(ls /sys/kernel/iommu_groups | wc -l)
    print_success "IOMMU is enabled ($iommu_groups IOMMU groups)"
else
    print_error "IOMMU not enabled - check BIOS settings and GRUB configuration"
    exit 1
fi

# Load driver paths if available
if [ -f "$SCRIPT_DIR/.driver_paths" ]; then
    source "$SCRIPT_DIR/.driver_paths"
fi

# Install vGPU host driver if available
if [ -n "$HOST_DRIVER" ] && [ -f "$HOST_DRIVER" ]; then
    print_info "Installing vGPU host driver..."
    sudo dpkg -i "$HOST_DRIVER" >> "$LOG_FILE" 2>&1
    print_success "vGPU host driver installed"
    print_warn "Reboot required to load vGPU driver"
else
    print_warn "vGPU host driver not found - manual installation required"
    print_info "Download from NVIDIA Enterprise portal and install with:"
    print_info "  sudo dpkg -i nvidia-vgpu-ubuntu-*.deb"
fi

print_info "Driver installation phase complete"
print_info "Next steps after reboot:"
print_info "  1. Verify nvidia-smi works"
print_info "  2. Enable SR-IOV VFs: /usr/lib/nvidia/sriov-manage -e <GPU_BDF>"
print_info "  3. Create vGPU mediated devices"
print_info "  4. Configure VMs with vGPU assignment"
EOF

    chmod +x "$SCRIPT_DIR/install_drivers.sh"
    print_success "Post-reboot script created: install_drivers.sh"
}

# Create VM creation helper script
create_vm_helper() {
    print_section "Creating VM Helper Scripts"
    
    cat > "$SCRIPT_DIR/create_vm.sh" << 'EOF'
#!/bin/bash

# VM Creation Helper Script
# Usage: ./create_vm.sh <vm_name> <iso_path> <disk_size_gb>

if [ $# -ne 3 ]; then
    echo "Usage: $0 <vm_name> <iso_path> <disk_size_gb>"
    echo "Example: $0 rocky-vm /path/to/rocky.iso 50"
    exit 1
fi

VM_NAME="$1"
ISO_PATH="$2"
DISK_SIZE="$3"

echo "Creating VM: $VM_NAME"
echo "ISO: $ISO_PATH"
echo "Disk Size: ${DISK_SIZE}GB"

# Create VM
virt-install \
    --name "$VM_NAME" \
    --ram 4096 \
    --disk path=/var/lib/libvirt/images/${VM_NAME}.qcow2,size="$DISK_SIZE" \
    --vcpus 2 \
    --os-type linux \
    --os-variant generic \
    --network bridge=virbr0 \
    --graphics vnc,listen=0.0.0.0 \
    --console pty,target_type=serial \
    --cdrom "$ISO_PATH" \
    --boot cdrom,hd

echo "VM $VM_NAME created successfully"
echo "Access via Cockpit at https://$(hostname -I | awk '{print $1}'):9090"
EOF

    chmod +x "$SCRIPT_DIR/create_vm.sh"
    print_success "VM creation helper created: create_vm.sh"
}

# Create vGPU management script
create_vgpu_helper() {
    cat > "$SCRIPT_DIR/manage_vgpu.sh" << 'EOF'
#!/bin/bash

# vGPU Management Helper Script

show_usage() {
    echo "Usage: $0 <command> [options]"
    echo "Commands:"
    echo "  list-gpus           - List available GPUs"
    echo "  list-profiles <bdf> - List vGPU profiles for GPU"
    echo "  enable-vfs <bdf>    - Enable SR-IOV VFs for GPU"
    echo "  create-vgpu <bdf> <profile> - Create vGPU instance"
    echo "  list-vgpus          - List created vGPU instances"
    echo ""
    echo "Examples:"
    echo "  $0 list-gpus"
    echo "  $0 list-profiles 0000:0a:00.0"
    echo "  $0 enable-vfs 0000:0a:00.0"
    echo "  $0 create-vgpu 0000:0a:00.4 nvidia-531"
}

list_gpus() {
    echo "Available NVIDIA GPUs:"
    lspci | grep -i nvidia | grep -i vga
}

list_profiles() {
    local bdf="$1"
    if [ -z "$bdf" ]; then
        echo "Error: BDF required"
        return 1
    fi
    
    echo "Available vGPU profiles for $bdf:"
    if [ -d "/sys/bus/pci/devices/$bdf/mdev_supported_types" ]; then
        for profile in /sys/bus/pci/devices/$bdf/mdev_supported_types/*; do
            if [ -d "$profile" ]; then
                profile_name=$(basename "$profile")
                name=$(cat "$profile/name" 2>/dev/null || echo "Unknown")
                desc=$(cat "$profile/description" 2>/dev/null || echo "No description")
                available=$(cat "$profile/available_instances" 2>/dev/null || echo "0")
                echo "  $profile_name: $name ($available available)"
                echo "    $desc"
            fi
        done
    else
        echo "Error: No mdev_supported_types found for $bdf"
        echo "Make sure vGPU driver is installed and VFs are enabled"
    fi
}

enable_vfs() {
    local bdf="$1"
    if [ -z "$bdf" ]; then
        echo "Error: BDF required"
        return 1
    fi
    
    echo "Enabling SR-IOV VFs for $bdf..."
    sudo /usr/lib/nvidia/sriov-manage -e "$bdf"
    echo "VFs enabled. New devices:"
    lspci | grep -i nvidia
}

create_vgpu() {
    local bdf="$1"
    local profile="$2"
    
    if [ -z "$bdf" ] || [ -z "$profile" ]; then
        echo "Error: BDF and profile required"
        return 1
    fi
    
    local uuid=$(uuidgen)
    local profile_path="/sys/class/mdev_bus/$bdf/mdev_supported_types/$profile"
    
    if [ ! -d "$profile_path" ]; then
        echo "Error: Profile $profile not found for $bdf"
        return 1
    fi
    
    echo "Creating vGPU instance..."
    echo "UUID: $uuid"
    echo "Profile: $profile"
    
    echo "$uuid" | sudo tee "$profile_path/create"
    echo "vGPU instance created successfully"
    echo "Use this UUID in VM configuration: $uuid"
}

list_vgpus() {
    echo "Created vGPU instances:"
    if [ -d "/sys/bus/mdev/devices" ]; then
        ls -la /sys/bus/mdev/devices/
    else
        echo "No vGPU instances found"
    fi
}

case "$1" in
    list-gpus)
        list_gpus
        ;;
    list-profiles)
        list_profiles "$2"
        ;;
    enable-vfs)
        enable_vfs "$2"
        ;;
    create-vgpu)
        create_vgpu "$2" "$3"
        ;;
    list-vgpus)
        list_vgpus
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
EOF

    chmod +x "$SCRIPT_DIR/manage_vgpu.sh"
    print_success "vGPU management helper created: manage_vgpu.sh"
}

# Main installation function
main() {
    print_header
    
    # Initialize log file
    echo "=== KVM vGPU Installation Started at $(date) ===" > "$LOG_FILE"
    
    check_sudo
    confirm_installation
    
    install_basic_packages
    configure_ssh
    verify_prerequisites
    install_kvm
    install_cockpit
    configure_grub
    blacklist_nouveau
    install_build_deps
    check_nvidia_drivers
    create_post_reboot_script
    create_vm_helper
    create_vgpu_helper
    
    print_section "Installation Summary"
    print_success "Base KVM vGPU installation completed!"
    
    echo
    print_info "Installation log saved to: $LOG_FILE"
    print_info "Helper scripts created:"
    print_info "  - install_drivers.sh (run after reboot)"
    print_info "  - create_vm.sh (VM creation helper)"
    print_info "  - manage_vgpu.sh (vGPU management)"
    
    echo
    if [ "$REBOOT_REQUIRED" = true ]; then
        print_warn "REBOOT REQUIRED to complete installation"
        print_info "After reboot, run: ./install_drivers.sh"
        echo
        read -p "Reboot now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Rebooting system..."
            sudo reboot
        else
            print_info "Please reboot manually when ready"
        fi
    else
        print_info "No reboot required - you can proceed with driver installation"
    fi
}

# Run main function
main "$@"
