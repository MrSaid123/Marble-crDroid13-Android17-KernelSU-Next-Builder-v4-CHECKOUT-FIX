#!/usr/bin/env bash
set -euo pipefail

KERNEL_DIR="${KERNEL_DIR:-kernel-source}"
ENABLE_SUSFS="${ENABLE_SUSFS:-false}"

if [[ "${ENABLE_SUSFS}" != "true" ]]; then
  echo "SUSFS disabled"
  exit 0
fi

source config/marble.env
source release/resolved-refs.env

if [[ -z "${susfs_commit}" ]]; then
  echo "::error::SUSFS resolution missing commit"
  exit 1
fi

work_root="$(pwd)"
susfs_dir="${work_root}/susfs4ksu"

# resolve-refs.sh now keeps the already-resolved checkout in the workspace.
# Reuse it instead of cloning GitLab a second time (the previous duplicate
# clone caused builds to fail when GitLab returned HTTP 503).
if [[ ! -d "${susfs_dir}/.git" ]]; then
  echo "SUSFS source checkout is missing; attempting a retrying clone as a fallback"
  clone_ok=false
  for attempt in 1 2 3 4 5; do
    echo "SUSFS: cloning ${SUSFS_REPO} (attempt ${attempt}/5)"
    if git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 \
      clone --filter=blob:none --no-checkout "${SUSFS_REPO}" "${susfs_dir}"; then
      clone_ok=true
      break
    fi
    rm -rf "${susfs_dir}"
    if [[ "${attempt}" -lt 5 ]]; then
      delay=$((attempt * 6))
      echo "SUSFS: clone failed; retrying in ${delay}s"
      sleep "${delay}"
    fi
  done
  if [[ "${clone_ok}" != "true" ]]; then
    echo "::error::Could not clone SUSFS after 5 attempts from ${SUSFS_REPO} (last failure may be HTTP 503). Re-run later, or disable Enable SUSFS."
    exit 1
  fi
fi

# Always verify that the source checkout is exactly the commit pinned by
# resolve-refs.sh; never silently build from a newer/different SUSFS revision.
if ! git -C "${susfs_dir}" cat-file -e "${susfs_commit}^{commit}" 2>/dev/null; then
  echo "::error::Cached SUSFS checkout does not contain pinned commit ${susfs_commit}; refusing to use a different revision"
  exit 1
fi
git -C "${susfs_dir}" checkout --detach "${susfs_commit}"
actual_susfs_commit="$(git -C "${susfs_dir}" rev-parse HEAD)"
if [[ "${actual_susfs_commit}" != "${susfs_commit}" ]]; then
  echo "::error::SUSFS commit mismatch: expected ${susfs_commit}, got ${actual_susfs_commit}"
  exit 1
fi

patch_root="${susfs_dir}/kernel_patches"
if [[ ! -d "${patch_root}" ]]; then
  echo "::error::Missing SUSFS patch directory: ${patch_root}"
  exit 1
fi

pushd "${KERNEL_DIR}" >/dev/null
patch_suffix="${SUSFS_KERNEL_BRANCH#gki-}"
main_patch="${patch_root}/50_add_susfs_in_gki-${patch_suffix}.patch"
if [[ -f "${main_patch}" ]]; then
  patch -p1 < "${main_patch}"
else
  echo "::error::Missing main SUSFS kernel patch for ${SUSFS_KERNEL_BRANCH}"
  exit 1
fi

rsync -a "${susfs_dir}/kernel_patches/fs/" fs/
rsync -a "${susfs_dir}/kernel_patches/include/" include/

