#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${PROJECT_ROOT:-$(pwd)}"
SCHEME_NAME="${SCHEME_NAME:?Set SCHEME_NAME to the Xcode scheme you want to build}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-generic/platform=iOS Simulator}"
SOURCE_DIR="${SOURCE_DIR:-${SCHEME_NAME}}"
WORKSPACE_PATH="${WORKSPACE_PATH:-${SCHEME_NAME}.xcworkspace}"
PROJECT_PATH="${PROJECT_PATH:-}"
OBFUSCATION_SEED="${OBFUSCATION_SEED:-${SCHEME_NAME}-${CONFIGURATION}}"
OBFUSCATION_EXCLUDES="${OBFUSCATION_EXCLUDES:-}"
OBFUSCATION_WORK_ROOT="${OBFUSCATION_WORK_ROOT:-${TMPDIR:-/tmp}/ork-swift-new}"
TOOL_PACKAGE_DIR="${TOOL_PACKAGE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

mkdir -p "${OBFUSCATION_WORK_ROOT}"
WORK_DIR="$(mktemp -d "${OBFUSCATION_WORK_ROOT}/${SCHEME_NAME}.XXXXXX")"
MANIFEST_PATH="${WORK_DIR}/obfuscation-manifest.json"

cleanup() {
    if [[ "${KEEP_OBFUSCATION_WORKDIR:-0}" != "1" ]]; then
        rm -rf "${WORK_DIR}"
    fi
}
trap cleanup EXIT

rsync -a --delete \
    --exclude ".git" \
    --exclude "DerivedData" \
    --exclude "DerivedData*" \
    --exclude "build" \
    --exclude "tmp" \
    "${ROOT_DIR}/" \
    "${WORK_DIR}/"

EXCLUDE_ARGS=()
if [[ -n "${OBFUSCATION_EXCLUDES}" ]]; then
    while IFS= read -r pattern; do
        [[ -z "${pattern}" ]] && continue
        EXCLUDE_ARGS+=(--exclude "${pattern}")
    done <<< "${OBFUSCATION_EXCLUDES}"
fi

if [[ -n "${TOOL_BIN:-}" ]]; then
    OBFUSCATOR=("${TOOL_BIN}")
else
    OBFUSCATOR=(swift run --package-path "${TOOL_PACKAGE_DIR}" -c release ork-swift-new)
fi

"${OBFUSCATOR[@]}" \
    --input "${WORK_DIR}/${SOURCE_DIR}" \
    --in-place \
    --rename-files \
    --rename-private-functions \
    --seed "${OBFUSCATION_SEED}" \
    --manifest "${MANIFEST_PATH}" \
    "${EXCLUDE_ARGS[@]}"

BUILD_ARGS=(-scheme "${SCHEME_NAME}" -configuration "${CONFIGURATION}" -destination "${DESTINATION}")
if [[ -d "${WORK_DIR}/${WORKSPACE_PATH}" ]]; then
    BUILD_ARGS=(-workspace "${WORK_DIR}/${WORKSPACE_PATH}" "${BUILD_ARGS[@]}")
elif [[ -n "${PROJECT_PATH}" && -d "${WORK_DIR}/${PROJECT_PATH}" ]]; then
    BUILD_ARGS=(-project "${WORK_DIR}/${PROJECT_PATH}" "${BUILD_ARGS[@]}")
elif [[ -d "${WORK_DIR}/${SCHEME_NAME}.xcodeproj" ]]; then
    BUILD_ARGS=(-project "${WORK_DIR}/${SCHEME_NAME}.xcodeproj" "${BUILD_ARGS[@]}")
else
    echo "Could not find workspace or project in copied work directory: ${WORK_DIR}" >&2
    exit 1
fi

echo "Obfuscated workspace: ${WORK_DIR}"
echo "Manifest: ${MANIFEST_PATH}"
xcodebuild "${BUILD_ARGS[@]}" build
