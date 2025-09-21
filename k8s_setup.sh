#!/bin/bash

# Kubernetes Setup Script for vGPU Environment
# This script sets up Kubernetes with GPU support for containerized workloads
# Run with: bash k8s_setup.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/k8s_install.log"
K8S_VERSION="1.28"
CONTAINERD_VERSION="1.7.2"
NVIDIA_OPERATOR_VERSION="v23.9.1"

print_header() {
    echo -e "${BLUE}=================================="
    echo "Kubernetes vGPU Setup Script"
    echo -e "==================================${NC}"
    echo
}

print_section() {
    echo -e "${MAGENTA}--- $1 ---${NC}"
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

# Check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_error "Please run this script as a normal user with sudo privileges, not as root"
        exit 1
    fi
    
    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo privileges. You may be prompted for your password."
    fi
    
    # Check if KVM is installed
    if ! command -v virsh >/dev/null 2>&1; then
        print_error "KVM/libvirt not found. Please run config_install.sh first"
        exit 1
    fi
    
    # Check if NVIDIA driver is available
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        print_warn "NVIDIA driver not detected. GPU support will be limited"
    else
        print_success "NVIDIA driver detected"
    fi
    
    # Check system resources
    total_mem_gb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    if [ "$total_mem_gb" -lt 8 ]; then
        print_error "Insufficient memory for Kubernetes (${total_mem_gb}GB < 8GB required)"
        exit 1
    fi
    
    print_success "Prerequisites check completed"
}

# Confirm installation
confirm_installation() {
    echo -e "${YELLOW}This script will install Kubernetes with GPU support.${NC}"
    echo "Components to be installed:"
    echo "  - containerd container runtime"
    echo "  - Kubernetes (kubeadm, kubelet, kubectl)"
    echo "  - NVIDIA Container Toolkit"
    echo "  - NVIDIA GPU Operator"
    echo "  - Helm package manager"
    echo
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled by user"
        exit 0
    fi
}

# Install containerd
install_containerd() {
    print_section "Installing containerd"
    
    # Install dependencies
    sudo apt update >> "$LOG_FILE" 2>&1
    sudo apt install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        >> "$LOG_FILE" 2>&1
    
    # Add Docker repository (for containerd)
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi
    
    sudo apt update >> "$LOG_FILE" 2>&1
    sudo apt install -y containerd.io >> "$LOG_FILE" 2>&1
    
    # Configure containerd
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml >> "$LOG_FILE"
    
    # Enable systemd cgroup driver
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    sudo systemctl restart containerd >> "$LOG_FILE" 2>&1
    sudo systemctl enable containerd >> "$LOG_FILE" 2>&1
    
    print_success "containerd installed and configured"
}

# Configure system for Kubernetes
configure_system() {
    print_section "Configuring System for Kubernetes"
    
    # Disable swap
    sudo swapoff -a >> "$LOG_FILE" 2>&1
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    
    # Load required kernel modules
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf >> "$LOG_FILE"
overlay
br_netfilter
EOF
    
    sudo modprobe overlay >> "$LOG_FILE" 2>&1
    sudo modprobe br_netfilter >> "$LOG_FILE" 2>&1
    
    # Configure sysctl
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf >> "$LOG_FILE"
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    
    sudo sysctl --system >> "$LOG_FILE" 2>&1
    
    print_success "System configured for Kubernetes"
}

