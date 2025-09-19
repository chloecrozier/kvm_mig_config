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
    echo -e "${BLUE}================================================================"
    echo "               KVM vGPU System Status Monitor"
    echo "================================================================${NC}"
    echo -e "${CYAN}Timestamp: $(date)${NC}"
    echo -e "${CYAN}Hostname: $(hostname)${NC}"
    echo
}

print_section() {
    echo -e "${MAGENTA}▶ $1${NC}"
    echo "----------------------------------------"
}

print_subsection() {
    echo -e "${YELLOW}  ► $1${NC}"
}

# System overview
show_system_overview() {
    print_section "System Overview"
    
    # OS Info
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        echo -e "${GREEN}OS:${NC} $PRETTY_NAME"
    fi
    
    # Kernel
    echo -e "${GREEN}Kernel:${NC} $(uname -r)"
    
    # Uptime
    echo -e "${GREEN}Uptime:${NC} $(uptime -p)"
    
    # Load average
    load_avg=$(uptime | awk -F'load average:' '{print $2}')
    echo -e "${GREEN}Load Average:${NC}$load_avg"
    
    # Memory usage
    mem_info=$(free -h | grep "^Mem:")
    mem_used=$(echo $mem_info | awk '{print $3}')
    mem_total=$(echo $mem_info | awk '{print $2}')
    mem_percent=$(echo $mem_info | awk '{printf "%.1f", ($3/$2)*100}')
    echo -e "${GREEN}Memory:${NC} $mem_used / $mem_total (${mem_percent}%)"
    
    echo
}

# KVM service status
show_kvm_status() {
    print_section "KVM Service Status"
    
    # libvirtd status
    if systemctl is-active --quiet libvirtd; then
        echo -e "${GREEN}✓ libvirtd:${NC} Active"
    else
        echo -e "${RED}✗ libvirtd:${NC} Inactive"
    fi
    
    # Check KVM modules
    print_subsection "KVM Modules"
    if lsmod | grep -q "kvm"; then
        lsmod | grep kvm | while read module rest; do
            echo -e "  ${GREEN}✓${NC} $module"
        done
    else
        echo -e "  ${RED}✗${NC} No KVM modules loaded"
    fi
    
    # Check VFIO modules (for vGPU)
    print_subsection "VFIO Modules"
    if lsmod | grep -q "vfio"; then
        lsmod | grep vfio | while read module rest; do
            echo -e "  ${GREEN}✓${NC} $module"
        done
    else
        echo -e "  ${YELLOW}⚠${NC} No VFIO modules loaded (normal if vGPU not configured)"
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
    print_section "Virtual Machines"
    
    if command -v virsh >/dev/null 2>&1; then
        # Get all VMs
        vm_list=$(virsh list --all 2>/dev/null | tail -n +3)
        
        if [ -z "$vm_list" ] || [ "$(echo "$vm_list" | wc -l)" -eq 0 ]; then
            echo -e "${YELLOW}No virtual machines found${NC}"
        else
            echo "$vm_list" | while read line; do
                if [ -n "$line" ] && [[ ! "$line" =~ ^[[:space:]]*$ ]]; then
                    id=$(echo "$line" | awk '{print $1}')
                    name=$(echo "$line" | awk '{print $2}')
                    state=$(echo "$line" | awk '{print $3" "$4}' | sed 's/shut off/shut_off/')
                    
                    case "$state" in
                        "running")
                            state_color="${GREEN}$state${NC}"
                            ;;
                        "shut_off")
                            state_color="${RED}shut off${NC}"
                            ;;
                        "paused")
                            state_color="${YELLOW}$state${NC}"
                            ;;
                        *)
                            state_color="${CYAN}$state${NC}"
                            ;;
                    esac
                    
                    if [ "$id" = "-" ]; then
                        id_display="${YELLOW}offline${NC}"
                    else
                        id_display="${GREEN}$id${NC}"
                    fi
                    
                    echo -e "  ${CYAN}$name${NC} (ID: $id_display): $state_color"
                    
                    # Show additional details for running VMs
                    if [ "$state" = "running" ] && [ "$SHOW_DETAILED" = true ]; then
                        # CPU and memory info
                        dominfo=$(virsh dominfo "$name" 2>/dev/null)
                        if [ $? -eq 0 ]; then
                            vcpus=$(echo "$dominfo" | grep "CPU(s)" | awk '{print $2}')
                            memory=$(echo "$dominfo" | grep "Max memory" | awk '{print $3" "$4}')
                            echo -e "    ${YELLOW}vCPUs:${NC} $vcpus, ${YELLOW}Memory:${NC} $memory"
                        fi
                        
                        # Network interfaces
                        interfaces=$(virsh domiflist "$name" 2>/dev/null | tail -n +3)
                        if [ -n "$interfaces" ]; then
                            echo -e "    ${YELLOW}Network Interfaces:${NC}"
                            echo "$interfaces" | while read iface_line; do
                                if [ -n "$iface_line" ]; then
                                    iface=$(echo "$iface_line" | awk '{print $1}')
                                    bridge=$(echo "$iface_line" | awk '{print $3}')
                                    echo -e "      $iface -> $bridge"
                                fi
                            done
                        fi
                    fi
                fi
            done
        fi
    else
        echo -e "${RED}virsh command not available${NC}"
    fi
    
    echo
}

