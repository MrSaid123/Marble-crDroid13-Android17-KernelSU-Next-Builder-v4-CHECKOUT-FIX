#!/usr/bin/env bash
set -euo pipefail

ENABLE_EPSS_LUT_DEBUG="${ENABLE_EPSS_LUT_DEBUG:-false}"
KERNEL_DIR="${KERNEL_DIR:-kernel-source}"
PATCH_FILE="patches/epss/0001-epss-lut-read-only-diagnostics.patch"

case "${ENABLE_EPSS_LUT_DEBUG}" in
  true|false) ;;
  *)
    echo "::error::ENABLE_EPSS_LUT_DEBUG must be true or false, got '${ENABLE_EPSS_LUT_DEBUG}'"
    exit 1
    ;;
esac

if [[ "${ENABLE_EPSS_LUT_DEBUG}" != "true" ]]; then
  mkdir -p "${KERNEL_DIR}/release"
  {
    echo "enabled=false"
    echo "mode=read-only"
    echo "note=diagnostic patch not applied"
  } > "${KERNEL_DIR}/release/epss-lut-diagnostics.txt"
  echo "EPSS LUT diagnostics disabled; no kernel files changed."
  exit 0
fi

if [[ ! -d "${KERNEL_DIR}/.git" && ! -f "${KERNEL_DIR}/.git" ]]; then
  echo "::error::Kernel source checkout not found: ${KERNEL_DIR}"
  exit 1
fi
if [[ ! -s "${PATCH_FILE}" ]]; then
  echo "::error::EPSS diagnostics patch is missing: ${PATCH_FILE}"
  exit 1
fi

TARGET="${KERNEL_DIR}/drivers/cpufreq/qcom-cpufreq-hw-debug.c"
if [[ ! -s "${TARGET}" ]]; then
  echo "::error::Expected Qualcomm EPSS debug driver not found: ${TARGET}"
  exit 1
fi

if grep -q 'cpufreq_hw_lut_show' "${TARGET}"; then
  echo "EPSS LUT diagnostics are already present in the kernel source."
else
  echo "Checking EPSS read-only LUT patch..."
  git -C "${KERNEL_DIR}" apply --check --whitespace=nowarn "${GITHUB_WORKSPACE:-$PWD}/${PATCH_FILE}"
  echo "Applying EPSS read-only LUT patch..."
  git -C "${KERNEL_DIR}" apply --whitespace=nowarn "${GITHUB_WORKSPACE:-$PWD}/${PATCH_FILE}"
fi

mkdir -p "${KERNEL_DIR}/release"
{
  echo "enabled=true"
  echo "patch=${PATCH_FILE}"
  echo "patch_sha256=$(sha256sum "${PATCH_FILE}" | awk '{print $1}')"
  echo "source_commit=$(git -C "${KERNEL_DIR}" rev-parse HEAD)"
  echo "mode=read-only"
  echo "sysfs=/sys/kernel/qcom-cpufreq-hw/print_cpufreq_lut"
} > "${KERNEL_DIR}/release/epss-lut-diagnostics.txt"

printf 'EPSS LUT diagnostics patch applied successfully.\n'
