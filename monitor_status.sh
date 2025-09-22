#!/bin/bash

# KVM vGPU System Status Monitor
# This script displays comprehensive status information for KVM, VMs, vGPUs, and system resources
# Run with: bash monitor_status.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
REFRESH_INTERVAL=5
SHOW_DETAILED=false

print_header() {
    clear
    echo -e "${BLUE}=== KVM vGPU Status Monitor ===${NC}"
    echo -e "${CYAN}$(date) | $(hostname)${NC}"
    echo
}

print_section() {
    echo -e "${MAGENTA}▶ $1${NC}"
}

print_subsection() {
    echo -e "${YELLOW}  ► $1${NC}"
}

# System overview
show_system_overview() {
    print_section "System"
    
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        echo -e "${GREEN}OS:${NC} $PRETTY_NAME | ${GREEN}Kernel:${NC} $(uname -r)"
    fi
    
    mem_info=$(free -h | grep "^Mem:")
    mem_used=$(echo $mem_info | awk '{print $3}')
    mem_total=$(echo $mem_info | awk '{print $2}')
    echo -e "${GREEN}Memory:${NC} $mem_used / $mem_total | ${GREEN}Uptime:${NC} $(uptime -p)"
    echo
}

# KVM service status
show_kvm_status() {
    print_section "KVM"
    
    if systemctl is-active --quiet libvirtd; then
        echo -e "${GREEN}✓ libvirtd active${NC}"
    else
        echo -e "${RED}✗ libvirtd inactive${NC}"
    fi
    
    if lsmod | grep -q "kvm"; then
        echo -e "${GREEN}✓ KVM modules loaded${NC}"
    else
        echo -e "${RED}✗ KVM modules missing${NC}"
    fi
    
    if lsmod | grep -q "vfio"; then
        echo -e "${GREEN}✓ VFIO modules loaded${NC}"
    else
        echo -e "${YELLOW}⚠ VFIO modules not loaded${NC}"
    fi
    echo
}

# Virtual networks
show_virtual_networks() {
    print_section "Virtual Networks"
    
    if command -v virsh >/dev/null 2>&1; then
        virsh net-list --all 2>/dev/null | tail -n +3 | while read line; do
            if [ -n "$line" ]; then
                name=$(echo "$line" | awk '{print $1}')
                state=$(echo "$line" | awk '{print $2}')
                autostart=$(echo "$line" | awk '{print $3}')
                
                if [ "$state" = "active" ]; then
                    state_color="${GREEN}$state${NC}"
                else
                    state_color="${RED}$state${NC}"
                fi
                
                if [ "$autostart" = "yes" ]; then
                    auto_color="${GREEN}$autostart${NC}"
                else
                    auto_color="${YELLOW}$autostart${NC}"
                fi
                
                echo -e "  ${CYAN}$name${NC}: $state_color (autostart: $auto_color)"
            fi
        done
    else
        echo -e "${RED}virsh command not available${NC}"
    fi
    
    echo
}

# Virtual machines status
show_vm_status() {
    print_section "VMs"
    
    if command -v virsh >/dev/null 2>&1; then
        running_vms=$(virsh list --state-running 2>/dev/null | tail -n +3 | wc -l)
        total_vms=$(virsh list --all 2>/dev/null | tail -n +3 | wc -l)
        
        echo -e "${GREEN}Running:${NC} $running_vms / $total_vms total"
        
        # Show running VMs
        virsh list --state-running 2>/dev/null | tail -n +3 | while read line; do
            if [ -n "$line" ]; then
                name=$(echo "$line" | awk '{print $2}')
                echo -e "  ${GREEN}✓${NC} $name"
            fi
        done
        
        # Show stopped VMs
        virsh list --state-shutoff 2>/dev/null | tail -n +3 | while read line; do
            if [ -n "$line" ]; then
                name=$(echo "$line" | awk '{print $2}')
                echo -e "  ${RED}✗${NC} $name"
            fi
        done
    else
        echo -e "${RED}virsh not available${NC}"
    fi
    echo
}

