#!/usr/bin/env bash
set -euo pipefail

# Load .env if present
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  source "${SCRIPT_DIR}/.env"
fi

# ----------------------------
# Defaults (override via flags or env vars)
# ----------------------------
PROJECT_ID="${PROJECT_ID:-}"
ZONE="${ZONE:-us-central1-a}"
INSTANCE_NAME="${INSTANCE_NAME:-}"
SSH_USER="${SSH_USER:-$(whoami)}"
BOOT_DISK_SIZE_GB="${BOOT_DISK_SIZE_GB:-50}"
BUCKET_NAME="${BUCKET_NAME:-}"
SCOPES="${SCOPES:-https://www.googleapis.com/auth/cloud-platform}"

# Mode-specific defaults
MODE="cpu"                               # cpu | gpu
# CPU (E2) defaults
CPU_MACHINE_TYPE="${CPU_MACHINE_TYPE:-e2-standard-2}"

# GPU defaults (L4 on g2). You can switch to T4(Ampere) or A100 via flags.
GPU_MACHINE_TYPE="${GPU_MACHINE_TYPE:-g2-standard-4}"
GPU_TYPE="${GPU_TYPE:-nvidia-l4}"        # e.g. nvidia-l4 | nvidia-tesla-t4 | nvidia-a100
GPU_COUNT="${GPU_COUNT:-1}"
GPU_MAINTENANCE_POLICY="${GPU_MAINTENANCE_POLICY:-TERMINATE}"

# Image selection
USE_NVIDIA_IMAGE="false"                  # if true, use NVIDIA CUDA image instead of Ubuntu LTS
UBUNTU_IMAGE_FAMILY="${UBUNTU_IMAGE_FAMILY:-ubuntu-2204-lts}"
UBUNTU_IMAGE_PROJECT="${UBUNTU_IMAGE_PROJECT:-ubuntu-os-cloud}"
NVIDIA_IMAGE_FAMILY="${NVIDIA_IMAGE_FAMILY:-common-cu121-ubuntu-2204}"
NVIDIA_IMAGE_PROJECT="${NVIDIA_IMAGE_PROJECT:-nvidia-ngc-public}"

# If not using NVIDIA image, allow auto-install of NVIDIA driver for GPU mode
AUTO_INSTALL_NVIDIA_DRIVER="${AUTO_INSTALL_NVIDIA_DRIVER:-true}"

# Misc
PROVISIONING_MODEL="${PROVISIONING_MODEL:-STANDARD}"  # STANDARD | SPOT

# ----------------------------
# Usage
# ----------------------------
usage() {
  cat <<EOF
Usage: $0 [options]

Modes:
  --mode cpu | gpu            Choose CPU (E2) or GPU VM. Default: cpu

General options:
  --project ID                GCP project ID (default: ${PROJECT_ID})
  --zone ZONE                 GCP zone (default: ${ZONE})
  --name NAME                 Instance name (default: ${INSTANCE_NAME})
  --disk SIZE_GB              Boot disk size in GB (default: ${BOOT_DISK_SIZE_GB})
  --scopes SCOPES             OAuth scopes (default: ${SCOPES})
  --bucket NAME               Ensure GCS bucket exists (default: ${BUCKET_NAME}; empty to skip)
  --provisioning STANDARD|SPOT  Provisioning model (default: ${PROVISIONING_MODEL})

CPU (E2) options:
  --cpu-type TYPE             E2 machine type (default: ${CPU_MACHINE_TYPE})

GPU options:
  --gpu-type TYPE             nvidia-l4 | nvidia-tesla-t4 | nvidia-a100 (default: ${GPU_TYPE})
  --gpu-count N               Number of GPUs (default: ${GPU_COUNT})
  --gpu-machine TYPE          GPU-capable machine type (default: ${GPU_MACHINE_TYPE})
  --gpu-maintenance POLICY    Usually TERMINATE for GPUs (default: ${GPU_MAINTENANCE_POLICY})

Image options:
  --use-nvidia-image          Use NVIDIA CUDA base image (default: ${USE_NVIDIA_IMAGE})
  --ubuntu-family NAME        Ubuntu family (default: ${UBUNTU_IMAGE_FAMILY})
  --ubuntu-project NAME       Ubuntu project (default: ${UBUNTU_IMAGE_PROJECT})
  --nvidia-family NAME        NVIDIA image family (default: ${NVIDIA_IMAGE_FAMILY})
  --nvidia-project NAME       NVIDIA project (default: ${NVIDIA_IMAGE_PROJECT})
  --auto-nvidia-driver true|false  Auto-install NVIDIA driver on first boot (GPU mode; default: ${AUTO_INSTALL_NVIDIA_DRIVER})

Examples:
  # Simple CPU E2 VM (defaults)
  $0 --mode cpu

  # GPU L4 in us-central1-a with NVIDIA driver auto-install
  $0 --mode gpu --gpu-type nvidia-l4 --gpu-count 1 --gpu-machine g2-standard-4 --zone us-central1-a

  # GPU T4 on n1 machine using NVIDIA CUDA image (no auto-install needed)
  $0 --mode gpu --gpu-type nvidia-tesla-t4 --gpu-machine n1-standard-8 --use-nvidia-image true

  # A100 (a2 family), 2 GPUs, spot VM
  $0 --mode gpu --gpu-type nvidia-a100 --gpu-machine a2-highgpu-2g --gpu-count 2 --provisioning SPOT
EOF
}

