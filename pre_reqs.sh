#!/bin/bash

# KVM vGPU Prerequisites Checker
# This script checks all prerequisites from the KVM vGPU Configuration Guide
# Run with: bash pre_reqs.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

print_header() {
    echo -e "${BLUE}=================================="
    echo "KVM vGPU Prerequisites Checker"
    echo -e "==================================${NC}"
    echo
}

print_section() {
    echo -e "${BLUE}--- $1 ---${NC}"
}

check_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((PASSED++))
}

check_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠ WARN:${NC} $1"
    ((WARNINGS++))
}

check_info() {
    echo -e "${BLUE}ℹ INFO:${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        check_warn "Running as root - some checks may not reflect normal user permissions"
    fi
}

# Check OS version
check_os() {
    print_section "Operating System"
    
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        check_info "OS: $PRETTY_NAME"
        
        if [[ "$ID" == "ubuntu" ]]; then
            if [[ "$VERSION_ID" == "24.04" ]]; then
                check_pass "Ubuntu 24.04 LTS detected"
            else
                check_warn "Ubuntu version is $VERSION_ID (guide targets 24.04)"
            fi
        else
            check_warn "OS is not Ubuntu (guide targets Ubuntu 24.04)"
        fi
    else
        check_fail "Cannot determine OS version"
    fi
    echo
}

# Check CPU virtualization support
check_cpu_virt() {
    print_section "CPU Virtualization Support"
    
    # Check for VMX or SVM flags
    virt_count=$(egrep -c '(vmx|svm)' /proc/cpuinfo 2>/dev/null || echo "0")
    
    if [ "$virt_count" -gt 0 ]; then
        check_pass "CPU virtualization supported ($virt_count cores with virt support)"
        
        # Check which type
        if grep -q vmx /proc/cpuinfo; then
            check_info "Intel VT-x detected"
        elif grep -q svm /proc/cpuinfo; then
            check_info "AMD SVM detected"
        fi
    else
        check_fail "CPU virtualization not supported or not enabled in BIOS"
        check_info "Enable Intel VT-x or AMD SVM in BIOS settings"
    fi
    
    # Check if kvm-ok is available and run it
    if command -v kvm-ok &> /dev/null; then
        check_info "Running kvm-ok check..."
        if kvm-ok 2>/dev/null | grep -q "KVM acceleration can be used"; then
            check_pass "KVM acceleration is available"
        else
            check_fail "KVM acceleration not available - check BIOS settings"
        fi
    else
        check_warn "kvm-ok not installed (install with: sudo apt install cpu-checker)"
    fi
    echo
}

# Check NVIDIA GPU presence
check_nvidia_gpu() {
    print_section "NVIDIA GPU Detection"
    
    # Check if nvidia GPUs are detected via lspci
    nvidia_gpus=$(lspci | grep -i nvidia | grep -i vga || true)
    
    if [ -n "$nvidia_gpus" ]; then
        check_pass "NVIDIA GPU(s) detected:"
        echo "$nvidia_gpus" | while read line; do
            check_info "  $line"
        done
        
        # Check for RTX 6000/8000/A6000 specifically
        if echo "$nvidia_gpus" | grep -q -E "(RTX 6000|RTX 8000|RTX A6000|Quadro RTX)"; then
            check_pass "Compatible vGPU GPU detected"
        else
            check_warn "GPU may not support vGPU - verify compatibility"
        fi
    else
        check_fail "No NVIDIA VGA GPUs detected"
        check_info "Ensure GPU is properly seated and powered"
    fi
    echo
}

# Check memory
check_memory() {
    print_section "System Memory"
    
    total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    total_mem_gb=$((total_mem_kb / 1024 / 1024))
    
    check_info "Total system memory: ${total_mem_gb}GB"
    
    if [ "$total_mem_gb" -ge 32 ]; then
        check_pass "Sufficient memory for vGPU workloads (${total_mem_gb}GB)"
    elif [ "$total_mem_gb" -ge 16 ]; then
        check_warn "Memory may be limited for multiple VMs (${total_mem_gb}GB)"
    else
        check_fail "Insufficient memory for vGPU workloads (${total_mem_gb}GB < 16GB recommended)"
    fi
    echo
}

# Check IOMMU support
check_iommu() {
    print_section "IOMMU Support"
    
    # Check if IOMMU is enabled in kernel
    if [ -d "/sys/kernel/iommu_groups" ] && [ -n "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]; then
        iommu_groups=$(ls /sys/kernel/iommu_groups | wc -l)
        check_pass "IOMMU is enabled ($iommu_groups IOMMU groups found)"
    else
        check_fail "IOMMU not enabled"
        check_info "Add 'intel_iommu=on' or 'amd_iommu=on' to GRUB_CMDLINE_LINUX_DEFAULT"
        check_info "Also ensure IOMMU is enabled in BIOS"
    fi
    
    # Check GRUB configuration
    if [ -f /etc/default/grub ]; then
        grub_cmdline=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub || true)
        if echo "$grub_cmdline" | grep -q "iommu=on"; then
            check_pass "IOMMU enabled in GRUB configuration"
        else
            check_warn "IOMMU not found in GRUB configuration"
            check_info "Current GRUB_CMDLINE_LINUX_DEFAULT: $grub_cmdline"
        fi
    fi
    echo
}