# GPU and vGPU status
show_gpu_status() {
    print_section "GPU"
    
    # Check for NVIDIA GPUs
    gpu_count=$(lspci | grep -i nvidia | grep -i vga | wc -l)
    if [ "$gpu_count" -gt 0 ]; then
        echo -e "${GREEN}✓ $gpu_count NVIDIA GPU(s) detected${NC}"
        
        # Driver status
        if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
            driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -n1)
            echo -e "${GREEN}✓ Driver v$driver_version${NC}"
        else
            echo -e "${RED}✗ Driver not working${NC}"
        fi
        
        # Check for VFs
        vf_count=$(lspci | grep -i nvidia | grep -E "\.[1-9a-f]" | wc -l)
        if [ "$vf_count" -gt 0 ]; then
            echo -e "${GREEN}✓ $vf_count Virtual Functions enabled${NC}"
        else
            echo -e "${YELLOW}⚠ No VFs enabled${NC}"
        fi
    else
        echo -e "${RED}✗ No NVIDIA GPUs found${NC}"
    fi
    echo
}

# vGPU mediated devices
show_vgpu_devices() {
    print_section "vGPU Mediated Devices"
    
    # Check for created mdev devices
    if [ -d "/sys/bus/mdev/devices" ]; then
        mdev_devices=$(ls /sys/bus/mdev/devices/ 2>/dev/null)
        if [ -n "$mdev_devices" ]; then
            echo -e "${GREEN}Active vGPU Instances:${NC}"
            for uuid in $mdev_devices; do
                # Try to find which VM is using this device
                vm_using=""
                if command -v virsh >/dev/null 2>&1; then
                    for vm in $(virsh list --all --name 2>/dev/null); do
                        if [ -n "$vm" ]; then
                            if virsh dumpxml "$vm" 2>/dev/null | grep -q "$uuid"; then
                                vm_using=" (used by: $vm)"
                                break
                            fi
                        fi
                    done
                fi
                
                # Get mdev type if available
                mdev_type=""
                if [ -L "/sys/bus/mdev/devices/$uuid/mdev_type" ]; then
                    mdev_type_path=$(readlink -f "/sys/bus/mdev/devices/$uuid/mdev_type")
                    mdev_type=" [$(basename "$mdev_type_path")]"
                fi
                
                echo -e "  ${CYAN}$uuid${NC}$mdev_type$vm_using"
            done
        else
            echo -e "${YELLOW}No vGPU instances found${NC}"
        fi
    else
        echo -e "${YELLOW}No mdev devices directory found${NC}"
    fi
    
    # Show available vGPU profiles
    print_subsection "Available vGPU Profiles"
    profile_found=false
    for gpu_bdf in $(lspci | grep -i nvidia | awk '{print $1}'); do
        # Check both the main GPU and potential VFs
        for bdf_variant in "0000:$gpu_bdf" $(lspci | grep -E "${gpu_bdf%.*}\.[1-9a-f]" | awk '{print "0000:"$1}'); do
            mdev_types_dir="/sys/bus/pci/devices/$bdf_variant/mdev_supported_types"
            if [ -d "$mdev_types_dir" ]; then
                echo -e "  ${GREEN}$bdf_variant profiles:${NC}"
                for profile_dir in "$mdev_types_dir"/*; do
                    if [ -d "$profile_dir" ]; then
                        profile_name=$(basename "$profile_dir")
                        profile_desc=$(cat "$profile_dir/name" 2>/dev/null || echo "Unknown")
                        available=$(cat "$profile_dir/available_instances" 2>/dev/null || echo "0")
                        echo -e "    ${CYAN}$profile_name${NC}: $profile_desc (${available} available)"
                    fi
                done
                profile_found=true
            fi
        done
    done
    
    if [ "$profile_found" = false ]; then
        echo -e "  ${YELLOW}⚠ No vGPU profiles available${NC}"
        echo -e "    Ensure vGPU driver is installed and VFs are enabled"
    fi
    
    echo
}

# IOMMU groups
show_iommu_groups() {
    print_section "IOMMU Groups"
    
    if [ -d "/sys/kernel/iommu_groups" ]; then
        group_count=$(ls /sys/kernel/iommu_groups | wc -l)
        echo -e "${GREEN}IOMMU Groups: $group_count${NC}"
        
        if [ "$SHOW_DETAILED" = true ]; then
            # Show NVIDIA devices in IOMMU groups
            echo -e "${YELLOW}NVIDIA devices in IOMMU groups:${NC}"
            for group in /sys/kernel/iommu_groups/*/devices/*; do
                if [ -L "$group" ]; then
                    device=$(basename "$group")
                    group_num=$(echo "$group" | sed 's|.*/iommu_groups/\([0-9]*\)/.*|\1|')
                    device_info=$(lspci -s "$device" 2>/dev/null | grep -i nvidia)
                    if [ -n "$device_info" ]; then
                        echo -e "  Group ${group_num}: ${CYAN}$device${NC} - $device_info"
                    fi
                fi
            done
        fi
    else
        echo -e "${RED}✗ IOMMU not enabled${NC}"
    fi
    
    echo
}