# Install Kubernetes components
install_kubernetes() {
    print_section "Installing Kubernetes"
    
    # Add Kubernetes repository
    if [ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    fi
    
    sudo apt update >> "$LOG_FILE" 2>&1
    sudo apt install -y kubelet kubeadm kubectl >> "$LOG_FILE" 2>&1
    sudo apt-mark hold kubelet kubeadm kubectl >> "$LOG_FILE" 2>&1
    
    print_success "Kubernetes components installed"
}

# Initialize Kubernetes cluster
init_cluster() {
    print_section "Initializing Kubernetes Cluster"
    
    # Get the primary IP address
    PRIMARY_IP=$(ip route get 8.8.8.8 | grep -oP 'src \K\S+')
    
    print_info "Initializing cluster with API server on $PRIMARY_IP"
    
    # Initialize cluster
    sudo kubeadm init \
        --apiserver-advertise-address="$PRIMARY_IP" \
        --pod-network-cidr=10.244.0.0/16 \
        --cri-socket=unix:///var/run/containerd/containerd.sock \
        >> "$LOG_FILE" 2>&1
    
    # Set up kubectl for regular user
    mkdir -p "$HOME/.kube"
    sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
    sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
    
    # Allow scheduling on control plane (single node setup)
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- >> "$LOG_FILE" 2>&1 || true
    
    print_success "Kubernetes cluster initialized"
    print_info "Cluster API server: https://$PRIMARY_IP:6443"
}

# Install CNI (Flannel)
install_cni() {
    print_section "Installing CNI (Flannel)"
    
    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml >> "$LOG_FILE" 2>&1
    
    # Wait for flannel to be ready
    print_info "Waiting for Flannel pods to be ready..."
    kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=300s >> "$LOG_FILE" 2>&1
    
    print_success "Flannel CNI installed"
}

# Install Helm
install_helm() {
    print_section "Installing Helm"
    
    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    
    sudo apt update >> "$LOG_FILE" 2>&1
    sudo apt install -y helm >> "$LOG_FILE" 2>&1
    
    print_success "Helm installed"
}

# Install NVIDIA Container Toolkit
install_nvidia_container_toolkit() {
    print_section "Installing NVIDIA Container Toolkit"
    
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        print_warn "NVIDIA driver not found, skipping container toolkit installation"
        return 0
    fi
    
    # Add NVIDIA repository
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    sudo apt update >> "$LOG_FILE" 2>&1
    sudo apt install -y nvidia-container-toolkit >> "$LOG_FILE" 2>&1
    
    # Configure containerd for NVIDIA
    sudo nvidia-ctk runtime configure --runtime=containerd >> "$LOG_FILE" 2>&1
    sudo systemctl restart containerd >> "$LOG_FILE" 2>&1
    
    print_success "NVIDIA Container Toolkit installed"
}

# Install NVIDIA GPU Operator
install_gpu_operator() {
    print_section "Installing NVIDIA GPU Operator"
    
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        print_warn "NVIDIA driver not found, skipping GPU operator installation"
        return 0
    fi
    
    # Add NVIDIA Helm repository
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >> "$LOG_FILE" 2>&1
    helm repo update >> "$LOG_FILE" 2>&1
    
    # Install GPU Operator
    helm install --wait gpu-operator \
        -n gpu-operator --create-namespace \
        nvidia/gpu-operator \
        --version="$NVIDIA_OPERATOR_VERSION" \
        --set driver.enabled=false \
        >> "$LOG_FILE" 2>&1
    
    print_success "NVIDIA GPU Operator installed"
}

# Create sample GPU workload
create_sample_workloads() {
    print_section "Creating Sample GPU Workloads"
    
    # Create namespace for examples
    kubectl create namespace gpu-examples >> "$LOG_FILE" 2>&1 || true
    
    # GPU test pod
    cat > "$SCRIPT_DIR/gpu-test-pod.yaml" << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
  namespace: gpu-examples
spec:
  containers:
  - name: gpu-test
    image: nvidia/cuda:11.8-runtime-ubuntu20.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
  restartPolicy: Never
EOF

    # GPU workload deployment
    cat > "$SCRIPT_DIR/gpu-workload.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-workload
  namespace: gpu-examples
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gpu-workload
  template:
    metadata:
      labels:
        app: gpu-workload
    spec:
      containers:
      - name: gpu-container
        image: nvidia/cuda:11.8-devel-ubuntu20.04
        command: ["sleep", "infinity"]
        resources:
          limits:
            nvidia.com/gpu: 1
          requests:
            nvidia.com/gpu: 1
---
apiVersion: v1
kind: Service
metadata:
  name: gpu-workload-service
  namespace: gpu-examples
spec:
  selector:
    app: gpu-workload
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
EOF

    # TensorFlow GPU example
    cat > "$SCRIPT_DIR/tensorflow-gpu.yaml" << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: tensorflow-gpu-test
  namespace: gpu-examples
spec:
  template:
    spec:
      containers:
      - name: tensorflow-gpu
        image: tensorflow/tensorflow:latest-gpu
        command: ["python", "-c"]
        args:
        - |
          import tensorflow as tf
          print("TensorFlow version:", tf.__version__)
          print("GPU Available: ", tf.config.list_physical_devices('GPU'))
          print("Built with CUDA: ", tf.test.is_built_with_cuda())
          
          # Simple GPU computation test
          if tf.config.list_physical_devices('GPU'):
              with tf.device('/GPU:0'):
                  a = tf.constant([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
                  b = tf.constant([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]])
                  c = tf.matmul(a, b)
                  print("Matrix multiplication result:")
                  print(c.numpy())
          else:
              print("No GPU found, running on CPU")
        resources:
          limits:
            nvidia.com/gpu: 1
      restartPolicy: Never
  backoffLimit: 4
EOF

    # PyTorch GPU example
    cat > "$SCRIPT_DIR/pytorch-gpu.yaml" << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: pytorch-gpu-test
  namespace: gpu-examples
spec:
  template:
    spec:
      containers:
      - name: pytorch-gpu
        image: pytorch/pytorch:latest
        command: ["python", "-c"]
        args:
        - |
          import torch
          print("PyTorch version:", torch.__version__)
          print("CUDA available:", torch.cuda.is_available())
          print("CUDA version:", torch.version.cuda)
          print("Number of GPUs:", torch.cuda.device_count())
          
          if torch.cuda.is_available():
              device = torch.device('cuda')
              print("Current GPU:", torch.cuda.get_device_name(0))
              
              # Simple tensor operations on GPU
              x = torch.randn(1000, 1000).to(device)
              y = torch.randn(1000, 1000).to(device)
              z = torch.matmul(x, y)
              print("GPU tensor computation completed")
              print("Result shape:", z.shape)
          else:
              print("No GPU available, using CPU")
        resources:
          limits:
            nvidia.com/gpu: 1
      restartPolicy: Never
  backoffLimit: 4
EOF

    print_success "Sample GPU workload manifests created"
    print_info "Files created:"
    print_info "  - gpu-test-pod.yaml (Simple GPU test)"
    print_info "  - gpu-workload.yaml (GPU deployment)"
    print_info "  - tensorflow-gpu.yaml (TensorFlow GPU test)"
    print_info "  - pytorch-gpu.yaml (PyTorch GPU test)"
}

# Create management scripts
create_management_scripts() {
    print_section "Creating Kubernetes Management Scripts"
    
    # Cluster status script
    cat > "$SCRIPT_DIR/k8s_status.sh" << 'EOF'
#!/bin/bash

# Kubernetes Cluster Status Script
# Shows comprehensive cluster and GPU status

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Kubernetes Cluster Status ===${NC}"
echo

echo -e "${YELLOW}Cluster Info:${NC}"
kubectl cluster-info
echo

echo -e "${YELLOW}Node Status:${NC}"
kubectl get nodes -o wide
echo

echo -e "${YELLOW}System Pods:${NC}"
kubectl get pods -n kube-system
echo

echo -e "${YELLOW}GPU Operator Status:${NC}"
kubectl get pods -n gpu-operator 2>/dev/null || echo "GPU Operator not installed"
echo

echo -e "${YELLOW}GPU Resources:${NC}"
kubectl describe nodes | grep -A 5 "nvidia.com/gpu" || echo "No GPU resources found"
echo

echo -e "${YELLOW}All Namespaces:${NC}"
kubectl get namespaces
echo

echo -e "${YELLOW}Running Workloads:${NC}"
kubectl get pods --all-namespaces | grep -v "kube-system\|gpu-operator"
echo

if command -v nvidia-smi >/dev/null 2>&1; then
    echo -e "${YELLOW}Host GPU Status:${NC}"
    nvidia-smi
fi
EOF

    # GPU workload management script
    cat > "$SCRIPT_DIR/k8s_gpu_manage.sh" << 'EOF'
#!/bin/bash

# Kubernetes GPU Workload Management Script

show_usage() {
    echo "Usage: $0 <command> [options]"
    echo "Commands:"
    echo "  deploy-examples     - Deploy all GPU example workloads"
    echo "  test-gpu           - Run simple GPU test pod"
    echo "  test-tensorflow    - Run TensorFlow GPU test"
    echo "  test-pytorch       - Run PyTorch GPU test"
    echo "  list-gpu-pods      - List all GPU-enabled pods"
    echo "  gpu-logs <pod>     - Show logs from GPU pod"
    echo "  cleanup            - Remove all example workloads"
    echo "  gpu-usage          - Show GPU resource usage"
}

deploy_examples() {
    echo "Deploying GPU example workloads..."
    kubectl apply -f gpu-workload.yaml
    echo "GPU workload deployed"
}

test_gpu() {
    echo "Running GPU test pod..."
    kubectl apply -f gpu-test-pod.yaml
    echo "Waiting for pod to complete..."
    kubectl wait --for=condition=complete pod/gpu-test -n gpu-examples --timeout=300s
    echo "GPU test results:"
    kubectl logs gpu-test -n gpu-examples
}

test_tensorflow() {
    echo "Running TensorFlow GPU test..."
    kubectl apply -f tensorflow-gpu.yaml
    echo "Job submitted. Check status with: kubectl get jobs -n gpu-examples"
}

test_pytorch() {
    echo "Running PyTorch GPU test..."
    kubectl apply -f pytorch-gpu.yaml
    echo "Job submitted. Check status with: kubectl get jobs -n gpu-examples"
}

list_gpu_pods() {
    echo "GPU-enabled pods:"
    kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.containers[*].resources.limits.nvidia\.com/gpu}{"\n"}{end}' | grep -v "^.*\t$"
}

gpu_logs() {
    if [ -z "$2" ]; then
        echo "Error: Pod name required"
        return 1
    fi
    kubectl logs "$2" -n gpu-examples
}

cleanup() {
    echo "Cleaning up GPU example workloads..."
    kubectl delete namespace gpu-examples --ignore-not-found=true
    echo "Cleanup completed"
}

gpu_usage() {
    echo "GPU resource usage in cluster:"
    kubectl top nodes 2>/dev/null || echo "Metrics server not available"
    echo
    echo "GPU allocations by pod:"
    kubectl get pods --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,GPU-LIMIT:.spec.containers[*].resources.limits.nvidia\.com/gpu,GPU-REQUEST:.spec.containers[*].resources.requests.nvidia\.com/gpu"
}

case "$1" in
    deploy-examples)
        deploy_examples
        ;;
    test-gpu)
        test_gpu
        ;;
    test-tensorflow)
        test_tensorflow
        ;;
    test-pytorch)
        test_pytorch
        ;;
    list-gpu-pods)
        list_gpu_pods
        ;;
    gpu-logs)
        gpu_logs "$@"
        ;;
    cleanup)
        cleanup
        ;;
    gpu-usage)
        gpu_usage
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
EOF

    chmod +x "$SCRIPT_DIR/k8s_status.sh"
    chmod +x "$SCRIPT_DIR/k8s_gpu_manage.sh"
    
    print_success "Management scripts created"
}

