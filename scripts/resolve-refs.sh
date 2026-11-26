#!/usr/bin/env bash
set -euo pipefail

source config/marble.env

MANAGER="${MANAGER:-kernelsu-next}"
MANAGER_REF="${MANAGER_REF:-}"
ENABLE_SUSFS="${ENABLE_SUSFS:-false}"
KERNEL_DIR="${KERNEL_DIR:-kernel-source}"

mkdir -p release

source_commit="$(git -C "${KERNEL_DIR}" rev-parse HEAD)"
manager_repo=""
manager_effective_ref=""
manager_commit=""
manager_tag=""
manager_setup_path=""
susfs_commit=""
susfs_reported_version=""
susfs_url=""

manager_repo="$(jq -r --arg manager "${MANAGER}" '.[$manager].repo' config/managers.json)"
manager_default_ref="$(jq -r --arg manager "${MANAGER}" '.[$manager].ref' config/managers.json)"

if [[ "${ENABLE_SUSFS}" == "true" ]]; then
  susfs_repo_override="$(jq -r --arg manager "${MANAGER}" '.[$manager].susfs.repo // empty' config/managers.json)"
  if [[ -n "${susfs_repo_override}" ]]; then
    manager_repo="${susfs_repo_override}"
  fi
  susfs_ref_override="$(jq -r --arg manager "${MANAGER}" '.[$manager].susfs.ref // empty' config/managers.json)"
  if [[ -n "${susfs_ref_override}" ]]; then
    manager_default_ref="${susfs_ref_override}"
  fi
fi

manager_effective_ref="${MANAGER_REF:-${manager_default_ref}}"
manager_setup_path="$(jq -r --arg manager "${MANAGER}" '.[$manager].setup_path' config/managers.json)"

if command -v gh >/dev/null 2>&1; then
  manager_commit="$(gh api "repos/${manager_repo}/commits/${manager_effective_ref}" --jq .sha)"
else
  manager_commit="$(git ls-remote "https://github.com/${manager_repo}.git" \
    "refs/heads/${manager_effective_ref}" "refs/tags/${manager_effective_ref}^{}" "refs/tags/${manager_effective_ref}" |
    awk 'NR == 1 { print $1 }')"
  if [[ -z "${manager_commit}" && "${manager_effective_ref}" =~ ^[0-9a-fA-F]{40}$ ]]; then
    manager_commit="${manager_effective_ref}"
  fi
fi
if [[ -z "${manager_commit}" ]]; then
  echo "::error::Could not resolve manager ref ${manager_repo}@${manager_effective_ref}"
  exit 1
fi

all_tags="$(git ls-remote --tags "https://github.com/${manager_repo}.git" 2>/dev/null || true)"
manager_tag="$(echo "${all_tags}" | awk -v sha="${manager_commit}" '
  $1 == sha {
    tag = $2
    sub(/^refs\/tags\//, "", tag)
    sub(/\^\{\}$/, "", tag)
    print tag
    exit
  }')"

if [[ "${ENABLE_SUSFS}" == "true" ]]; then
  susfs_requested_ref="${SUSFS_COMMIT}"
  # Keep the resolved checkout in the workspace so apply-susfs.sh can reuse it.
  # The old flow cloned GitLab once here and then cloned it a second time in
  # apply-susfs.sh; a transient GitLab 503 during that second clone aborted CI.
  susfs_source_dir="${PWD}/susfs4ksu"
  rm -rf "${susfs_source_dir}"

  clone_ok=false
  for attempt in 1 2 3 4 5; do
    echo "SUSFS: cloning ${SUSFS_REPO} (attempt ${attempt}/5)"
    if git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 \
      clone --filter=blob:none --no-checkout "${SUSFS_REPO}" "${susfs_source_dir}"; then
      clone_ok=true
      break
    fi
    rm -rf "${susfs_source_dir}"
    if [[ "${attempt}" -lt 5 ]]; then
      delay=$((attempt * 6))
      echo "SUSFS: clone failed; retrying in ${delay}s (transient HTTP 5xx/network errors are retried)"
      sleep "${delay}"
    fi
  done

  if [[ "${clone_ok}" != "true" ]]; then
    echo "::error::Could not clone SUSFS after 5 attempts from ${SUSFS_REPO}. This may be a temporary GitLab outage (for example HTTP 503). Re-run the workflow later, or disable Enable SUSFS for an image-only build."
    exit 1
  fi

  if ! git -C "${susfs_source_dir}" checkout "${susfs_requested_ref}"; then
    echo "::error::SUSFS ref ${susfs_requested_ref} was not found in ${SUSFS_REPO}"
    exit 1
  fi
  # Accept a branch/tag too: pin to the exact commit so cache keys and logs stay reproducible.
  susfs_commit="$(git -C "${susfs_source_dir}" rev-parse HEAD)"
  susfs_repo_used="$(git -C "${susfs_source_dir}" remote get-url origin)"
  susfs_reported_version="$(
    find "${susfs_source_dir}/kernel_patches" -path '*/include/linux/susfs.h' -type f -print0 2>/dev/null |
      xargs -0 -r grep -hoE 'SUSFS_VERSION[[:space:]]+"v[0-9]+\.[0-9]+\.[0-9]+"' 2>/dev/null |
      head -n1 |
      sed -E 's/.*"(v[^"]+)".*/\1/' || true
  )"

  susfs_url="https://gitlab.com/simonpunk/susfs4ksu/-/commit/${susfs_commit}"
fi

ENABLE_NOMOUNT="${ENABLE_NOMOUNT:-false}"
nomount_commit=""

if [[ "${ENABLE_NOMOUNT}" == "true" ]]; then
  nomount_commit="$(git ls-remote "https://github.com/${NOMOUNT_REPO}.git" \
    "refs/heads/${NOMOUNT_REF}" "refs/tags/${NOMOUNT_REF}^{}" "refs/tags/${NOMOUNT_REF}" |
    awk 'NR == 1 { print $1 }')"
  if [[ -z "${nomount_commit}" && "${NOMOUNT_REF}" =~ ^[0-9a-fA-F]{40}$ ]]; then
    nomount_commit="${NOMOUNT_REF}"
  fi
  if [[ -z "${nomount_commit}" ]]; then
    echo "::error::Could not resolve NoMount ref ${NOMOUNT_REPO}@${NOMOUNT_REF}"
    exit 1
  fi
fi

{
  echo "source_commit=${source_commit}"
  echo "manager=${MANAGER}"
  echo "manager_repo=${manager_repo}"
  echo "manager_ref=${manager_effective_ref}"
  echo "manager_commit=${manager_commit}"
  echo "manager_tag=${manager_tag}"
  echo "manager_setup_path=${manager_setup_path}"
  echo "enable_susfs=${ENABLE_SUSFS}"
  echo "susfs_kernel_branch=${SUSFS_KERNEL_BRANCH}"
  echo "susfs_commit=${susfs_commit}"
  echo "susfs_reported_version=${susfs_reported_version}"
  echo "susfs_url=${susfs_url}"
  echo "susfs_repo_used=${susfs_repo_used:-}"
  echo "susfs_source_dir=${susfs_source_dir:-}"
  echo "enable_nomount=${ENABLE_NOMOUNT}"
  echo "nomount_repo=${NOMOUNT_REPO:-}"
  echo "nomount_ref=${NOMOUNT_REF:-}"
  echo "nomount_commit=${nomount_commit}"
} | tee release/resolved-refs.env
