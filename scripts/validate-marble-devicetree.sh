#!/usr/bin/env bash
set -euo pipefail

# The LineageOS devicetree repository is a separate source tree. Keep it outside
# kernel-source: the kernel checkout already owns arch/arm64/boot/dts/vendor.
DT_ROOT="${MARBLE_DT_SOURCE:-external/marble-devicetrees}"

required=(
  "${DT_ROOT}/Makefile"
  "${DT_ROOT}/qcom/Makefile"
  "${DT_ROOT}/qcom/ukee.dts"
  "${DT_ROOT}/qcom/ukee.dtsi"
  "${DT_ROOT}/qcom/marble-sm7475-pm8008-overlay.dts"
)
for path in "${required[@]}"; do
  if [[ ! -s "${path}" ]]; then
    echo "::error::Marble Device Tree source file missing: ${path}"
    exit 1
  fi
done

if ! grep -Fq 'marble-sm7475-pm8008-overlay.dtbo' "${DT_ROOT}/qcom/Makefile"; then
  echo "::error::External Device Tree Makefile does not declare the Marble SM7475 overlay"
  exit 1
fi
if ! grep -Fq 'marble-sm7475-pm8008-overlay.dtbo-base := ukee.dtb' "${DT_ROOT}/qcom/Makefile"; then
  echo "::error::Marble overlay base declaration is missing or changed"
  exit 1
fi

if git -C "${DT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Marble Device Tree checkout: $(git -C "${DT_ROOT}" rev-parse HEAD)"
fi
echo "Verified Marble/SM7475 Device Tree source at ${DT_ROOT} (validation only; not overlaid into kernel-source or packaged)"