# Show completion summary
show_completion_summary() {
    print_section "Installation Complete"
    
    echo -e "${GREEN}Kubernetes with GPU support has been successfully installed!${NC}"
    echo
    
    print_info "Cluster Information:"
    PRIMARY_IP=$(ip route get 8.8.8.8 | grep -oP 'src \K\S+')
    echo -e "  API Server: https://$PRIMARY_IP:6443"
    echo -e "  Config: $HOME/.kube/config"
    echo
    
    print_info "Useful Commands:"
    echo -e "  ${CYAN}kubectl get nodes${NC}                    - Check node status"
    echo -e "  ${CYAN}kubectl get pods --all-namespaces${NC}    - List all pods"
    echo -e "  ${CYAN}./k8s_status.sh${NC}                      - Comprehensive cluster status"
    echo -e "  ${CYAN}./k8s_gpu_manage.sh test-gpu${NC}         - Test GPU functionality"
    echo
    
    print_info "GPU Testing:"
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo -e "  ${CYAN}./k8s_gpu_manage.sh deploy-examples${NC}  - Deploy GPU workloads"
        echo -e "  ${CYAN}./k8s_gpu_manage.sh test-tensorflow${NC}  - Test TensorFlow GPU"
        echo -e "  ${CYAN}./k8s_gpu_manage.sh test-pytorch${NC}     - Test PyTorch GPU"
    else
        echo -e "  ${YELLOW}NVIDIA driver not detected - GPU features limited${NC}"
    fi
    echo
    
    print_info "Files Created:"
    echo -e "  - k8s_status.sh (cluster monitoring)"
    echo -e "  - k8s_gpu_manage.sh (GPU workload management)"
    echo -e "  - gpu-*.yaml (sample GPU workloads)"
    echo
    
    print_info "Next Steps:"
    echo -e "  1. Wait for all pods to be ready: kubectl get pods --all-namespaces"
    echo -e "  2. Check cluster status: ./k8s_status.sh"
    echo -e "  3. Test GPU functionality: ./k8s_gpu_manage.sh test-gpu"
    echo -e "  4. Deploy your GPU workloads using the sample manifests"
}

# Main installation function
main() {
    print_header
    
    # Initialize log file
    echo "=== Kubernetes Installation Started at $(date) ===" > "$LOG_FILE"
    
    check_prerequisites
    confirm_installation
    
    install_containerd
    configure_system
    install_kubernetes
    init_cluster
    install_cni
    install_helm
    install_nvidia_container_toolkit
    install_gpu_operator
    create_sample_workloads
    create_management_scripts
    
    show_completion_summary
}

# Run main function
main "$@"