# --- Workaround: as of susfs4ksu commit 769e31f, the gki-android12-5.10
# kernel patch calls susfs_sus_kstat_spoof_vfs_statfs() in fs/statfs.c
# before declaring it, which fails under -Werror,-Wimplicit-function-declaration.
# Upstream tracking: https://github.com/xingguangcuican6666/ABK/issues/267
# Self-disabling: only acts if upstream hasn't already fixed the ordering,
# so this becomes a no-op automatically once simonpunk ships a real fix.
if [[ "${SUSFS_KERNEL_BRANCH}" == "gki-android12-5.10" && -f fs/statfs.c ]]; then
  fn="susfs_sus_kstat_spoof_vfs_statfs"
  call_line="$(grep -n "${fn}(" fs/statfs.c | grep -v extern | head -n1 | cut -d: -f1)" || true
  if [[ -n "${call_line}" ]]; then
    decl_line="$(grep -n "extern.*${fn}" fs/statfs.c | head -n1 | cut -d: -f1)" || true
    if [[ -z "${decl_line}" || "${decl_line}" -gt "${call_line}" ]]; then
      echo "susfs-statfs-workaround: forward-declaring ${fn}() before its use in fs/statfs.c (upstream ordering bug, susfs_commit=${susfs_commit})"
      # Insert at file scope (right after the last #include), not next to the
      # call site: inserting inside the function body trips
      # -Werror,-Wdeclaration-after-statement whenever the call isn't the
      # very first line of its block (kernel code disallows declarations
      # after statements within a block; file-scope declarations are exempt).
      last_include_line="$(grep -n '^#include' fs/statfs.c | tail -n1 | cut -d: -f1)" || true
      insert_line="${last_include_line:-0}"
      insert_line=$((insert_line + 1))
      sed -i "${insert_line}i\\
extern int ${fn}(struct inode *inode, struct kstatfs *buf, bool *is_fuse);" fs/statfs.c
    else
      echo "susfs-statfs-workaround: upstream already declares ${fn}() before use, skipping"
    fi
  else
    echo "susfs-statfs-workaround: ${fn}() not referenced in fs/statfs.c, skipping"
  fi
fi

# --- Workaround: as of susfs4ksu commit e466df6, the gki-android12-5.10
# fs/susfs.c calls security_sb_statfs() but no longer gets <linux/security.h>
# pulled in transitively by its other includes, which fails under
# -Werror,-Wimplicit-function-declaration.
# Self-disabling: only acts if the header isn't already included, so this
# becomes a no-op automatically once simonpunk ships a real fix upstream.
if [[ "${SUSFS_KERNEL_BRANCH}" == "gki-android12-5.10" && -f fs/susfs.c ]]; then
  fn="security_sb_statfs"
  if grep -q "${fn}(" fs/susfs.c && ! grep -q '^#include <linux/security\.h>' fs/susfs.c; then
    echo "susfs-security-include-workaround: adding missing #include <linux/security.h> to fs/susfs.c (susfs_commit=${susfs_commit})"
    last_include_line="$(grep -n '^#include' fs/susfs.c | tail -n1 | cut -d: -f1)" || true
    insert_line="${last_include_line:-0}"
    insert_line=$((insert_line + 1))
    sed -i "${insert_line}i\\
#include <linux/security.h>" fs/susfs.c
  else
    echo "susfs-security-include-workaround: fs/susfs.c already has the header or doesn't need it, skipping"
  fi
fi

manager_kconfig=""
for candidate in KernelSU/kernel/Kconfig KernelSU-Next/kernel/Kconfig drivers/kernelsu/Kconfig; do
  if [[ -f "${candidate}" ]]; then
    manager_kconfig="${candidate}"
    break
  fi
done

if [[ -z "${manager_kconfig}" ]]; then
  echo "::error::Could not find manager source directory for SUSFS integration"
  exit 1
fi

if ! grep -q '^config KSU_SUSFS$' "${manager_kconfig}"; then
  echo "::error::Official manager ref ${manager_repo}@${manager_ref} does not include manager-side SUSFS support"
  exit 1
fi

echo "Using manager-side SUSFS support from ${manager_repo}@${manager_ref}"

popd >/dev/null
echo "SUSFS applied from ${susfs_commit}"