# ----------------------------
# Parse args
# ----------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --project) PROJECT_ID="$2"; shift 2 ;;
    --zone) ZONE="$2"; shift 2 ;;
    --name) INSTANCE_NAME="$2"; shift 2 ;;
    --disk) BOOT_DISK_SIZE_GB="$2"; shift 2 ;;
    --scopes) SCOPES="$2"; shift 2 ;;
    --bucket) BUCKET_NAME="$2"; shift 2 ;;
    --provisioning) PROVISIONING_MODEL="$2"; shift 2 ;;

    --cpu-type) CPU_MACHINE_TYPE="$2"; shift 2 ;;

    --gpu-type) GPU_TYPE="$2"; shift 2 ;;
    --gpu-count) GPU_COUNT="$2"; shift 2 ;;
    --gpu-machine) GPU_MACHINE_TYPE="$2"; shift 2 ;;
    --gpu-maintenance) GPU_MAINTENANCE_POLICY="$2"; shift 2 ;;

    --use-nvidia-image) USE_NVIDIA_IMAGE="$2"; shift 2 ;;
    --ubuntu-family) UBUNTU_IMAGE_FAMILY="$2"; shift 2 ;;
    --ubuntu-project) UBUNTU_IMAGE_PROJECT="$2"; shift 2 ;;
    --nvidia-family) NVIDIA_IMAGE_FAMILY="$2"; shift 2 ;;
    --nvidia-project) NVIDIA_IMAGE_PROJECT="$2"; shift 2 ;;
    --auto-nvidia-driver) AUTO_INSTALL_NVIDIA_DRIVER="$2"; shift 2 ;;

    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ----------------------------
# Sanity checks
# ----------------------------
# Required parameters check
if [[ -z "${PROJECT_ID}" ]]; then
  echo "ERROR: --project or PROJECT_ID env var is required"; exit 1
fi
if [[ -z "${INSTANCE_NAME}" ]]; then
  echo "ERROR: --name or INSTANCE_NAME env var is required"; exit 1
fi

if [[ "${MODE}" != "cpu" && "${MODE}" != "gpu" ]]; then
  echo "ERROR: --mode must be 'cpu' or 'gpu'"; exit 1
fi

if [[ "${MODE}" == "gpu" ]]; then
  if [[ -z "${GPU_MACHINE_TYPE}" || -z "${GPU_TYPE}" ]]; then
    echo "ERROR: GPU mode requires --gpu-machine and --gpu-type"; exit 1
  fi
fi

# ----------------------------
# Helpers
# ----------------------------
ensure_bucket() {
  local bucket="$1"
  if [[ -z "${bucket}" ]]; then
    echo "==> Skipping bucket ensure (BUCKET_NAME empty)."
    return
  fi
  if gsutil ls -p "${PROJECT_ID}" "gs://${bucket}" >/dev/null 2>&1; then
    echo "==> Bucket 'gs://${bucket}' already exists."
  else
    echo "==> Creating bucket 'gs://${bucket}' in project '${PROJECT_ID}' (location: US)"
    gsutil mb -p "${PROJECT_ID}" -l US "gs://${bucket}"
  fi
}

instance_exists() {
  gcloud compute instances describe "${INSTANCE_NAME}" --zone "${ZONE}" >/dev/null 2>&1
}

