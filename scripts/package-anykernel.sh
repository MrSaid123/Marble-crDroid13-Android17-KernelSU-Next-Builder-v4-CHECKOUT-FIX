#!/usr/bin/env bash
set -euo pipefail

source config/marble.env

KERNEL_DIR="${KERNEL_DIR:-kernel-source}"
MANAGER="${MANAGER:-kernelsu-next}"
ENABLE_SUSFS="${ENABLE_SUSFS:-false}"
LTO="${LTO:-thin}"

release_dir="${KERNEL_DIR}/${RELEASE_DIR}"
if [[ -f release/resolved-refs.env ]]; then
  # shellcheck disable=SC1091
  source release/resolved-refs.env
fi
if [[ -f release/kernel-source.env ]]; then
  # shellcheck disable=SC1091
  source release/kernel-source.env
fi

KERNEL_SOURCE="${KERNEL_SOURCE:-aosp-pablo}"

sanitize_token() {
  printf '%s' "$1" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+//; s/-+$//'
}

case "${MANAGER}" in
  kernelsu)      manager_token="ksun" ;;
  kernelsu-next) manager_token="ksunext" ;;
  sukisu-ultra)  manager_token="sukisu" ;;
  resukisu)      manager_token="resukisu" ;;
  *)             manager_token="$(sanitize_token "${MANAGER}")" ;;
esac

case "${KERNEL_SOURCE}" in
  aosp-pablo)  preset_prefix="" ;;
  aospa-pablo) preset_prefix="aospa-" ;;
  *)           preset_prefix="$(sanitize_token "${KERNEL_SOURCE}")-" ;;
esac

susfs_segment=""
if [[ "${ENABLE_SUSFS}" == "true" ]]; then
  susfs_segment="_susfs"
fi

epss_debug_segment=""
if [[ "${ENABLE_EPSS_LUT_DEBUG:-false}" == "true" ]]; then
  epss_debug_segment="_epssdiag"
fi

build_date="$(date '+%Y.%m.%d')"
zip_name="${preset_prefix}${manager_token}${susfs_segment}${epss_debug_segment}-marble-${build_date}.zip"

if [[ "${PACKAGE_NAME_ONLY:-false}" == "true" ]]; then
  printf '%s\n' "${zip_name}"
  exit 0
fi

image_path="${release_dir}/Image"
if [[ ! -s "${image_path}" ]]; then
  echo "::error::Cannot package without ${image_path}"
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
rsync -a ak3/ "${work_dir}/ak3/"
cp LICENSE "${work_dir}/ak3/LICENSE"
cp "${image_path}" "${work_dir}/ak3/Image"

# Hard fail if an old build left external-partition payloads in the AK3 staging
# template. This package is deliberately boot-only.
for forbidden in dtb dtb.img dtbo dtbo.img vendor_boot vendor_boot.img \
                 vendor_kernel_boot vendor_kernel_boot.img vendor_dlkm vendor_dlkm.img \
                 system_dlkm system_dlkm.img; do
  if [[ -e "${work_dir}/ak3/${forbidden}" ]]; then
    echo "::error::Refusing to package external partition payload: ${forbidden}"
    exit 1
  fi
done

pushd "${work_dir}/ak3" >/dev/null
zip -r9 "${OLDPWD}/${release_dir}/${zip_name}" . -x ".git/*" "README.md" "*placeholder*" "banner" "banner.txt"
popd >/dev/null

pushd "${release_dir}" >/dev/null
sha256sum "${zip_name}" > "${zip_name}.sha256"
printf 'zip_name=%s\n' "${zip_name}" > zip-name.env
printf 'zip_sha256=%s\n' "$(sha256sum "${zip_name}" | awk '{print $1}')" >> zip-name.env
popd >/dev/null

echo "Packaged boot-only kernel zip (vendor_boot, DTBO and module partitions are not touched): ${release_dir}/${zip_name}"