# GPU and vGPU status
show_gpu_status() {
    print_section "GPU Status"
    
    # Physical GPUs
    print_subsection "Physical GPUs"
    gpu_list=$(lspci | grep -i nvidia | grep -i vga)
    if [ -n "$gpu_list" ]; then
        echo "$gpu_list" | while read line; do
            bdf=$(echo "$line" | awk '{print $1}')
            gpu_name=$(echo "$line" | cut -d':' -f3- | sed 's/^ *//')
            echo -e "  ${GREEN}$bdf${NC}: $gpu_name"
        done
    else
        echo -e "  ${RED}No NVIDIA GPUs detected${NC}"
    fi
    
    # NVIDIA driver status
    print_subsection "NVIDIA Driver"
    if command -v nvidia-smi >/dev/null 2>&1; then
        if nvidia-smi >/dev/null 2>&1; then
            driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -n1)
            echo -e "  ${GREEN}✓ Driver Version:${NC} $driver_version"
            
            # GPU utilization
            gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -n1)
            mem_util=$(nvidia-smi --query-gpu=utilization.memory --format=csv,noheader,nounits | head -n1)
            echo -e "  ${GREEN}GPU Utilization:${NC} ${gpu_util}%, ${GREEN}Memory Utilization:${NC} ${mem_util}%"
            
        else
            echo -e "  ${RED}✗ nvidia-smi failed${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠ NVIDIA driver not installed${NC}"
    fi
    
    # SR-IOV Virtual Functions
    print_subsection "SR-IOV Virtual Functions"
    vf_found=false
    for gpu_bdf in $(lspci | grep -i nvidia | grep -i vga | awk '{print $1}'); do
        full_bdf="0000:$gpu_bdf"
        # Check for VFs (they usually have different function numbers)
        vfs=$(lspci | grep -E "${gpu_bdf%.*}\.[1-9a-f]" | grep -i nvidia)
        if [ -n "$vfs" ]; then
            echo -e "  ${GREEN}VFs for $gpu_bdf:${NC}"
            echo "$vfs" | while read vf_line; do
                vf_bdf=$(echo "$vf_line" | awk '{print $1}')
                vf_desc=$(echo "$vf_line" | cut -d':' -f3- | sed 's/^ *//')
                echo -e "    ${CYAN}$vf_bdf${NC}: $vf_desc"
            done
            vf_found=true
        fi
    done
    
    if [ "$vf_found" = false ]; then
        echo -e "  ${YELLOW}⚠ No SR-IOV VFs detected${NC}"
        echo -e "    Enable with: /usr/lib/nvidia/sriov-manage -e <GPU_BDF>"
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
    print_section "Issues & Troubleshooting"
    
    issues_found=false
    
    print_subsection "Common Issues Detection"
    
    # Check 1: Virtualization not enabled
    virt_count=$(egrep -c '(vmx|svm)' /proc/cpuinfo 2>/dev/null || echo "0")
    if [ "$virt_count" -eq 0 ]; then
        echo -e "  ${RED}✗ ISSUE:${NC} CPU virtualization not enabled"
        echo -e "    ${YELLOW}Fix:${NC} Enable Intel VT-x or AMD SVM in BIOS"
        issues_found=true
    fi
    
    # Check 2: IOMMU not enabled
    if [ ! -d "/sys/kernel/iommu_groups" ] || [ -z "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]; then
        echo -e "  ${RED}✗ ISSUE:${NC} IOMMU not enabled"
        echo -e "    ${YELLOW}Fix:${NC} Add 'intel_iommu=on' or 'amd_iommu=on' to GRUB and reboot"
        echo -e "    ${CYAN}Command:${NC} sudo nano /etc/default/grub"
        echo -e "    ${CYAN}Add to GRUB_CMDLINE_LINUX_DEFAULT:${NC} intel_iommu=on (or amd_iommu=on)"
        echo -e "    ${CYAN}Then run:${NC} sudo update-grub && sudo reboot"
        issues_found=true
    fi
    
    # Check 3: Nouveau driver loaded
    if lsmod | grep -q nouveau; then
        echo -e "  ${RED}✗ ISSUE:${NC} Nouveau driver is loaded (conflicts with NVIDIA vGPU)"
        echo -e "    ${YELLOW}Fix:${NC} Blacklist nouveau driver"
        echo -e "    ${CYAN}Command:${NC} echo 'blacklist nouveau' | sudo tee /etc/modprobe.d/blacklist-nouveau.conf"
        echo -e "    ${CYAN}Then run:${NC} sudo update-initramfs -u && sudo reboot"
        issues_found=true
    fi
    
    # Check 4: libvirtd not running
    if ! systemctl is-active --quiet libvirtd; then
        echo -e "  ${RED}✗ ISSUE:${NC} libvirtd service not running"
        echo -e "    ${YELLOW}Fix:${NC} Start and enable libvirtd service"
        echo -e "    ${CYAN}Command:${NC} sudo systemctl enable --now libvirtd"
        issues_found=true
    fi
    
    # Check 5: User not in required groups
    current_user=$(whoami)
    if ! groups "$current_user" | grep -q libvirt; then
        echo -e "  ${RED}✗ ISSUE:${NC} User not in libvirt group"
        echo -e "    ${YELLOW}Fix:${NC} Add user to libvirt group"
        echo -e "    ${CYAN}Command:${NC} sudo adduser $current_user libvirt"
        echo -e "    ${CYAN}Note:${NC} Logout/login required after adding to group"
        issues_found=true
    fi
    
    if ! groups "$current_user" | grep -q kvm; then
        echo -e "  ${RED}✗ ISSUE:${NC} User not in kvm group"
        echo -e "    ${YELLOW}Fix:${NC} Add user to kvm group"
        echo -e "    ${CYAN}Command:${NC} sudo adduser $current_user kvm"
        echo -e "    ${CYAN}Note:${NC} Logout/login required after adding to group"
        issues_found=true
    fi
    
    # Check 6: NVIDIA driver issues
    if command -v nvidia-smi >/dev/null 2>&1; then
        if ! nvidia-smi >/dev/null 2>&1; then
            echo -e "  ${RED}✗ ISSUE:${NC} NVIDIA driver loaded but nvidia-smi fails"
            echo -e "    ${YELLOW}Possible causes:${NC}"
            echo -e "      - Driver/kernel version mismatch"
            echo -e "      - Incomplete driver installation"
            echo -e "      - Hardware issues"
            echo -e "    ${YELLOW}Fix:${NC} Reinstall NVIDIA driver or rollback kernel"
            issues_found=true
        fi
    fi
    
    # Check 7: No VFs available when expected
    vf_found=false
    for gpu_bdf in $(lspci | grep -i nvidia | grep -i vga | awk '{print $1}'); do
        vfs=$(lspci | grep -E "${gpu_bdf%.*}\.[1-9a-f]" | grep -i nvidia)
        if [ -n "$vfs" ]; then
            vf_found=true
            break
        fi
    done
    
    if [ "$vf_found" = false ] && command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
        echo -e "  ${YELLOW}⚠ NOTICE:${NC} No SR-IOV VFs detected"
        echo -e "    ${YELLOW}Enable VFs:${NC} /usr/lib/nvidia/sriov-manage -e <GPU_BDF>"
        echo -e "    ${CYAN}Find GPU BDF:${NC} lspci | grep -i nvidia | grep -i vga"
    fi
    
    # Check 8: VM fails to start
    failed_vms=$(virsh list --all 2>/dev/null | grep "shut off" | wc -l)
    if [ "$failed_vms" -gt 0 ] && [ "$SHOW_DETAILED" = true ]; then
        echo -e "  ${YELLOW}⚠ NOTICE:${NC} $failed_vms VMs are shut off"
        echo -e "    ${YELLOW}Check VM logs:${NC} journalctl -u libvirtd -f"
        echo -e "    ${YELLOW}Check VM config:${NC} virsh dumpxml <vm_name>"
    fi
    
    if [ "$issues_found" = false ]; then
        echo -e "  ${GREEN}✓ No critical issues detected${NC}"
    fi
    
    echo
    
    print_subsection "Kernel Rollback Instructions"
    echo -e "${YELLOW}If NVIDIA driver fails after kernel update:${NC}"
    echo
    echo -e "${CYAN}1. List available kernels:${NC}"
    echo -e "   dpkg --list | grep linux-image"
    echo
    echo -e "${CYAN}2. Reboot and select older kernel from GRUB menu${NC}"
    echo -e "   (Hold Shift during boot to show GRUB menu)"
    echo
    echo -e "${CYAN}3. Or set default kernel in GRUB:${NC}"
    echo -e "   sudo nano /etc/default/grub"
    echo -e "   # Set GRUB_DEFAULT to kernel menu entry number"
    echo -e "   # Example: GRUB_DEFAULT=\"1>2\" for submenu 1, entry 2"
    echo -e "   sudo update-grub"
    echo
    echo -e "${CYAN}4. Remove problematic kernel:${NC}"
    echo -e "   sudo apt remove linux-image-X.X.X-XX-generic"
    echo -e "   sudo apt autoremove"
    echo
    echo -e "${CYAN}5. Hold kernel packages to prevent auto-update:${NC}"
    echo -e "   sudo apt-mark hold linux-image-generic linux-headers-generic"
    echo
    echo -e "${CYAN}6. Unhold when ready to update:${NC}"
    echo -e "   sudo apt-mark unhold linux-image-generic linux-headers-generic"
    echo
    
    print_subsection "Driver Recovery Commands"
    echo -e "${YELLOW}NVIDIA Driver Issues:${NC}"
    echo
    echo -e "${CYAN}1. Completely remove NVIDIA drivers:${NC}"
    echo -e "   sudo nvidia-uninstall"
    echo -e "   sudo apt purge 'nvidia-*'"
    echo -e "   sudo apt autoremove"
    echo
    echo -e "${CYAN}2. Reinstall build dependencies:${NC}"
    echo -e "   sudo apt update"
    echo -e "   sudo apt install dkms gcc make linux-headers-\$(uname -r)"
    echo
    echo -e "${CYAN}3. Reinstall vGPU driver:${NC}"
    echo -e "   sudo dpkg -i nvidia-vgpu-ubuntu-*.deb"
    echo -e "   # Or run the .run file again"
    echo
    echo -e "${CYAN}4. Check driver build logs:${NC}"
    echo -e "   dkms status"
    echo -e "   sudo dkms build nvidia-vgpu/XXX"  # Replace XXX with version
    echo
    
    print_subsection "Emergency Recovery"
    echo -e "${YELLOW}If system won't boot after changes:${NC}"
    echo
    echo -e "${CYAN}1. Boot from recovery mode:${NC}"
    echo -e "   Select 'Advanced options' in GRUB"
    echo -e "   Choose 'recovery mode'"
    echo
    echo -e "${CYAN}2. Remove problematic configurations:${NC}"
    echo -e "   # Remove nouveau blacklist"
    echo -e "   rm /etc/modprobe.d/blacklist-nouveau.conf"
    echo -e "   update-initramfs -u"
    echo
    echo -e "   # Reset GRUB configuration"
    echo -e "   cp /etc/default/grub.backup.* /etc/default/grub"
    echo -e "   update-grub"
    echo
    echo -e "${CYAN}3. Boot from USB/Live CD:${NC}"
    echo -e "   Mount root filesystem"
    echo -e "   Chroot into system"
    echo -e "   Fix configurations and reboot"
    echo
    
    print_subsection "Log Files for Debugging"
    echo -e "${CYAN}System logs:${NC}"
    echo -e "  /var/log/syslog"
    echo -e "  journalctl -u libvirtd"
    echo -e "  journalctl -u nvidia-persistenced"
    echo -e "  dmesg | grep -i nvidia"
    echo -e "  dmesg | grep -i vfio"
    echo
    echo -e "${CYAN}VM logs:${NC}"
    echo -e "  /var/log/libvirt/qemu/<vm_name>.log"
    echo -e "  virsh dominfo <vm_name>"
    echo -e "  virsh qemu-monitor-command <vm_name> --hmp 'info qtree'"
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