# Check network configuration
check_network() {
    print_section "Network Configuration"
    
    # Check if we have network connectivity
    if ping -c 1 8.8.8.8 &> /dev/null; then
        check_pass "Network connectivity available"
    else
        check_fail "No network connectivity"
    fi
    
    # Check for static IP (basic check)
    ip_info=$(ip route | grep default || true)
    if [ -n "$ip_info" ]; then
        check_info "Default route: $ip_info"
        
        # Get primary interface
        primary_if=$(ip route | grep default | awk '{print $5}' | head -n1)
        if [ -n "$primary_if" ]; then
            ip_addr=$(ip addr show "$primary_if" | grep "inet " | awk '{print $2}' | head -n1)
            check_info "Primary interface $primary_if: $ip_addr"
        fi
    else
        check_warn "No default route configured"
    fi
    echo
}

# Check required packages
check_packages() {
    print_section "Required Packages"
    
    packages=("openssh-server" "net-tools" "cpu-checker")
    
    for pkg in "${packages[@]}"; do
        if dpkg -l | grep -q "^ii  $pkg "; then
            check_pass "$pkg is installed"
        else
            check_warn "$pkg is not installed"
            check_info "Install with: sudo apt install $pkg"
        fi
    done
    echo
}

# Check KVM installation
check_kvm() {
    print_section "KVM Installation"
    
    kvm_packages=("qemu-kvm" "libvirt-daemon-system" "libvirt-clients" "bridge-utils")
    
    for pkg in "${kvm_packages[@]}"; do
        if dpkg -l | grep -q "^ii  $pkg "; then
            check_pass "$pkg is installed"
        else
            check_warn "$pkg is not installed"
        fi
    done
    
    # Check if libvirtd is running
    if systemctl is-active --quiet libvirtd; then
        check_pass "libvirtd service is running"
    else
        check_warn "libvirtd service is not running"
    fi
    
    # Check user groups
    current_user=$(whoami)
    if groups "$current_user" | grep -q libvirt; then
        check_pass "User $current_user is in libvirt group"
    else
        check_warn "User $current_user is not in libvirt group"
        check_info "Add with: sudo adduser $current_user libvirt"
    fi
    
    if groups "$current_user" | grep -q kvm; then
        check_pass "User $current_user is in kvm group"
    else
        check_warn "User $current_user is not in kvm group"
        check_info "Add with: sudo adduser $current_user kvm"
    fi
    echo
}

# Check nouveau driver status
check_nouveau() {
    print_section "Nouveau Driver Status"
    
    if lsmod | grep -q nouveau; then
        check_warn "Nouveau driver is loaded - should be blacklisted for vGPU"
        check_info "Blacklist with: echo 'blacklist nouveau' | sudo tee /etc/modprobe.d/blacklist-nouveau.conf"
    else
        check_pass "Nouveau driver is not loaded"
    fi
    
    # Check blacklist file
    if [ -f /etc/modprobe.d/blacklist-nouveau.conf ]; then
        if grep -q "blacklist nouveau" /etc/modprobe.d/blacklist-nouveau.conf; then
            check_pass "Nouveau is blacklisted in modprobe configuration"
        else
            check_warn "Blacklist file exists but may not be configured correctly"
        fi
    else
        check_info "No nouveau blacklist file found (will be needed for vGPU setup)"
    fi
    echo
}

# Check NVIDIA driver status
check_nvidia_driver() {
    print_section "NVIDIA Driver Status"
    
    if command -v nvidia-smi &> /dev/null; then
        check_pass "nvidia-smi command available"
        check_info "NVIDIA driver appears to be installed"
        
        # Try to run nvidia-smi
        if nvidia-smi &> /dev/null; then
            check_pass "nvidia-smi runs successfully"
            driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -n1)
            check_info "Driver version: $driver_version"
        else
            check_warn "nvidia-smi command fails - driver may not be properly loaded"
        fi
    else
        check_info "NVIDIA driver not installed (expected for fresh installation)"
    fi
    echo
}

# Print summary
print_summary() {
    echo -e "${BLUE}=================================="
    echo "Prerequisites Check Summary"
    echo -e "==================================${NC}"
    echo -e "${GREEN}Passed: $PASSED${NC}"
    echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
    echo -e "${RED}Failed: $FAILED${NC}"
    echo
    
    if [ "$FAILED" -eq 0 ]; then
        if [ "$WARNINGS" -eq 0 ]; then
            echo -e "${GREEN}✓ All prerequisites met! Ready to proceed with KVM vGPU setup.${NC}"
        else
            echo -e "${YELLOW}⚠ Prerequisites mostly met, but please review warnings above.${NC}"
        fi
    else
        echo -e "${RED}✗ Some critical prerequisites are missing. Please address failed checks before proceeding.${NC}"
    fi
    echo
    echo "For detailed setup instructions, refer to the KVM vGPU Configuration Guide."
}

# Main execution
main() {
    print_header
    check_root
    check_os
    check_cpu_virt
    check_nvidia_gpu
    check_memory
    check_iommu
    check_network
    check_packages
    check_kvm
    check_nouveau
    check_nvidia_driver
    print_summary
}

# Run main function
main "$@"