# Storage information
show_storage_info() {
    print_section "VM Storage"
    
    # VM disk images location
    vm_images_dir="/var/lib/libvirt/images"
    if [ -d "$vm_images_dir" ]; then
        echo -e "${GREEN}VM Images Directory:${NC} $vm_images_dir"
        disk_usage=$(du -sh "$vm_images_dir" 2>/dev/null | awk '{print $1}')
        echo -e "${GREEN}Total Size:${NC} $disk_usage"
        
        if [ "$SHOW_DETAILED" = true ]; then
            echo -e "${YELLOW}VM Disk Images:${NC}"
            ls -lh "$vm_images_dir"/*.{qcow2,img,raw} 2>/dev/null | while read line; do
                if [ -n "$line" ]; then
                    size=$(echo "$line" | awk '{print $5}')
                    name=$(basename "$(echo "$line" | awk '{print $9}')")
                    echo -e "  $name: $size"
                fi
            done
        fi
    fi
    
    # Available disk space
    available_space=$(df -h /var/lib/libvirt/images 2>/dev/null | tail -1)
    if [ -n "$available_space" ]; then
        used=$(echo "$available_space" | awk '{print $3}')
        avail=$(echo "$available_space" | awk '{print $4}')
        use_percent=$(echo "$available_space" | awk '{print $5}')
        echo -e "${GREEN}Disk Usage:${NC} $used used, $avail available ($use_percent)"
    fi
    
    echo
}

# Resource usage summary
show_resource_summary() {
    print_section "Resource Summary"
    
    if command -v virsh >/dev/null 2>&1; then
        # Count running VMs
        running_vms=$(virsh list --state-running 2>/dev/null | tail -n +3 | wc -l)
        total_vms=$(virsh list --all 2>/dev/null | tail -n +3 | wc -l)
        
        echo -e "${GREEN}VMs:${NC} $running_vms running / $total_vms total"
        
        # Total allocated resources for running VMs
        total_vcpus=0
        total_memory_kb=0
        
        for vm in $(virsh list --state-running --name 2>/dev/null); do
            if [ -n "$vm" ]; then
                vcpus=$(virsh dominfo "$vm" 2>/dev/null | grep "CPU(s)" | awk '{print $2}')
                memory_kb=$(virsh dominfo "$vm" 2>/dev/null | grep "Used memory" | awk '{print $3}')
                
                if [ -n "$vcpus" ] && [[ "$vcpus" =~ ^[0-9]+$ ]]; then
                    total_vcpus=$((total_vcpus + vcpus))
                fi
                
                if [ -n "$memory_kb" ] && [[ "$memory_kb" =~ ^[0-9]+$ ]]; then
                    total_memory_kb=$((total_memory_kb + memory_kb))
                fi
            fi
        done
        
        total_memory_gb=$((total_memory_kb / 1024 / 1024))
        echo -e "${GREEN}Allocated to VMs:${NC} $total_vcpus vCPUs, ${total_memory_gb}GB memory"
    fi
    
    # vGPU instances
    if [ -d "/sys/bus/mdev/devices" ]; then
        vgpu_count=$(ls /sys/bus/mdev/devices/ 2>/dev/null | wc -l)
        echo -e "${GREEN}vGPU Instances:${NC} $vgpu_count active"
    fi
    
    echo
}

# Issue detection and troubleshooting
show_issues_and_troubleshooting() {
    print_section "Issues"
    
    issues_found=false
    
    # Quick checks
    virt_count=$(egrep -c '(vmx|svm)' /proc/cpuinfo 2>/dev/null || echo "0")
    if [ "$virt_count" -eq 0 ]; then
        echo -e "${RED}✗ CPU virtualization disabled - Enable VT-x/SVM in BIOS${NC}"
        issues_found=true
    fi
    
    if [ ! -d "/sys/kernel/iommu_groups" ] || [ -z "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]; then
        echo -e "${RED}✗ IOMMU disabled - Add intel_iommu=on to GRUB${NC}"
        issues_found=true
    fi
    
    if lsmod | grep -q nouveau; then
        echo -e "${RED}✗ Nouveau loaded - Blacklist in /etc/modprobe.d/${NC}"
        issues_found=true
    fi
    
    if ! systemctl is-active --quiet libvirtd; then
        echo -e "${RED}✗ libvirtd not running - sudo systemctl start libvirtd${NC}"
        issues_found=true
    fi
    
    current_user=$(whoami)
    if ! groups "$current_user" | grep -q libvirt; then
        echo -e "${RED}✗ User not in libvirt group - sudo adduser $current_user libvirt${NC}"
        issues_found=true
    fi
    
    if [ "$issues_found" = false ]; then
        echo -e "${GREEN}✓ No critical issues detected${NC}"
    fi
    
    echo
    echo -e "${YELLOW}Quick fixes:${NC}"
    echo -e "• Kernel rollback: dpkg --list | grep linux-image"
    echo -e "• Driver reinstall: sudo dpkg -i nvidia-vgpu-ubuntu-*.deb"
    echo -e "• Check logs: dmesg | grep -i nvidia"
    echo
}

# Show help
show_help() {
    echo "KVM vGPU System Status Monitor"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -d, --detailed     Show detailed information"
    echo "  -r, --refresh N    Refresh every N seconds (default: $REFRESH_INTERVAL)"
    echo "  -w, --watch        Continuous monitoring mode"
    echo "  -h, --help         Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                 Show status once"
    echo "  $0 -d              Show detailed status"
    echo "  $0 -w              Continuous monitoring"
    echo "  $0 -w -r 10        Continuous monitoring, refresh every 10 seconds"
}

# Main monitoring function
show_status() {
    print_header
    show_system_overview
    show_kvm_status
    show_virtual_networks
    show_vm_status
    show_gpu_status
    show_vgpu_devices
    show_iommu_groups
    show_storage_info
    show_resource_summary
    show_issues_and_troubleshooting
    
    if [ "$1" != "watch" ]; then
        echo -e "${BLUE}Run with -w for continuous monitoring${NC}"
        echo -e "${BLUE}Run with -h for help${NC}"
    fi
}

# Parse command line arguments
WATCH_MODE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--detailed)
            SHOW_DETAILED=true
            shift
            ;;
        -r|--refresh)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        -w|--watch)
            WATCH_MODE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
if [ "$WATCH_MODE" = true ]; then
    echo -e "${CYAN}Starting continuous monitoring (refresh every ${REFRESH_INTERVAL}s)${NC}"
    echo -e "${CYAN}Press Ctrl+C to exit${NC}"
    echo
    
    while true; do
        show_status "watch"
        echo -e "${BLUE}Next refresh in ${REFRESH_INTERVAL}s... (Ctrl+C to exit)${NC}"
        sleep "$REFRESH_INTERVAL"
    done
else
    show_status
fi