create_cpu_instance() {
  echo "==> Creating CPU (E2) VM '${INSTANCE_NAME}' in ${ZONE} ..."
  gcloud compute instances create "${INSTANCE_NAME}" \
    --project "${PROJECT_ID}" \
    --zone "${ZONE}" \
    --machine-type "${CPU_MACHINE_TYPE}" \
    --image-family "${UBUNTU_IMAGE_FAMILY}" \
    --image-project "${UBUNTU_IMAGE_PROJECT}" \
    --boot-disk-size "${BOOT_DISK_SIZE_GB}" \
    --scopes "${SCOPES}" \
    --provisioning-model "${PROVISIONING_MODEL}"
}

create_gpu_instance() {
  echo "==> Creating GPU VM '${INSTANCE_NAME}' in ${ZONE} ..."
  local image_flags=()
  local metadata_flags=()

  if [[ "${USE_NVIDIA_IMAGE}" == "true" ]]; then
    image_flags=( --image-family="${NVIDIA_IMAGE_FAMILY}" --image-project="${NVIDIA_IMAGE_PROJECT}" )
  else
    image_flags=( --image-family "${UBUNTU_IMAGE_FAMILY}" --image-project "${UBUNTU_IMAGE_PROJECT}" )
    if [[ "${AUTO_INSTALL_NVIDIA_DRIVER}" == "true" ]]; then
      metadata_flags+=( --metadata=install-nvidia-driver=True )
    fi
  fi

  gcloud compute instances create "${INSTANCE_NAME}" \
    --project "${PROJECT_ID}" \
    --zone "${ZONE}" \
    --machine-type "${GPU_MACHINE_TYPE}" \
    "${image_flags[@]}" \
    --boot-disk-size "${BOOT_DISK_SIZE_GB}" \
    --accelerator="count=${GPU_COUNT},type=${GPU_TYPE}" \
    --maintenance-policy="${GPU_MAINTENANCE_POLICY}" \
    --provisioning-model "${PROVISIONING_MODEL}" \
    --scopes "${SCOPES}" \
    "${metadata_flags[@]}"
}

print_plan() {
  echo "================ PLAN ================"
  echo "Project:          ${PROJECT_ID}"
  echo "Zone:             ${ZONE}"
  echo "Instance:         ${INSTANCE_NAME}"
  echo "Mode:             ${MODE}"
  echo "Provisioning:     ${PROVISIONING_MODEL}"
  echo "Disk (GB):        ${BOOT_DISK_SIZE_GB}"
  echo "Bucket:           ${BUCKET_NAME:-<skip>}"
  echo "Scopes:           ${SCOPES}"
  if [[ "${MODE}" == "cpu" ]]; then
    echo "Machine type:     ${CPU_MACHINE_TYPE}"
    echo "Image:            ${UBUNTU_IMAGE_PROJECT}/${UBUNTU_IMAGE_FAMILY}"
  else
    echo "GPU machine:      ${GPU_MACHINE_TYPE}"
    echo "GPU type/count:   ${GPU_TYPE} x ${GPU_COUNT}"
    echo "Maintenance:      ${GPU_MAINTENANCE_POLICY}"
    if [[ "${USE_NVIDIA_IMAGE}" == "true" ]]; then
      echo "Image:            ${NVIDIA_IMAGE_PROJECT}/${NVIDIA_IMAGE_FAMILY}"
    else
      echo "Image:            ${UBUNTU_IMAGE_PROJECT}/${UBUNTU_IMAGE_FAMILY}"
      echo "Auto NVIDIA drv:  ${AUTO_INSTALL_NVIDIA_DRIVER}"
    fi
  fi
  echo "======================================"
}

# ----------------------------
# Main
# ----------------------------
echo "==> Verifying gcloud is installed..."
command -v gcloud >/dev/null || { echo "gcloud not found"; exit 1; }
command -v gsutil >/dev/null || { echo "gsutil not found"; exit 1; }

print_plan
ensure_bucket "${BUCKET_NAME}"

if instance_exists; then
  echo "==> VM '${INSTANCE_NAME}' already exists; skipping create."
else
  if [[ "${MODE}" == "cpu" ]]; then
    create_cpu_instance
  else
    create_gpu_instance
  fi
fi

echo "==> Done."
echo "SSH example:"
echo "  gcloud compute ssh ${SSH_USER}@${INSTANCE_NAME} --zone ${ZONE}"

