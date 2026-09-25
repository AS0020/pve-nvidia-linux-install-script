#!/usr/bin/env bash
# ==============================================================================
# NVIDIA Driver Clean Install für Proxmox VE, Ubuntu-Hosts sowie Debian/Ubuntu-LXC
# Version: 2.13.3
#
# Unterstützte NVIDIA-Versionen:
# Versionen werden dynamisch aus dem offiziellen NVIDIA-APT-Repository erkannt.
# 610.43.02 und 595.71.05 bleiben nur als Menue-Fallbacks hinterlegt.
#
# Host (Proxmox VE oder Ubuntu):
#   - bereinigt den bisherigen NVIDIA-Treiberstack
#   - installiert Kernel-Header, DKMS und den Compute-only-Treiber
#   - erkennt GPU-Generation und wählt das passende Kernelmodul automatisch
#   - kann mehrere GPUs per UUID/PCI-Adresse über native devN-Einträge durchreichen
#
# LXC (Debian oder Ubuntu):
#   - bereinigt alte NVIDIA-Userspace-Bibliotheken und falsche DKMS-Pakete
#   - installiert ausschließlich explizite Userspace-Bibliotheken und Werkzeuge
#
# Sicherheit:
#   - echter schreibgeschützter Dry-Run und transaktionaler Rollback
#   - exakter Versions-/Repository-Abgleich und automatische Fehlerdiagnose
#
# Update (Menü 12/13): vorhandenen Stack ohne pauschale Neuinstallation
# aktualisieren und vollständig pinnen. Menü 14 simuliert dieses Update.
#
# Bei einer vollständigen Neuinstallation werden alle paketverwalteten
# NVIDIA-/CUDA-/Container-Toolkit-Komponenten inventarisiert, gesichert und
# entfernt. Treibergebundene Komponenten werden eindeutig auf den Zielzweig
# abgebildet; unabhängige Komponenten werden aus ihrem exakten Original-DEB
# neu installiert. Im LXC bleiben Kernel-/DKMS-Pakete und Host-Hilfsprogramme
# wie nvidia-modprobe strikt ausgeschlossen.
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'
# Maschinenlesbare Ausgaben von apt, dkms und pciutils dürfen nicht von der
# Systemsprache abhängen. Die eigenen deutschen Meldungen bleiben unverändert.
export LC_ALL=C

SCRIPT_VERSION="2.13.3"
RESUME_SCHEMA_CURRENT=2
PENDING_SCHEMA_CURRENT=3
REQUESTED_VERSION="auto"
MODE="auto"
KERNEL_FLAVOR="auto"
FIX_MICROSOFT_CONFLICT=0
ASSUME_YES=0
CHECK_ONLY=0
ATTACH_ONLY=0
DRY_RUN=0
DIAGNOSE_ALL=0
ROLLBACK_REQUEST=""
RESUME_REQUEST=0
UNINSTALL_REQUEST=0
CLEANUP_BACKUPS_REQUEST=0
FINALIZE_PENDING_REQUEST=""
KEEP_SUCCESS_BACKUP=0
DELETE_SUCCESS_LOGS=1
SUCCESS_BACKUP_CLEANUP_BLOCKED=0
SUCCESS_BACKUP_REMOVED=0
SUCCESS_LOG_REMOVED=0
TRANSCODE_SMOKE_TEST="auto"
TRANSCODE_SMOKE_RESOLUTION="640x360"
TRANSCODE_SMOKE_SOURCE="testsrc2=size=${TRANSCODE_SMOKE_RESOLUTION}:rate=10"
NVTOP_MANAGEMENT="auto"
NVTOP_TEST_STATUS="nicht geprüft"
NVTOP_TEST_DETAIL=""
GPU_CONSUMER_POLICY="abort"
STOPPED_GPU_CONSUMERS=()
INITIAL_APT_AUTOREMOVE=0
FINAL_APT_AUTOREMOVE=1
AUTOMATIC_REPAIR=1
REPAIR_ONLY_REQUEST=0
UPDATE_ONLY=0
NVIDIA_UPDATE_NEEDED=0
NVIDIA_UPDATE_SPECS=()
NVIDIA_UPDATE_REMOVALS=()
NVIDIA_UPDATE_APT_OPTIONS=()
NVIDIA_UPDATE_APPROVED_PLAN=""
CLEAN_INSTALL_SCOPE="full"
MACHINE_READABLE_RESULT=0
MACHINE_RESULT_EMITTED=0
LAST_ROLLBACK_STATUS="not-needed"
ROLLBACK_COVERAGE="exact"
REPAIR_OUTCOME="not-run"
REPAIR_ACTIONS=()
REPAIR_UNRESOLVED=()
APT_POLICY_ENFORCE_TARGET_VERSION=1
BOOTSTRAP_APT_OPTIONS=()
CLEAN_APT_OPTIONS=()
CLEAN_REMOVE_PACKAGES=()
ROLLBACK_READY=0
ROLLBACK_IN_PROGRESS=0
MUTATION_STARTED=0
PACKAGE_MUTATION_ALLOWED=0
CONFIG_MUTATION_ALLOWED=0
TRANSACTION_FINISHED=0
GLOBAL_LOCK_ACQUIRED=0
EXPECTED_HOST_VERSION=""
CONFIGURE_LXC_GPU=0
INSTALL_LXC_USERSPACE_FROM_HOST=0
HOST_LXC_OPERATION=0
TARGET_LXC_ID=""
TARGET_LXC_NAME=""
TARGET_GPU_DEVICE="auto"
TARGET_GPU_UUID=""
TARGET_GPU_BUS_ID=""
LXC_DEVICE_MODE="inherit"
LXC_DEVICE_UID=""
LXC_DEVICE_GID="44"
LXC_DEVICE_BACKEND="auto"
DEVICE_PERMISSIONS_EXPLICIT=0
LXC_SMI_PAYLOAD_DEB=""
LXC_SMI_PAYLOAD_VERSION=""
TARGET_GPU_SELECTORS=()
TARGET_GPU_DEVICES=()
TARGET_GPU_UUIDS=()
TARGET_GPU_BUS_IDS=()
TARGET_GPU_SELECTION_SUMMARY="automatisch"
LXC_GPU_CONFIGURED=0
LXC_GPU_DEFERRED=0
LXC_USERSPACE_CONFIGURED=0
LXC_USERSPACE_DEFERRED=0
LXC_TEMPORARY_START_ALLOWED=0
LXC_RESTART_RUNNING_ALLOWED=0
LXC_ORIGINAL_STATE=""
LXC_RUNTIME_TOUCHED=0
LXC_DEVICE_SYNC_RESTART_DONE=0
LXC_REMOTE_SCRIPT_PENDING=0
LXC_REMOTE_SCRIPT_PATH="/root/.nvidia-driver-setup-host-managed-${SCRIPT_VERSION}-$$.sh"
LXC_REMOTE_SUCCESS_BACKUP=""
LXC_REMOTE_BACKUP_CLEANUP_PENDING=0
LXC_REMOTE_RESULT=""
PENDING_LXC_STARTED_BY_FINALIZER=0
REBOOT_REQUIRED=0
REBOOT_REASONS=()
PIN_NVIDIA_PACKAGES=0
PIN_CHOICE_EXPLICIT=0
BACKUP_ROOT="/opt/nvidia-backup"
BACKUP_RETENTION_DAYS=30
COMPLETION_REPORT_ROOT="/var/log/nvidia-driver-setup"
COMPLETION_REPORT_FILE=""
INSTALL_LOG_FILE=""
INSTALL_LOG_ACTIVE=0
ORIGINAL_COMMAND_ARGS=()
ACTIVE_TRANSACTION_FILE="/opt/nvidia-backup/.active-transaction"
TRANSACTION_ACTION="install"
RESUME_SOURCE_BACKUP=""
INTERRUPTED_TRANSACTION_PENDING=0
DIAGNOSTIC_ERROR_COUNT=0
TEMPORARY_VERSION_PREFERENCE=""
PENDING_VERIFICATION_REASONS=()

TARGET_VERSION=""
DISTRO=""
OS_ID=""
OS_VERSION_ID=""
OS_LABEL=""
IS_PROXMOX_HOST=0
BACKUP_DIR=""
TMP_DIR=""
APT_SOURCE_FILES=()
BASELINE_AUTOREMOVE=()
NVIDIA_HOLDS=()
NVIDIA_DRIVER_REGEX='^((cuda-drivers)|firmware-nvidia-gsp|lib(cuda|cudadebugger|nvcuvid)[0-9]*|lib(egl|gl|gles|glx)[0-9]*-nvidia[^:]*|libnvidia-(allocator|api|cfg|common|compute|decode|eglcore|encode|extra|fbc|gl|glcore|glvkspirv|gpucomp|ml|ngx|nscq|nvvm|opticalflow|pkcs11-openssl|present|ptxjitcompiler|rtcore|sandboxutils|tileiras|vksc-core)[0-9]*|libnvoptix[0-9]*|libnvsdm[0-9]*|libxnvctrl[0-9]*|linux-(modules|objects|signatures)-nvidia|nvidia-(alternative|compute-utils|detect|dkms|driver|egl-common|egl-icd|fabricmanager|firmware|headless|imex|kernel|legacy|modprobe|open|opencl|persistenced|powerd|settings|smi|support|suspend-common|utils|vaapi-driver|vdpau-driver|vulkan|xconfig)|xserver-xorg-video-nvidia)([-:].*)?$'
NVIDIA_AUXILIARY_REGEX='^((cuda(:.*)?|cuda-[0-9]+-[0-9]+(:.*)?|cuda-(compat|mps|cccl|command-line-tools|compiler|cudart|cuobjdump|cupti|cuxxfilt|demo-suite|documentation|gdb|libraries|minimal-build|nvcc|nvdisasm|nvml-dev|nvprof|nvprune|nvrtc|nvtx|opencl|profiler-api|runtime|sanitizer|toolkit|tools|visual-tools)([-:].*)?)|(lib(accinj|cublas|cudart|cudadevrt|cudnn|cufft|cufile|cuinj|curand|cusolver|cusparse|cupti|npp|nvblas|nvfatbin|nvjitlink|nvjpeg|nvrtc|nvtoolsext|nccl)[0-9A-Za-z+_.:-]*)|(nsight-[A-Za-z0-9+_.:-]+)|(nvidia-(cuda|profiler|visual-profiler|openjdk|nsight)([-:].*)?)|(libnvidia-container[0-9A-Za-z+_.:-]*)|(nvidia-container-(runtime|toolkit)([-:].*)?)|(nvidia-docker2([:-].*)?))$'
NVIDIA_REPOSITORY_PACKAGE_REGEX='^(cuda-keyring(:.*)?|cuda-repo-|nvidia-driver-local-repo-)'
NVIDIA_OPTIONAL_DRIVER_REGEX='^((cuda-drivers)|libnvidia-(fbc|opticalflow|ngx|nscq|rtcore|pkcs11-openssl)[0-9]*|libnvoptix[0-9]*|libnvsdm|libxnvctrl[0-9]*|nvidia-(driver|headless|fabricmanager|imex|opencl|powerd|settings|support|vaapi-driver|vdpau-driver|vulkan|xconfig)|xserver-xorg-video-nvidia)([-:].*)?$'
NVIDIA_INDEPENDENT_OPTIONAL_REGEX='^(nvidia-(detect|settings|support|vaapi-driver)(:.*)?|libxnvctrl[0-9]*(:.*)?)$'
LXC_FORBIDDEN_KERNEL_REGEX='^((linux-(modules|objects|signatures)-nvidia)([-:].*)?|nvidia-(dkms|kernel|headless|open)([-:].*)?|nvidia-driver(:.*)?|nvidia-driver-(cuda|[0-9][0-9A-Za-z.+-]*)(:.*)?|cuda(:.*)?|cuda-[0-9]+-[0-9]+(:.*)?|cuda-(drivers|runtime)([-:].*)?)$'
LXC_FORBIDDEN_HOST_UTILITY_REGEX='^(nvidia-(fabricmanager|imex|modprobe|persistenced|powerd|suspend-common)([-:].*)?)$'
LXC_FORBIDDEN_PACKAGE_REGEX='^((linux-(modules|objects|signatures)-nvidia)([-:].*)?|nvidia-(dkms|kernel|headless|open)([-:].*)?|nvidia-driver(:.*)?|nvidia-driver-(cuda|[0-9][0-9A-Za-z.+-]*)(:.*)?|cuda(:.*)?|cuda-[0-9]+-[0-9]+(:.*)?|cuda-(drivers|runtime)([-:].*)?|nvidia-(fabricmanager|imex|modprobe|persistenced|powerd|suspend-common)([-:].*)?)$'
PROFILE_USERSPACE_PACKAGES=()
PREFLIGHT_DRIVER_PACKAGES=()
VERIFY_USERSPACE_PACKAGES=()
VERIFY_HOST_PACKAGES=()
AUXILIARY_PACKAGES=()
AUXILIARY_REINSTALL_DEBS=()
OPTIONAL_DRIVER_TARGET_PACKAGES=()
OPTIONAL_DRIVER_REINSTALL_DEBS=()
VERIFY_OPTIONAL_DRIVER_PACKAGES=()

DETECTED_GPU_MODELS=()
DETECTED_GPU_PCI_IDS=()
DETECTED_GPU_SUMMARY="nicht erkannt"
DETECTED_GPU_GENERATIONS=()
DETECTED_HOST_MODULE_VERSION=""
DETECTED_HOST_MODULE_SOURCE=""
DETECTED_HOST_MODULE_LOADED=0
DETECTED_PACKAGE_VERSION=""
DETECTED_PACKAGE_DEBIAN_VERSION=""
DETECTED_INSTALLED_MODULE_VERSION=""
DETECTED_SMI_VERSION=""
DETECTED_VERSION_STATE="nicht geprüft"
RECOMMENDED_VERSION=""
RECOMMENDED_KERNEL="open"
RECOMMENDATION_REASON=""
GPU_COMPATIBILITY="unknown"
NVIDIA_PERSISTENCED_WAS_ACTIVE=0
NVIDIA_HOLDS_RELEASED=0
declare -A EXPECTED_PACKAGE_VERSIONS=()
AVAILABLE_DRIVER_VERSIONS=()
BUILTIN_DRIVER_VERSIONS=(610.43.02 595.71.05)

# ------------------------------- Ausgabe -------------------------------------
log()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }

persistent_install_log_requested() {
    ((CHECK_ONLY == 0 && DRY_RUN == 0 && CLEANUP_BACKUPS_REQUEST == 0))
}

persistent_install_log_action() {
    if [[ -n "${ROLLBACK_REQUEST:-}" ]]; then
        printf 'rollback'
    elif [[ -n "${FINALIZE_PENDING_REQUEST:-}" ]]; then
        printf 'abschlusspruefung'
    elif ((ATTACH_ONLY)); then
        printf 'lxc-gpu-freigabe'
    else
        printf '%s' "${TRANSACTION_ACTION:-aktion}"
    fi
}

strip_terminal_colors() {
    sed -u $'s/\033\\[[0-9;]*[mK]//g'
}

start_persistent_install_log() {
    local timestamp action role owner command_part

    ((INSTALL_LOG_ACTIVE == 0)) || return 0
    command -v tee >/dev/null 2>&1 || return 1
    command -v sed >/dev/null 2>&1 || return 1
    if [[ -L "$COMPLETION_REPORT_ROOT" \
          || (-e "$COMPLETION_REPORT_ROOT" && ! -d "$COMPLETION_REPORT_ROOT") ]]; then
        return 1
    fi
    mkdir -p -- "$COMPLETION_REPORT_ROOT" || return 1
    [[ -d "$COMPLETION_REPORT_ROOT" && ! -L "$COMPLETION_REPORT_ROOT" ]] || return 1
    owner="$(stat -c '%u' "$COMPLETION_REPORT_ROOT" 2>/dev/null || true)"
    [[ "$owner" == "$EUID" ]] || return 1
    chmod 0750 "$COMPLETION_REPORT_ROOT" || return 1

    timestamp="$(date +%Y%m%d-%H%M%S)"
    action="$(persistent_install_log_action)"
    role="${MODE:-auto}"
    [[ "$role" != "auto" ]] || role="${MENU_DETECTED_MODE:-auto}"
    action="${action//[^A-Za-z0-9._-]/-}"
    role="${role//[^A-Za-z0-9._-]/-}"
    INSTALL_LOG_FILE="$COMPLETION_REPORT_ROOT/installationslog-${timestamp}-${action}-${role}-pid$$"
    [[ -z "${TARGET_LXC_ID:-}" ]] || INSTALL_LOG_FILE+="-lxc-${TARGET_LXC_ID}"
    INSTALL_LOG_FILE+=".log"
    (umask 077; : >"$INSTALL_LOG_FILE") || { INSTALL_LOG_FILE=""; return 1; }
    chmod 0600 "$INSTALL_LOG_FILE" || { INSTALL_LOG_FILE=""; return 1; }

    # Das Terminal behält seine Farben; im dauerhaften Protokoll werden nur
    # ANSI-Steuerfolgen entfernt. stdout und stderr bleiben zeitlich zusammen.
    exec > >(tee >(strip_terminal_colors >>"$INSTALL_LOG_FILE")) 2>&1
    INSTALL_LOG_ACTIVE=1

    printf '\nNVIDIA-DRIVER-SETUP – GESAMTPROTOKOLL\n'
    printf '%s\n' '======================================================================'
    printf 'Start:          %s\n' "$(date --iso-8601=seconds)"
    printf 'Skriptversion:  %s\n' "$SCRIPT_VERSION"
    printf 'Aktion:         %s\n' "$action"
    printf 'Rolle:          %s\n' "$role"
    printf 'System:         %s\n' "${OS_LABEL:-noch nicht bestimmt}"
    printf 'Protokoll:      %s\n' "$INSTALL_LOG_FILE"
    printf 'Aufruf:'
    printf ' %q' "$0"
    for command_part in "${ORIGINAL_COMMAND_ARGS[@]}"; do
        printf ' %q' "$command_part"
    done
    printf '\n%s\n\n' '======================================================================'
    ok "Dauerhaftes Gesamtprotokoll aktiviert: $INSTALL_LOG_FILE"
}

is_safe_backup_dir() {
    local path="${1:-}" canonical root_canonical
    [[ -n "$path" && "$path" == "$BACKUP_ROOT"/nvidia-* && -d "$path" && ! -L "$path" ]] \
        || return 1
    canonical="$(readlink -f -- "$path" 2>/dev/null || true)"
    root_canonical="$(readlink -f -- "$BACKUP_ROOT" 2>/dev/null || true)"
    [[ -n "$canonical" && -n "$root_canonical" \
       && "$canonical" == "$root_canonical"/nvidia-* \
       && "$(dirname -- "$canonical")" == "$root_canonical" ]]
}

acquire_global_lock() {
    ((GLOBAL_LOCK_ACQUIRED == 0)) || return 0
    command -v flock >/dev/null 2>&1 \
        || die "flock fehlt; ohne globale Sperre wird keine Aktion ausgeführt."
    if [[ $EUID -eq 0 ]]; then
        mkdir -p /run/lock
        exec 9>/run/lock/nvidia-driver-setup.lock
    else
        exec 9>"${XDG_RUNTIME_DIR:-/tmp}/nvidia-driver-setup-${UID}.lock"
    fi
    flock -n 9 || die "Eine andere Instanz dieses Skripts läuft bereits."
    GLOBAL_LOCK_ACQUIRED=1
}

ensure_backup_root() {
    [[ $EUID -eq 0 ]] || die "Sicherungen unter $BACKUP_ROOT erfordern root."
    mkdir -p "$BACKUP_ROOT"
    chmod 0700 "$BACKUP_ROOT"
}

create_backup_dir() {
    local kind="$1" timestamp
    ensure_backup_root
    timestamp="$(date +%Y%m%d-%H%M%S)"
    umask 077
    BACKUP_DIR="$(mktemp -d "$BACKUP_ROOT/nvidia-${kind}-${timestamp}-XXXXXX")"
    chmod 0700 "$BACKUP_DIR"
}

refresh_backup_checksums() {
    local temporary
    is_safe_backup_dir "${BACKUP_DIR:-}" || return 1
    temporary="$(mktemp "$BACKUP_DIR/.backup-checksums.XXXXXX")" || return 1
    (
        cd "$BACKUP_DIR"
        while IFS= read -r -d '' file; do
            sha256sum "$file"
        done < <(
            find . -type f \
                ! -name 'backup-checksums.sha256' \
                ! -name 'transaction-status' \
                ! -name '*.log' \
                ! -name '*-after.txt' \
                ! -name '*-after-current' \
                ! -name '.backup-checksums.*' \
                -print0 | sort -z
        ) >"$temporary"
    ) || { rm -f -- "$temporary"; return 1; }
    [[ -s "$temporary" ]] || { rm -f -- "$temporary"; return 1; }
    mv -f -- "$temporary" "$BACKUP_DIR/backup-checksums.sha256" \
        || { rm -f -- "$temporary"; return 1; }
}

verify_backup_checksums() {
    local directory="$1"
    is_safe_backup_dir "$directory" \
        || { warn "Unsicheres Sicherungsverzeichnis: $directory"; return 1; }
    [[ -s "$directory/backup-checksums.sha256" ]] \
        || { warn "Prüfsummenmanifest fehlt: $directory/backup-checksums.sha256"; return 1; }
    (cd "$directory" && sha256sum -c --quiet backup-checksums.sha256) \
        && verify_no_unmanifested_package_payloads "$directory"
}

verify_no_unmanifested_package_payloads() {
    local directory="$1" payload relative
    local payload_dir

    for payload_dir in rollback-debs full-reinstall-debs optional-driver-reinstall-debs lxc-smi-payload; do
        [[ -d "$directory/$payload_dir" ]] || continue
        while IFS= read -r -d '' payload; do
            relative=".${payload#"$directory"}"
            awk -v expected="$relative" '$2 == expected { found = 1 } END { exit !found }' \
                "$directory/backup-checksums.sha256" || {
                warn "Nicht im Prüfsummenmanifest erfasste Paketdatei: $payload"
                return 1
            }
        done < <(find "$directory/$payload_dir" -maxdepth 1 -type f -name '*.deb' -print0 2>/dev/null || true)
    done
    return 0
}

write_transaction_phase() {
    local phase="$1"
    [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]] || return 0
    printf '%s\t%s\n' "$(date --iso-8601=seconds)" "$phase" >"$BACKUP_DIR/transaction-status"
}

write_resume_state() {
    local resume_file temporary_file
    is_safe_backup_dir "${BACKUP_DIR:-}" || return 1
    resume_file="$BACKUP_DIR/resume.env"
    temporary_file="$(mktemp "${resume_file}.tmp.XXXXXX")" || return 1
    if ! {
        printf 'RESUME_SCHEMA_VERSION=%q\n' "$RESUME_SCHEMA_CURRENT"
        printf 'RESUME_SCRIPT_VERSION=%q\n' "$SCRIPT_VERSION"
        printf 'REQUESTED_VERSION=%q\n' "$REQUESTED_VERSION"
        printf 'MODE=%q\n' "$MODE"
        printf 'KERNEL_FLAVOR=%q\n' "$KERNEL_FLAVOR"
        printf 'FIX_MICROSOFT_CONFLICT=%q\n' "$FIX_MICROSOFT_CONFLICT"
        printf 'EXPECTED_HOST_VERSION=%q\n' "$EXPECTED_HOST_VERSION"
        printf 'CONFIGURE_LXC_GPU=%q\n' "$CONFIGURE_LXC_GPU"
        printf 'INSTALL_LXC_USERSPACE_FROM_HOST=%q\n' "$INSTALL_LXC_USERSPACE_FROM_HOST"
        printf 'HOST_LXC_OPERATION=%q\n' "$HOST_LXC_OPERATION"
        printf 'TARGET_LXC_ID=%q\n' "$TARGET_LXC_ID"
        printf 'LXC_DEVICE_MODE=%q\n' "$LXC_DEVICE_MODE"
        printf 'LXC_DEVICE_UID=%q\n' "$LXC_DEVICE_UID"
        printf 'LXC_DEVICE_GID=%q\n' "$LXC_DEVICE_GID"
        printf 'LXC_DEVICE_BACKEND=%q\n' "$LXC_DEVICE_BACKEND"
        printf 'LXC_TEMPORARY_START_ALLOWED=%q\n' "$LXC_TEMPORARY_START_ALLOWED"
        printf 'LXC_RESTART_RUNNING_ALLOWED=%q\n' "$LXC_RESTART_RUNNING_ALLOWED"
        printf 'LXC_ORIGINAL_STATE=%q\n' "$LXC_ORIGINAL_STATE"
        printf 'LXC_RUNTIME_TOUCHED=%q\n' "$LXC_RUNTIME_TOUCHED"
        printf 'LXC_DEVICE_SYNC_RESTART_DONE=%q\n' "$LXC_DEVICE_SYNC_RESTART_DONE"
        printf 'LXC_REMOTE_SCRIPT_PENDING=%q\n' "$LXC_REMOTE_SCRIPT_PENDING"
        printf 'LXC_REMOTE_SCRIPT_PATH=%q\n' "$LXC_REMOTE_SCRIPT_PATH"
        printf 'LXC_REMOTE_SUCCESS_BACKUP=%q\n' "$LXC_REMOTE_SUCCESS_BACKUP"
        printf 'LXC_REMOTE_BACKUP_CLEANUP_PENDING=%q\n' "$LXC_REMOTE_BACKUP_CLEANUP_PENDING"
        printf 'LXC_REMOTE_RESULT=%q\n' "$LXC_REMOTE_RESULT"
        printf 'PIN_NVIDIA_PACKAGES=%q\n' "$PIN_NVIDIA_PACKAGES"
        printf 'TRANSACTION_ACTION=%q\n' "$TRANSACTION_ACTION"
        printf 'ATTACH_ONLY=%q\n' "$ATTACH_ONLY"
        printf 'UNINSTALL_REQUEST=%q\n' "$UNINSTALL_REQUEST"
        printf 'KEEP_SUCCESS_BACKUP=%q\n' "$KEEP_SUCCESS_BACKUP"
        printf 'DELETE_SUCCESS_LOGS=%q\n' "$DELETE_SUCCESS_LOGS"
        printf 'TRANSCODE_SMOKE_TEST=%q\n' "$TRANSCODE_SMOKE_TEST"
        printf 'NVTOP_MANAGEMENT=%q\n' "$NVTOP_MANAGEMENT"
        printf 'GPU_CONSUMER_POLICY=%q\n' "$GPU_CONSUMER_POLICY"
        printf 'STOPPED_GPU_CONSUMERS=('
        ((${#STOPPED_GPU_CONSUMERS[@]} == 0)) || printf ' %q' "${STOPPED_GPU_CONSUMERS[@]}"
        printf ' )\n'
        printf 'INITIAL_APT_AUTOREMOVE=%q\n' "$INITIAL_APT_AUTOREMOVE"
        printf 'FINAL_APT_AUTOREMOVE=%q\n' "$FINAL_APT_AUTOREMOVE"
        printf 'AUTOMATIC_REPAIR=%q\n' "$AUTOMATIC_REPAIR"
        printf 'REPAIR_ONLY_REQUEST=%q\n' "$REPAIR_ONLY_REQUEST"
        printf 'UPDATE_ONLY=%q\n' "$UPDATE_ONLY"
        printf 'REPAIR_OUTCOME=%q\n' "$REPAIR_OUTCOME"
        printf 'REPAIR_ACTIONS=('; ((${#REPAIR_ACTIONS[@]} == 0)) || printf ' %q' "${REPAIR_ACTIONS[@]}"; printf ' )\n'
        printf 'REPAIR_UNRESOLVED=('; ((${#REPAIR_UNRESOLVED[@]} == 0)) || printf ' %q' "${REPAIR_UNRESOLVED[@]}"; printf ' )\n'
        printf 'CLEAN_INSTALL_SCOPE=%q\n' "$CLEAN_INSTALL_SCOPE"
        printf 'ROLLBACK_COVERAGE=%q\n' "$ROLLBACK_COVERAGE"
        printf 'BACKUP_RETENTION_DAYS=%q\n' "$BACKUP_RETENTION_DAYS"
        printf 'NVIDIA_PERSISTENCED_WAS_ACTIVE=%q\n' "$NVIDIA_PERSISTENCED_WAS_ACTIVE"
        printf 'TEMPORARY_VERSION_PREFERENCE=%q\n' "$TEMPORARY_VERSION_PREFERENCE"
        printf 'TARGET_GPU_SELECTORS=('; printf ' %q' "${TARGET_GPU_SELECTORS[@]}"; printf ' )\n'
        printf 'TARGET_GPU_UUIDS=('; printf ' %q' "${TARGET_GPU_UUIDS[@]}"; printf ' )\n'
        printf 'TARGET_GPU_BUS_IDS=('; printf ' %q' "${TARGET_GPU_BUS_IDS[@]}"; printf ' )\n'
    } >"$temporary_file"; then
        rm -f -- "$temporary_file"
        return 1
    fi
    chmod 0600 "$temporary_file" || { rm -f -- "$temporary_file"; return 1; }
    mv -f -- "$temporary_file" "$resume_file" \
        || { rm -f -- "$temporary_file"; return 1; }
}

load_resume_state_file() {
    local resume_file="$1" schema
    [[ -r "$resume_file" ]] || return 1

    # Sichere Migration alter Sicherungen: Fehlte der Umfang, darf ein neuer
    # globaler Standard den früheren Vorgang niemals auf CUDA/Container erweitern.
    RESUME_SCHEMA_VERSION=""
    RESUME_SCRIPT_VERSION=""
    CLEAN_INSTALL_SCOPE="driver"
    ROLLBACK_COVERAGE="exact"
    DELETE_SUCCESS_LOGS=1
    UPDATE_ONLY=0
    FINAL_APT_AUTOREMOVE=1
    TARGET_GPU_SELECTORS=()
    TARGET_GPU_UUIDS=()
    TARGET_GPU_BUS_IDS=()
    # shellcheck disable=SC1090
    source "$resume_file"
    [[ "${TRANSACTION_ACTION:-}" != update && "${TRANSACTION_ACTION:-}" != lxc-update ]] || UPDATE_ONLY=1
    schema="${RESUME_SCHEMA_VERSION:-0}"
    case "$schema" in
        0)
            grep -q '^CLEAN_INSTALL_SCOPE=' "$resume_file" || CLEAN_INSTALL_SCOPE="driver"
            ;;
        1)
            [[ -n "$RESUME_SCRIPT_VERSION" ]] || {
                warn "Fortsetzungszustand enthält keine Skriptversion."
                return 1
            }
            ;;
        "$RESUME_SCHEMA_CURRENT")
            local required_field
            for required_field in \
                RESUME_SCHEMA_VERSION RESUME_SCRIPT_VERSION CLEAN_INSTALL_SCOPE \
                ROLLBACK_COVERAGE TARGET_GPU_SELECTORS TARGET_GPU_UUIDS \
                TARGET_GPU_BUS_IDS; do
                grep -q "^${required_field}=" "$resume_file" || {
                    warn "Fortsetzungszustand ist unvollständig: $required_field fehlt."
                    return 1
                }
            done
            [[ -n "$RESUME_SCRIPT_VERSION" ]] || {
                warn "Fortsetzungszustand enthält keine Skriptversion."
                return 1
            }
            ;;
        *)
            warn "Nicht unterstütztes Fortsetzungsformat: ${schema:-leer}"
            return 1
            ;;
    esac
    case "$CLEAN_INSTALL_SCOPE" in full|driver) ;; *)
        warn "Ungültiger Neuinstallationsumfang im Fortsetzungszustand: $CLEAN_INSTALL_SCOPE"
        return 1
    esac
    case "$ROLLBACK_COVERAGE" in exact|normalized) ;; *)
        warn "Ungültige Rollback-Abdeckung im Fortsetzungszustand: $ROLLBACK_COVERAGE"
        return 1
    esac
    [[ "$UPDATE_ONLY" =~ ^[01]$ ]] || { warn "Ungültiger Update-Modus im Fortsetzungszustand."; return 1; }
    return 0
}

mark_transaction_active() {
    is_safe_backup_dir "${BACKUP_DIR:-}" || return 1
    write_resume_state
    refresh_backup_checksums
    printf '%s\n' "$BACKUP_DIR" >"$ACTIVE_TRANSACTION_FILE"
    write_transaction_phase vorbereitet
}

clear_transaction_marker() {
    local recorded=""
    [[ -f "$ACTIVE_TRANSACTION_FILE" ]] || return 0
    recorded="$(head -n1 "$ACTIVE_TRANSACTION_FILE" 2>/dev/null || true)"
    if [[ -z "${BACKUP_DIR:-}" || "$recorded" == "$BACKUP_DIR" ]]; then
        rm -f -- "$ACTIVE_TRANSACTION_FILE"
    fi
}

cleanup_old_backups() {
    local days="${1:-$BACKUP_RETENTION_DAYS}" active="" directory
    [[ "$days" =~ ^[0-9]+$ ]] || die "Die Aufbewahrungszeit muss eine nichtnegative Ganzzahl sein."
    ensure_backup_root
    active="$(head -n1 "$ACTIVE_TRANSACTION_FILE" 2>/dev/null || true)"
    while IFS= read -r -d '' directory; do
        [[ "$directory" == "$active" ]] && continue
        is_safe_backup_dir "$directory" || continue
        [[ ! -e "$BACKUP_ROOT/.abandoned-transaction-${directory##*/}" \
           && ! -L "$BACKUP_ROOT/.abandoned-transaction-${directory##*/}" ]] || {
            log "Bewahre Sicherung eines ausdrücklich aufgegebenen Host-Updates: $directory"
            continue
        }
        [[ ! -f "$directory/pending-verification.env" ]] || {
            log "Bewahre Sicherung mit ausstehender Abschlussprüfung: $directory"
            continue
        }
        log "Entferne abgelaufene NVIDIA-Sicherung: $directory"
        rm -rf -- "$directory"
    done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'nvidia-*' -mtime "+$days" -print0)
}

backup_transaction_phase() {
    local directory="$1"
    [[ -r "$directory/transaction-status" ]] || return 1
    awk -F'\t' 'NF >= 2 { phase = $2 } END { print phase }' \
        "$directory/transaction-status"
}

remove_success_backup_directory() {
    local directory="${1:-}" phase active=""

    is_safe_backup_dir "$directory" || {
        warn "Erfolgssicherung wird nicht entfernt: unsicheres Verzeichnis '$directory'."
        return 1
    }
    phase="$(backup_transaction_phase "$directory" 2>/dev/null || true)"
    [[ "$phase" == "abgeschlossen" ]] || {
        warn "Erfolgssicherung wird nicht entfernt: Transaktionsstatus ist '${phase:-unbekannt}'."
        return 1
    }
    active="$(head -n1 "$ACTIVE_TRANSACTION_FILE" 2>/dev/null || true)"
    [[ "$active" != "$directory" ]] || {
        warn "Erfolgssicherung wird nicht entfernt: Sie ist noch als aktive Transaktion markiert."
        return 1
    }
    if rm -rf -- "$directory" && [[ ! -e "$directory" ]]; then
        SUCCESS_BACKUP_REMOVED=1
        return 0
    fi
    warn "Erfolgssicherung konnte nicht vollständig entfernt werden: $directory"
    return 1
}

block_success_backup_cleanup() {
    local reason="${1:-Abschlussprüfung noch ausstehend}"
    SUCCESS_BACKUP_CLEANUP_BLOCKED=1
    append_unique PENDING_VERIFICATION_REASONS "$reason"
}

emit_machine_result() {
    local result="success" backup="${BACKUP_DIR:-}" backup_state="retained"
    ((MACHINE_READABLE_RESULT)) || return 0
    ((MACHINE_RESULT_EMITTED == 0)) || return 0
    MACHINE_RESULT_EMITTED=1
    ((SUCCESS_BACKUP_CLEANUP_BLOCKED == 0)) || result="pending"
    if ((SUCCESS_BACKUP_REMOVED)); then
        backup=""
        backup_state="removed"
    elif [[ -z "$backup" ]]; then
        backup_state="none"
    fi
    printf 'NVIDIA_SETUP_RESULT=%s\n' "$result"
    printf 'NVIDIA_SETUP_BACKUP=%s\n' "$backup"
    printf 'NVIDIA_SETUP_BACKUP_STATE=%s\n' "$backup_state"
    printf 'NVIDIA_SETUP_TARGET_VERSION=%s\n' "${TARGET_VERSION:-}"
    printf 'NVIDIA_SETUP_PENDING_COUNT=%s\n' "${#PENDING_VERIFICATION_REASONS[@]}"
}

emit_machine_failure() {
    local code="${1:-1}"
    ((MACHINE_READABLE_RESULT && MACHINE_RESULT_EMITTED == 0)) || return 0
    MACHINE_RESULT_EMITTED=1
    printf 'NVIDIA_SETUP_RESULT=failed\nNVIDIA_SETUP_BACKUP=%s\n' "${BACKUP_DIR:-}"
    printf 'NVIDIA_SETUP_BACKUP_STATE=retained\nNVIDIA_SETUP_EXIT_CODE=%s\n' "$code"
    printf 'NVIDIA_SETUP_ROLLBACK_STATUS=%s\n' "$LAST_ROLLBACK_STATUS"
    printf 'NVIDIA_SETUP_TARGET_VERSION=%s\n' "${TARGET_VERSION:-}"
}

completion_exit_code() {
    if ((SUCCESS_BACKUP_CLEANUP_BLOCKED && MACHINE_READABLE_RESULT == 0)); then
        printf '2'
    else
        printf '0'
    fi
}

write_pending_verification_state() {
    local pending_file temporary
    is_safe_backup_dir "${BACKUP_DIR:-}" || return 1
    pending_file="$BACKUP_DIR/pending-verification.env"
    temporary="$(mktemp "$BACKUP_DIR/.pending-verification.XXXXXX")" || return 1
    {
        printf 'PENDING_SCHEMA_VERSION=%q\n' "$PENDING_SCHEMA_CURRENT"
        printf 'PENDING_SCRIPT_VERSION=%q\n' "$SCRIPT_VERSION"
        printf 'PENDING_MODE=%q\n' "${MODE:-auto}"
        printf 'PENDING_ACTION=%q\n' "${TRANSACTION_ACTION:-install}"
        printf 'PENDING_TARGET_VERSION=%q\n' "${TARGET_VERSION:-}"
        printf 'PENDING_CLEAN_INSTALL_SCOPE=%q\n' "${CLEAN_INSTALL_SCOPE:-full}"
        printf 'PENDING_KEEP_SUCCESS_BACKUP=%q\n' "${KEEP_SUCCESS_BACKUP:-0}"
        printf 'PENDING_DELETE_SUCCESS_LOGS=%q\n' "${DELETE_SUCCESS_LOGS:-1}"
        printf 'PENDING_TARGET_LXC_ID=%q\n' "${TARGET_LXC_ID:-}"
        printf 'PENDING_TARGET_LXC_NAME=%q\n' "${TARGET_LXC_NAME:-}"
        printf 'PENDING_TARGET_GPU_SELECTION_SUMMARY=%q\n' "${TARGET_GPU_SELECTION_SUMMARY:-}"
        printf 'PENDING_TARGET_GPU_SELECTORS=('; ((${#TARGET_GPU_SELECTORS[@]} == 0)) || printf ' %q' "${TARGET_GPU_SELECTORS[@]}"; printf ' )\n'
        printf 'PENDING_TARGET_GPU_UUIDS=('; ((${#TARGET_GPU_UUIDS[@]} == 0)) || printf ' %q' "${TARGET_GPU_UUIDS[@]}"; printf ' )\n'
        printf 'PENDING_TARGET_GPU_BUS_IDS=('; ((${#TARGET_GPU_BUS_IDS[@]} == 0)) || printf ' %q' "${TARGET_GPU_BUS_IDS[@]}"; printf ' )\n'
        printf 'PENDING_LXC_DEVICE_BACKEND=%q\n' "${LXC_DEVICE_BACKEND:-auto}"
        printf 'PENDING_LXC_DEVICE_MODE=%q\n' "${LXC_DEVICE_MODE:-inherit}"
        printf 'PENDING_LXC_DEVICE_UID=%q\n' "${LXC_DEVICE_UID:-}"
        printf 'PENDING_LXC_DEVICE_GID=%q\n' "${LXC_DEVICE_GID:-}"
        printf 'PENDING_VERIFY_GPU=%q\n' "${CONFIGURE_LXC_GPU:-0}"
        printf 'PENDING_VERIFY_USERSPACE=%q\n' "${INSTALL_LXC_USERSPACE_FROM_HOST:-0}"
        printf 'PENDING_REMOTE_BACKUP=%q\n' "${LXC_REMOTE_SUCCESS_BACKUP:-}"
        printf 'PENDING_LXC_ORIGINAL_STATE=%q\n' "${LXC_ORIGINAL_STATE:-}"
        printf 'PENDING_TRANSCODE_SMOKE_TEST=%q\n' "${TRANSCODE_SMOKE_TEST:-auto}"
        printf 'PENDING_NVTOP_MANAGEMENT=%q\n' "${NVTOP_MANAGEMENT:-auto}"
        printf 'PENDING_STOPPED_GPU_CONSUMERS=('
        ((${#STOPPED_GPU_CONSUMERS[@]} == 0)) || printf ' %q' "${STOPPED_GPU_CONSUMERS[@]}"
        printf ' )\n'
        printf 'PENDING_NVIDIA_PERSISTENCED_WAS_ACTIVE=%q\n' "${NVIDIA_PERSISTENCED_WAS_ACTIVE:-0}"
        printf 'PENDING_REASONS=('; printf ' %q' "${PENDING_VERIFICATION_REASONS[@]:-}"; printf ' )\n'
    } >"$temporary" || { rm -f -- "$temporary"; return 1; }
    chmod 0600 "$temporary" || { rm -f -- "$temporary"; return 1; }
    mv -f -- "$temporary" "$pending_file" \
        || { rm -f -- "$temporary"; return 1; }
    refresh_backup_checksums
}

backup_manifest_contains_relative_file() {
    local directory="$1" relative="$2"
    [[ -s "$directory/backup-checksums.sha256" ]] || return 1
    awk -v expected="$relative" '$2 == expected { found = 1 } END { exit !found }' \
        "$directory/backup-checksums.sha256"
}

completion_action_label() {
    case "${TRANSACTION_ACTION:-install}" in
        update) printf 'NVIDIA-Pakete aktualisiert und exakt gepinnt' ;;
        lxc-update) printf 'NVIDIA-Pakete im LXC vom Host aktualisiert und exakt gepinnt' ;;
        install)
            if [[ "${MODE:-host}" == "lxc" ]]; then
                printf 'NVIDIA-Userspace-Bibliotheken im LXC sauber installiert oder aktualisiert'
            else
                printf 'NVIDIA-Host-Treiber sauber installiert oder aktualisiert'
            fi
            ;;
        lxc-complete)  printf 'LXC vollständig vom Proxmox-Host eingerichtet' ;;
        lxc-userspace) printf 'NVIDIA-Userspace im LXC vom Host installiert' ;;
        attach)        printf 'NVIDIA-GPU-Geräte an LXC durchgereicht' ;;
        uninstall)
            if [[ "${MODE:-host}" == "lxc" ]]; then
                printf 'NVIDIA-Userspace, CUDA-/Container-Toolkit und LXC-interne Konfiguration entfernt'
            else
                printf 'NVIDIA-Treiber, Bibliotheken, CUDA-/Container-Toolkit und verwaltete LXC-Einträge entfernt'
            fi
            ;;
        repair)        printf 'Automatische Fehleranalyse und sichere Reparatur abgeschlossen' ;;
        *)             printf '%s' "${TRANSACTION_ACTION:-unbekannt}" ;;
    esac
}

write_success_completion_report() {
    local timestamp report_name temporary backup_state script_hash="nicht ermittelbar"
    local target_version="${TARGET_VERSION:-nicht zutreffend}"
    local module_version="${DETECTED_HOST_MODULE_VERSION:-nicht geladen/entfällt}"
    local package_version="${DETECTED_PACKAGE_DEBIAN_VERSION:-nicht installiert/entfällt}"
    local report_scope="nicht zutreffend"

    ((TRANSACTION_FINISHED)) || return 0
    ((SUCCESS_BACKUP_CLEANUP_BLOCKED == 0)) || return 0
    ((DIAGNOSTIC_ERROR_COUNT == 0)) || return 0
    ((REBOOT_REQUIRED == 0)) || return 0

    if [[ -L "$COMPLETION_REPORT_ROOT" \
          || (-e "$COMPLETION_REPORT_ROOT" && ! -d "$COMPLETION_REPORT_ROOT") ]]; then
        warn "Abschlussbericht nicht gespeichert: unsicherer Zielpfad $COMPLETION_REPORT_ROOT"
        return 1
    fi
    mkdir -p -- "$COMPLETION_REPORT_ROOT" || return 1
    chmod 0750 "$COMPLETION_REPORT_ROOT" 2>/dev/null || true

    timestamp="$(date +%Y%m%d-%H%M%S)"
    report_name="abschlussbericht-${timestamp}-${TRANSACTION_ACTION:-aktion}"
    [[ -z "${TARGET_LXC_ID:-}" ]] || report_name+="-lxc-${TARGET_LXC_ID}"
    COMPLETION_REPORT_FILE="$COMPLETION_REPORT_ROOT/${report_name}.txt"
    temporary="$(mktemp "$COMPLETION_REPORT_ROOT/.abschlussbericht.XXXXXX")" || return 1

    if [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]]; then
        backup_state="behalten: $BACKUP_DIR"
    elif [[ -n "${BACKUP_DIR:-}" ]]; then
        backup_state="nach erfolgreicher Prüfung automatisch entfernt: $BACKUP_DIR"
    else
        backup_state="keine Transaktionssicherung"
    fi
    [[ ! -f "$0" ]] || script_hash="$(sha256sum "$0" 2>/dev/null | awk '{print $1}' || printf 'nicht ermittelbar')"

    {
        printf 'NVIDIA-ABSCHLUSSBERICHT\n'
        printf '======================================================================\n'
        printf 'Status:                 ERFOLGREICH\n'
        printf 'Zeitpunkt:              %s\n' "$(date --iso-8601=seconds)"
        if [[ -n "${PENDING_SCRIPT_VERSION:-}" ]]; then
            printf 'Transaktion erstellt mit:%s\n' " $PENDING_SCRIPT_VERSION"
            printf 'Abschluss finalisiert mit:%s\n' " $SCRIPT_VERSION"
        else
            printf 'Skriptversion:          %s\n' "$SCRIPT_VERSION"
        fi
        printf 'Skript-SHA256:          %s\n' "$script_hash"
        printf 'Aktion:                 %s\n' "$(completion_action_label)"
        printf '\nSYSTEM UND ZIEL\n'
        printf '%s\n' '----------------------------------------------------------------------'
        printf 'Distribution:           %s (%s)\n' "${OS_LABEL:-unbekannt}" "${DISTRO:-unbekannt}"
        printf 'Rolle:                  %s\n' "${MODE:-unbekannt}"
        printf 'Kernel:                 %s\n' "$(uname -r)"
        printf 'GPU(s):                 %s\n' "${DETECTED_GPU_SUMMARY:-nicht erkannt}"
        printf 'Zielversion:            %s\n' "$target_version"
        case "${TRANSACTION_ACTION:-install}" in
            install|lxc-complete|lxc-userspace)
                report_scope="${CLEAN_INSTALL_SCOPE:-full}"
                if [[ "${PENDING_SCHEMA_VERSION:-}" == "1" \
                      || "${PENDING_SCHEMA_VERSION:-}" == "2" ]]; then
                    printf 'Neuinstallationsumfang: unbekannt (Legacy-Sicherung; Prüfstandard: driver)\n'
                else
                    printf 'Neuinstallationsumfang:%s\n' " $report_scope"
                fi
                ;;
            *) printf 'Neuinstallationsumfang: nicht zutreffend\n' ;;
        esac
        printf 'Geladenes Kernelmodul:  %s\n' "$module_version"
        printf 'Installierte DEB-Version:%s\n' "${package_version:+ $package_version}"
        printf 'Versionsstatus:         %s\n' "${DETECTED_VERSION_STATE:-nicht zutreffend}"
        [[ "${REPAIR_OUTCOME:-not-run}" == "not-run" ]] \
            || printf 'Reparaturergebnis:      %s\n' "$REPAIR_OUTCOME"
        if [[ -n "${TARGET_LXC_ID:-}" ]]; then
            printf 'Ziel-LXC:               %s (%s)\n' "$TARGET_LXC_ID" "${TARGET_LXC_NAME:-unbekannt}"
            if ((CONFIGURE_LXC_GPU)); then
                printf 'GPU-Auswahl:            %s\n' "${TARGET_GPU_SELECTION_SUMMARY:-nicht zutreffend}"
                if [[ "${PENDING_SCHEMA_VERSION:-}" == "1" \
                      || "${PENDING_SCHEMA_VERSION:-}" == "2" ]]; then
                    printf 'Gerätezugriff:          unbekannt (Legacy-Sicherung)\n'
                else
                    printf 'Gerätezugriff:          mode=%s%s%s\n' "${LXC_DEVICE_MODE:-0666}" \
                        "${LXC_DEVICE_UID:+, uid=$LXC_DEVICE_UID}" "${LXC_DEVICE_GID:+, gid=$LXC_DEVICE_GID}"
                fi
            else
                printf 'GPU-Auswahl:            unverändert (nicht Teil dieser Aktion)\n'
                printf 'Gerätezugriff:          unverändert (nicht Teil dieser Aktion)\n'
            fi
        fi
        printf '\nABSCHLUSSPRÜFUNGEN\n'
        printf '%s\n' '----------------------------------------------------------------------'
        printf '[ OK ] Transaktion ohne unbehandelten Fehler abgeschlossen\n'
        printf '[ OK ] Rollback-/Sicherungsstatus konsistent abgeschlossen\n'
        case "${TRANSACTION_ACTION:-install}" in
            uninstall)
                printf '[ OK ] APT-/dpkg-Endzustand ohne gemeldeten Abschlussfehler\n'
                if [[ "$MODE" == "lxc" ]]; then
                    printf '[ OK ] NVIDIA-/CUDA-/Container-Pakete und LXC-interne Konfiguration vollständig entfernt\n'
                    printf '[INFO] Gerätezuweisungen auf dem Proxmox-Host blieben unverändert\n'
                else
                    printf '[ OK ] NVIDIA-/CUDA-/Container-Pakete und verwaltete LXC-Einträge vollständig entfernt\n'
                fi
                ;;
            attach)
                printf '[INFO] Treiber, Pakete und APT wurden bei der Gerätezuweisung nicht verändert\n'
                printf '[ OK ] LXC-Gerätezuweisung zur Laufzeit verifiziert\n'
                ;;
            lxc-complete|lxc-userspace|lxc-update)
                printf '[ OK ] LXC-APT-/dpkg-Endzustand wurde durch den Host-Orchestrator geprüft\n'
                printf '[ OK ] NVIDIA-Userspace und Host-Kernelmodul stimmen exakt überein\n'
                printf '[ OK ] NVML-Abschlussdiagnose ohne Fehler\n'
                printf '[INFO] NVENC/NVDEC werden im nachfolgenden Transcoding-Status separat ausgewiesen\n'
                ;;
            *)
                printf '[ OK ] APT-/dpkg-Endzustand ohne gemeldeten Abschlussfehler\n'
                printf '[ OK ] NVIDIA-Paket-, Modul- und Versionsabgleich abgeschlossen\n'
                printf '[ OK ] NVML-Abschlussdiagnose ohne Fehler\n'
                printf '[INFO] NVENC/NVDEC werden im nachfolgenden Transcoding-Status separat ausgewiesen\n'
                ;;
        esac
        [[ "$MODE" != "lxc" ]] \
            || printf '[ OK ] Im LXC wurden keine Kernel-/DKMS-/Host-Hilfspakete eingerichtet\n'
        [[ -z "${TARGET_LXC_ID:-}" ]] \
            || printf '[ OK ] Ursprünglicher LXC-Laufzustand wiederhergestellt\n'
        printf '[ OK ] Keine NVIDIA-bedingte Abschlussprüfung oder Neustartanforderung offen\n'
        case "${TRANSCODE_SMOKE_TEST:-auto}" in
            yes) printf '[ OK ] Erzwungener NVENC-/NVDEC-Transcoding-Test erfolgreich\n' ;;
            no)  printf '[INFO] Transcoding-Smoke-Test wurde auf Wunsch übersprungen\n' ;;
            *)   printf '[INFO] Automatischer Transcoding-Test wurde bei vorhandenem FFmpeg ausgeführt, andernfalls nachvollziehbar als nicht möglich protokolliert\n' ;;
        esac
        case "${NVTOP_MANAGEMENT:-auto}" in
            install) printf '[ OK ] nvtop installiert und mit echtem NVML-Start geprüft\n' ;;
            skip)    printf '[INFO] nvtop-Verwaltung wurde auf Wunsch übersprungen\n' ;;
            *)       printf '[INFO] Vorhandenes nvtop wurde automatisch geprüft und bei Bedarf repariert\n' ;;
        esac
        case "${TRANSACTION_ACTION:-install}" in
            install|update|lxc-complete|lxc-userspace|lxc-update)
                if ((FINAL_APT_AUTOREMOVE)); then
                    printf '[ OK ] Abschließendes apt autoremove --purge wurde simuliert, rollbackgesichert und nachgeprüft\n'
                else
                    printf '[INFO] Abschließendes apt autoremove wurde auf Wunsch übersprungen\n'
                fi
                ;;
            *) printf '[INFO] Abschließendes apt autoremove war für diese Aktion nicht vorgesehen\n' ;;
        esac
        printf '\nSICHERUNG UND PROTOKOLL\n'
        printf '%s\n' '----------------------------------------------------------------------'
        printf 'Transaktionssicherung: %s\n' "$backup_state"
        printf 'Aufbewahrungsrichtlinie:%s Tage\n' " ${BACKUP_RETENTION_DAYS:-30}"
        if ((DELETE_SUCCESS_LOGS)) && [[ -n "${INSTALL_LOG_FILE:-}" ]]; then
            printf 'Gesamtprotokoll:       %s (wird nach diesem Erfolgsbericht automatisch entfernt)\n' "$INSTALL_LOG_FILE"
        else
            printf 'Gesamtprotokoll:       %s\n' "${INSTALL_LOG_FILE:-nicht aktiviert}"
        fi
        printf 'Abschlussbericht:      %s\n' "$COMPLETION_REPORT_FILE"
        printf '======================================================================\n'
    } >"$temporary" || { rm -f -- "$temporary"; return 1; }

    chmod 0640 "$temporary" 2>/dev/null || true
    mv -f -- "$temporary" "$COMPLETION_REPORT_FILE" || { rm -f -- "$temporary"; return 1; }

    printf '\n\033[1;32m╭────────────────────────────────────────────────────────────────────╮\033[0m\n'
    printf '\033[1;32m│                 ABSCHLUSS ERFOLGREICH                              │\033[0m\n'
    printf '\033[1;32m╰────────────────────────────────────────────────────────────────────╯\033[0m\n'
    sed 's/^/  /' "$COMPLETION_REPORT_FILE"
    ok "Dauerhafter Abschlussbericht gespeichert: $COMPLETION_REPORT_FILE"
    cleanup_successful_install_logs
}

cleanup_successful_transaction_backup() {
    local completed_backup="${BACKUP_DIR:-}"

    is_safe_backup_dir "$completed_backup" || return 0
    ((TRANSACTION_FINISHED)) || {
        warn "Sicherung bleibt erhalten, weil die Transaktion nicht als abgeschlossen markiert ist: $completed_backup"
        return 0
    }
    if ((SUCCESS_BACKUP_CLEANUP_BLOCKED)); then
        if write_pending_verification_state; then
            warn "Ausstehende Prüfung gespeichert: $completed_backup/pending-verification.env"
        else
            warn "Die ausstehende Abschlussprüfung konnte nicht in der Sicherung vermerkt werden."
        fi
        warn "Sicherung bleibt für die noch ausstehende Abschlussprüfung erhalten: $completed_backup"
        return 0
    fi
    if ((KEEP_SUCCESS_BACKUP)); then
        log "Erfolgssicherung wird auf Wunsch behalten: $completed_backup"
        return 0
    fi
    if remove_success_backup_directory "$completed_backup"; then
        ok "Erfolgssicherung automatisch entfernt: $completed_backup"
    else
        warn "Der Vorgang bleibt erfolgreich; die Sicherung muss bei Bedarf manuell bereinigt werden."
    fi
    return 0
}

success_install_log_path_is_safe() {
    local file="${1:-}" root resolved_file resolved_root
    [[ -n "$file" && -e "$file" && ! -L "$file" ]] || return 1
    [[ "$(basename -- "$file")" == installationslog-*.log ]] || return 1
    resolved_root="$(readlink -f -- "$COMPLETION_REPORT_ROOT" 2>/dev/null || true)"
    resolved_file="$(readlink -f -- "$file" 2>/dev/null || true)"
    [[ -n "$resolved_root" && -n "$resolved_file" ]] || return 1
    [[ "$(dirname -- "$resolved_file")" == "$resolved_root" ]]
}

cleanup_successful_install_logs() {
    local file current="${INSTALL_LOG_FILE:-}" days="${BACKUP_RETENTION_DAYS:-30}"

    ((DELETE_SUCCESS_LOGS)) || return 0
    ((TRANSACTION_FINISHED)) || return 0
    ((SUCCESS_BACKUP_CLEANUP_BLOCKED == 0 && DIAGNOSTIC_ERROR_COUNT == 0 && REBOOT_REQUIRED == 0)) \
        || return 0
    [[ -n "${COMPLETION_REPORT_FILE:-}" && -s "$COMPLETION_REPORT_FILE" ]] || {
        warn "Erfolgslog bleibt erhalten, weil kein vollständiger Abschlussbericht gespeichert wurde."
        return 0
    }
    [[ "$days" =~ ^[0-9]+$ ]] || return 0
    [[ -d "$COMPLETION_REPORT_ROOT" && ! -L "$COMPLETION_REPORT_ROOT" ]] || return 0

    # Alte Detailprotokolle werden erst nach einem erneut vollständig geprüften
    # Erfolg und gemäß derselben Aufbewahrungszeit wie Fehlerbackups bereinigt.
    while IFS= read -r -d '' file; do
        [[ "$file" == "$current" ]] && continue
        success_install_log_path_is_safe "$file" || continue
        rm -f -- "$file" || warn "Altes Installationslog konnte nicht entfernt werden: $file"
    done < <(find "$COMPLETION_REPORT_ROOT" -maxdepth 1 -type f \
        -name 'installationslog-*.log' -mtime "+$days" -print0 2>/dev/null || true)

    [[ -e "$current" ]] || return 0
    success_install_log_path_is_safe "$current" || {
        warn "Erfolgslog wird wegen eines unsicheren Pfads nicht entfernt: $current"
        return 0
    }
    if rm -f -- "$current" && [[ ! -e "$current" ]]; then
        SUCCESS_LOG_REMOVED=1
        ok "Erfolgreiches Installationslog automatisch entfernt: $current"
    else
        warn "Erfolgreiches Installationslog konnte nicht entfernt werden: $current"
    fi
    return 0
}

load_interrupted_transaction() {
    local directory=""
    [[ -s "$ACTIVE_TRANSACTION_FILE" ]] || return 1
    directory="$(head -n1 "$ACTIVE_TRANSACTION_FILE" 2>/dev/null || true)"
    is_safe_backup_dir "$directory" || return 1
    [[ -r "$directory/resume.env" && -x "$directory/rollback.sh" ]] || return 1
    verify_backup_checksums "$directory" || return 1
    # Die Datei wurde ausschließlich mit printf %q aus validierten Menü-/CLI-Werten erzeugt.
    load_resume_state_file "$directory/resume.env" || return 1
    BACKUP_DIR="$directory"
    RESUME_SOURCE_BACKUP="$directory"
    ROLLBACK_READY=1
    return 0
}

dpkg_status_is_healthy_installed() {
    local status="${1:-}"
    # db:Status-Abbrev besteht aus Wunschstatus, Iststatus und Fehlerflag.
    # Auch ein gehaltenes Paket (z. B. "hi ") ist gesund installiert.
    [[ ${#status} -ge 2 && "${status:1:1}" == "i" \
       && "${status:2:1}" != "R" ]]
}

restore_nvidia_holds() {
    local package status
    ((NVIDIA_HOLDS_RELEASED)) || return 0
    command -v apt-mark >/dev/null 2>&1 || return 0
    for package in "${NVIDIA_HOLDS[@]}"; do
        status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null || true)"
        dpkg_status_is_healthy_installed "$status" || continue
        apt-mark hold "$package" >/dev/null 2>&1 || true
    done
    NVIDIA_HOLDS_RELEASED=0
}

extract_lxc_id_from_cgroup() {
    sed -nE '
        s#.*lxc\.payload\.([0-9]+).*#\1#p
        s#.*pve-container@([0-9]+)\.service.*#\1#p
        s#.*\/lxc\/([0-9]+)(\/.*)?#\1#p
    ' | head -n1
}

extract_systemd_service_from_cgroup() {
    grep -oE '[A-Za-z0-9_.@:-]+\.service' | tail -n1
}

gpu_consumer_unit_is_safe() {
    local unit="${1:-}"
    [[ "$unit" =~ ^[A-Za-z0-9_.@:-]+\.service$ ]] || return 1
    [[ "$unit" =~ ^(jellyfin|plexmediaserver|emby-server|fileflows|tdarr|frigate|beszel-agent|nvidia-persistenced)(@[A-Za-z0-9_.:-]+)?\.service$ ]]
}

gpu_consumer_target_is_valid() {
    local target="${1:-}" kind ctid unit extra
    IFS='|' read -r kind ctid unit extra <<<"$target"
    [[ -z "${extra:-}" ]] || return 1
    case "$kind" in
        host)
            [[ -z "$ctid" ]] && gpu_consumer_unit_is_safe "$unit"
            ;;
        lxc)
            [[ "$ctid" =~ ^[0-9]+$ ]] && gpu_consumer_unit_is_safe "$unit"
            ;;
        *) return 1 ;;
    esac
}

read_gpu_consumer_pid_cgroup() {
    local pid="$1"
    [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/cgroup" ]] || return 1
    cat "/proc/$pid/cgroup"
}

read_gpu_consumer_lxc_cgroup() {
    local ctid="$1" host_pid="$2" namespace_pid
    [[ "$ctid" =~ ^[0-9]+$ && "$host_pid" =~ ^[0-9]+$ ]] || return 1
    command -v pct >/dev/null 2>&1 || return 1
    namespace_pid="$(awk '/^NSpid:/ {print $NF; exit}' "/proc/$host_pid/status" 2>/dev/null || true)"
    [[ "$namespace_pid" =~ ^[0-9]+$ ]] || return 1
    pct exec "$ctid" -- cat "/proc/$namespace_pid/cgroup" 2>/dev/null
}

resolve_gpu_consumer_target() {
    local pid="$1" cgroup ctid="" unit="" inner=""
    cgroup="$(read_gpu_consumer_pid_cgroup "$pid" 2>/dev/null || true)"
    [[ -n "$cgroup" ]] || return 1
    ctid="$(extract_lxc_id_from_cgroup <<<"$cgroup" || true)"
    if [[ -n "$ctid" ]]; then
        inner="$(read_gpu_consumer_lxc_cgroup "$ctid" "$pid" 2>/dev/null || true)"
        unit="$(extract_systemd_service_from_cgroup <<<"$inner" || true)"
        gpu_consumer_unit_is_safe "$unit" || return 1
        printf 'lxc|%s|%s' "$ctid" "$unit"
        return 0
    fi
    unit="$(extract_systemd_service_from_cgroup <<<"$cgroup" || true)"
    gpu_consumer_unit_is_safe "$unit" || return 1
    printf 'host||%s' "$unit"
}

collect_gpu_consumer_pids() {
    local smi_pids="" device_pids=""
    if command -v nvidia-smi >/dev/null 2>&1; then
        smi_pids="$(nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits 2>/dev/null \
            | awk '$1 ~ /^[0-9]+$/ {print $1}' || true)"
    fi
    if command -v fuser >/dev/null 2>&1 && compgen -G '/dev/nvidia*' >/dev/null; then
        device_pids="$(fuser /dev/nvidia* 2>/dev/null \
            | tr ' ' '\n' | sed -nE 's/^([0-9]+).*/\1/p' || true)"
    fi
    printf '%s\n%s\n' "$smi_pids" "$device_pids" | awk '/^[0-9]+$/' | sort -nu
}

gpu_consumer_target_is_active() {
    local target="$1" kind ctid unit
    gpu_consumer_target_is_valid "$target" || return 1
    IFS='|' read -r kind ctid unit <<<"$target"
    case "$kind" in
        host) systemctl is-active --quiet "$unit" 2>/dev/null ;;
        lxc)
            [[ "$(pct status "$ctid" 2>/dev/null | awk '{print $2}' || true)" == "running" ]] \
                && pct exec "$ctid" -- systemctl is-active --quiet "$unit" 2>/dev/null
            ;;
        *) return 1 ;;
    esac
}

stop_gpu_consumer_target() {
    local target="$1" kind ctid unit
    gpu_consumer_target_is_valid "$target" || return 1
    IFS='|' read -r kind ctid unit <<<"$target"
    case "$kind" in
        host)
            log "Stoppe GPU-Dienst auf dem Host: $unit"
            systemctl stop "$unit"
            ;;
        lxc)
            log "Stoppe GPU-Dienst in LXC $ctid: $unit"
            pct exec "$ctid" -- systemctl stop "$unit"
            ;;
        *) return 1 ;;
    esac
}

start_gpu_consumer_target() {
    local target="$1" kind ctid unit
    gpu_consumer_target_is_valid "$target" || return 1
    IFS='|' read -r kind ctid unit <<<"$target"
    case "$kind" in
        host)
            systemctl is-active --quiet "$unit" 2>/dev/null && return 0
            log "Starte zuvor aktiven GPU-Dienst auf dem Host erneut: $unit"
            systemctl start "$unit"
            ;;
        lxc)
            [[ "$(pct status "$ctid" 2>/dev/null | awk '{print $2}' || true)" == "running" ]] || return 1
            pct exec "$ctid" -- systemctl is-active --quiet "$unit" 2>/dev/null && return 0
            log "Starte zuvor aktiven GPU-Dienst in LXC $ctid erneut: $unit"
            pct exec "$ctid" -- systemctl start "$unit"
            ;;
        *) return 1 ;;
    esac
}

restore_stopped_gpu_consumers() {
    local index target rc=0
    local -a remaining=()
    ((${#STOPPED_GPU_CONSUMERS[@]})) || return 0
    for ((index=${#STOPPED_GPU_CONSUMERS[@]} - 1; index >= 0; index--)); do
        target="${STOPPED_GPU_CONSUMERS[index]}"
        if ! start_gpu_consumer_target "$target"; then
            warn "Zuvor aktiver GPU-Dienst konnte nicht wiederhergestellt werden: $target"
            remaining+=("$target")
            rc=1
        fi
    done
    STOPPED_GPU_CONSUMERS=()
    ((${#remaining[@]} == 0)) || STOPPED_GPU_CONSUMERS=("${remaining[@]}")
    return "$rc"
}

restore_nvidia_persistenced() {
    ((NVIDIA_PERSISTENCED_WAS_ACTIVE)) || return 0
    command -v systemctl >/dev/null 2>&1 || return 1
    if systemctl start nvidia-persistenced.service >/dev/null 2>&1; then
        NVIDIA_PERSISTENCED_WAS_ACTIVE=0
        return 0
    fi
    warn "nvidia-persistenced.service konnte nicht wieder gestartet werden."
    return 1
}

restore_runtime_state() {
    local rc=0
    restore_nvidia_holds || rc=1
    if declare -F cleanup_remote_lxc_script >/dev/null 2>&1; then
        cleanup_remote_lxc_script || rc=1
    fi
    if declare -F restore_lxc_runtime_state >/dev/null 2>&1; then
        restore_lxc_runtime_state || rc=1
    fi
    if declare -F cleanup_remote_lxc_script >/dev/null 2>&1; then
        cleanup_remote_lxc_script || rc=1
    fi
    restore_stopped_gpu_consumers || rc=1
    restore_nvidia_persistenced || rc=1
    return "$rc"
}

verify_remote_lxc_rollback_basis() {
    local directory="$1" status phase result="${LXC_REMOTE_RESULT:-}"
    [[ "$directory" =~ ^/opt/nvidia-backup/nvidia-[A-Za-z0-9._-]+$ ]] || return 1
    pct exec "$TARGET_LXC_ID" -- test -x "$directory/rollback.sh" >/dev/null 2>&1 || return 1
    pct exec "$TARGET_LXC_ID" -- sh -c '
        directory=$1
        cd "$directory" || exit 1
        test -s backup-checksums.sha256 || exit 1
        sha256sum -c --quiet backup-checksums.sha256
    ' sh "$directory" >/dev/null 2>&1 || return 1
    status="$(pct exec "$TARGET_LXC_ID" -- tail -n1 \
        "$directory/transaction-status" 2>/dev/null | tr -d '\r' || true)"
    phase="${status#*$'\t'}"
    [[ "$status" == *$'\t'* && "$phase" == "abgeschlossen" ]] || return 1
    case "$result" in
        pending)
            pct exec "$TARGET_LXC_ID" -- test -f \
                "$directory/pending-verification.env" >/dev/null 2>&1 || return 1
            ;;
        success)
            ! pct exec "$TARGET_LXC_ID" -- test -e \
                "$directory/pending-verification.env" >/dev/null 2>&1 || return 1
            ;;
        "") ;;
        *) return 1 ;;
    esac
    return 0
}

rollback_remote_lxc_transaction() {
    local directory="${LXC_REMOTE_SUCCESS_BACKUP:-}" state
    local started_for_rollback=0 restore_stopped_after=0 rollback_rc=0
    [[ -n "$directory" ]] || return 0
    [[ "$directory" =~ ^/opt/nvidia-backup/nvidia-[A-Za-z0-9._-]+$ ]] || {
        warn "Remote-LXC-Rollback verweigert: unsicherer Sicherungspfad '$directory'."
        return 1
    }
    command -v pct >/dev/null 2>&1 && [[ "${TARGET_LXC_ID:-}" =~ ^[0-9]+$ ]] || return 1
    state="$(pct status "$TARGET_LXC_ID" 2>/dev/null | awk '{print $2}' || true)"
    if [[ "$state" == "stopped" ]]; then
        case "${LXC_ORIGINAL_STATE:-}" in
            running)
                log "Starte den zuvor laufenden LXC $TARGET_LXC_ID erneut, damit sein Rollback ausgeführt werden kann."
                pct start "$TARGET_LXC_ID" || return 1
                started_for_rollback=1
                ;;
            stopped)
                ((LXC_TEMPORARY_START_ALLOWED)) || {
                    warn "Remote-LXC-Rollback ausstehend: LXC $TARGET_LXC_ID war zuvor gestoppt und es liegt keine Startfreigabe vor. Sicherung: $directory"
                    return 1
                }
                log "Starte LXC $TARGET_LXC_ID mit der vorhandenen temporären Freigabe nur für den Rollback."
                pct start "$TARGET_LXC_ID" || return 1
                started_for_rollback=1
                restore_stopped_after=1
                ;;
            *)
                warn "Remote-LXC-Rollback ausstehend: Ursprungszustand von LXC $TARGET_LXC_ID ist unbekannt. Sicherung: $directory"
                return 1
                ;;
        esac
    elif [[ "$state" != "running" ]]; then
        warn "Remote-LXC-Rollback ausstehend: Zustand von LXC $TARGET_LXC_ID ist '$state'. Sicherung: $directory"
        return 1
    fi
    verify_remote_lxc_rollback_basis "$directory" || rollback_rc=1
    if ((rollback_rc == 0)); then
        log "Rolle die erfolgreiche LXC-Teiltransaktion vor dem Host-Rollback zurück: $directory"
        pct exec "$TARGET_LXC_ID" -- "$directory/rollback.sh" host-koordiniert \
            || rollback_rc=1
    else
        warn "Remote-LXC-Rollbackskript fehlt: $directory/rollback.sh"
    fi
    if ((rollback_rc == 0 && LXC_REMOTE_SCRIPT_PENDING)) \
       && [[ "$LXC_REMOTE_SCRIPT_PATH" =~ ^/root/\.nvidia-driver-setup-host-managed-[A-Za-z0-9._-]+\.sh$ ]]; then
        pct exec "$TARGET_LXC_ID" -- rm -f -- "$LXC_REMOTE_SCRIPT_PATH" >/dev/null 2>&1 \
            && ! pct exec "$TARGET_LXC_ID" -- test -e "$LXC_REMOTE_SCRIPT_PATH" >/dev/null 2>&1 \
            || rollback_rc=1
        ((rollback_rc)) || LXC_REMOTE_SCRIPT_PENDING=0
    fi
    if ((restore_stopped_after && started_for_rollback)); then
        pct shutdown "$TARGET_LXC_ID" --timeout 60 --forceStop 1 \
            || { warn "LXC $TARGET_LXC_ID konnte nach dem Rollback nicht wieder gestoppt werden."; rollback_rc=1; }
    fi
    ((rollback_rc == 0)) || {
        warn "Remote-LXC-Rollback ist fehlgeschlagen oder unvollständig: $directory"
        return 1
    }
    LXC_REMOTE_BACKUP_CLEANUP_PENDING=0
    LXC_REMOTE_SUCCESS_BACKUP=""
    LXC_REMOTE_RESULT=""
    if [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]]; then
        write_resume_state || return 1
        refresh_backup_checksums || return 1
    fi
}

restore_runtime_state_from_backup() {
    local directory="$1" state rc=0
    [[ -r "$directory/resume.env" ]] || return 0
    # Die Datei wird ausschließlich nach erfolgreicher Sicherungs-Prüfsumme
    # geladen und liegt unter dem root-geschützten Backup-Verzeichnis.
    load_resume_state_file "$directory/resume.env" || return 1
    if ((LXC_REMOTE_SCRIPT_PENDING)) && command -v pct >/dev/null 2>&1 \
       && [[ "${TARGET_LXC_ID:-}" =~ ^[0-9]+$ \
           && "$LXC_REMOTE_SCRIPT_PATH" =~ ^/root/\.nvidia-driver-setup-host-managed-[A-Za-z0-9._-]+\.sh$ ]]; then
        state="$(pct status "$TARGET_LXC_ID" 2>/dev/null | awk '{print $2}' || true)"
        if [[ "$state" == "running" ]]; then
            pct exec "$TARGET_LXC_ID" -- rm -f -- "$LXC_REMOTE_SCRIPT_PATH" >/dev/null 2>&1 \
                || rc=1
        fi
    fi
    if ((LXC_RUNTIME_TOUCHED)) && command -v pct >/dev/null 2>&1 \
       && [[ "${TARGET_LXC_ID:-}" =~ ^[0-9]+$ ]]; then
        state="$(pct status "$TARGET_LXC_ID" 2>/dev/null | awk '{print $2}' || true)"
        case "${LXC_ORIGINAL_STATE:-}:$state" in
            stopped:running)
                pct shutdown "$TARGET_LXC_ID" --timeout 60 --forceStop 1 >/dev/null 2>&1 || rc=1
                ;;
            running:stopped)
                pct start "$TARGET_LXC_ID" >/dev/null 2>&1 || rc=1
                ;;
        esac
    fi
    restore_stopped_gpu_consumers || rc=1
    restore_nvidia_persistenced || rc=1
    return "$rc"
}

rollback_transaction() {
    local reason="${1:-Fehler}"
    local rollback_script="${BACKUP_DIR:-}/rollback.sh" rollback_log="${BACKUP_DIR:-}/automatic-rollback.log"
    local remote_rc=0 host_rc=0

    ((ROLLBACK_READY && MUTATION_STARTED && ROLLBACK_IN_PROGRESS == 0 \
        && TRANSACTION_FINISHED == 0)) || return 0
    [[ -x "$rollback_script" ]] || return 0

    if [[ -z "${LXC_REMOTE_SUCCESS_BACKUP:-}" ]] \
       && declare -F recover_remote_lxc_result_from_install_log >/dev/null 2>&1; then
        recover_remote_lxc_result_from_install_log 1 || true
    fi

    ROLLBACK_IN_PROGRESS=1
    LAST_ROLLBACK_STATUS="failed"
    trap - ERR HUP INT TERM
    warn "${reason}: Der NVIDIA-bezogene Zustand wird automatisch zurückgesetzt."
    rollback_remote_lxc_transaction || remote_rc=1
    : >"$rollback_log"
    if ! verify_backup_checksums "$BACKUP_DIR"; then
        printf '[rollback] Sicherungsprüfung fehlgeschlagen; Rollback wird aus Sicherheitsgründen nicht ausgeführt.\n' \
            | tee -a "$rollback_log"
        host_rc=1
    elif ! "$rollback_script" automatic 2>&1 | tee -a "$rollback_log"; then
        host_rc=1
    fi
    if ((remote_rc == 0 && host_rc == 0)); then
        LAST_ROLLBACK_STATUS="completed"
        ok "Rollback abgeschlossen. Protokoll: $BACKUP_DIR/automatic-rollback.log"
        write_transaction_phase automatisch-zurueckgerollt
        clear_transaction_marker
    else
        warn "Rollback nicht vollständig erfolgreich. Protokoll: $BACKUP_DIR/automatic-rollback.log"
        write_transaction_phase rollback-fehlgeschlagen
    fi
    ROLLBACK_IN_PROGRESS=0
}

die() {
    trap - ERR HUP INT TERM
    set +e
    printf '\033[1;31m[FEHLER]\033[0m %s\n' "$*" >&2
    [[ -n "${BACKUP_DIR:-}" ]] && printf 'Sicherung: %s\n' "$BACKUP_DIR" >&2
    [[ -n "${INSTALL_LOG_FILE:-}" ]] && printf 'Installationslog: %s\n' "$INSTALL_LOG_FILE" >&2
    rollback_transaction "Abbruch"
    restore_runtime_state || true
    emit_machine_failure 1
    exit 1
}

cleanup_tmp() {
    local exit_status=$? end_time
    if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
        case "$TMP_DIR" in
            /tmp/*|/var/tmp/*|"${TMPDIR:-/tmp}"/*) rm -rf -- "$TMP_DIR" ;;
            *) warn "Unsicheres temporäres Verzeichnis wird nicht automatisch entfernt: $TMP_DIR" ;;
        esac
    fi
    if ((INSTALL_LOG_ACTIVE)); then
        end_time="$(date --iso-8601=seconds 2>/dev/null || printf 'unbekannt')"
        printf '\n%s\n' '======================================================================'
        printf 'Protokollende: %s | Exit-Code: %s\n' "$end_time" "$exit_status"
        printf 'Gesamtprotokoll: %s\n' "$INSTALL_LOG_FILE"
    fi
    return 0
}

on_error() {
    local rc=$?
    trap - ERR HUP INT TERM
    set +e
    printf '\n\033[1;31m[FEHLER]\033[0m Abbruch in Zeile %s bei `%s` (Exit-Code %s).\n' \
        "${BASH_LINENO[0]:-?}" "${BASH_COMMAND:-unbekannt}" "$rc" >&2
    [[ -n "${BACKUP_DIR:-}" ]] && printf 'Sicherung: %s\n' "$BACKUP_DIR" >&2
    [[ -n "${INSTALL_LOG_FILE:-}" ]] && printf 'Installationslog: %s\n' "$INSTALL_LOG_FILE" >&2
    rollback_transaction "Unerwarteter Fehler"
    restore_runtime_state || true
    emit_machine_failure "$rc"
    exit "$rc"
}

on_signal() {
    trap - ERR HUP INT TERM
    set +e
    warn "Durch Signal abgebrochen; temporäre Zustände werden bereinigt und Änderungen zurückgerollt."
    rollback_transaction "Signalabbruch"
    restore_runtime_state || true
    emit_machine_failure 130
    exit 130
}

trap cleanup_tmp EXIT
trap on_error ERR
trap on_signal HUP INT TERM

assert_package_mutation_allowed() {
    ((PACKAGE_MUTATION_ALLOWED)) \
        || die "Interner Schutz: Eine Paketänderung wurde in einem schreibgeschützten Modus verhindert."
}

parse_apt_plan_packages() {
    local event="$1" file="$2"
    awk -v event="$event" '$1 == event || (event == "Remv" && $1 == "Purg") {print $2}' "$file" | sort -u
}

parse_apt_install_plan() {
    local file="$1"
    awk '
        $1 == "Inst" {
            package = $2
            version = ""
            if (match($0, /\([^[:space:]]+/)) {
                version = substr($0, RSTART + 1, RLENGTH - 1)
            }
            print package "\t" version
        }
    ' "$file" | sort -u
}

assert_apt_simulation_policy() {
    local simulation_file="$1" action="${2:-unknown}"
    shift 2 || true
    local package package_base version normalized bad="" allowed allowed_base explicit
    local running_kernel="$(uname -r)"
    local critical_regex='^(proxmox-ve|pve-manager|pve-container|proxmox-default-kernel|proxmox-kernel-helper|proxmox-kernel-[^[:space:]]+|pve-kernel-[^[:space:]]+|proxmox-headers-[^[:space:]]+|pve-headers-[^[:space:]]+|linux-image-[^[:space:]]+|linux-headers-[^[:space:]]+|systemd|systemd-sysv|init|openssh-server|apt|dpkg|fileflows)$'
    local -a unexpected_removals=() forbidden_installs=() wrong_versions=()

    [[ -r "$simulation_file" ]] || die "APT-Planprüfung kann die Simulation nicht lesen: $simulation_file"
    bad="$(
        while IFS= read -r package; do
            package_base="${package%%:*}"
            [[ "$package_base" =~ $critical_regex ]] || continue
            if [[ "$action" == "autoremove" \
                  && "$package_base" =~ ^(proxmox-kernel-|pve-kernel-|proxmox-headers-|pve-headers-|linux-image-|linux-headers-) ]]; then
                if [[ "$package_base" == *"$running_kernel"* \
                      || "$package_base" =~ ^(proxmox-kernel|pve-kernel|proxmox-headers|pve-headers)-[0-9]+\.[0-9]+$ \
                      || "$package_base" =~ ^linux-(image|headers)-(generic|amd64|virtual|lowlatency|cloud-amd64)$ ]]; then
                    printf '%s\n' "$package"
                fi
                continue
            fi
            printf '%s\n' "$package"
        done < <(parse_apt_plan_packages Remv "$simulation_file")
        true
    )"
    [[ -z "$bad" ]] \
        || die "APT-Plan abgelehnt: kritische Pakete würden entfernt: $(tr '\n' ' ' <<<"$bad"). Details: $simulation_file"

    if [[ "$action" == "install" || "$action" == "purge" || "$action" == "remove" \
          || "$action" == "autoremove" \
          || "$action" == "upgrade" \
          || "$action" == "dist-upgrade" || "$action" == "full-upgrade" ]]; then
        while IFS= read -r package; do
            [[ -n "$package" ]] || continue
            if [[ "$package" =~ $NVIDIA_DRIVER_REGEX \
                  || "$package" =~ ^(cuda-keyring|cuda-repo-|nvidia-driver-local-repo-) ]]; then
                continue
            fi
            explicit=0
            if [[ "$action" == "purge" || "$action" == "remove" ]]; then
                for allowed in "$@"; do
                    [[ "$allowed" == "$action" || "$allowed" == -* ]] && continue
                    allowed="${allowed%%=*}"
                    allowed_base="${allowed%%:*}"
                    package_base="${package%%:*}"
                    if [[ "$package" == "$allowed" || "$package_base" == "$allowed_base" ]]; then
                        explicit=1
                        break
                    fi
                done
            elif [[ "$action" == "autoremove" ]]; then
                for allowed in "$@"; do
                    allowed_base="${allowed%%:*}"
                    package_base="${package%%:*}"
                    if [[ "$package" == "$allowed" || "$package_base" == "$allowed_base" ]]; then
                        explicit=1
                        break
                    fi
                done
            elif [[ "${CLEAN_INSTALL_SCOPE:-driver}" == "full" \
                   && "$package" =~ $NVIDIA_AUXILIARY_REGEX ]]; then
                explicit=1
            fi
            ((explicit)) && continue
            unexpected_removals+=("$package")
        done < <(parse_apt_plan_packages Remv "$simulation_file")
    fi

    while IFS=$'\t' read -r package version; do
        [[ -n "$package" ]] || continue
        if [[ "${MODE:-}" == "lxc" && "$package" =~ $LXC_FORBIDDEN_PACKAGE_REGEX ]]; then
            forbidden_installs+=("$package")
        fi
        if ((APT_POLICY_ENFORCE_TARGET_VERSION)) \
           && [[ -n "${TARGET_VERSION:-}" && "$package" =~ $NVIDIA_DRIVER_REGEX \
              && -n "$version" ]]; then
            normalized="$(normalize_driver_version "$version")"
            [[ -z "$normalized" || "$normalized" == "$TARGET_VERSION" ]] \
                || independent_package_version_is_manifested "$package" "$version" \
                || wrong_versions+=("$package=$version")
        fi
    done < <(parse_apt_install_plan "$simulation_file")

    ((${#unexpected_removals[@]} == 0)) \
        || die "APT-Plan abgelehnt: Eine Installation würde fremde Pakete entfernen: ${unexpected_removals[*]}. Details: $simulation_file"
    ((${#forbidden_installs[@]} == 0)) \
        || die "APT-Plan abgelehnt: Im LXC würden Kernel-/DKMS-/Host-Hilfspakete installiert: ${forbidden_installs[*]}. Details: $simulation_file"
    ((${#wrong_versions[@]} == 0)) \
        || die "APT-Plan abgelehnt: NVIDIA-Abhängigkeiten weichen von $TARGET_VERSION ab: ${wrong_versions[*]}. Details: $simulation_file"
}

record_planned_package_introductions() {
    local simulation_file="$1" manifest temporary
    is_safe_backup_dir "${BACKUP_DIR:-}" || return 0
    [[ -r "$BACKUP_DIR/packages-before.txt" ]] || return 0
    manifest="$BACKUP_DIR/packages-planned-by-transaction.txt"
    temporary="$(mktemp "$BACKUP_DIR/.packages-planned.XXXXXX")"
    {
        [[ -r "$manifest" ]] && cat "$manifest"
        parse_apt_install_plan "$simulation_file" | cut -f1
    } | sed '/^$/d' | sort -u >"$temporary"
    mv -f -- "$temporary" "$manifest"
    refresh_backup_checksums
}

apt_mutate() {
    local argument action="" simulation_file=""
    local -a approved_autoremove_packages=()
    assert_package_mutation_allowed
    for argument in "$@"; do
        case "$argument" in
            install|purge|remove|autoremove|upgrade|dist-upgrade|full-upgrade)
                action="$argument"
                break
                ;;
        esac
    done
    if [[ -n "$action" && " $* " != *' --download-only '* ]]; then
        simulation_file="${BACKUP_DIR:-${TMP_DIR:-/tmp}}/apt-simulation-${action}-$(date +%s%N).txt"
        log "APT-Sicherheitsprüfung: simuliere '$action' vor der Paketänderung."
        apt_simulate_readonly "$@" >"$simulation_file" \
            || die "APT-Simulation für '$action' fehlgeschlagen; es wurde nichts durch diesen Aufruf geändert. Details: $simulation_file"
        if [[ "$action" == "autoremove" && -n "${APT_AUTOREMOVE_APPROVED_PLAN:-}" ]]; then
            # Freigabe nur aus der aktiven, bereits DEB-gesicherten Phase.
            # Ein altes Anfangs-/Abschlussmanifest ist keine neue Freigabe.
            [[ -r "$APT_AUTOREMOVE_APPROVED_PLAN" ]] \
                || die "Autoremove-Freigabe kann nicht gelesen werden: $APT_AUTOREMOVE_APPROVED_PLAN"
            [[ "$(parse_apt_plan_packages Remv "$simulation_file")" \
                == "$(parse_apt_plan_packages Remv "$APT_AUTOREMOVE_APPROVED_PLAN")" ]] \
                || die "Autoremove-Plan hat sich nach der Sicherung geändert; keine Entfernung ausgeführt. Details: $simulation_file"
            [[ -z "$(awk '$1 == "Inst" || $1 == "Conf" {print $2}' "$simulation_file")" ]] \
                || die "Autoremove-Plan enthält zusätzliche Installations-/Konfigurationsschritte; keine Entfernung ausgeführt. Details: $simulation_file"
            mapfile -t approved_autoremove_packages < <(parse_apt_plan_packages Remv "$APT_AUTOREMOVE_APPROVED_PLAN")
        fi
        assert_apt_simulation_policy "$simulation_file" "$action" "$@" "${approved_autoremove_packages[@]}"
        if [[ "$action" == install && -n "${NVIDIA_UPDATE_ACTIVE_PLAN:-}" ]]; then
            assert_nvidia_update_plan "$simulation_file" "$NVIDIA_UPDATE_ACTIVE_PLAN"
        fi
        if [[ "$action" == purge ]]; then
            assert_clean_purge_plan "$simulation_file" "$@"
        fi
        if ((ROLLBACK_READY)) \
           && declare -F extend_rollback_packages_from_simulation >/dev/null 2>&1; then
            extend_rollback_packages_from_simulation "$simulation_file"
        fi
        record_planned_package_introductions "$simulation_file"
    fi
    MUTATION_STARTED=1
    write_transaction_phase "apt-${action:-metadaten}"
    run_apt_get "$@"
}

dpkg_mutate() {
    local simulation_file
    assert_package_mutation_allowed
    if [[ "$*" == *'--configure'* || "$*" == *' -i '* || "${1:-}" == "-i" ]]; then
        log "APT-Sicherheitsprüfung: simuliere Reparaturplan vor dem dpkg-Aufruf."
        simulation_file="${BACKUP_DIR:-${TMP_DIR:-/tmp}}/apt-simulation-before-dpkg-$(date +%s%N).txt"
        apt_simulate_readonly -f install >"$simulation_file" \
            || die "APT-Simulation vor dpkg ist fehlgeschlagen."
        assert_apt_simulation_policy "$simulation_file" install
        if ((ROLLBACK_READY)) \
           && declare -F extend_rollback_packages_from_simulation >/dev/null 2>&1; then
            extend_rollback_packages_from_simulation "$simulation_file"
        fi
        record_planned_package_introductions "$simulation_file"
    fi
    MUTATION_STARTED=1
    write_transaction_phase dpkg
    command dpkg "$@"
}

apt_mark_mutate() {
    assert_package_mutation_allowed
    MUTATION_STARTED=1
    write_transaction_phase apt-mark
    command apt-mark "$@"
}

list_apt_holds() {
    command apt-mark showhold 2>/dev/null || true
}

package_is_managed_nvidia_package() {
    local package="${1:-}"
    [[ -n "$package" ]] || return 1
    [[ "$package" =~ $NVIDIA_DRIVER_REGEX \
       || "$package" =~ $NVIDIA_AUXILIARY_REGEX \
       || "$package" =~ $NVIDIA_REPOSITORY_PACKAGE_REGEX ]]
}

list_managed_nvidia_holds() {
    local package
    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        package_is_managed_nvidia_package "$package" \
            && printf '%s\n' "$package"
    done < <(list_apt_holds)
    return 0
}

list_held_target_packages() {
    local held held_base target target_base
    local -a targets=("$@")

    ((${#targets[@]})) || return 0
    while IFS= read -r held; do
        [[ -n "$held" ]] || continue
        held_base="${held%%:*}"
        for target in "${targets[@]}"; do
            [[ -n "$target" ]] || continue
            target_base="${target%%:*}"
            if [[ "$held_base" == "$target_base" ]]; then
                printf '%s\n' "$held"
                break
            fi
        done
    done < <(list_apt_holds)
    return 0
}

remember_original_package_hold() {
    local package="${1:-}" existing
    [[ -n "$package" ]] || return 0
    for existing in "${NVIDIA_HOLDS[@]:-}"; do
        [[ "$existing" == "$package" ]] && return 0
    done
    NVIDIA_HOLDS+=("$package")
}

release_and_verify_package_holds() {
    local package
    local -a held=() remaining=()

    (($#)) || return 0
    mapfile -t held < <(list_held_target_packages "$@")
    if ((${#held[@]})); then
        for package in "${held[@]}"; do
            remember_original_package_hold "$package"
        done
        warn "Entferne Paketholds vor der NVIDIA-Bereinigung: ${held[*]}"
        apt_mark_mutate unhold "${held[@]}" \
            || die "Die Paketholds konnten nicht sicher aufgehoben werden: ${held[*]}"
        NVIDIA_HOLDS_RELEASED=1
    fi

    # Direkt nach apt-mark erneut aus der Paketdatenbank lesen. So erreicht ein
    # gehaltenes Alt-/Zusatzpaket niemals den simulierten oder echten Purge.
    mapfile -t remaining < <(list_held_target_packages "$@")
    ((${#remaining[@]} == 0)) \
        || die "Verbliebene Paketholds verhindern eine sichere NVIDIA-Bereinigung: ${remaining[*]}"
}

apt_simulate_readonly() {
    run_apt_get \
        -o Debug::NoLocking=1 \
        -o Dir::Cache::pkgcache= \
        -o Dir::Cache::srcpkgcache= \
        -s "$@"
}

run_apt_get() {
    if [[ "${NVIDIA_SETUP_TEST_MODE:-0}" == "1" ]] \
       && declare -F apt_get_test >/dev/null 2>&1; then
        apt_get_test "${BOOTSTRAP_APT_OPTIONS[@]}" "$@"
    else
        command apt-get "${BOOTSTRAP_APT_OPTIONS[@]}" "$@"
    fi
}

filter_bootstrap_nvidia_source() {
    local file="$1" uri="$2"
    case "$file" in
        *.sources)
            awk -v RS='' -v ORS='\n\n' -v target="${uri%/}" '
                {
                    n=split($0, lines, "\n"); uris=""; field=""; disabled=0
                    for (i=1; i<=n; i++) {
                        line=lines[i]; sub(/\r$/, "", line)
                        if (line ~ /^[[:space:]]*#/) continue
                        if (line ~ /^[^[:space:]][^:]*:/) {
                            field=tolower(line); sub(/:.*/, "", field)
                            sub(/^[^:]*:[[:space:]]*/, "", line)
                            if (field == "enabled" && tolower(line) ~ /^no[[:space:]]*$/) disabled=1
                        } else if (line !~ /^[[:space:]]/) field=""
                        if (field == "uris") uris=uris " " line
                    }
                    found=0; foreign=0; n=split(uris, values, /[[:space:]]+/)
                    for (i=1; i<=n; i++) {
                        value=values[i]; sub(/\/$/, "", value)
                        if (value == target) found=1
                        else if (value != "") foreign=1
                    }
                    if (found && !disabled) matched=1
                    if (found && !disabled && foreign) {fatal=42; exit}
                    if (!found || disabled) print
                }
                END {if (fatal) exit fatal; if (!matched) exit 10}
            ' "$file"
            ;;
        *)
            awk -v target="${uri%/}" '
                {
                    found=0
                    if ($0 ~ /^[[:space:]]*deb(-src)?[[:space:]]/) {
                        line=$0; sub(/#.*/, "", line)
                        sub(/^[[:space:]]*deb(-src)?[[:space:]]+/, "", line)
                        sub(/^\[[^]]*\][[:space:]]*/, "", line)
                        split(line, values, /[[:space:]]+/)
                        value=values[1]; sub(/\/$/, "", value)
                        if (value == target) found=1
                    }
                    if (!found) print
                    else matched=1
                }
                END {if (!matched) exit 10}
            ' "$file"
            ;;
    esac
}

prepare_nvidia_apt_source_view() {
    local root="${1:-/etc/apt}" key="${2:-}" output uri file relative canonical filter_rc
    local view="$BACKUP_DIR/apt-bootstrap"
    local -a files=() probe_options=(
        -o Debug::NoLocking=1 -o Dir::Cache::pkgcache= -o Dir::Cache::srcpkgcache=
        -o "Dir::Etc::sourcelist=$root/sources.list"
        -o "Dir::Etc::sourceparts=$root/sources.list.d"
    )
    ((CONFIG_MUTATION_ALLOWED && CHECK_ONLY == 0 && ATTACH_ONLY == 0 && DRY_RUN == 0)) \
        || die "Quellenvorbereitung ist in diesem schreibgeschützten Modus nicht erlaubt."
    BOOTSTRAP_APT_OPTIONS=()
    if output="$(apt-cache "${probe_options[@]}" policy 2>&1)"; then
        return 0
    fi
    printf '%s\n' "$output" >"$BACKUP_DIR/apt-source-bootstrap-error.log"
    uri="$(sed -n 's|.*Conflicting values set for option Signed-By regarding source \(https://developer\.download\.nvidia\.com/compute/cuda/repos/[^ ]*\) .*|\1|p' <<<"$output" | sort -u)"
    [[ "$uri" == "https://developer.download.nvidia.com/compute/cuda/repos/$DISTRO/x86_64/" ]] || {
        printf '%s\n' "$output" >&2
        die "APT-Quellen können nicht gelesen werden; kein eindeutig automatisch behebbarer NVIDIA-Signed-By-Konflikt. Es wurde nichts entfernt."
    }
    if [[ -z "$key" ]]; then
        for file in /usr/share/keyrings/cuda-archive-keyring.gpg \
            /var/lib/extrepo/keys/nvidia-cuda.asc /etc/apt/keyrings/nvidia-cuda.asc \
            /etc/apt/keyrings/cuda-archive-keyring.gpg /usr/share/keyrings/nvidia-cuda-keyring.gpg; do
            [[ -s "$file" && -r "$file" ]] || continue
            key="$file"
            break
        done
    fi
    [[ -n "$key" && -s "$key" && -r "$key" && "$key" != *[[:space:]]* ]] \
        || die "Kein lesbarer vorhandener NVIDIA-Schlüssel für die sichere Quellenansicht. Signaturprüfung wird nicht deaktiviert."
    [[ ! -e "$view" ]] || die "Eine Quellenansicht existiert bereits; ursprüngliche Sicherung wird nicht überschrieben."
    mkdir -p "$view/sources.list.d" "$view/originals/sources.list.d"
    : >"$view/sources.list"
    : >"$view/changed-files.txt"
    [[ ! -f "$root/sources.list" ]] || files+=("$root/sources.list")
    for file in "$root/sources.list.d/"*.list "$root/sources.list.d/"*.sources; do
        [[ ! -f "$file" ]] || files+=("$file")
    done
    for file in "${files[@]}"; do
        relative="${file#"$root/"}"
        # Dereferenzierte Kopie: niemals über einen kopierten Symlink schreiben.
        cp -L -- "$file" "$view/originals/$relative"
        if filter_bootstrap_nvidia_source "$file" "$uri" >"$view/$relative"; then
            :
        else
            filter_rc=$?
            if ((filter_rc == 10)); then
                # Unbeteiligte Quellen bytegenau erhalten, auch ohne Schluss-LF.
                cp -- "$view/originals/$relative" "$view/$relative"
            else
                die "Gemischte oder unlesbare NVIDIA-/Fremd-URIs in $file: sichere automatische Trennung nicht möglich. Original bleibt unverändert."
            fi
        fi
        if ! cmp -s "$file" "$view/$relative"; then
            [[ ! -L "$file" ]] || die "Quellen-Symlink $file wird nicht automatisch verändert."
            printf '%s\n' "$relative" >>"$view/changed-files.txt"
        fi
    done
    canonical="$(mktemp "$view/sources.list.d/nvidia-setup-bootstrap-XXXXXX.list")"
    relative="${canonical#"$view/"}"
    [[ ! -e "$root/$relative" && ! -L "$root/$relative" ]] \
        || die "Namenskollision beim Vorbereiten der NVIDIA-Quelle."
    printf 'deb [signed-by=%s] %s /\n' "$key" "$uri" >"$canonical"
    printf '%s\n' "$relative" >>"$view/changed-files.txt"
    BOOTSTRAP_APT_OPTIONS=(
        -o "Dir::Etc::sourcelist=$view/sources.list"
        -o "Dir::Etc::sourceparts=$view/sources.list.d"
    )
    if ! output="$(apt-cache -o Debug::NoLocking=1 -o Dir::Cache::pkgcache= \
        -o Dir::Cache::srcpkgcache= "${BOOTSTRAP_APT_OPTIONS[@]}" policy 2>&1)"; then
        printf '%s\n' "$output" >&2
        die "Auch die isolierte NVIDIA-Quellenansicht ist nicht lesbar. Keine aktiven Quellen oder Pakete verändert."
    fi
    # -o gilt nur für den jeweiligen APT-Prozess. apt-extracttemplates und
    # andere von dpkg-preconfigure gestartete APT-Werkzeuge erben diese Optionen
    # nicht. Für den Rollback die effektive Konfiguration samt Quellenansicht
    # sichern und über APT_CONFIG an Kindprozesse vererben. Alle anderen Optionen
    # (z.B. Proxy/Acquire/DPkg-Hooks) bleiben aus dem effektiven Dump erhalten.
    if ! apt-config "${BOOTSTRAP_APT_OPTIONS[@]}" dump >"$view/apt.conf"; then
        die "Die APT-Konfiguration für einen sicheren Rollback konnte nicht gesichert werden."
    fi
    mkdir -p "$view/empty-apt.conf.d"
    printf '\nDir::Etc::parts "%s";\nDir::Etc::main "/dev/null";\n' \
        "$view/empty-apt.conf.d" >>"$view/apt.conf"
    chmod 0600 "$view/apt.conf"
    printf '%s\n' "$key" >"$view/signing-key.txt"
    printf 'ready\n' >"$view/ready"
    warn "NVIDIA-Signed-By-Konflikt erkannt: Sicherung nutzt eine isolierte Quellenansicht mit bestehendem Schlüssel. Aktive Quellen bleiben vorerst unverändert."
}

apply_nvidia_apt_source_view() {
    local root="${1:-/etc/apt}" view="$BACKUP_DIR/apt-bootstrap" relative
    [[ -f "$view/ready" && ! -f "$view/applied" ]] || return 0
    ((ROLLBACK_READY && CONFIG_MUTATION_ALLOWED && CHECK_ONLY == 0 && ATTACH_ONLY == 0 && DRY_RUN == 0)) \
        || die "NVIDIA-Quellen dürfen erst nach einer vollständigen Rückkehrsicherung geändert werden."
    verify_backup_checksums "$BACKUP_DIR" || die "Quellenbereinigung verweigert: Sicherung ist beschädigt."
    # Alle Ziele vor der ersten Änderung prüfen, nicht erst während des Kopierens.
    while IFS= read -r relative; do
        case "$relative" in
            sources.list|sources.list.d/*.list|sources.list.d/*.sources) ;;
            *) die "Ungültiger Quellenpfad in der Sicherung: $relative" ;;
        esac
        [[ "$relative" != *..* && ! -L "$root/$relative" ]] \
            || die "Unsicherer Quellenpfad: $relative"
        if [[ -f "$view/originals/$relative" ]]; then
            cmp -s "$root/$relative" "$view/originals/$relative" \
                || cmp -s "$root/$relative" "$view/$relative" \
                || die "Quelle wurde zwischenzeitlich verändert: $root/$relative"
        else
            [[ ! -e "$root/$relative" ]] || cmp -s "$root/$relative" "$view/$relative" \
                || die "Neue Quelldatei kollidiert mit einer bestehenden Datei: $root/$relative"
        fi
    done <"$view/changed-files.txt"
    begin_config_mutation
    while IFS= read -r relative; do
        install -m 0644 -- "$view/$relative" "$root/$relative"
    done <"$view/changed-files.txt"
    printf 'applied\n' >"$view/applied"
    BOOTSTRAP_APT_OPTIONS=()
    refresh_backup_checksums
    ok "Doppelte NVIDIA-Quellen nach geprüfter Sicherung vereinheitlicht; fremde Paketquellen bleiben erhalten."
}

begin_config_mutation() {
    ((CONFIG_MUTATION_ALLOWED)) \
        || die "Interner Schutz: Eine Konfigurationsänderung wurde in einem schreibgeschützten Modus verhindert."
    MUTATION_STARTED=1
}

normalize_driver_version() {
    local value="${1:-}"
    value="${value%%-*}"
    if [[ "$value" =~ ([0-9]{3}\.[0-9]+\.[0-9]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    elif [[ "$value" =~ ([0-9]{3}\.[0-9]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    fi
}

is_valid_driver_version() {
    [[ "${1:-}" =~ ^[0-9]{3}\.[0-9]+\.[0-9]+$ ]]
}

apt_candidate_version() {
    local package="$1" policy_output rc

    # Eine optionale Abfrage darf weder Cache-Dateien schreiben noch den
    # globalen ERR-Trap auslösen. Erst vollständig lesen, dann auswerten:
    # ein frühes awk-exit in einer Pipe kann apt-cache per SIGPIPE abbrechen.
    if policy_output="$(apt-cache \
        -o Debug::NoLocking=1 \
        -o Dir::Cache::pkgcache= \
        -o Dir::Cache::srcpkgcache= \
        policy "$package" 2>&1)"; then
        awk '$1 == "Candidate:" && !found {print $2; found=1}' <<<"$policy_output"
    else
        rc=$?
        warn "APT-Kandidatenabfrage für $package fehlgeschlagen (Exit-Code $rc)." >&2
        [[ -z "$policy_output" ]] || printf '%s\n' "$policy_output" >&2
        return "$rc"
    fi
}

discover_available_driver_versions() {
    local package version madison candidate probe
    local -a discovered=()

    AVAILABLE_DRIVER_VERSIONS=()
    command -v apt-cache >/dev/null 2>&1 || return 0

    while IFS= read -r package; do
        [[ "$package" == nvidia-driver-pinning-* ]] || continue
        version="${package#nvidia-driver-pinning-}"
        is_valid_driver_version "$version" || continue
        madison="$(apt-cache madison "$package" 2>/dev/null || true)"
        [[ "$madison" == *developer.download.nvidia.com* ]] \
            && append_unique discovered "$version"
    done < <(apt-cache pkgnames nvidia-driver-pinning- 2>/dev/null || true)

    probe="$(driver_version_probe_package "${MODE:-host}")"
    if candidate="$(apt_candidate_version "$probe")"; then
        version="$(normalize_driver_version "$candidate")"
        if is_valid_driver_version "$version"; then
            madison="$(apt-cache madison "$probe" 2>/dev/null || true)"
            [[ "$madison" == *developer.download.nvidia.com* ]] \
                && append_unique discovered "$version"
        fi
    else
        warn "Optionale APT-Versionssuche übersprungen. Die verbindliche Paketprüfung erfolgt vor der NVIDIA-Installation." >&2
    fi

    if ((${#discovered[@]})); then
        mapfile -t AVAILABLE_DRIVER_VERSIONS < <(printf '%s\n' "${discovered[@]}" | sort -Vr)
    fi
}

preferred_modern_driver_version() {
    local version major
    for version in "${AVAILABLE_DRIVER_VERSIONS[@]:-}" "${BUILTIN_DRIVER_VERSIONS[@]}"; do
        is_valid_driver_version "$version" || continue
        major="${version%%.*}"
        ((10#$major >= 590)) || continue
        printf '%s' "$version"
        return 0
    done
    printf '610.43.02'
}

debian_version_epoch() {
    local value="${1:-}"
    [[ "$value" == *:* ]] && printf '%s' "${value%%:*}" || printf '0'
}

debian_version_without_epoch() {
    local value="${1:-}"
    [[ "$value" == *:* ]] && printf '%s' "${value#*:}" || printf '%s' "$value"
}

debian_version_upstream() {
    local value
    value="$(debian_version_without_epoch "${1:-}")"
    [[ "$value" == *-* ]] && printf '%s' "${value%-*}" || printf '%s' "$value"
}

debian_version_revision() {
    local value
    value="$(debian_version_without_epoch "${1:-}")"
    [[ "$value" == *-* ]] && printf '%s' "${value##*-}" || printf '0'
}

debian_versions_equal() {
    local left="${1:-}" right="${2:-}"
    [[ -n "$left" && -n "$right" ]] || return 1
    dpkg --compare-versions "$left" eq "$right"
}

configure_distribution_profile() {
    local id="$1" version="$2"
    OS_ID="$id"
    OS_VERSION_ID="$version"
    case "$id:$version" in
        debian:12)  DISTRO="debian12";  OS_LABEL="Debian 12" ;;
        debian:13)  DISTRO="debian13";  OS_LABEL="Debian 13" ;;
        ubuntu:22.04) DISTRO="ubuntu2204"; OS_LABEL="Ubuntu 22.04 LTS" ;;
        ubuntu:24.04) DISTRO="ubuntu2404"; OS_LABEL="Ubuntu 24.04 LTS" ;;
        ubuntu:26.04) DISTRO="ubuntu2604"; OS_LABEL="Ubuntu 26.04 LTS" ;;
        *)
            die "Unterstützt werden Debian 12/13 und Ubuntu 22.04/24.04/26.04; erkannt: ${id:-unbekannt} ${version:-unbekannt}."
            ;;
    esac
}

detect_distribution_profile() {
    local detected_id detected_version
    [[ -r /etc/os-release ]] || die "/etc/os-release fehlt."
    detected_id="$(. /etc/os-release; printf '%s' "${ID:-}")"
    detected_version="$(. /etc/os-release; printf '%s' "${VERSION_ID:-}")"
    configure_distribution_profile "$detected_id" "$detected_version"
    if command -v pveversion >/dev/null 2>&1 || [[ -d /etc/pve ]]; then
        IS_PROXMOX_HOST=1
    else
        IS_PROXMOX_HOST=0
    fi
}

driver_version_probe_package() {
    local effective_mode="${1:-${MODE:-host}}"
    if [[ "$OS_ID" == "ubuntu" ]]; then
        printf 'libnvidia-compute'
    elif [[ "$effective_mode" == "lxc" ]]; then
        printf 'libnvidia-ml1'
    else
        printf 'nvidia-driver-cuda'
    fi
}

build_target_package_profile() {
    PROFILE_USERSPACE_PACKAGES=()
    PREFLIGHT_DRIVER_PACKAGES=()
    VERIFY_USERSPACE_PACKAGES=()
    VERIFY_HOST_PACKAGES=()

    if [[ "$OS_ID" == "ubuntu" ]]; then
        PROFILE_USERSPACE_PACKAGES=(
            libnvidia-compute
            libnvidia-encode
            libnvidia-decode
        )
        VERIFY_USERSPACE_PACKAGES=("${PROFILE_USERSPACE_PACKAGES[@]}")
        PREFLIGHT_DRIVER_PACKAGES=("${PROFILE_USERSPACE_PACKAGES[@]}")
        if [[ "$MODE" == "host" ]]; then
            PROFILE_USERSPACE_PACKAGES=(nvidia-modprobe "${PROFILE_USERSPACE_PACKAGES[@]}")
            VERIFY_USERSPACE_PACKAGES=("${PROFILE_USERSPACE_PACKAGES[@]}")
            PREFLIGHT_DRIVER_PACKAGES=("${PROFILE_USERSPACE_PACKAGES[@]}")
            if [[ "$KERNEL_FLAVOR" == "open" ]]; then
                PREFLIGHT_DRIVER_PACKAGES+=(nvidia-dkms-open)
                VERIFY_HOST_PACKAGES=(nvidia-dkms-open)
            else
                PREFLIGHT_DRIVER_PACKAGES+=(nvidia-dkms)
                VERIFY_HOST_PACKAGES=(nvidia-dkms)
            fi
        fi
    else
        PROFILE_USERSPACE_PACKAGES=(
            libcuda1
            libnvidia-ml1
            libnvidia-encode1
            libnvcuvid1
        )
        if [[ "$MODE" == "host" ]]; then
            # Im offiziellen NVIDIA-Repository fuer Debian stellt
            # nvidia-driver-cuda das nvidia-smi-Werkzeug selbst bereit und
            # kollidiert deshalb mit dem gleichnamigen Einzelpaket. Fordert
            # APT beide explizit an, ist die exakte Installation unloesbar.
            PROFILE_USERSPACE_PACKAGES=(nvidia-modprobe "${PROFILE_USERSPACE_PACKAGES[@]}")
            VERIFY_USERSPACE_PACKAGES=("${PROFILE_USERSPACE_PACKAGES[@]}")
            PREFLIGHT_DRIVER_PACKAGES=(nvidia-driver-cuda "${PROFILE_USERSPACE_PACKAGES[@]}")
            if [[ "$KERNEL_FLAVOR" == "open" ]]; then
                PREFLIGHT_DRIVER_PACKAGES+=(nvidia-kernel-open-dkms)
                VERIFY_HOST_PACKAGES=(nvidia-driver-cuda nvidia-kernel-open-dkms)
            else
                PREFLIGHT_DRIVER_PACKAGES+=(nvidia-kernel-dkms)
                VERIFY_HOST_PACKAGES=(nvidia-driver-cuda nvidia-kernel-dkms)
            fi
        else
            # Im LXC ist das Treiber-Metapaket verboten; dort wird nur das
            # passende Userspace-Werkzeug als Einzelpaket installiert.
            PROFILE_USERSPACE_PACKAGES=(nvidia-smi "${PROFILE_USERSPACE_PACKAGES[@]}")
            VERIFY_USERSPACE_PACKAGES=("${PROFILE_USERSPACE_PACKAGES[@]}")
            PREFLIGHT_DRIVER_PACKAGES=("${PROFILE_USERSPACE_PACKAGES[@]}")
        fi
    fi
}

query_managed_nvidia_package_states() {
    local scope="${1:-full}" package version status
    case "$scope" in full|driver) ;; *) return 2 ;; esac

    while IFS=$'\t' read -r package version status; do
        [[ -n "$package" && "${status:0:2}" != "un" ]] || continue
        if [[ "$package" =~ $NVIDIA_DRIVER_REGEX \
              || "$package" =~ $NVIDIA_REPOSITORY_PACKAGE_REGEX \
              || ("$scope" == "full" && "$package" =~ $NVIDIA_AUXILIARY_REGEX) ]]; then
            printf '%s\t%s\t%s\n' "$package" "$version" "$status"
        fi
    done < <(dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' 2>/dev/null || true)
}

list_unrelated_broken_dpkg_states() {
    local scope="${1:-full}" package version status current_state
    case "$scope" in full|driver) ;; *) return 2 ;; esac

    while IFS=$'\t' read -r package version status; do
        [[ -n "$package" ]] || continue
        dpkg_status_is_healthy_installed "$status" && continue
        current_state="${status:1:1}"
        # not-installed und config-files werden durch --configure -a nicht
        # normalisiert und sind daher keine transaktionale Fremdänderung.
        case "$current_state" in n|c) continue ;; esac
        if [[ "$package" =~ $NVIDIA_DRIVER_REGEX \
              || "$package" =~ $NVIDIA_REPOSITORY_PACKAGE_REGEX \
              || ("$scope" == "full" && "$package" =~ $NVIDIA_AUXILIARY_REGEX) ]]; then
            continue
        fi
        printf '%s\t%s\t%s\n' "$package" "$version" "$status"
    done < <(dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' 2>/dev/null || true)
}

assert_no_unrelated_broken_dpkg_states() {
    local scope="${1:-full}" broken report=""
    broken="$(list_unrelated_broken_dpkg_states "$scope")"
    [[ -z "$broken" ]] && return 0
    if [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]]; then
        report="$BACKUP_DIR/unrelated-broken-dpkg-states.tsv"
        printf 'Paket\tVersion\tStatus\n%s\n' "$broken" >"$report"
        refresh_backup_checksums || true
    fi
    die "Nicht zur NVIDIA-Transaktion gehörende Pakete sind unvollständig konfiguriert. Sicherer Abbruch vor dpkg/APT-Mutationen; repariere zuerst diese Pakete.${report:+ Details: $report}"
}

package_profile_contains() {
    local needle="${1%%:*}" item item_base
    shift
    for item in "$@"; do
        item_base="${item%%=*}"
        item_base="${item_base%%:*}"
        [[ "$item_base" == "$needle" ]] && return 0
    done
    return 1
}

prepare_clean_install_apt_view() {
    local status_file="${1:-/var/lib/dpkg/status}" package version status
    local view="$BACKUP_DIR/clean-apt"
    [[ -r "$status_file" ]] || die "dpkg-Status für die Neuinstallationsplanung fehlt."
    mkdir -p "$view"
    query_managed_nvidia_package_states "$CLEAN_INSTALL_SCOPE" >"$view/inventory.tsv"
    CLEAN_REMOVE_PACKAGES=()
    while IFS=$'\t' read -r package version status; do
        [[ -n "$package" ]] || continue
        # Der frisch initialisierte Repository-Zugang bleibt bis zur Installation
        # verfügbar. Alte Versions-Pins werden dagegen mit entfernt.
        [[ "${package%%:*}" != cuda-keyring ]] || continue
        [[ -z "${PIN_PACKAGE:-}" || "${package%%:*}" != "$PIN_PACKAGE" ]] || continue
        append_unique CLEAN_REMOVE_PACKAGES "$package"
    done <"$view/inventory.tsv"
    printf '%s\n' "${CLEAN_REMOVE_PACKAGES[@]}" | sed '/^$/d' >"$view/remove.txt"
    # Nur eine private Modellkopie wird verändert, niemals /var/lib/dpkg/status.
    # Fremde Pakete samt ihren Abhängigkeiten bleiben für den Solver sichtbar.
    awk '
        FILENAME == ARGV[1] { removed[$0]=1; next }
        {
            if ($0 != "") { record=record $0 "\n" }
            if ($1 == "Package:") package=$2
            if ($1 == "Architecture:") arch=$2
            if ($0 == "") {
                if (record != "" && !(package in removed) && !((package ":" arch) in removed)) printf "%s\n", record
                record=""; package=""; arch=""
            }
        }
        END {
            if (record != "" && !(package in removed) && !((package ":" arch) in removed)) printf "%s\n", record
        }
    ' "$view/remove.txt" "$status_file" >"$view/status"
    CLEAN_APT_OPTIONS=(-o "Dir::State::status=$view/status"
        -o Debug::NoLocking=1 -o Dir::Cache::pkgcache= -o Dir::Cache::srcpkgcache=)
    refresh_backup_checksums
}

simulate_clean_target() {
    local output="$1" dependency
    shift
    # Vor- und Nach-Purge müssen dieselbe komplette Zielmenge verwenden.
    if ! DEBIAN_FRONTEND=noninteractive run_apt_get "${CLEAN_APT_OPTIONS[@]}" \
        -s install --fix-broken --reinstall --allow-downgrades \
        --no-install-recommends "$@" >"$output" 2>&1; then
        cat "$output" >&2
        if [[ "$MODE" == "lxc" ]]; then
            while IFS= read -r dependency; do
                if [[ "$dependency" =~ $LXC_FORBIDDEN_PACKAGE_REGEX ]]; then
                    die "Der exakte NVIDIA-Zielplan verlangt im LXC die verbotene Host-Komponente $dependency. Kein sicherer Bibliotheks-only-Paketplan verfügbar; vorhandene NVIDIA-Pakete bleiben unangetastet. Details: $output"
                fi
            done < <(sed -nE 's/.*Depends:[[:space:]]*([a-z0-9][a-z0-9+.-]*).*/\1/p' "$output" | sort -u)
        fi
        die "Neuinstallation ist auch ohne NVIDIA-Altbestand nicht lösbar. Keine Bereinigung auf Basis dieses Plans. Details: $output"
    fi
    assert_apt_simulation_policy "$output" install "$@"
}

assert_clean_purge_plan() {
    local simulation="$1" changes
    shift
    assert_apt_simulation_policy "$simulation" purge "$@"
    changes="$(awk '$1 == "Inst" || $1 == "Conf" {print}' "$simulation")"
    [[ -z "$changes" ]] \
        || die "Bereinigung abgelehnt: Der Purge würde Pakete installieren oder konfigurieren. Details: $simulation"
}

rollback_package_allowed() {
    [[ "${ROLLBACK_ROLE:-host}" != lxc \
       || ! "$1" =~ ${ROLLBACK_LXC_FORBIDDEN_REGEX:-$LXC_FORBIDDEN_PACKAGE_REGEX} ]]
}

install_clean_target_stack() {
    DEBIAN_FRONTEND=noninteractive apt_mutate \
        install -V -y --reinstall --no-install-recommends --allow-downgrades \
        --no-download "${EXACT_DRIVER_PACKAGE_SPECS[@]}" "${AUXILIARY_REINSTALL_DEBS[@]}"
}

rollback_role_plan_allowed() {
    local package
    while IFS= read -r package; do
        rollback_package_allowed "$package" || return 1
    done < <(awk '$1 == "Inst" || $1 == "Conf" {print $2}' "$1")
}

rollback_removal_plan_allowed() {
    local plan="$1" package explicit match
    shift
    while IFS= read -r package; do
        [[ "$package" =~ ${NVIDIA_REGEX:-$NVIDIA_DRIVER_REGEX} \
           || "$package" =~ ${NVIDIA_AUX_REGEX:-$NVIDIA_AUXILIARY_REGEX} \
           || "$package" =~ ^(cuda-keyring|cuda-repo-|nvidia-driver-local-repo-) ]] && continue
        match=0
        for explicit in "$@"; do
            [[ "${explicit%%:*}" != "${package%%:*}" ]] || { match=1; break; }
        done
        if ((match == 0)); then
            printf '[rollback] Fremdes Paket würde entfernt: %s; Plan abgelehnt.\n' "$package" >&2
            return 1
        fi
    done < <(awk '$1 == "Remv" || $1 == "Purg" {print $2}' "$plan")
    return 0
}

official_target_package_version() {
    if ((UPDATE_ONLY)); then
        latest_nvidia_update_version "$1" "$TARGET_VERSION"
        return
    fi
    local package="$1" line listed_package version source normalized foreign_match=0
    local madison_output=""
    local -a madison_lines=() official_versions=()

    madison_output="$(apt-cache madison "$package" 2>/dev/null || true)"
    [[ -n "$madison_output" ]] || return 1
    mapfile -t madison_lines <<<"$madison_output"
    for line in "${madison_lines[@]}"; do
        IFS='|' read -r listed_package version source <<<"$line" || continue
        version="${version#${version%%[![:space:]]*}}"
        version="${version%${version##*[![:space:]]}}"
        source="${source#${source%%[![:space:]]*}}"
        normalized="$(normalize_driver_version "$version")"
        [[ "$normalized" == "$TARGET_VERSION" ]] || continue
        if [[ "$source" == *developer.download.nvidia.com* ]]; then
            append_unique official_versions "$version"
        else
            foreign_match=1
        fi
    done

    ((foreign_match == 0 && ${#official_versions[@]} == 1)) || return 1
    printf '%s' "${official_versions[0]}"
}

independent_package_version_is_manifested() {
    local package="$1" version="$2" recorded recorded_version
    [[ "$package" =~ $NVIDIA_INDEPENDENT_OPTIONAL_REGEX \
       && -r "${BACKUP_DIR:-}/auxiliary-nvidia-package-versions.tsv" ]] || return 1
    while IFS=$'\t' read -r recorded recorded_version; do
        [[ "${recorded%%:*}" == "${package%%:*}" ]] || continue
        # APT druckt native Architektursuffixe nicht immer mit aus. Die komplette
        # DEB-Version muss trotzdem exakt dem ausdrücklich gesicherten Plan entsprechen.
        debian_versions_equal "$version" "$recorded_version" && return 0
    done <"$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv"
    return 1
}

transaction_package_architecture() {
    local package="$1" version="$2" file actual_package actual_version architecture
    local -a architectures=()

    # Nach der LXC-Vorbereinigung kann das Ausgangspaket bereits gepurgt sein.
    # Metadaten aus dem exakt gesicherten DEB bleiben auch beim Fortsetzen gültig.
    # Die Nutzdaten eines rekonstruierten Rollbacks werden NICHT zur Neuinstallation
    # verwendet; diese lädt weiterhin ein geprüftes Originalarchiv herunter.
    if [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR/rollback-debs" ]]; then
        while IFS= read -r -d '' file; do
            actual_package="$(dpkg-deb -f "$file" Package 2>/dev/null || true)"
            [[ "$actual_package" == "${package%%:*}" ]] || continue
            actual_version="$(dpkg-deb -f "$file" Version 2>/dev/null || true)"
            debian_versions_equal "$actual_version" "$version" || continue
            architecture="$(dpkg-deb -f "$file" Architecture 2>/dev/null || true)"
            [[ "$architecture" =~ ^[a-z0-9][a-z0-9-]*$ ]] || continue
            if [[ "$package" == *:* && "$architecture" != "${package##*:}" && "$architecture" != all ]]; then
                continue
            fi
            append_unique architectures "$architecture"
        done < <(find "$BACKUP_DIR/rollback-debs" -maxdepth 1 -type f -name '*.deb' -print0)
    fi
    if ((${#architectures[@]} == 1)); then
        printf '%s' "${architectures[0]}"
        return 0
    elif ((${#architectures[@]} > 1)); then
        warn "Mehrdeutige gesicherte Architektur für $package=$version; keine Architektur wird geraten."
        return 1
    fi
    # Kompatibilität mit Prüfungen vor der Sicherung und älteren Zuständen.
    architecture="$(dpkg-query -W -f='${Architecture}' "$package" 2>/dev/null || true)"
    [[ "$architecture" =~ ^[a-z0-9][a-z0-9-]*$ ]] || return 1
    printf '%s' "$architecture"
}

extend_target_profile_with_existing_optional_driver_packages() {
    local package current package_base architecture_suffix="" architecture=""
    local candidate mapped mapped_base current_driver old_major target_major disposition
    local map_tmp input_count=0 mapped_count=0

    OPTIONAL_DRIVER_TARGET_PACKAGES=()
    OPTIONAL_DRIVER_REINSTALL_DEBS=()
    VERIFY_OPTIONAL_DRIVER_PACKAGES=()
    map_tmp="$(mktemp "$BACKUP_DIR/.optional-driver-map.XXXXXX")"
    target_major="${TARGET_VERSION%%.*}"
    printf 'Ausgangspaket\tAusgangsversion\tDisposition\tZiel\n' >"$map_tmp"

    while IFS=$'\t' read -r package current; do
        [[ -n "$package" ]] || continue
        if [[ ! "$package" =~ $NVIDIA_DRIVER_REGEX \
              && ! "$package" =~ $NVIDIA_REPOSITORY_PACKAGE_REGEX \
              && "$package" != nvidia-driver-pinning* ]]; then
            continue
        fi
        input_count=$((input_count + 1))
        disposition=""

        if [[ "$package" == nvidia-driver-pinning* \
              || "$package" =~ $NVIDIA_REPOSITORY_PACKAGE_REGEX ]]; then
            disposition="repository-bootstrap-replaced"
            printf '%s\t%s\t%s\t-\n' "$package" "$current" "$disposition" >>"$map_tmp"
            continue
        fi
        if package_profile_contains "$package" "${PREFLIGHT_DRIVER_PACKAGES[@]}"; then
            disposition="covered-by-base-profile"
            printf '%s\t%s\t%s\t%s\n' "$package" "$current" "$disposition" "$package" >>"$map_tmp"
            continue
        fi
        if [[ "$MODE" == "lxc" && "$package" =~ $LXC_FORBIDDEN_PACKAGE_REGEX ]]; then
            disposition="removed-lxc-forbidden"
            printf '%s\t%s\t%s\t-\n' "$package" "$current" "$disposition" >>"$map_tmp"
            continue
        fi
        if [[ "$MODE" == "host" \
              && "$package" =~ ^((linux-(modules|objects|signatures)-nvidia)([-:].*)?|nvidia-(dkms|kernel|open)([-:].*)?)$ ]]; then
            disposition="replaced-by-host-kernel-profile"
            printf '%s\t%s\t%s\t%s\n' "$package" "$current" "$disposition" \
                "$(join_by ',' "${VERIFY_HOST_PACKAGES[@]}")" >>"$map_tmp"
            continue
        fi

        # Auch bisher "unabhängig" eingeordnete Werkzeuge können im NVIDIA-
        # Repository versionsgebundene Abhängigkeiten besitzen (xconfig/settings).
        # Ein vorhandener exakter Zielkandidat hat immer Vorrang vor Altarchiven.
        candidate="$(official_target_package_version "$package" || true)"
        if [[ -n "$candidate" ]]; then
            append_unique PREFLIGHT_DRIVER_PACKAGES "$package"
            append_unique OPTIONAL_DRIVER_TARGET_PACKAGES "$package"
            append_unique VERIFY_OPTIONAL_DRIVER_PACKAGES "$package"
            printf '%s\t%s\tmapped-to-target-package\t%s\n' "$package" "$current" "$package" >>"$map_tmp"
            continue
        fi

        if [[ "$package" =~ $NVIDIA_INDEPENDENT_OPTIONAL_REGEX ]]; then
            architecture="$(transaction_package_architecture "$package" "$current" || true)"
            [[ -n "$architecture" ]] \
                || die "Architektur der zusätzlichen NVIDIA-Komponente $package konnte nicht bestimmt werden."
            stage_trusted_reinstall_package_deb "$package" "$current" "$architecture" \
                "$BACKUP_DIR/optional-driver-reinstall-debs" \
                || die "Zusätzliche NVIDIA-Komponente $package=$current kann nicht aus einem geprüften Original-DEB neu installiert werden. Bereits erfolgte Änderungen werden über die Rückkehrsicherung behandelt."
            grep -qF "${package}"$'\t'"${current}" \
                "$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv" \
                || printf '%s\t%s\n' "$package" "$current" \
                    >>"$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv"
            disposition="independent-package-preserved"
            printf '%s\t%s\t%s\t%s=%s\n' "$package" "$current" "$disposition" "$package" "$current" >>"$map_tmp"
            continue
        fi

        package_base="${package%%:*}"
        architecture_suffix=""
        [[ "$package" != *:* ]] || architecture_suffix=":${package##*:}"
        current_driver="$(normalize_driver_version "$current")"
        old_major="${current_driver%%.*}"
        mapped_base="$package_base"
        if [[ "$old_major" =~ ^[0-9]{3}$ && "$package_base" == *"-${old_major}"* ]]; then
            mapped_base="${package_base/-${old_major}/-${target_major}}"
        fi
        mapped="${mapped_base}${architecture_suffix}"
        if [[ "$mapped" != "$package" ]]; then
            candidate="$(official_target_package_version "$mapped" || true)"
            if [[ -n "$candidate" ]]; then
                append_unique PREFLIGHT_DRIVER_PACKAGES "$mapped"
                append_unique OPTIONAL_DRIVER_TARGET_PACKAGES "$mapped"
                append_unique VERIFY_OPTIONAL_DRIVER_PACKAGES "$mapped"
                disposition="mapped-to-target-package"
                printf '%s\t%s\t%s\t%s\n' "$package" "$current" "$disposition" "$mapped" >>"$map_tmp"
                continue
            fi
        fi

        if [[ "$CLEAN_INSTALL_SCOPE" == "full" ]]; then
            disposition="obsolete-component-removed"
            printf '%s\t%s\t%s\t-\n' "$package" "$current" "$disposition" >>"$map_tmp"
            warn "Alte NVIDIA-Komponente $package=$current besitzt kein eindeutiges Gegenstück für $TARGET_VERSION. Bei der gewählten vollständigen Neuinstallation wird sie kontrolliert entfernt und nicht als veraltete Altlast zurückgespielt."
            continue
        fi

        rm -f -- "$map_tmp"
        die "Zusätzliche NVIDIA-Komponente $package=$current kann nicht eindeutig auf Treiber $TARGET_VERSION abgebildet werden. Wähle die vollständige Neuinstallation, um diese veraltete Komponente kontrolliert zu entfernen."
    done <"$BACKUP_DIR/nvidia-package-versions.tsv"

    mapped_count="$(awk 'NR > 1 { count++ } END { print count + 0 }' "$map_tmp")"
    [[ "$mapped_count" -eq "$input_count" ]] || {
        rm -f -- "$map_tmp"
        die "Interner Sicherheitsfehler: Nur $mapped_count von $input_count NVIDIA-Treiberkomponenten erhielten eine eindeutige Neuinstallationsbehandlung."
    }

    sort -u -o "$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv" \
        "$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv"
    mv -f -- "$map_tmp" "$BACKUP_DIR/optional-driver-package-map.tsv"
    while IFS= read -r -d '' mapped; do
        OPTIONAL_DRIVER_REINSTALL_DEBS+=("$mapped")
    done < <(find "$BACKUP_DIR/optional-driver-reinstall-debs" -maxdepth 1 \
        -type f -name '*.deb' -print0 2>/dev/null || true)
    refresh_backup_checksums
}

# Alte, nicht mehr von einem installierten DEB verwaltete NVIDIA-Dateien werden
# vor der Neuinstallation quarantänisiert. CUDA-Toolkit und
# libnvidia-container liegen absichtlich außerhalb dieser Allowlist.
legacy_nvidia_residual_path_is_safe() {
    local path="${1:-}"
    case "$path" in
        /etc/nvidia|/etc/nvidia/*|\
        /var/lib/nvidia|/var/lib/nvidia/*|\
        /var/cache/nvidia|/var/cache/nvidia/*|\
        /run/nvidia|/run/nvidia/*|/run/nvidia-persistenced|/run/nvidia-persistenced/*|\
        /usr/local/nvidia|/usr/local/nvidia/*|\
        /usr/lib/nvidia|/usr/lib/nvidia/*|\
        /usr/lib/x86_64-linux-gnu/nvidia|/usr/lib/x86_64-linux-gnu/nvidia/*|\
        /var/lib/dkms/nvidia*|/usr/src/nvidia-*|\
        /etc/modprobe.d/*nvidia*|/etc/modprobe.d/blacklist-nouveau.conf|\
        /etc/ld.so.conf.d/*nvidia*|\
        /etc/OpenCL/vendors/*nvidia*|\
        /etc/vulkan/icd.d/*nvidia*|/etc/vulkan/implicit_layer.d/*nvidia*|\
        /usr/share/vulkan/icd.d/*nvidia*|/usr/share/vulkan/implicit_layer.d/*nvidia*|\
        /usr/share/glvnd/egl_vendor.d/*nvidia*|/usr/share/nvidia|/usr/share/nvidia/*|\
        /etc/X11/xorg.conf|/etc/X11/xorg.conf.d/*nvidia*|\
        /etc/udev/rules.d/*nvidia*|\
        /etc/systemd/system/nvidia*.service|/etc/systemd/system/*/nvidia*.service|\
        /usr/lib/systemd/system/nvidia*.service|/lib/systemd/system/nvidia*.service|\
        /usr/local/lib/libnvidia*|/usr/local/lib/libcuda*|/usr/local/lib/libnvcuvid*|\
        /usr/local/lib64/libnvidia*|/usr/local/lib64/libcuda*|/usr/local/lib64/libnvcuvid*|\
        /usr/lib/x86_64-linux-gnu/libnvidia*|/usr/lib/x86_64-linux-gnu/libcuda*|\
        /usr/lib/x86_64-linux-gnu/libnvcuvid*|\
        /lib/x86_64-linux-gnu/libnvidia*|/lib/x86_64-linux-gnu/libcuda*|\
        /lib/x86_64-linux-gnu/libnvcuvid*|\
        /usr/local/bin/nvidia-smi|/usr/local/bin/nvidia-modprobe|\
        /usr/local/bin/nvidia-settings|/usr/local/bin/nvidia-xconfig|\
        /usr/local/bin/nvidia-persistenced|/usr/local/bin/nvidia-uninstall|\
        /usr/bin/nvidia-smi|/usr/bin/nvidia-uninstall|\
        /var/lib/nvidia-driver-setup/lxc-nvidia-smi-payload.env|\
        /var/log/nvidia-installer.log|/var/log/nvidia-uninstall.log)
            return 0
            ;;
        *) return 1 ;;
    esac
}

emit_legacy_nvidia_residual_candidates() {
    local root directory pattern path
    local -a roots=(
        /etc/nvidia
        /var/lib/nvidia
        /var/cache/nvidia
        /run/nvidia
        /run/nvidia-persistenced
        /usr/local/nvidia
        /usr/lib/nvidia
        /usr/lib/x86_64-linux-gnu/nvidia
        /usr/share/nvidia
    )
    local -a searches=(
        '/etc/modprobe.d|*nvidia*'
        '/etc/ld.so.conf.d|*nvidia*'
        '/etc/OpenCL/vendors|*nvidia*'
        '/etc/vulkan/icd.d|*nvidia*'
        '/etc/vulkan/implicit_layer.d|*nvidia*'
        '/usr/share/vulkan/icd.d|*nvidia*'
        '/usr/share/vulkan/implicit_layer.d|*nvidia*'
        '/usr/share/glvnd/egl_vendor.d|*nvidia*'
        '/etc/X11/xorg.conf.d|*nvidia*'
        '/etc/udev/rules.d|*nvidia*'
        '/usr/local/lib|libnvidia*'
        '/usr/local/lib|libcuda*'
        '/usr/local/lib|libnvcuvid*'
        '/usr/local/lib64|libnvidia*'
        '/usr/local/lib64|libcuda*'
        '/usr/local/lib64|libnvcuvid*'
        '/usr/lib/x86_64-linux-gnu|libnvidia*'
        '/usr/lib/x86_64-linux-gnu|libcuda*'
        '/usr/lib/x86_64-linux-gnu|libnvcuvid*'
        '/lib/x86_64-linux-gnu|libnvidia*'
        '/lib/x86_64-linux-gnu|libcuda*'
        '/lib/x86_64-linux-gnu|libnvcuvid*'
    )

    for root in "${roots[@]}"; do
        [[ -e "$root" || -L "$root" ]] || continue
        if [[ -L "$root" ]]; then
            printf '%s\0' "$root"
        else
            find "$root" -xdev \( -type f -o -type l \) -print0 2>/dev/null || true
        fi
    done
    while IFS= read -r -d '' root; do
        find "$root" -xdev \( -type f -o -type l \) -print0 2>/dev/null || true
    done < <(find /var/lib/dkms -mindepth 1 -maxdepth 1 -type d -iname 'nvidia*' -print0 2>/dev/null || true)
    while IFS= read -r -d '' root; do
        find "$root" -xdev \( -type f -o -type l \) -print0 2>/dev/null || true
    done < <(find /usr/src -mindepth 1 -maxdepth 1 -type d -iname 'nvidia-*' -print0 2>/dev/null || true)
    for path in \
        /etc/modprobe.d/blacklist-nouveau.conf \
        /usr/local/bin/nvidia-smi /usr/local/bin/nvidia-modprobe \
        /usr/local/bin/nvidia-settings /usr/local/bin/nvidia-xconfig \
        /usr/local/bin/nvidia-persistenced /usr/local/bin/nvidia-uninstall \
        /usr/bin/nvidia-smi /usr/bin/nvidia-uninstall \
        /var/lib/nvidia-driver-setup/lxc-nvidia-smi-payload.env \
        /var/log/nvidia-installer.log /var/log/nvidia-uninstall.log; do
        [[ -e "$path" || -L "$path" ]] && printf '%s\0' "$path"
    done
    if [[ -f /etc/X11/xorg.conf ]] && grep -qi 'nvidia' /etc/X11/xorg.conf; then
        printf '%s\0' /etc/X11/xorg.conf
    fi
    for path in /etc/systemd/system /usr/lib/systemd/system /lib/systemd/system; do
        [[ -d "$path" ]] || continue
        find "$path" -maxdepth 2 \( -type f -o -type l \) -iname 'nvidia*.service' -print0 2>/dev/null || true
    done
    for path in "${searches[@]}"; do
        IFS='|' read -r directory pattern <<<"$path"
        [[ -d "$directory" ]] || continue
        find "$directory" -maxdepth 1 \( -type f -o -type l \) -iname "$pattern" -print0 2>/dev/null || true
    done
}

collect_unowned_legacy_nvidia_residuals() {
    local path owner
    while IFS= read -r -d '' path; do
        [[ -e "$path" || -L "$path" ]] || continue
        [[ "$path" != /etc/modules-load.d/nvidia-lxc.conf ]] || continue
        [[ "$path" != *nvidia-lxc-device-sync-* ]] || continue
        legacy_nvidia_residual_path_is_safe "$path" || {
            warn "Nicht erlaubter NVIDIA-Restpfad wird nicht verändert: $path"
            continue
        }
        owner="$(dpkg-query -S "$path" 2>/dev/null | head -n1 || true)"
        if [[ -n "$owner" ]]; then
            [[ -z "${BACKUP_DIR:-}" ]] \
                || printf '%s\t%s\n' "$path" "$owner" >>"$BACKUP_DIR/legacy-residuals-retained-package-owned.txt"
            continue
        fi
        printf '%s\0' "$path"
    done < <(emit_legacy_nvidia_residual_candidates | sort -zu)
}

quarantine_legacy_nvidia_residuals() {
    local list="$BACKUP_DIR/legacy-residuals.list0"
    local archive="$BACKUP_DIR/legacy-residuals.tar"
    local path relative count=0

    : >"$BACKUP_DIR/legacy-residuals-retained-package-owned.txt"
    collect_unowned_legacy_nvidia_residuals >"$list"
    : >"$BACKUP_DIR/legacy-residuals.txt"
    while IFS= read -r -d '' path; do
        legacy_nvidia_residual_path_is_safe "$path" \
            || die "Unsicherer NVIDIA-Restpfad in der Bereinigungsliste: $path"
        printf '%s\n' "$path" >>"$BACKUP_DIR/legacy-residuals.txt"
        count=$((count + 1))
    done <"$list"
    if ((count == 0)); then
        rm -f -- "$list"
        ok "Keine unverwalteten alten NVIDIA-Dateireste gefunden."
        refresh_backup_checksums
        return 0
    fi

    if ! tar --null -C / -cpf "$archive" -T "$list" \
       || ! tar -tf "$archive" >"$BACKUP_DIR/legacy-residuals-archive-contents.txt"; then
        rm -f -- "$archive" "$list" \
            "$BACKUP_DIR/legacy-residuals.txt" \
            "$BACKUP_DIR/legacy-residuals-retained-package-owned.txt" \
            "$BACKUP_DIR/legacy-residuals-archive-contents.txt"
        die "Die alten NVIDIA-Dateireste konnten nicht vollständig archiviert werden; es wurde noch keine Altdatei entfernt."
    fi
    if ! refresh_backup_checksums; then
        rm -f -- "$archive" "$list" \
            "$BACKUP_DIR/legacy-residuals.txt" \
            "$BACKUP_DIR/legacy-residuals-retained-package-owned.txt" \
            "$BACKUP_DIR/legacy-residuals-archive-contents.txt"
        die "Das Prüfsummenmanifest für die NVIDIA-Altdateien konnte nicht atomar aktualisiert werden; es wurde noch keine Altdatei entfernt."
    fi
    while IFS= read -r -d '' path; do
        legacy_nvidia_residual_path_is_safe "$path" \
            || die "Unsicherer NVIDIA-Restpfad vor dem Entfernen: $path"
        rm -f -- "$path"
    done <"$list"

    collect_unowned_legacy_nvidia_residuals >"$BACKUP_DIR/legacy-residuals-after-cleanup.list0"
    [[ ! -s "$BACKUP_DIR/legacy-residuals-after-cleanup.list0" ]] \
        || die "Nicht alle alten unverwalteten NVIDIA-Dateireste konnten entfernt werden."
    refresh_backup_checksums
    command -v ldconfig >/dev/null 2>&1 && ldconfig || true
    command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true
    ok "$count alte unverwaltete NVIDIA-Dateireste gesichert und entfernt."
}

verify_all_installed_nvidia_driver_versions() {
    local package debian_version normalized
    local -a mixed=()
    : >"$BACKUP_DIR/all-installed-nvidia-versions-after.txt"
    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        debian_version="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
        normalized="$(normalize_driver_version "$debian_version")"
        printf '%s\t%s\t%s\n' "$package" "${debian_version:-nicht installiert}" \
            "${normalized:-nicht als Treiberversion erkennbar}" \
            >>"$BACKUP_DIR/all-installed-nvidia-versions-after.txt"
        if independent_package_version_is_manifested "$package" "$debian_version"; then
            # Explizit klassifizierte, treiberzweig-unabhängige optionale
            # Komponenten besitzen absichtlich ihre eigene DEB-Version.
            continue
        fi
        [[ "$normalized" == "$TARGET_VERSION" ]] || mixed+=("$package=${debian_version:-fehlt}")
    done < <(get_installed_nvidia_driver_packages)
    ((${#mixed[@]} == 0)) \
        || die "Nach der Neuinstallation sind noch NVIDIA-Pakete mit fremdem Versionsstand vorhanden: ${mixed[*]}"
    ok "Alle treiberzweiggebundenen NVIDIA-Pakete gehören zum Zielstand $TARGET_VERSION; klassifizierte unabhängige Komponenten wurden exakt geprüft."
}

record_repair_action() {
    append_unique REPAIR_ACTIONS "$1"
}

record_repair_unresolved() {
    append_unique REPAIR_UNRESOLVED "$1"
    block_success_backup_cleanup "$1"
}

write_automatic_repair_report() {
    local file="${BACKUP_DIR:-}/automatic-repair-summary.txt" item
    is_safe_backup_dir "${BACKUP_DIR:-}" || return 0
    if ((${#REPAIR_UNRESOLVED[@]})) \
       || ((DIAGNOSTIC_ERROR_COUNT > 0)) \
       || ((SUCCESS_BACKUP_CLEANUP_BLOCKED && REBOOT_REQUIRED == 0)); then
        REPAIR_OUTCOME="unresolved"
    elif ((REBOOT_REQUIRED)); then
        REPAIR_OUTCOME="reboot-required"
    else
        REPAIR_OUTCOME="resolved"
    fi
    {
        printf 'Ergebnis: %s\n' "$REPAIR_OUTCOME"
        printf 'Ausgeführt:\n'
        if ((${#REPAIR_ACTIONS[@]})); then
            for item in "${REPAIR_ACTIONS[@]}"; do printf '  - %s\n' "$item"; done
        else
            printf '  - keine Änderung erforderlich\n'
        fi
        printf 'Offen:\n'
        if ((${#REPAIR_UNRESOLVED[@]})); then
            for item in "${REPAIR_UNRESOLVED[@]}"; do printf '  - %s\n' "$item"; done
        elif ((REBOOT_REQUIRED)); then
            for item in "${REBOOT_REASONS[@]}"; do printf '  - Neustart: %s\n' "$item"; done
        else
            printf '  - nichts\n'
        fi
    } >"$file"
    refresh_backup_checksums
}

run_automatic_preinstall_repair() {
    local audit_before="$BACKUP_DIR/dpkg-audit-before-auto-repair.txt"
    local apt_check_before="$BACKUP_DIR/apt-check-before-auto-repair.txt"
    local simulation="$BACKUP_DIR/apt-fix-simulation-before-clean-install.txt"

    ((AUTOMATIC_REPAIR)) || {
        log "Automatische Fehleranalyse/-behebung wurde deaktiviert."
        return 0
    }
    dpkg --audit >"$audit_before" 2>&1 || true
    if apt-get check >"$apt_check_before" 2>&1 && [[ ! -s "$audit_before" ]]; then
        ok "APT- und dpkg-Ausgangszustand sind konsistent."
        return 0
    fi

    warn "APT/dpkg meldet einen unvollständigen Zustand; starte eine simulierte automatische Reparatur."
    apt_simulate_readonly -f install >"$simulation" \
        || die "APT kann den defekten Paketstand nicht sicher simuliert reparieren. Details: $simulation"
    APT_POLICY_ENFORCE_TARGET_VERSION=0
    assert_apt_simulation_policy "$simulation" install
    extend_rollback_packages_from_simulation "$simulation"
    DEBIAN_FRONTEND=noninteractive apt_mutate -f install -y
    dpkg_mutate --configure -a
    record_repair_action "APT-Abhängigkeiten repariert und unvollständige dpkg-Konfiguration abgeschlossen"
    APT_POLICY_ENFORCE_TARGET_VERSION=1

    dpkg --audit >"$BACKUP_DIR/dpkg-audit-after-auto-repair.txt" 2>&1 || true
    apt-get check >"$BACKUP_DIR/apt-check-after-auto-repair.txt" 2>&1 \
        || die "APT ist nach der automatischen Reparatur weiterhin inkonsistent."
    [[ ! -s "$BACKUP_DIR/dpkg-audit-after-auto-repair.txt" ]] \
        || die "dpkg meldet nach der automatischen Reparatur weiterhin unvollständige Pakete."
    ok "APT-/dpkg-Fehler wurden automatisch behoben."
}

run_automatic_postinstall_repair() {
    local ld_cache="" apt_repair_needed=0 package_repair_needed=0 kernel
    local nvml_log="$BACKUP_DIR/nvidia-smi-before-post-repair.txt"

    ((AUTOMATIC_REPAIR)) || return 0
    log "Führe automatische Fehleranalyse und sichere Nachbesserungen aus ..."
    dpkg --audit >"$BACKUP_DIR/dpkg-audit-after-install.txt" 2>&1 || true
    apt-get check >"$BACKUP_DIR/apt-check-after-install.txt" 2>&1 || apt_repair_needed=1
    if [[ -s "$BACKUP_DIR/dpkg-audit-after-install.txt" || $apt_repair_needed -eq 1 ]]; then
        warn "dpkg meldet nach der Installation unvollständige Pakete; konfiguriere und repariere erneut."
        DEBIAN_FRONTEND=noninteractive apt_mutate -f install -y
        dpkg_mutate --configure -a
        dpkg --audit >"$BACKUP_DIR/dpkg-audit-after-post-repair.txt" 2>&1 || true
        [[ ! -s "$BACKUP_DIR/dpkg-audit-after-post-repair.txt" ]] \
            || die "Die automatische Nachreparatur konnte den dpkg-Zustand nicht vollständig korrigieren."
        apt-get check >"$BACKUP_DIR/apt-check-after-post-repair.txt" 2>&1 \
            || die "APT ist nach der automatischen Nachreparatur weiterhin inkonsistent."
        record_repair_action "APT-/dpkg-Endzustand nach der Installation repariert"
    fi

    command -v ldconfig >/dev/null 2>&1 && ldconfig || true
    ld_cache="$(ldconfig -p 2>/dev/null || true)"
    grep -q 'libnvidia-encode\.so' <<<"$ld_cache" || package_repair_needed=1
    grep -q 'libnvcuvid\.so' <<<"$ld_cache" || package_repair_needed=1
    command -v nvidia-smi >/dev/null 2>&1 || package_repair_needed=1
    if ((package_repair_needed)); then
        warn "NVIDIA-Werkzeug oder NVENC/NVDEC-Linker-Eintrag fehlt; installiere nur deshalb den exakten Zielpaketsatz einmal automatisch nach."
        DEBIAN_FRONTEND=noninteractive apt_mutate install -V -y --reinstall \
            --allow-downgrades --no-install-recommends "${EXACT_DRIVER_PACKAGE_SPECS[@]}"
        dpkg_mutate --configure -a
        command -v ldconfig >/dev/null 2>&1 && ldconfig || true
        record_repair_action "Exakten NVIDIA-Zielpaketsatz einmalig neu installiert"
    fi

    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi -L >"$nvml_log" 2>&1 || true
    else
        printf 'nvidia-smi ist nicht installiert oder nicht im PATH.\n' >"$nvml_log"
    fi

    if [[ "$MODE" == "host" ]]; then
        kernel="$(uname -r)"
        command -v depmod >/dev/null 2>&1 && depmod -a "$kernel" || true
        if [[ ! -d /sys/module/nouveau ]]; then
            modprobe nvidia >"$BACKUP_DIR/auto-repair-modprobe-nvidia.txt" 2>&1 \
                || {
                    REBOOT_REQUIRED=1
                    append_unique REBOOT_REASONS "NVIDIA-Kernelmodul konnte im laufenden Kernel nicht geladen werden"
                    warn "NVIDIA-Kernelmodul konnte noch nicht geladen werden; ein Host-Neustart ist erforderlich."
                }
            modprobe nvidia_uvm >"$BACKUP_DIR/auto-repair-modprobe-uvm.txt" 2>&1 \
                || {
                    REBOOT_REQUIRED=1
                    append_unique REBOOT_REASONS "nvidia_uvm konnte im laufenden Kernel nicht geladen werden"
                    warn "nvidia_uvm konnte noch nicht geladen werden; Diagnose und Neustartprüfung folgen."
                }
        fi
        if command -v nvidia-modprobe >/dev/null 2>&1; then
            if nvidia-modprobe -u -c=0 >"$BACKUP_DIR/auto-repair-device-nodes.txt" 2>&1; then
                command -v udevadm >/dev/null 2>&1 && udevadm trigger --subsystem-match=misc --subsystem-match=char >/dev/null 2>&1 || true
                command -v udevadm >/dev/null 2>&1 && udevadm settle >/dev/null 2>&1 || true
                record_repair_action "NVIDIA-Geräteknoten über nvidia-modprobe/udev synchronisiert"
            fi
        fi
    fi

    if command -v nvidia-smi >/dev/null 2>&1 \
       && nvidia-smi -L >"$BACKUP_DIR/nvidia-smi-after-auto-repair.txt" 2>&1; then
        record_repair_action "NVML-Abfrage nach Reparatur erfolgreich verifiziert"
    else
        if [[ "$MODE" == "host" && $REBOOT_REQUIRED -eq 1 ]]; then
            block_success_backup_cleanup "NVML-Prüfung erst nach dem erforderlichen Host-Neustart möglich"
        else
            record_repair_unresolved "nvidia-smi/NVML funktioniert nach dem begrenzten Reparaturversuch weiterhin nicht"
        fi
    fi
    write_automatic_repair_report
    ok "Automatische Nachanalyse abgeschlossen; verbleibende nicht sicher behebbare Punkte erscheinen in der Abschlussdiagnose."
}

run_standalone_automatic_repair() {
    local kernel dkms_rc=0 module_rc=0 package version status ld_cache="" runtime_repair_needed=0
    local reinstall_simulation="$BACKUP_DIR/repair-only-package-reinstall-simulation.txt"
    local nvml_before="$BACKUP_DIR/nvidia-smi-before-repair-only.txt"
    local -a reinstall_specs=() forbidden_lxc_packages=()

    log "Analysiere APT, dpkg und die NVIDIA-Laufzeit und führe nur sichere Reparaturversuche aus ..."
    audit_nvidia_repository_configuration \
        || warn "Die NVIDIA-Paketquellen sind nicht eindeutig; eine bereinigende Neuinstallation über Menüpunkt 1 wird empfohlen."
    command -v ldconfig >/dev/null 2>&1 && ldconfig || true
    ld_cache="$(ldconfig -p 2>/dev/null || true)"
    if ! command -v nvidia-smi >/dev/null 2>&1 \
       || ! nvidia-smi -L >"$nvml_before" 2>&1; then
        runtime_repair_needed=1
    fi
    grep -q 'libnvidia-encode\.so' <<<"$ld_cache" || runtime_repair_needed=1
    grep -q 'libnvcuvid\.so' <<<"$ld_cache" || runtime_repair_needed=1

    if ((runtime_repair_needed)); then
        while IFS=$'\t' read -r package version status; do
            dpkg_status_is_healthy_installed "$status" || continue
            [[ "$(normalize_driver_version "$version")" == "$TARGET_VERSION" ]] || continue
            if [[ "$MODE" == "lxc" && "$package" =~ $LXC_FORBIDDEN_PACKAGE_REGEX ]]; then
                continue
            fi
            reinstall_specs+=("${package}=${version}")
        done < <(
            dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' 2>/dev/null \
                | awk -F'\t' -v re="$NVIDIA_DRIVER_REGEX" '$1 ~ re {print}'
        )
        if ((${#reinstall_specs[@]})); then
            if apt_simulate_readonly install -V --reinstall --no-install-recommends \
                    "${reinstall_specs[@]}" >"$reinstall_simulation"; then
                assert_apt_simulation_policy "$reinstall_simulation" install
                extend_rollback_packages_from_simulation "$reinstall_simulation"
                DEBIAN_FRONTEND=noninteractive apt_mutate install -V -y --reinstall \
                    --no-install-recommends "${reinstall_specs[@]}"
                command -v ldconfig >/dev/null 2>&1 && ldconfig || true
                record_repair_action "Exakt installierte NVIDIA-Laufzeitpakete erneut eingespielt"
                ok "Beschädigte oder fehlende NVIDIA-Laufzeitdateien wurden aus den exakt installierten Paketversionen wiederhergestellt."
            else
                warn "Die exakt installierten NVIDIA-Paketversionen sind nicht sicher erneut verfügbar; es wurde keine Paketänderung ausgeführt."
            fi
        else
            warn "NVIDIA-Laufzeitkomponenten fehlen, aber es wurde kein sicher exakt reinstallierbarer Paketsatz gefunden. Nutze für eine saubere Neuinstallation Menüpunkt 1."
        fi
    fi

    if [[ "$MODE" == "lxc" ]]; then
        mapfile -t forbidden_lxc_packages < <(
            dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null \
                | awk '$2 !~ /^un/ {print $1}' | grep -E "$LXC_FORBIDDEN_PACKAGE_REGEX" \
                | sort -u || true
        )
        if ((${#forbidden_lxc_packages[@]})); then
            warn "Entferne im LXC unzulässige Kernel-/DKMS-/Host-Hilfspakete: ${forbidden_lxc_packages[*]}"
            DEBIAN_FRONTEND=noninteractive apt_mutate purge -y "${forbidden_lxc_packages[@]}"
            record_repair_action "Unzulässige NVIDIA-Kernel-/DKMS-/Host-Hilfspakete aus dem LXC entfernt"
        fi
    fi

    if [[ "$MODE" == "host" ]]; then
        kernel="$(uname -r)"
        if command -v dkms >/dev/null 2>&1 \
           && dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' 2>/dev/null \
                | grep -qE '^.i[[:space:]].*(nvidia|cuda).*dkms'; then
            dkms autoinstall -k "$kernel" >"$BACKUP_DIR/repair-only-dkms-autoinstall.txt" 2>&1 \
                || dkms_rc=$?
            ((dkms_rc == 0)) \
                && ok "DKMS-Module für $kernel wurden geprüft/nachgebaut." \
                || record_repair_unresolved "DKMS-Autoinstall für $kernel blieb fehlerhaft"
        fi
        command -v depmod >/dev/null 2>&1 && depmod -a "$kernel" || true
        if command -v update-initramfs >/dev/null 2>&1; then
            update-initramfs -u -k "$kernel" >"$BACKUP_DIR/repair-only-initramfs.txt" 2>&1 \
                || warn "initramfs konnte nicht automatisch aktualisiert werden."
        fi

        if ! grep -RqsE '^[[:space:]]*blacklist[[:space:]]+nouveau([[:space:]]|$)' \
                /etc/modprobe.d 2>/dev/null; then
            begin_config_mutation
            cat >/etc/modprobe.d/blacklist-nouveau.conf <<'EOF_REPAIR_NOUVEAU_BASELINE'
# Erstellt durch nvidia-driver-setup-v2.13.3.sh
blacklist nouveau
options nouveau modeset=0
EOF_REPAIR_NOUVEAU_BASELINE
            command -v update-initramfs >/dev/null 2>&1 \
                && update-initramfs -u -k "$kernel" >"$BACKUP_DIR/repair-only-initramfs-nouveau-baseline.txt" 2>&1 || true
            record_repair_action "Fehlende Nouveau-Blacklist sicher ergänzt"
        fi

        if [[ -d /sys/module/nouveau ]]; then
            warn "Nouveau ist geladen und wird im laufenden Betrieb nicht automatisch entladen; ein kontrollierter Neustart kann erforderlich sein."
            begin_config_mutation
            cat >/etc/modprobe.d/blacklist-nouveau.conf <<'EOF_REPAIR_NOUVEAU'
# Erstellt durch nvidia-driver-setup-v2.13.3.sh
blacklist nouveau
options nouveau modeset=0
EOF_REPAIR_NOUVEAU
            command -v update-initramfs >/dev/null 2>&1 \
                && update-initramfs -u -k "$kernel" >"$BACKUP_DIR/repair-only-initramfs-nouveau.txt" 2>&1 || true
            REBOOT_REQUIRED=1
            append_unique REBOOT_REASONS "Nouveau ist geladen und wurde für den nächsten Start deaktiviert"
            block_success_backup_cleanup "Nouveau-Umstellung erfordert einen Host-Neustart"
            record_repair_action "Nouveau sicher für den nächsten Start deaktiviert"
        else
            modprobe nvidia >"$BACKUP_DIR/repair-only-modprobe-nvidia.txt" 2>&1 || module_rc=$?
            modprobe nvidia_uvm >"$BACKUP_DIR/repair-only-modprobe-uvm.txt" 2>&1 || module_rc=$?
            ((module_rc == 0)) \
                || {
                    REBOOT_REQUIRED=1
                    append_unique REBOOT_REASONS "NVIDIA-Kernelmodule konnten nicht vollständig geladen werden"
                    block_success_backup_cleanup "Kernelmodulprüfung erfordert Neustart oder Secure-Boot-Klärung"
                    warn "NVIDIA-Kernelmodule konnten noch nicht vollständig geladen werden; Secure Boot, DKMS und Neustartbedarf werden diagnostiziert."
                }
        fi
        if command -v nvidia-modprobe >/dev/null 2>&1; then
            if nvidia-modprobe -u -c=0 >"$BACKUP_DIR/repair-only-device-nodes.txt" 2>&1; then
                command -v udevadm >/dev/null 2>&1 && udevadm trigger >/dev/null 2>&1 || true
                command -v udevadm >/dev/null 2>&1 && udevadm settle >/dev/null 2>&1 || true
                record_repair_action "NVIDIA-Geräteknoten über nvidia-modprobe/udev synchronisiert"
            fi
        fi
    fi

    dpkg --audit >"$BACKUP_DIR/dpkg-audit-after-repair-only.txt" 2>&1 || true
    apt-get check >"$BACKUP_DIR/apt-check-after-repair-only.txt" 2>&1 \
        || die "APT ist nach den sicheren Reparaturversuchen weiterhin inkonsistent."
    [[ ! -s "$BACKUP_DIR/dpkg-audit-after-repair-only.txt" ]] \
        || die "dpkg meldet nach der Reparatur weiterhin unvollständige Pakete."
    if command -v nvidia-smi >/dev/null 2>&1 \
       && nvidia-smi -L >"$BACKUP_DIR/nvidia-smi-after-repair-only.txt" 2>&1; then
        record_repair_action "NVML-Abfrage erfolgreich verifiziert"
    elif [[ "$MODE" == "host" && $REBOOT_REQUIRED -eq 1 ]]; then
        block_success_backup_cleanup "NVML-Prüfung erst nach dem erforderlichen Host-Neustart möglich"
    else
        record_repair_unresolved "nvidia-smi/NVML funktioniert nach der Reparatur weiterhin nicht"
    fi
    capture_nvidia_diagnostic_bundle reparatur
    write_automatic_repair_report
    refresh_backup_checksums
    ok "Automatische Fehleranalyse und sichere Reparaturversuche abgeschlossen."
}

append_unique() {
    local array_name="$1"
    local value="$2"
    local existing
    [[ -n "$value" ]] || return 0
    # shellcheck disable=SC2178,SC1087
    local -n target_array="$array_name"
    for existing in "${target_array[@]:-}"; do
        [[ "$existing" == "$value" ]] && return 0
    done
    target_array+=("$value")
}

join_by() {
    local delimiter="$1"
    shift
    local first=1 value
    for value in "$@"; do
        ((first)) || printf '%s' "$delimiter"
        printf '%s' "$value"
        first=0
    done
}

classify_gpu_model() {
    local model="${1^^}"

    # Marketingnamen überschneiden sich teilweise. Spezifische Produktfamilien
    # müssen deshalb vor den allgemeineren Mustern geprüft werden.
    if [[ "$model" =~ (GEFORCE[[:space:]]+RTX[[:space:]]+50|RTX[[:space:]]+PRO.*BLACKWELL|GB[0-9]{2,3}|(^|[^A-Z0-9])B(100|200|300)([^0-9]|$)) ]]; then
        printf 'blackwell'
    elif [[ "$model" =~ ((^|[^A-Z0-9])(H20|H100|H200|H800|GH200)([^0-9]|$)) ]]; then
        printf 'hopper'
    elif [[ "$model" =~ (GEFORCE[[:space:]]+RTX[[:space:]]+40|RTX[[:space:]]+(500|1000|2000|3000|3500|4000|4500|5000|5880|6000)[[:space:]]+ADA|(^|[^A-Z0-9])L(2|4|20|40|40S)([^0-9]|$)|AD[0-9]{2,3}) ]]; then
        printf 'ada'
    elif [[ "$model" =~ (GEFORCE[[:space:]]+RTX[[:space:]]+30|RTX[[:space:]]+A(400|500|1000|2000|3000|4000|4500|5000|5500|6000)|(^|[^A-Z0-9])A(2|10|16|30|40|100|800)([^0-9]|$)|GA[0-9]{2,3}) ]]; then
        printf 'ampere'
    elif [[ "$model" =~ (GEFORCE[[:space:]]+RTX[[:space:]]+20|GEFORCE[[:space:]]+GTX[[:space:]]+16|QUADRO[[:space:]]+RTX|TITAN[[:space:]]+RTX|(^|[^A-Z0-9])T(4|400|500|600|1000|1200)([^0-9]|$)|TU[0-9]{2,3}) ]]; then
        printf 'turing'
    elif [[ "$model" =~ (TESLA[[:space:]]+V100|QUADRO[[:space:]]+GV|TITAN[[:space:]]+V([^A-Z0-9]|$)|GV[0-9]{2,3}) ]]; then
        printf 'volta'
    elif [[ "$model" =~ (GEFORCE[[:space:]]+GTX[[:space:]]+10|QUADRO[[:space:]]+P[0-9]|TESLA[[:space:]]+P[0-9]|(^|[^A-Z0-9])P(4|40|100)([^0-9]|$)|GP[0-9]{2,3}) ]]; then
        printf 'pascal'
    elif [[ "$model" =~ (GEFORCE[[:space:]]+GTX[[:space:]]+(9|7(45|50))|QUADRO[[:space:]]+M[0-9]|TESLA[[:space:]]+M[0-9]|(^|[^A-Z0-9])M(4|6|40|60)([^0-9]|$)|GM[0-9]{2,3}) ]]; then
        printf 'maxwell'
    elif [[ "$model" =~ (GEFORCE.*(GTX[[:space:]]+6|GTX[[:space:]]+7)|QUADRO[[:space:]]+K[0-9]|TESLA[[:space:]]+K[0-9]|GK[0-9]{2,3}) ]]; then
        printf 'kepler'
    else
        printf 'unknown'
    fi
}

detect_gpu_hardware() {
    local line model pci_id generation info_file device vendor class
    local smi_output=""

    DETECTED_GPU_MODELS=()
    DETECTED_GPU_PCI_IDS=()
    DETECTED_GPU_GENERATIONS=()

    # 1. nvidia-smi liefert den zuverlässigsten Produktnamen, wenn NVML funktioniert.
    if command -v nvidia-smi >/dev/null 2>&1; then
        if smi_output="$(nvidia-smi --query-gpu=name,pci.device_id --format=csv,noheader 2>/dev/null)"; then
            while IFS=',' read -r model pci_id; do
                model="${model#"${model%%[![:space:]]*}"}"
                model="${model%"${model##*[![:space:]]}"}"
                pci_id="${pci_id//[[:space:]]/}"
                pci_id="${pci_id#0x}"
                pci_id="${pci_id:0:4}"
                append_unique DETECTED_GPU_MODELS "$model"
                [[ "$pci_id" =~ ^[0-9A-Fa-f]{4}$ ]] \
                    && append_unique DETECTED_GPU_PCI_IDS "${pci_id^^}"
            done <<<"$smi_output"
        fi
    fi

    # 2. Funktioniert NVML nicht, ist das Modell oft weiterhin unter /proc sichtbar.
    if ((${#DETECTED_GPU_MODELS[@]} == 0)) && [[ -d /proc/driver/nvidia/gpus ]]; then
        while IFS= read -r -d '' info_file; do
            model="$(awk -F: '/^Model:/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' "$info_file" 2>/dev/null || true)"
            append_unique DETECTED_GPU_MODELS "$model"
        done < <(find /proc/driver/nvidia/gpus -mindepth 2 -maxdepth 2 -name information -print0 2>/dev/null || true)
    fi

    # 3. Auf dem Host bleibt lspci auch bei einem Treiber-/NVML-Mismatch nutzbar.
    if ((${#DETECTED_GPU_MODELS[@]} == 0)) && command -v lspci >/dev/null 2>&1; then
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            pci_id="$(sed -nE 's/.*\[10de:([0-9A-Fa-f]{4})\].*/\1/p' <<<"$line" | head -n1)"
            model="$(sed -E 's/^[^ ]+[[:space:]]+[^:]+:[[:space:]]*//' <<<"$line")"
            model="$(sed -E 's/[[:space:]]*\[[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}\].*$//' <<<"$model")"
            append_unique DETECTED_GPU_MODELS "$model"
            [[ "$pci_id" =~ ^[0-9A-Fa-f]{4}$ ]] \
                && append_unique DETECTED_GPU_PCI_IDS "${pci_id^^}"
        done < <(lspci -Dnn 2>/dev/null | grep -iE 'NVIDIA.*\[(0300|0302|0380)\]|(VGA|3D|Display).*NVIDIA' || true)
    fi

    # 4. Letzter Fallback: NVIDIA-Displaygeräte direkt in sysfs erkennen.
    if ((${#DETECTED_GPU_PCI_IDS[@]} == 0)); then
        for device in /sys/bus/pci/devices/*; do
            [[ -r "$device/vendor" && -r "$device/device" && -r "$device/class" ]] || continue
            vendor="$(<"$device/vendor")"
            class="$(<"$device/class")"
            [[ "${vendor,,}" == "0x10de" && "${class,,}" == 0x03* ]] || continue
            pci_id="$(<"$device/device")"
            pci_id="${pci_id#0x}"
            append_unique DETECTED_GPU_PCI_IDS "${pci_id^^}"
        done
    fi

    for model in "${DETECTED_GPU_MODELS[@]:-}"; do
        generation="$(classify_gpu_model "$model")"
        append_unique DETECTED_GPU_GENERATIONS "$generation"
    done

    if ((${#DETECTED_GPU_MODELS[@]})); then
        DETECTED_GPU_SUMMARY="$(join_by '; ' "${DETECTED_GPU_MODELS[@]}")"
    elif ((${#DETECTED_GPU_PCI_IDS[@]})); then
        DETECTED_GPU_SUMMARY="NVIDIA PCI-ID(s): $(join_by ', ' "${DETECTED_GPU_PCI_IDS[@]}")"
    else
        DETECTED_GPU_SUMMARY="nicht erkannt"
    fi
}

detect_driver_versions() {
    local effective_mode="${1:-${MODE:-auto}}"
    local raw="" package_status="" version_package="" package version normalized
    local -a installed_driver_versions=() mixed_details=()

    DETECTED_HOST_MODULE_VERSION=""
    DETECTED_HOST_MODULE_SOURCE=""
    DETECTED_HOST_MODULE_LOADED=0
    DETECTED_PACKAGE_VERSION=""
    DETECTED_PACKAGE_DEBIAN_VERSION=""
    DETECTED_INSTALLED_MODULE_VERSION=""
    DETECTED_SMI_VERSION=""
    DETECTED_VERSION_STATE="nicht installiert"

    if [[ -r /sys/module/nvidia/version ]]; then
        raw="$(</sys/module/nvidia/version)"
        DETECTED_HOST_MODULE_VERSION="$(normalize_driver_version "$raw")"
        DETECTED_HOST_MODULE_SOURCE="/sys/module/nvidia/version"
        DETECTED_HOST_MODULE_LOADED=1
    elif [[ -r /proc/driver/nvidia/version ]]; then
        raw="$(cat /proc/driver/nvidia/version 2>/dev/null || true)"
        DETECTED_HOST_MODULE_VERSION="$(normalize_driver_version "$raw")"
        DETECTED_HOST_MODULE_SOURCE="/proc/driver/nvidia/version"
        DETECTED_HOST_MODULE_LOADED=1
    fi
    # modinfo beschreibt die installierte Moduldatei, nicht das laufende Modul.
    # Beide Stände werden deshalb getrennt erfasst und explizit verglichen.
    if [[ "$effective_mode" != "lxc" ]] && command -v modinfo >/dev/null 2>&1; then
        raw="$(modinfo -F version nvidia 2>/dev/null | head -n1 || true)"
        DETECTED_INSTALLED_MODULE_VERSION="$(normalize_driver_version "$raw")"
        if [[ -z "$DETECTED_HOST_MODULE_VERSION" && -n "$DETECTED_INSTALLED_MODULE_VERSION" ]]; then
            DETECTED_HOST_MODULE_SOURCE="kein NVIDIA-Modul geladen"
        fi
    fi

    version_package="$(driver_version_probe_package "$effective_mode")"
    raw="$(dpkg-query -W -f='${Version}' "$version_package" 2>/dev/null || true)"
    package_status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$version_package" 2>/dev/null || true)"
    dpkg_status_is_healthy_installed "$package_status" || raw=""
    if [[ -z "$raw" && "$OS_ID" == "ubuntu" ]]; then
        raw="$(
            dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' 'libnvidia-compute*' 2>/dev/null \
                | awk -F'\t' '$1 ~ /^libnvidia-compute(-[0-9]+)?(:.*)?$/ && substr($3, 2, 1) == "i" && substr($3, 3, 1) != "R" {print $2; exit}' \
                || true
        )"
    fi
    DETECTED_PACKAGE_DEBIAN_VERSION="$raw"
    DETECTED_PACKAGE_VERSION="$(normalize_driver_version "$raw")"

    while IFS=$'\t' read -r package version package_status; do
        dpkg_status_is_healthy_installed "$package_status" || continue
        [[ "$package" =~ $NVIDIA_DRIVER_REGEX ]] || continue
        # Hilfsprogramme/X-Control sind unabhängig versioniert und gehören
        # nicht zum versionsgleichen Kernel-/CUDA-/NVML-Treiberstack.
        [[ ! "$package" =~ $NVIDIA_INDEPENDENT_OPTIONAL_REGEX ]] || continue
        normalized="$(normalize_driver_version "$version")"
        [[ -n "$normalized" ]] || continue
        append_unique installed_driver_versions "$normalized"
        mixed_details+=("$package=$version")
    done < <(dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' 2>/dev/null || true)

    if command -v nvidia-smi >/dev/null 2>&1; then
        if raw="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1)"; then
            DETECTED_SMI_VERSION="$(normalize_driver_version "$raw")"
        fi
    fi

    if [[ "$effective_mode" == "lxc" && -z "$DETECTED_HOST_MODULE_VERSION" \
          && -n "$DETECTED_SMI_VERSION" ]]; then
        DETECTED_HOST_MODULE_VERSION="$DETECTED_SMI_VERSION"
        DETECTED_HOST_MODULE_SOURCE="nvidia-smi"
        DETECTED_HOST_MODULE_LOADED=1
    fi

    if [[ "$effective_mode" == "lxc" && -z "$DETECTED_HOST_MODULE_VERSION" \
          && -n "$EXPECTED_HOST_VERSION" ]]; then
        DETECTED_HOST_MODULE_VERSION="$EXPECTED_HOST_VERSION"
        DETECTED_HOST_MODULE_SOURCE="--host-version (nicht lokal verifiziert)"
    fi

    if ((${#installed_driver_versions[@]} > 1)); then
        DETECTED_VERSION_STATE="Mismatch: mehrere installierte NVIDIA-Treiberstände ($(join_by ', ' "${installed_driver_versions[@]}"))"
    elif [[ "$effective_mode" != "lxc" && -n "$DETECTED_INSTALLED_MODULE_VERSION" \
          && -n "$DETECTED_HOST_MODULE_VERSION" \
          && "$DETECTED_INSTALLED_MODULE_VERSION" != "$DETECTED_HOST_MODULE_VERSION" ]]; then
        DETECTED_VERSION_STATE="Mismatch: geladen $DETECTED_HOST_MODULE_VERSION / Moduldatei $DETECTED_INSTALLED_MODULE_VERSION / Paket ${DETECTED_PACKAGE_DEBIAN_VERSION:-unbekannt}"
    elif [[ -n "$DETECTED_HOST_MODULE_VERSION" && -n "$DETECTED_PACKAGE_VERSION" ]]; then
        if [[ "$DETECTED_HOST_MODULE_VERSION" == "$DETECTED_PACKAGE_VERSION" ]]; then
            DETECTED_VERSION_STATE="konsistent: $DETECTED_PACKAGE_VERSION (DEB: $DETECTED_PACKAGE_DEBIAN_VERSION)"
        else
            DETECTED_VERSION_STATE="Mismatch: geladen $DETECTED_HOST_MODULE_VERSION / Paket $DETECTED_PACKAGE_DEBIAN_VERSION"
        fi
    elif [[ "$effective_mode" != "lxc" && -n "$DETECTED_INSTALLED_MODULE_VERSION" ]]; then
        DETECTED_VERSION_STATE="Moduldatei: $DETECTED_INSTALLED_MODULE_VERSION; geladen: keines; Paket: ${DETECTED_PACKAGE_DEBIAN_VERSION:-fehlt}"
    elif [[ -n "$DETECTED_HOST_MODULE_VERSION" ]]; then
        DETECTED_VERSION_STATE="Kernelmodul: $DETECTED_HOST_MODULE_VERSION"
    elif [[ -n "$DETECTED_PACKAGE_VERSION" ]]; then
        DETECTED_VERSION_STATE="Pakete: $DETECTED_PACKAGE_VERSION"
    fi
}

determine_gpu_compatibility() {
    local generation
    local has_legacy=0
    local has_modern=0
    local has_unknown=0

    for generation in "${DETECTED_GPU_GENERATIONS[@]:-}"; do
        case "$generation" in
            turing|ampere|ada|hopper|blackwell) has_modern=1 ;;
            maxwell|pascal|volta|kepler) has_legacy=1 ;;
            *) has_unknown=1 ;;
        esac
    done

    if ((has_legacy && has_modern)); then
        GPU_COMPATIBILITY="mixed-legacy"
    elif ((has_legacy)); then
        GPU_COMPATIBILITY="legacy"
    elif ((has_modern && has_unknown)); then
        GPU_COMPATIBILITY="mixed-unknown"
    elif ((has_modern)); then
        GPU_COMPATIBILITY="modern"
    elif ((has_unknown)); then
        GPU_COMPATIBILITY="unknown"
    else
        GPU_COMPATIBILITY="unknown"
    fi
}

determine_recommendation() {
    local effective_mode="$1" preferred_version

    determine_gpu_compatibility
    preferred_version="$(preferred_modern_driver_version)"
    RECOMMENDED_KERNEL="open"
    RECOMMENDED_VERSION="$preferred_version"
    RECOMMENDATION_REASON="Für aktuelle NVENC/NVDEC-Workloads wird die höchste passende Version aus dem offiziellen APT-Cache bevorzugt."

    if [[ "$effective_mode" == "lxc" && -z "$DETECTED_HOST_MODULE_VERSION" ]]; then
        RECOMMENDED_VERSION="host-version-required"
        RECOMMENDED_KERNEL="not-applicable"
        RECOMMENDATION_REASON="Im LXC muss die geladene NVIDIA-Version des Hosts sicher erkannt oder mit --host-version angegeben werden."
        return 0
    fi

    # Im LXC muss die Userspace-Version in erster Linie exakt zum Host-Kernelmodul passen.
    if [[ "$effective_mode" == "lxc" && -n "$DETECTED_HOST_MODULE_VERSION" ]]; then
        if is_valid_driver_version "$DETECTED_HOST_MODULE_VERSION"; then
            RECOMMENDED_VERSION="$DETECTED_HOST_MODULE_VERSION"
            RECOMMENDATION_REASON="Der LXC muss exakt zum geladenen NVIDIA-Kernelmodul des Hosts passen; die Repository-Verfügbarkeit wird vor jeder Änderung geprüft."
        else
            RECOMMENDED_VERSION="unsupported-host-version"
            RECOMMENDATION_REASON="Die geladene Host-Version konnte nicht als vollständige NVIDIA-Version ausgewertet werden."
        fi
    fi

    case "$GPU_COMPATIBILITY" in
        legacy|mixed-legacy)
            RECOMMENDED_VERSION="legacy-580"
            RECOMMENDED_KERNEL="proprietary"
            RECOMMENDATION_REASON="Maxwell, Pascal und Volta benötigen den 580-Legacy-Zweig; Kepler benötigt 470. Dieses Skript unterstützt diese Legacy-Zweige nicht."
            ;;
        modern)
            RECOMMENDED_KERNEL="open"
            if [[ "$effective_mode" != "lxc" || -z "$DETECTED_HOST_MODULE_VERSION" ]]; then
                RECOMMENDED_VERSION="$preferred_version"
                RECOMMENDATION_REASON="Für Turing und neuer ist das offene Kernelmodul empfohlen; gewählt wird die höchste passende Version aus dem offiziellen APT-Cache."
            fi
            ;;
        unknown|mixed-unknown)
            RECOMMENDED_KERNEL="manual"
            if [[ "$effective_mode" != "lxc" ]]; then
                RECOMMENDED_VERSION="$preferred_version"
                RECOMMENDATION_REASON="Mindestens eine GPU-Generation ist nicht eindeutig erkannt; die Kernelmodul-Variante muss explizit gewählt werden."
            fi
            ;;
    esac
}

refresh_hardware_detection() {
    local effective_mode="$1"
    detect_gpu_hardware
    detect_driver_versions "$effective_mode"
    discover_available_driver_versions
    determine_recommendation "$effective_mode"
}

print_detection_summary() {
    printf '  Erkannte GPU(s):      %s\n' "$DETECTED_GPU_SUMMARY"
    printf '  Installierter Stand:  %s\n' "$DETECTED_VERSION_STATE"
    if [[ -n "$DETECTED_HOST_MODULE_SOURCE" ]]; then
        printf '  Modulquelle:          %s\n' "$DETECTED_HOST_MODULE_SOURCE"
    fi
    if [[ -n "$DETECTED_INSTALLED_MODULE_VERSION" ]]; then
        printf '  Installierte Moduldatei: %s\n' "$DETECTED_INSTALLED_MODULE_VERSION"
    fi
    if [[ -n "$DETECTED_PACKAGE_DEBIAN_VERSION" ]]; then
        printf '  DEB-Paketversion:     %s (Epoch %s, Revision %s)\n' \
            "$DETECTED_PACKAGE_DEBIAN_VERSION" \
            "$(debian_version_epoch "$DETECTED_PACKAGE_DEBIAN_VERSION")" \
            "$(debian_version_revision "$DETECTED_PACKAGE_DEBIAN_VERSION")"
    fi
    if [[ -n "$DETECTED_SMI_VERSION" ]]; then
        printf '  nvidia-smi:           %s\n' "$DETECTED_SMI_VERSION"
    fi
    case "$RECOMMENDED_VERSION" in
        legacy-580)
            printf '  Empfehlung:           NVIDIA 580 + proprietäres Kernelmodul\n'
            ;;
        unsupported-host-version)
            printf '  Empfehlung:           exakt Host-Version %s im LXC\n' "${DETECTED_HOST_MODULE_VERSION:-unbekannt}"
            ;;
        host-version-required)
            printf '  Empfehlung:           Host-Version im LXC erforderlich\n'
            ;;
        *)
            printf '  Empfehlung:           NVIDIA %s\n' "$RECOMMENDED_VERSION"
            ;;
    esac
    printf '  Begründung:           %s\n' "$RECOMMENDATION_REASON"
}

detect_reboot_requirement() {
    local installed_module=""
    local reason

    REBOOT_REQUIRED=0
    REBOOT_REASONS=()
    [[ "${MODE:-auto}" == "host" ]] || return 0

    if command -v modinfo >/dev/null 2>&1; then
        installed_module="$(normalize_driver_version "$(modinfo -F version nvidia 2>/dev/null | head -n1 || true)")"
    fi
    if [[ -n "$installed_module" && "$installed_module" != "${DETECTED_HOST_MODULE_VERSION:-}" ]]; then
        append_unique REBOOT_REASONS \
            "geladenes Modul ${DETECTED_HOST_MODULE_VERSION:-nicht geladen}, installiertes Modul $installed_module"
    fi
    if [[ -n "${DETECTED_PACKAGE_VERSION:-}" && -n "${DETECTED_HOST_MODULE_VERSION:-}" \
          && "$DETECTED_PACKAGE_VERSION" != "$DETECTED_HOST_MODULE_VERSION" ]]; then
        append_unique REBOOT_REASONS \
            "Paketversion $DETECTED_PACKAGE_VERSION, geladenes Modul $DETECTED_HOST_MODULE_VERSION"
    fi
    if [[ -e /var/run/reboot-required ]]; then
        append_unique REBOOT_REASONS "/var/run/reboot-required ist vorhanden"
    fi
    if [[ -d /sys/module/nouveau ]]; then
        append_unique REBOOT_REASONS "Nouveau ist noch geladen"
    fi

    if ((${#REBOOT_REASONS[@]})); then
        REBOOT_REQUIRED=1
    fi

    for reason in "${REBOOT_REASONS[@]:-}"; do
        [[ -n "$reason" ]] || continue
        warn "Neustartgrund: $reason"
    done
}

diagnostic_line() {
    local state="$1" label="$2" detail="$3"
    [[ "$state" != "FEHLER" ]] || DIAGNOSTIC_ERROR_COUNT=$((DIAGNOSTIC_ERROR_COUNT + 1))
    printf '  %-8s %-18s %s\n' "[$state]" "$label" "$detail"
}

refresh_source_file_list() {
    local file
    APT_SOURCE_FILES=()
    [[ -f /etc/apt/sources.list ]] && APT_SOURCE_FILES+=(/etc/apt/sources.list)
    for file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [[ -f "$file" ]] && APT_SOURCE_FILES+=("$file")
    done
}

audit_nvidia_repository_configuration() {
    local file line repo_distro
    local require_official="${1:-0}"
    local network=0 local_repo=0 legacy_key=0 foreign_distro=0
    local -a findings=()

    refresh_source_file_list
    for file in "${APT_SOURCE_FILES[@]:-}"; do
        [[ -r "$file" ]] || continue
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            case "$line" in
                *developer.download.nvidia.com/compute/cuda/repos*)
                    network=1
                    append_unique findings "Netzwerk: $file"
                    repo_distro="$(sed -nE 's#.*developer\.download\.nvidia\.com/compute/cuda/repos/([^/[:space:]]+)/.*#\1#p' <<<"$line" | head -n1)"
                    if [[ -n "$repo_distro" && -n "${DISTRO:-}" && "$repo_distro" != "$DISTRO" ]]; then
                        foreign_distro=1
                        append_unique findings "Falsche Distribution $repo_distro: $file (erwartet: $DISTRO)"
                    fi
                    ;;
                *file:/var/cuda-repo*|*file:/var/nvidia-driver-local-repo*|*/var/cuda-repo*|*/var/nvidia-driver-local-repo*)
                    local_repo=1
                    append_unique findings "Lokal: $file"
                    ;;
            esac
            [[ "$line" == *'/etc/apt/keyrings/nvidia-cuda.asc'* ]] && legacy_key=1
        done <"$file"
    done

    printf '\nNVIDIA-Repository-Prüfung:\n'
    if ((foreign_distro)); then
        diagnostic_line FEHLER "Paketquellen" "NVIDIA-Repository für eine andere Distribution aktiv"
        printf '    %s\n' "${findings[@]}"
        return 1
    elif ((network && local_repo)); then
        diagnostic_line FEHLER "Paketquellen" "Netzwerk- und Local-Repository sind gleichzeitig aktiv"
        printf '    %s\n' "${findings[@]}"
        return 1
    elif ((legacy_key && network)); then
        diagnostic_line WARN "Paketquellen" "Netzwerk-Repository verwendet eine alte manuelle Schlüsselkonfiguration"
    elif ((network)); then
        diagnostic_line OK "Paketquellen" "offizielles NVIDIA-Netzwerk-Repository"
    elif ((local_repo)); then
        diagnostic_line WARN "Paketquellen" "lokales NVIDIA-Repository aktiv"
    else
        if ((require_official)); then
            diagnostic_line FEHLER "Paketquellen" "offizielles NVIDIA-Netzwerk-Repository fehlt"
            return 1
        fi
        diagnostic_line INFO "Paketquellen" "kein NVIDIA-spezifisches Repository aktiv"
    fi
    return 0
}

ensure_official_nvidia_repository_source() {
    local distro="${1:-${DISTRO:-}}"
    local keyring="${2:-/usr/share/keyrings/cuda-archive-keyring.gpg}"
    local source_file="${3:-/etc/apt/sources.list.d/cuda-${distro}-x86_64.list}"
    local source_dir expected temporary

    [[ "$distro" =~ ^(debian12|debian13|ubuntu2204|ubuntu2404|ubuntu2604)$ ]] || {
        warn "Unsicherer NVIDIA-Repository-Code: ${distro:-leer}"
        return 1
    }
    [[ -s "$keyring" ]] || {
        warn "NVIDIA-Repository-Schluessel fehlt oder ist leer: $keyring"
        return 1
    }
    source_dir="$(dirname -- "$source_file")"
    [[ -d "$source_dir" ]] || {
        warn "APT-Quellenverzeichnis fehlt: $source_dir"
        return 1
    }

    expected="deb [signed-by=${keyring}] https://developer.download.nvidia.com/compute/cuda/repos/${distro}/x86_64/ /"
    if [[ -f "$source_file" ]] && [[ "$(<"$source_file")" == "$expected" ]]; then
        return 0
    fi

    begin_config_mutation
    temporary="$(mktemp "${source_file}.nvidia.XXXXXX")" || return 1
    printf '%s\n' "$expected" >"$temporary"
    chmod 0644 "$temporary"
    mv -f -- "$temporary" "$source_file"
    ok "Offizielle NVIDIA-Paketquelle wiederhergestellt: $source_file"
}

install_temporary_version_preference() {
    local destination="/etc/apt/preferences.d/nvidia-driver-setup-transaction.pref"
    local temporary

    is_valid_driver_version "${TARGET_VERSION:-}" \
        || die "Für den temporären Paket-Pin fehlt eine gültige NVIDIA-Zielversion."
    begin_config_mutation
    temporary="$(mktemp "${destination}.XXXXXX")"
    {
        printf 'Package: nvidia-* libnvidia-* libcuda* libnvcuvid* cuda-drivers* firmware-nvidia-gsp\n'
        printf 'Pin: version *%s*\n' "$TARGET_VERSION"
        printf 'Pin-Priority: 1001\n'
    } >"$temporary"
    chmod 0644 "$temporary"
    mv -f -- "$temporary" "$destination"
    TEMPORARY_VERSION_PREFERENCE="$destination"
    write_resume_state
    refresh_backup_checksums
    apt_mutate update
    ok "Temporäre exakte APT-Versionspräferenz eingerichtet: $TARGET_VERSION"
}

remove_obsolete_nvidia_pin_files() {
    local preferences_dir="${1:-/etc/apt/preferences.d}" pin_file
    [[ -d "$preferences_dir" ]] || return 0

    while IFS= read -r -d '' pin_file; do
        if dpkg-query -S -- "$pin_file" >/dev/null 2>&1; then
            log "Erhalte paketverwaltete Pinning-Datei bis zum kontrollierten Paketaustausch: $pin_file"
            continue
        fi
        log "Entferne veraltete oder manuelle Pinning-Datei: $pin_file"
        rm -f -- "$pin_file"
    done < <(
        find "$preferences_dir" -maxdepth 1 -type f \
            \( -iname 'cuda-repository-pin-*' -o -iname 'nvidia-driver-pinning*' -o -iname '*nvidia*pin*' \) \
            -print0 2>/dev/null || true
    )
}

nvidia_device_node_is_character() {
    [[ -c "$1" ]]
}

list_nvidia_gpu_character_devices() {
    local device_root="${1:-/dev}" node
    local -a candidates=()

    shopt -s nullglob
    candidates=("$device_root"/nvidia[0-9]*)
    shopt -u nullglob
    for node in "${candidates[@]:-}"; do
        [[ "${node##*/}" =~ ^nvidia[0-9]+$ ]] || continue
        nvidia_device_node_is_character "$node" || continue
        printf '%s\n' "$node"
    done
}

nvidia_runtime_device_missing_summary() {
    local device_root="${1:-/dev}"
    local -a missing=()

    nvidia_device_node_is_character "$device_root/nvidiactl" \
        || missing+=("$device_root/nvidiactl")
    nvidia_device_node_is_character "$device_root/nvidia-uvm" \
        || missing+=("$device_root/nvidia-uvm")
    [[ -n "$(list_nvidia_gpu_character_devices "$device_root")" ]] \
        || missing+=("$device_root/nvidiaN (mindestens ein GPU-Character-Device)")
    join_by ', ' "${missing[@]:-}"
}

nvidia_runtime_devices_ready() {
    local device_root="${1:-/dev}"
    nvidia_device_node_is_character "$device_root/nvidiactl" \
        && nvidia_device_node_is_character "$device_root/nvidia-uvm" \
        && [[ -n "$(list_nvidia_gpu_character_devices "$device_root")" ]]
}

nvidia_runtime_ready_for_transcode() {
    nvidia_runtime_devices_ready /dev \
        && command -v nvidia-smi >/dev/null 2>&1 \
        && nvidia-smi -L >/dev/null 2>&1
}

run_nvtop_smoke_test() {
    local base clean_home output rc=0 owns_base=0 detail=""

    NVTOP_TEST_STATUS="fehlgeschlagen"
    NVTOP_TEST_DETAIL=""
    if ! command -v nvtop >/dev/null 2>&1; then
        NVTOP_TEST_STATUS="nicht installiert"
        NVTOP_TEST_DETAIL="Befehl nvtop fehlt"
        return 2
    fi
    local ld_cache=""
    ld_cache="$(ldconfig -p 2>/dev/null || true)"
    if ! grep -q 'libnvidia-ml\.so\.1' <<<"$ld_cache"; then
        NVTOP_TEST_DETAIL="libnvidia-ml.so.1 fehlt im dynamischen Linker-Cache"
        return 1
    fi
    if ! nvidia-smi -L >/dev/null 2>&1; then
        NVTOP_TEST_STATUS="wartet auf NVML"
        NVTOP_TEST_DETAIL="nvidia-smi kann die GPU-Laufzeit noch nicht abfragen"
        return 3
    fi

    if ! command -v script >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1; then
        if nvtop --version >/dev/null 2>&1; then
            NVTOP_TEST_STATUS="eingeschränkt erfolgreich"
            NVTOP_TEST_DETAIL="Binärdatei, NVML-Bibliothek und GPU-Abfrage funktionieren; util-linux script oder timeout fehlt für den interaktiven Starttest"
            return 0
        fi
        NVTOP_TEST_DETAIL="nvtop --version schlägt fehl und der Pseudo-TTY-Test ist nicht verfügbar"
        return 1
    fi

    base="${BACKUP_DIR:-${TMP_DIR:-}}"
    if [[ -z "$base" || ! -d "$base" ]]; then
        base="$(mktemp -d /tmp/nvidia-nvtop-test.XXXXXX)"
        owns_base=1
    fi
    clean_home="$(mktemp -d "$base/nvtop-clean-home.XXXXXX")"
    output="$base/nvtop-smoke-test.txt"

    # nvtop ist eine ncurses-Anwendung. Ein sauberer HOME-Pfad verhindert, dass
    # eine alte Benutzerkonfiguration den Backend-Test verfälscht; script stellt
    # das erforderliche Pseudo-TTY bereit. Exit 124 bedeutet: nvtop blieb nach
    # erfolgreicher Initialisierung bis zum kontrollierten Timeout interaktiv.
    set +e
    HOME="$clean_home" TERM=xterm timeout --signal=TERM 4s \
        script --quiet --return --command 'nvtop --delay 1' /dev/null \
        >"$output" 2>&1
    rc=$?
    set -e

    [[ "$clean_home" == "$base"/nvtop-clean-home.* ]] && rm -rf -- "$clean_home"
    if ((rc == 124)); then
        NVTOP_TEST_STATUS="erfolgreich"
        NVTOP_TEST_DETAIL="interaktiver Start über NVML blieb bis zum kontrollierten Timeout aktiv"
        ((owns_base == 0)) || rm -rf -- "$base"
        return 0
    fi

    detail="$(tr -d '\r' <"$output" 2>/dev/null \
        | sed -E 's/\x1B\[[0-9;?]*[ -\/]*[@-~]//g' \
        | sed '/^[[:space:]]*$/d' | tail -n3 | tr '\n' ' ' || true)"
    NVTOP_TEST_DETAIL="nvtop wurde unerwartet beendet (Exit-Code $rc)${detail:+: $detail}"
    ((owns_base == 0)) || rm -rf -- "$base"
    return 1
}

ensure_nvtop_monitoring_ready() {
    local test_rc=0 installed_version="" candidate="" target="" reinstall=0
    local -a reinstall_option=()

    [[ "${NVTOP_MANAGEMENT:-auto}" != "skip" ]] || {
        log "nvtop-Verwaltung wurde übersprungen."
        return 0
    }

    if run_nvtop_smoke_test; then
        ok "nvtop kann die GPU über NVML abfragen ($NVTOP_TEST_DETAIL)."
        return 0
    else
        test_rc=$?
    fi
    if ((test_rc == 3)); then
        log "nvtop-Prüfung wird bis zur funktionierenden NVML-Laufzeit zurückgestellt: $NVTOP_TEST_DETAIL"
        return 0
    fi
    if ((test_rc == 2)) && [[ "${NVTOP_MANAGEMENT:-auto}" == "auto" ]]; then
        log "nvtop ist nicht installiert; im automatischen Modus wird kein zusätzliches Monitoring-Paket eingerichtet."
        return 0
    fi
    ((AUTOMATIC_REPAIR)) \
        || die "nvtop ist nicht funktionsfähig und die automatische Reparatur ist deaktiviert: $NVTOP_TEST_DETAIL"

    installed_version="$(dpkg-query -W -f='${Version}' nvtop 2>/dev/null || true)"
    if ! candidate="$(apt_candidate_version nvtop)"; then
        die "nvtop kann nicht automatisch repariert werden: APT konnte den Paketkandidaten nicht lesen. Die ursprüngliche APT-Fehlermeldung steht oben im Protokoll."
    fi
    [[ -n "$candidate" && "$candidate" != "(none)" ]] \
        || die "nvtop kann nicht automatisch repariert werden: Im aktiven Debian-/Ubuntu-Repository ist kein Kandidat verfügbar."
    target="$candidate"
    if [[ -n "$installed_version" ]] \
       && apt-cache madison nvtop 2>/dev/null \
            | awk -F'|' -v expected="$installed_version" \
                '{v=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); if (v == expected) found=1} END {exit !found}'; then
        target="$installed_version"
        reinstall=1
        reinstall_option=(--reinstall)
    fi

    if ((test_rc == 2)); then
        log "Installiere nvtop=$target mit vorangestellter APT-Simulation."
    else
        warn "nvtop-Starttest fehlgeschlagen; installiere das Paket sicher neu: $NVTOP_TEST_DETAIL"
    fi
    DEBIAN_FRONTEND=noninteractive apt_mutate install -V -y \
        "${reinstall_option[@]}" "nvtop=$target"
    hash -r
    if run_nvtop_smoke_test; then
        if ((reinstall)); then
            record_repair_action "nvtop=$target exakt neu installiert und per Pseudo-TTY/NVML geprüft"
        else
            record_repair_action "nvtop=$target installiert und per Pseudo-TTY/NVML geprüft"
        fi
        ok "nvtop funktioniert nach der automatischen Installation/Reparatur ($NVTOP_TEST_DETAIL)."
        return 0
    fi
    die "nvtop ist auch nach der sicheren Neuinstallation nicht funktionsfähig: $NVTOP_TEST_DETAIL"
}

preflight_direct_lxc_runtime_devices() {
    local missing
    [[ "$MODE" == "lxc" ]] || return 0
    nvidia_runtime_devices_ready /dev && return 0

    missing="$(nvidia_runtime_device_missing_summary /dev)"
    if ((MACHINE_READABLE_RESULT)); then
        warn "Die Host-gesteuerte LXC-Installation läuft vorläufig ohne vollständige Laufzeitgeräte weiter: ${missing:-unbekannte Geräte}. Die Host-Abschlussprüfung übernimmt Neustart und Geräteabgleich."
        return 0
    fi
    die "Im LXC fehlt die vollständige NVIDIA-Gerätefreigabe: ${missing:-unbekannte Geräte}. Es wurden keine Pakete verändert. Starte dieses Skript auf dem Proxmox-Host und wähle im Menü „LXC vollständig vom Host einrichten“. Nur der Host kann die LXC-Gerätezuweisung korrigieren."
}

run_local_diagnostics() {
    local effective_mode="$1"
    local secure_boot="unbekannt"
    local signer=""
    local ld_cache=""
    local ffmpeg_encoders=""
    local ffmpeg_decoders=""
    local forbidden_lxc=""
    local kernel_security_log="" nvml_error="" nvml_rc=0
    local visible_gpu_devices="" missing_devices=""
    local -a visible_gpu_device_list=()

    printf '\nNVIDIA-Diagnose (%s):\n' "$effective_mode"
    if [[ "$effective_mode" == "host" ]]; then
        if command -v dkms >/dev/null 2>&1; then
            if dkms status -k "$(uname -r)" 2>/dev/null | grep -qi '^nvidia/.*installed'; then
                diagnostic_line OK DKMS "NVIDIA-Modul für den laufenden Kernel $(uname -r) installiert"
            else
                diagnostic_line WARN DKMS "kein installiertes NVIDIA-DKMS-Modul gefunden"
            fi
        else
            diagnostic_line WARN DKMS "dkms ist nicht installiert"
        fi

        if [[ -n "$DETECTED_HOST_MODULE_VERSION" && -n "$DETECTED_INSTALLED_MODULE_VERSION" ]]; then
            if [[ "$DETECTED_HOST_MODULE_VERSION" == "$DETECTED_INSTALLED_MODULE_VERSION" ]]; then
                diagnostic_line OK "Modulstand" "geladen und installiert: $DETECTED_HOST_MODULE_VERSION"
            else
                diagnostic_line FEHLER "Modulstand" "geladen $DETECTED_HOST_MODULE_VERSION, installiert $DETECTED_INSTALLED_MODULE_VERSION"
            fi
        elif [[ -n "$DETECTED_INSTALLED_MODULE_VERSION" ]]; then
            diagnostic_line WARN "Modulstand" "installiert $DETECTED_INSTALLED_MODULE_VERSION, aber nicht geladen"
        else
            diagnostic_line INFO "Modulstand" "keine NVIDIA-Moduldatei erkannt"
        fi
        [[ -z "$DETECTED_PACKAGE_DEBIAN_VERSION" ]] \
            || diagnostic_line INFO "DEB-Version" "$DETECTED_PACKAGE_DEBIAN_VERSION (Epoch $(debian_version_epoch "$DETECTED_PACKAGE_DEBIAN_VERSION"), Revision $(debian_version_revision "$DETECTED_PACKAGE_DEBIAN_VERSION"))"

        if [[ -d /sys/module/nouveau ]]; then
            diagnostic_line FEHLER Nouveau "Modul ist geladen und kollidiert mit dem NVIDIA-Treiber"
        elif grep -RqsE '^[[:space:]]*blacklist[[:space:]]+nouveau([[:space:]]|$)' /etc/modprobe.d 2>/dev/null; then
            diagnostic_line OK Nouveau "nicht geladen und auf der Blacklist"
        else
            diagnostic_line WARN Nouveau "nicht geladen, aber keine Blacklist gefunden"
        fi

        if command -v mokutil >/dev/null 2>&1; then
            secure_boot="$(mokutil --sb-state 2>/dev/null | head -n1 || true)"
            signer="$(modinfo -F signer nvidia 2>/dev/null | head -n1 || true)"
            kernel_security_log="$(journalctl -k -b --no-pager 2>/dev/null \
                | grep -iE 'nvidia.*(key was rejected|required key not available|verification failed)' \
                | tail -n3 || true)"
            if [[ -n "$kernel_security_log" ]]; then
                diagnostic_line FEHLER "Secure Boot" "Kernel hat die NVIDIA-Modulsignatur abgelehnt; MOK-Einbindung manuell prüfen"
            elif [[ "$secure_boot" == *enabled* && -z "$signer" ]]; then
                diagnostic_line FEHLER "Secure Boot" "aktiv, NVIDIA-Modul ohne erkannten Signierer"
            elif [[ "$secure_boot" == *enabled* ]]; then
                diagnostic_line OK "Secure Boot" "aktiv; Modulsignierer: $signer"
            else
                diagnostic_line OK "Secure Boot" "${secure_boot:-deaktiviert}"
            fi
        else
            diagnostic_line INFO "Secure Boot" "mokutil nicht verfügbar"
        fi
    else
        forbidden_lxc="$(
            dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null \
                | awk '$2 !~ /^un/ {print $1}' \
                | grep -E "$LXC_FORBIDDEN_PACKAGE_REGEX" | sort -u || true
        )"
        if [[ -n "$forbidden_lxc" ]]; then
            diagnostic_line FEHLER "LXC-Pakettrennung" "im LXC unzulässig: $(tr '\n' ' ' <<<"$forbidden_lxc")"
        else
            diagnostic_line OK "LXC-Pakettrennung" "keine NVIDIA-Kernel-/DKMS-/Host-Hilfspakete im LXC"
        fi
    fi

    mapfile -t visible_gpu_device_list < <(list_nvidia_gpu_character_devices /dev || true)
    visible_gpu_devices="$(join_by ', ' "${visible_gpu_device_list[@]:-}")"
    missing_devices="$(nvidia_runtime_device_missing_summary /dev)"
    if [[ -n "$missing_devices" ]]; then
        diagnostic_line FEHLER "Geräte" "fehlend oder kein Character Device: $missing_devices"
    else
        diagnostic_line OK "Geräte" "vollständig; GPU-Geräte: $visible_gpu_devices"
    fi

    if ! command -v nvidia-smi >/dev/null 2>&1; then
        if [[ "$MODE" == "lxc" && "$DISTRO" == "debian13" ]] \
           && dpkg_status_is_healthy_installed "$(dpkg-query -W -f='${db:Status-Abbrev}' nvidia-smi 2>/dev/null || true)"; then
            diagnostic_line FEHLER NVML "Debian-13-Übergangspaket nvidia-smi ist installiert, aber die echte Binärdatei aus dem geprüften NVIDIA-Userspace-Payload fehlt"
        else
            diagnostic_line FEHLER NVML "nvidia-smi ist nicht installiert oder nicht im PATH"
        fi
    elif nvml_error="$(nvidia-smi -L 2>&1)"; then
        diagnostic_line OK NVML "nvidia-smi kann die GPU(s) abfragen"
    else
        nvml_rc=$?
        nvml_error="$(head -n2 <<<"$nvml_error" | tr '\n' ' ' || true)"
        [[ -n "${nvml_error//[[:space:]]/}" ]] \
            || nvml_error="keine Programmausgabe"
        diagnostic_line FEHLER NVML "nvidia-smi/NVML fehlgeschlagen (Exit-Code $nvml_rc): $nvml_error"
    fi

    if [[ "${NVTOP_MANAGEMENT:-auto}" == "skip" ]]; then
        diagnostic_line INFO nvtop "Prüfung auf Wunsch übersprungen"
    elif run_nvtop_smoke_test; then
        diagnostic_line OK nvtop "$NVTOP_TEST_STATUS: $NVTOP_TEST_DETAIL"
    else
        nvml_rc=$?
        case "$nvml_rc" in
            2)
                if [[ "${NVTOP_MANAGEMENT:-auto}" == "install" ]]; then
                    diagnostic_line FEHLER nvtop "nicht installiert, obwohl Installation und Prüfung gewählt wurden"
                else
                    diagnostic_line INFO nvtop "nicht installiert"
                fi
                ;;
            3) diagnostic_line WARN nvtop "$NVTOP_TEST_STATUS: $NVTOP_TEST_DETAIL" ;;
            *) diagnostic_line FEHLER nvtop "$NVTOP_TEST_STATUS: $NVTOP_TEST_DETAIL" ;;
        esac
    fi

    ld_cache="$(ldconfig -p 2>/dev/null || true)"
    if grep -q 'libnvidia-encode\.so' <<<"$ld_cache"; then
        diagnostic_line OK NVENC "libnvidia-encode ist im Linker-Cache"
    else
        diagnostic_line FEHLER NVENC "libnvidia-encode fehlt im Linker-Cache"
    fi
    if grep -q 'libnvcuvid\.so' <<<"$ld_cache"; then
        diagnostic_line OK NVDEC "libnvcuvid ist im Linker-Cache"
    else
        diagnostic_line FEHLER NVDEC "libnvcuvid fehlt im Linker-Cache"
    fi
    if command -v ffmpeg >/dev/null 2>&1; then
        ffmpeg_encoders="$(ffmpeg -hide_banner -encoders 2>/dev/null || true)"
        ffmpeg_decoders="$(ffmpeg -hide_banner -decoders 2>/dev/null || true)"
        grep -q '_nvenc' <<<"$ffmpeg_encoders" \
            && diagnostic_line OK "FFmpeg NVENC" "Encoder registriert" \
            || diagnostic_line WARN "FFmpeg NVENC" "keine NVENC-Encoder registriert"
        grep -qE '(_cuvid|[[:space:]]av1_cuvid|[[:space:]]hevc_cuvid|[[:space:]]h264_cuvid)' <<<"$ffmpeg_decoders" \
            && diagnostic_line OK "FFmpeg NVDEC" "CUVID/NVDEC-Decoder registriert" \
            || diagnostic_line WARN "FFmpeg NVDEC" "keine CUVID/NVDEC-Decoder registriert"
    else
        diagnostic_line INFO FFmpeg "nicht installiert; Codec-Registrierung nicht geprüft"
    fi
}

report_transcode_failure_log() {
    local label="${1:-FFmpeg-Fehlerausgabe}" file="${2:-}"
    [[ -n "$file" && -s "$file" ]] || return 0
    warn "$label (letzte maximal 20 Zeilen):"
    tail -n 20 -- "$file" 2>/dev/null | sed 's/^/    /' >&2 || true
    return 0
}

run_local_transcode_smoke_test() {
    local mode="${TRANSCODE_SMOKE_TEST:-auto}"
    local workdir output encode_log decode_log encoders decoders

    [[ "$mode" != "no" ]] || {
        diagnostic_line INFO "Transcoding" "echter NVENC/NVDEC-Smoke-Test bewusst übersprungen"
        return 2
    }
    if ! nvidia_runtime_ready_for_transcode; then
        diagnostic_line WARN "Transcoding" "übersprungen: vollständige GPU-Gerätezuweisung oder erfolgreiche NVML-Abfrage fehlt"
        return 2
    fi
    if ! command -v ffmpeg >/dev/null 2>&1; then
        if [[ "$mode" == "yes" ]]; then
            diagnostic_line FEHLER "Transcoding" "FFmpeg fehlt, der zwingend gewählte Smoke-Test ist nicht möglich"
            return 1
        fi
        diagnostic_line INFO "Transcoding" "FFmpeg fehlt; automatischer Smoke-Test übersprungen"
        return 2
    fi

    encoders="$(ffmpeg -hide_banner -encoders 2>/dev/null || true)"
    decoders="$(ffmpeg -hide_banner -decoders 2>/dev/null || true)"
    if ! grep -q 'h264_nvenc' <<<"$encoders" \
       || ! grep -q 'h264_cuvid' <<<"$decoders"; then
        diagnostic_line FEHLER "Transcoding" "FFmpeg enthält nicht gleichzeitig h264_nvenc und h264_cuvid"
        return 1
    fi

    workdir="${BACKUP_DIR:-${TMP_DIR:-/tmp}}/transcode-smoke"
    mkdir -p "$workdir"
    output="$workdir/nvenc-smoke.mp4"
    encode_log="$workdir/nvenc-encode.log"
    decode_log="$workdir/nvdec-decode.log"
    if ! ffmpeg -hide_banner -loglevel error -y \
        -f lavfi -i "$TRANSCODE_SMOKE_SOURCE" -frames:v 10 -an \
        -c:v h264_nvenc -preset p1 "$output" >"$encode_log" 2>&1; then
        report_transcode_failure_log "NVENC-Fehlerausgabe" "$encode_log"
        diagnostic_line FEHLER "NVENC-Test" "Hardware-Kodierung fehlgeschlagen; Protokoll: $encode_log"
        return 1
    fi
    if ! ffmpeg -hide_banner -loglevel error -c:v h264_cuvid \
        -i "$output" -f null - >"$decode_log" 2>&1; then
        report_transcode_failure_log "NVDEC-Fehlerausgabe" "$decode_log"
        diagnostic_line FEHLER "NVDEC-Test" "Hardware-Dekodierung fehlgeschlagen; Protokoll: $decode_log"
        return 1
    fi
    rm -f -- "$output"
    diagnostic_line OK "Transcoding" "echter NVENC-Encode- und NVDEC-Decode-Test erfolgreich"
    return 0
}

summarize_nvidia_lxc_containers() {
    local ctid status name config versions package_version package_driver nvml_version wrong_kernel result
    local host_version="${DETECTED_HOST_MODULE_VERSION:-unbekannt}"
    local found=0

    [[ "${MODE:-}" == "host" ]] || return 0
    command -v pct >/dev/null 2>&1 || return 0

    printf '\nNVIDIA-LXC-Zusammenfassung:\n'
    printf '  Host geladenes Kernelmodul: %s\n' "$host_version"
    printf '  Host installierte Moduldatei: %s\n' "${DETECTED_INSTALLED_MODULE_VERSION:-unbekannt}"
    printf '  Host-DEB-Paketversion: %s\n' "${DETECTED_PACKAGE_DEBIAN_VERSION:-unbekannt}"
    printf '  %-7s %-18s %-9s %-8s %-24s %-12s %s\n' CTID NAME STATUS ERGEBNIS USERSPACE-DEBIAN NVML KERNELPAKETE
    while IFS= read -r ctid; do
        [[ "$ctid" =~ ^[0-9]+$ ]] || continue
        config="$(pct config "$ctid" 2>/dev/null || true)"
        grep -qE '(^dev[0-9]+:[[:space:]]+((path=)?/dev/nvidia)|^lxc\.(mount\.entry|cgroup2?\.devices\.).*nvidia)' \
            <<<"$config" || continue
        found=1
        name="$(awk -F': ' '$1 == "hostname" {print $2; exit}' <<<"$config")"
        status="$(pct status "$ctid" 2>/dev/null | awk '{print $2}')"
        versions="nicht laufend|||"
        if [[ "$status" == "running" ]]; then
            versions="$(pct exec "$ctid" -- sh -c \
                'pkg=$(dpkg-query -W -f="\${Version}" libnvidia-ml1 2>/dev/null || true); [ -n "$pkg" ] || pkg=$(dpkg-query -W -f="\${Version}" libnvidia-compute 2>/dev/null || true); smi=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 || true); wrong=$(dpkg-query -W -f="\${binary:Package} \${db:Status-Abbrev}\n" 2>/dev/null | awk "substr(\$2, 2, 1) == \"i\" {print \$1}" | grep -E "^((linux-(modules|objects|signatures)-nvidia)|nvidia-(kernel-.*|dkms.*|open.*|headless.*)|cuda-drivers.*)$" | paste -sd, - || true); printf "%s|%s|%s" "${pkg:-fehlt}" "${smi:-fehlt}" "${wrong:-keine}"' \
                2>/dev/null || printf 'fehlt|fehlt|Abfrage-fehlgeschlagen')"
        fi
        IFS='|' read -r package_version nvml_version wrong_kernel <<<"$versions"
        package_driver="$(normalize_driver_version "$package_version")"
        result="INFO"
        if [[ "$status" == "running" ]]; then
            if [[ "$package_driver" == "$host_version" && "$nvml_version" == "$host_version" \
                  && "$wrong_kernel" == "keine" ]]; then
                result="OK"
            else
                result="FEHLER"
            fi
        fi
        printf '  %-7s %-18s %-9s %-8s %-24s %-12s %s\n' \
            "$ctid" "${name:-CT-$ctid}" "${status:-?}" "$result" \
            "${package_version:-?}" "${nvml_version:-?}" "${wrong_kernel:-?}"
    done < <(pct list 2>/dev/null | awk 'NR > 1 {print $1}')
    ((found)) || printf '  Keine LXC-Konfiguration mit nativen NVIDIA-devN-Einträgen gefunden.\n'
}

run_diagnostic_summary() {
    local effective_mode="$1" dpkg_audit="" apt_check=""
    audit_nvidia_repository_configuration || true
    dpkg_audit="$(dpkg --audit 2>&1 || true)"
    if [[ -n "$dpkg_audit" ]]; then
        diagnostic_line FEHLER "dpkg" "unvollständige Paketkonfiguration erkannt"
    else
        diagnostic_line OK "dpkg" "keine unvollständigen Pakete"
    fi
    if apt_check="$(apt-get check 2>&1)"; then
        diagnostic_line OK "APT" "Abhängigkeiten konsistent"
    else
        diagnostic_line FEHLER "APT" "Abhängigkeitsprüfung fehlgeschlagen"
    fi
    if [[ "$DETECTED_VERSION_STATE" == "Mismatch: mehrere installierte NVIDIA-Treiberstände"* ]]; then
        diagnostic_line FEHLER "Paketmix" "$DETECTED_VERSION_STATE"
    fi
    run_local_diagnostics "$effective_mode"
    detect_reboot_requirement
    if ((REBOOT_REQUIRED)); then
        diagnostic_line WARN Neustart "Host-Neustart erforderlich"
    elif [[ "$effective_mode" == "host" ]]; then
        diagnostic_line OK Neustart "kein NVIDIA-bedingter Neustart erkannt"
    fi
    summarize_nvidia_lxc_containers
}

capture_nvidia_diagnostic_bundle() {
    local label="${1:-diagnose}"
    local destination="${BACKUP_DIR:-}"
    [[ -n "$destination" && -d "$destination" ]] || return 0

    {
        printf 'Zeit: %s\n' "$(date --iso-8601=seconds)"
        printf 'Rolle: %s\n' "${MODE:-unbekannt}"
        printf 'Kernel: %s\n' "$(uname -r)"
        printf '\n== Module ==\n'
        lsmod 2>/dev/null | grep -E '^(nvidia|nouveau)' || true
        printf '\n== modinfo nvidia ==\n'
        modinfo nvidia 2>/dev/null || true
        printf '\n== DKMS ==\n'
        dkms status 2>/dev/null || true
        printf '\n== Secure Boot ==\n'
        mokutil --sb-state 2>/dev/null || true
        printf '\n== NVML ==\n'
        nvidia-smi 2>&1 || true
        printf '\n== nvtop ==\n'
        nvtop --version 2>&1 || true
        printf 'Prüfstatus: %s\nDetails: %s\n' \
            "${NVTOP_TEST_STATUS:-nicht geprüft}" "${NVTOP_TEST_DETAIL:-keine}"
        printf '\n== NVENC/NVDEC libraries ==\n'
        ldconfig -p 2>/dev/null | grep -E 'libnvidia-encode|libnvcuvid' || true
        printf '\n== FFmpeg codecs ==\n'
        ffmpeg -hide_banner -encoders 2>/dev/null | grep nvenc || true
        ffmpeg -hide_banner -decoders 2>/dev/null | grep cuvid || true
    } >"$destination/diagnostic-${label}.txt" 2>&1
    command -v journalctl >/dev/null 2>&1 \
        && journalctl -k -b --no-pager 2>/dev/null \
            | grep -iE 'nvidia|nouveau|NVRM|secure boot|module verification' \
            >"$destination/kernel-nvidia-${label}.log" || true
    find /var/lib/dkms -path '*/nvidia*/*/build/make.log' -type f -exec cp -a {} "$destination/" \; 2>/dev/null || true
}

usage() {
    cat <<EOF_USAGE
Nutzung:
  $0                  Interaktives Menü öffnen
  $0 [Optionen]       Ohne Menü ausführen

Ohne Optionen wird zuerst ein Aktionsmenü angezeigt:
  1. NVIDIA passend zur erkannten Rolle sauber installieren/aktualisieren
  2. einen LXC vollständig vom Host einrichten
  3. nur eine oder mehrere GPUs an einen LXC durchreichen
  4. nur NVIDIA-Bibliotheken im LXC vom Host installieren
  5. GPU, Versionen, Host und NVIDIA-LXC prüfen
  6. automatische Fehleranalyse und sichere Reparaturversuche ausführen
  7. Installation und LXC-Änderungen vollständig simulieren
  8. ausstehende Abschlussprüfung oder Transaktion fortsetzen
  9. Sicherung prüfen und zurückrollen
  10. alte Sicherungen bereinigen
  11. NVIDIA auf diesem System vollständig entfernen
  12. vorhandene NVIDIA-Pakete auf diesem System aktualisieren und exakt pinnen
  13. vorhandene NVIDIA-Pakete in einem LXC vom Host aus aktualisieren
  14. NVIDIA-Update mit vorhandenen Paketlisten schreibgeschützt simulieren

Unterstützte Systeme (amd64):
  - Proxmox VE auf Debian 12 oder Debian 13
  - Ubuntu 22.04 LTS, 24.04 LTS oder 26.04 LTS als Host
  - Debian 12/13 oder Ubuntu 22.04/24.04/26.04 in einem LXC
  - LXC-Gerätezuweisung ausschließlich auf einem Proxmox-Host mit pct

Protokollierung:
  Verändernde Läufe speichern stdout und stderr automatisch als dauerhaftes,
  farbfreies Gesamtprotokoll unter /var/log/nvidia-driver-setup/. Nach vollständig
  geprüftem Erfolg wird es standardmäßig entfernt; der Abschlussbericht bleibt.
  --check-only, --diagnose-all und --dry-run erzeugen bewusst kein Systemlog.

Optionen:
  --update                    vorhandenen NVIDIA-Stack aktualisieren statt neu
                               installieren; neueste offizielle Version ermitteln,
                               alle geplanten NVIDIA-/CUDA-/Container-Pakete pinnen
  --update-lxc <CTID>         denselben Updateablauf vom Proxmox-Host im LXC ausführen;
                               Gerätezuweisung unverändert, exakt wie geladenes Host-Modul
  --version auto|<Version>     Zielversion, z. B. 610.43.02; Versionen aus dem
                               offiziellen APT-Cache werden dynamisch angeboten
  --mode auto|host|lxc        Rolle erkennen oder explizit festlegen
  --kernel auto|open|proprietary
                               Kernelmodul auf dem Host; Standard: automatisch
  --fix-microsoft-conflict    bekannten Microsoft-Signed-By-Konflikt beheben
  --no-microsoft-fix          Kompatibilitätsalias; Microsoft nicht verändern
  --host-version <Version>    geladene Host-Version, falls im LXC nicht sichtbar
  --check-only                Nur GPU, Versionen und Empfehlung prüfen
  --diagnose-all              Diagnose für Host und alle NVIDIA-LXC ausgeben
  --dry-run                   vollständigen Ablauf nur planen/simulieren
  --rollback <Sicherung>      eine von diesem Skript erzeugte Sicherung einspielen
  --resume                    unterbrochene Transaktion aus dem Marker fortsetzen
  --finalize-pending <Sicherung>
                               ausstehende Laufzeitprüfung abschließen; danach die
                               gespeicherte Behalten-/Entfernen-Richtlinie anwenden
  --uninstall                 NVIDIA-Treiber/-Bibliotheken, CUDA-/Container-Toolkit und
                               Konfiguration auf diesem System entfernen; verwaltete
                               LXC-Einträge nur bei Ausführung auf dem Proxmox-Host
  --cleanup-backups           Sicherungen außerhalb der Aufbewahrungszeit entfernen
  --retention-days <Tage>     Aufbewahrungszeit; Standard: 30
  --delete-success-backup     Sicherung nach vollständig geprüftem Erfolg entfernen
                               (Standard; nie bei Fehler, Abbruch oder offener Prüfung)
  --keep-success-backup       Sicherung auch nach vollständig geprüftem Erfolg behalten
  --delete-success-logs       erfolgreiches Installationslog nach dem Abschlussbericht entfernen
                               (Standard; Fehler-/Pending-Logs bleiben erhalten)
  --keep-success-logs         auch das erfolgreiche Installationslog behalten
  --transcode-test            echten FFmpeg-NVENC-/NVDEC-Smoke-Test erzwingen
  --no-transcode-test         Transcoding-Smoke-Test ausdrücklich überspringen
  --nvtop auto|install|skip   vorhandenes nvtop prüfen/reparieren, installieren
                               und prüfen oder vollständig überspringen
  --stop-gpu-services         eindeutig zugeordnete unkritische Host-/LXC-Dienste
                               vor der Host-Wartung stoppen und danach neu starten
  --no-stop-gpu-services      bei GPU-Belegung nur Details ausgeben und abbrechen
  --initial-autoremove        zu Beginn sicheres apt autoremove --purge ausführen
  --no-initial-autoremove     vorhandene verwaiste Pakete nicht bereinigen
  --final-autoremove          am Ende sicheres apt autoremove --purge ausführen (Standard)
  --no-final-autoremove       Abschluss-Autoremove überspringen
  --auto-repair               sichere APT/dpkg/DKMS/NVML-Nachbesserungen ausführen (Standard)
  --no-auto-repair            automatische Reparaturversuche deaktivieren
  --repair-only               Fehler analysieren und nur sichere Reparaturversuche
                               ausführen; keine vollständige Neuinstallation
  --clean-scope full|driver   gesamten paketverwalteten NVIDIA-/CUDA-/Container-
                               Stack (Standard: full) oder nur Treiber neu aufsetzen
  --machine-readable-result   bei Installation/LXC-Verwaltung Ergebnis-/Backup-Marker
                               ausgeben; Erfolg und offene Prüfung enden dann mit Exit 0
                               und NVIDIA_SETUP_RESULT=success|pending|failed. Ohne diese Option
                               endet eine offene Prüfung mit Exit 2. Check/Diagnose nutzt
                               Exit 2 für Befunde und erzeugt keinen Ergebnis-Marker.
  --pin-packages              installierte NVIDIA-Pakete anschließend halten
  --no-pin-packages           keine neue Versionsbindung setzen
  --attach-lxc <CTID>         Gewählte NVIDIA-GPU an diesen LXC durchreichen
                               (nach der Host-Treiberinstallation)
  --attach-only <CTID>        Nur die GPU an diesen LXC durchreichen;
                               keine Pakete oder Treiber verändern
  --manage-lxc <CTID>         GPU-Zuweisung und LXC-Bibliotheken vollständig
                               vom Proxmox-Host aus einrichten
  --lxc-userspace-only <CTID> Nur passende NVIDIA-Bibliotheken im LXC vom Host
                               aus installieren; GPU-Konfiguration unverändert
  --install-lxc-userspace     zusammen mit --attach-lxc auch die exakt passenden
                               LXC-Bibliotheken vom Host aus installieren
  --start-stopped-lxc         gestoppten Ziel-LXC ausdrücklich temporär starten
                               und danach wieder herunterfahren
  --restart-running-lxc       laufenden Ziel-LXC für neue GPU-Geräte kontrolliert
                               neu starten
  --gpu-device /dev/nvidiaN   wiederholbar; GPU-Gerät auswählen
  --gpu-uuid <GPU-UUID>       wiederholbar; GPU stabil über UUID auswählen
  --gpu-pci <PCI-Adresse>     wiederholbar; z. B. 0000:01:00.0
  --all-gpus                  alle erkannten NVIDIA-GPUs auswählen
  --device-mode <Modus>       Gerätezugriff; Standard: inherit (Host-Modus)
  --device-uid <UID|inherit>  Besitzer im LXC; Standard: Proxmox-Vorgabe
  --device-gid <GID|inherit>  Gruppe im LXC; Standard: erkannte video-GID bzw. 44
  --lxc-backend auto|native|manual
                               native Proxmox-Zuweisung bevorzugen oder Fallback wählen
  -y, --yes                   Sicherheitsabfrage überspringen
  -h, --help                  Hilfe anzeigen

Beispiele:
  # Vorhandene NVIDIA-Pakete aktualisieren und ihre Versionen fest binden
  $0 --update --mode host

  # Passende LXC-Pakete vom Host aus aktualisieren
  $0 --update-lxc 111

  # Update schreibgeschützt mit dem vorhandenen APT-Cache prüfen
  $0 --update --mode host --dry-run

  # Proxmox- oder Ubuntu-Host, NVIDIA 610, offenes Kernelmodul
  $0 --mode host --version 610

  # Debian-/Ubuntu-LXC, exakt dieselbe vollständige Version wie auf dem Host
  $0 --mode lxc --version auto --host-version 610.57.04

  # GPU, installierte Version und Empfehlung automatisch erkennen
  $0 --version auto

  # Host installieren und /dev/nvidia0 zusätzlich an LXC 111 durchreichen
  $0 --mode host --version auto --attach-lxc 111 --gpu-device /dev/nvidia0

  # Nur /dev/nvidia0 an LXC 111 durchreichen, Treiber unverändert lassen
  $0 --attach-only 111 --gpu-device /dev/nvidia0

  # LXC 111 einschließlich GPU und Bibliotheken vollständig vom Host einrichten
  $0 --manage-lxc 111 --gpu-device /dev/nvidia0 --start-stopped-lxc

  # Zwei GPUs stabil auswählen und nur der video-Gruppe Zugriff geben
  $0 --attach-only 111 --gpu-uuid GPU-abc --gpu-pci 0000:65:00.0 \
      --device-mode 0660 --device-gid 44

  # Installation und LXC-Änderungen vollständig ohne Schreibzugriff simulieren
  $0 --mode host --version auto --dry-run --attach-lxc 111 --all-gpus

Ablauf der sauberen Neuinstallation (Menü 1/2/4):
  1. GPU-Modell, GPU-Generation und installierte Treiberversion prüfen
  2. System und APT-Zustand prüfen und sichern
  3. alte NVIDIA-Quellen bereinigen; Microsoft nur auf ausdrückliche Option ändern
  4. Keyring, Pinning, Zielpakete, Header und Installationsplan vorab prüfen
  5. NVIDIA-Holds lösen und den bisherigen Treiberstack kontrolliert entfernen
  6. nur neu entstandene NVIDIA-Abhängigkeiten bereinigen
  7. vorab geprüfte Zielversion exakt installieren
  8. Paketversionen, DKMS, Host/LXC-Abgleich und NVIDIA-Geräte prüfen
  9. nach vollständig erfolgreicher Prüfung einen dauerhaften Abschlussbericht
     unter /var/log/nvidia-driver-setup/ speichern und im Terminal anzeigen

Update (Menü 12/13):
  - Rückkehrbasis sichern, offizielle Paketquellen und frische Paketlisten prüfen
  - neueste Treiberversion wählen; im LXC ausschließlich die geladene Host-Version
  - alle installierten verwalteten NVIDIA-Komponenten auf verfügbare neue DEB-Versionen
    abbilden; CUDA-/Container-/unabhängige Zusatzpakete behalten ihr eigenes Versionsschema
  - gemeinsames APT-Update simulieren, Pakete vorladen, alte Holds kontrolliert lösen
  - nur tatsächlich notwendige Paketänderungen ausführen, kein pauschales Purge/--reinstall
  - genaue Paketversionen prüfen, APT-Präferenz schreiben und apt-mark hold verifizieren
  - kein globales Systemupgrade; Versions-/Layoutkonflikte werden nicht gewaltsam übergangen
  - die installierte Host-Kernelmodulvariante bleibt erhalten; ein nötiger Neustart wird gemeldet

Versionierte CUDA-Toolkits werden innerhalb ihrer installierten Paketnamen aktualisiert;
ein zusätzliches neues CUDA-Major-Toolkit wird nur durch ein vorhandenes Metapaket nachgezogen.
Ein Update benötigt einen gesunden Paketstand und eine eindeutige Paketabbildung.
Bei beschädigten/inkompatiblen Altbeständen zuerst Reparatur oder saubere Installation wählen.
Menü 14/--update --dry-run aktualisiert keine Paketlisten, sondern verwendet nur den Cache;
kurzlebige Planungsdateien werden automatisch entfernt. Der echte Lauf prüft erneut.

Bei --clean-scope full werden vorhandene paketverwaltete CUDA- und NVIDIA-
Container-Komponenten exakt gesichert, vollständig entfernt und danach in
derselben DEB-Version neu installiert. Persönliche Projekte, Medien, Docker-
Volumes, FileFlows und deren Nutzdaten werden niemals gelöscht.
EOF_USAGE
}

# --------------------------- Interaktives Menü -------------------------------
ORIGINAL_ARGC=$#
ORIGINAL_COMMAND_ARGS=("$@")
MENU_DETECTED_MODE="unknown"
MENU_RESET=""
MENU_BOLD=""
MENU_BLUE=""
MENU_CYAN=""
MENU_GREEN=""
MENU_YELLOW=""
MENU_RED=""
MENU_DIM=""

menu_detect_mode() {
    if command -v pveversion >/dev/null 2>&1 || [[ -d /etc/pve ]]; then
        printf 'host'
    elif { command -v systemd-detect-virt >/dev/null 2>&1 \
           && [[ "$(systemd-detect-virt --container 2>/dev/null || true)" == "lxc" ]]; } \
         || grep -qa 'container=lxc' /proc/1/environ 2>/dev/null; then
        printf 'lxc'
    elif [[ "${OS_ID:-}" == "ubuntu" ]]; then
        printf 'host'
    else
        printf 'unknown'
    fi
}

menu_read() {
    local prompt="$1"
    local reply
    if ! read -r -p "$prompt" reply; then
        printf '\n' >&2
        die "Keine Eingabe möglich. Nutze alternativ die Kommandozeilenoptionen."
    fi
    printf '%s' "$reply"
}

menu_choose_mode() {
    local choice
    while true; do
        menu_section "AUSFÜHRUNGSORT"
        case "$MENU_DETECTED_MODE" in
            host) menu_item 1 "Automatisch erkennen  [Empfohlen]" "Erkannt: ${OS_LABEL:-Host}" ;;
            lxc)  menu_item 1 "Automatisch erkennen  [Empfohlen]" "Erkannt: LXC" ;;
            *)    menu_item 1 "Automatisch erkennen" "Rolle wird vor Änderungen erneut geprüft" ;;
        esac
        menu_item 2 "Host" "Proxmox VE, Debian-Host oder Ubuntu-Host"
        menu_item 3 "LXC" "Debian- oder Ubuntu-Container; niemals Kernel/DKMS"
        menu_item 0 "Abbrechen"
        choice="$(menu_read 'Auswahl [1]: ')"
        choice="${choice:-1}"
        case "$choice" in
            1) MODE="auto"; return 0 ;;
            2) MODE="host"; return 0 ;;
            3) MODE="lxc"; return 0 ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *) warn "Ungültige Auswahl: $choice" ;;
        esac
    done
}

menu_choose_version() {
    local choice version index
    local -a menu_versions=()
    while true; do
        menu_section "TREIBERVERSION"
        menu_note "Automatische Erkennung und Repository-Verfügbarkeit:"
        print_detection_summary
        case "$RECOMMENDED_VERSION" in
            [0-9][0-9][0-9].[0-9]*.[0-9]*)
                menu_item 1 "Automatisch: $RECOMMENDED_VERSION  [Empfohlen]" "Aus GPU, Host-Modul und offiziellem APT-Cache ermittelt"
                ;;
            legacy-580)
                menu_item 1 "Automatisch prüfen" "Abbruch erwartet: NVIDIA 580 erforderlich"
                ;;
            unsupported-host-version)
                menu_item 1 "Automatisch prüfen" "Abbruch erwartet: Host-Version nicht verfügbar"
                ;;
            host-version-required)
                menu_item 1 "Automatisch prüfen" "Abbruch erwartet: exakte Host-Version erforderlich"
                ;;
            *)
                menu_item 1 "Automatische Repository-Auswahl  [Empfohlen]"
                ;;
        esac
        menu_versions=()
        if is_valid_driver_version "$RECOMMENDED_VERSION"; then
            append_unique menu_versions "$RECOMMENDED_VERSION"
        fi
        for version in "${AVAILABLE_DRIVER_VERSIONS[@]:-}" "${BUILTIN_DRIVER_VERSIONS[@]}"; do
            [[ "$version" == "$RECOMMENDED_VERSION" ]] && continue
            is_valid_driver_version "$version" && append_unique menu_versions "$version"
        done
        index=2
        for version in "${menu_versions[@]}"; do
            if [[ " ${AVAILABLE_DRIVER_VERSIONS[*]:-} " == *" $version "* ]]; then
                menu_item "$index" "$version manuell" "Im offiziellen APT-Cache erkannt"
            else
                menu_item "$index" "$version manuell" "Verfügbarkeit wird im Preflight geprüft"
            fi
            index=$((index + 1))
        done
        menu_item M "Andere exakte Version eingeben" "Vollständiges Format, z. B. 610.57.04"
        menu_item 0 "Abbrechen"
        choice="$(menu_read 'Auswahl [1]: ')"
        choice="${choice:-1}"
        case "$choice" in
            1) REQUESTED_VERSION="auto"; return 0 ;;
            m|M)
                version="$(menu_read 'Exakte NVIDIA-Version: ')"
                version="$(normalize_driver_version "$version")"
                if is_valid_driver_version "$version"; then
                    REQUESTED_VERSION="$version"
                    return 0
                fi
                warn "Ungültige NVIDIA-Version."
                ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] \
                   && { choice=$((10#$choice)); ((choice >= 2 && choice < index)); }; then
                    REQUESTED_VERSION="${menu_versions[choice - 2]}"
                    return 0
                fi
                warn "Ungültige Auswahl: $choice"
                ;;
        esac
    done
}

menu_choose_clean_install_scope() {
    local choice effective_mode="$MODE"
    [[ "$effective_mode" == "auto" ]] && effective_mode="$MENU_DETECTED_MODE"
    while true; do
        menu_section "NEUINSTALLATIONSUMFANG"
        menu_note "Welche bereits installierten NVIDIA-Komponenten sollen vollständig neu aufgesetzt werden?"
        if [[ "$effective_mode" == "lxc" ]]; then
            menu_item 1 "Gesamter NVIDIA-Userspace-Stack  [Standard]" "Bibliotheken, Werkzeuge, CUDA Toolkit und NVIDIA Container Toolkit exakt sichern, entfernen und neu installieren; Kernel/DKMS bleiben ausgeschlossen"
            menu_item 2 "Nur NVIDIA-Userspace-Bibliotheken" "CUDA Toolkit und NVIDIA Container Toolkit installiert lassen; Kernel/DKMS bleiben ausgeschlossen"
        else
            menu_item 1 "Gesamter NVIDIA-Softwarestack  [Standard]" "Treiber, Userspace, CUDA Toolkit und NVIDIA Container Toolkit exakt sichern, entfernen und neu installieren"
            menu_item 2 "Nur NVIDIA-Treiberstack" "CUDA Toolkit und NVIDIA Container Toolkit installiert lassen"
        fi
        menu_item 0 "Abbrechen"
        choice="$(menu_read 'Auswahl [1]: ')"
        choice="${choice:-1}"
        case "$choice" in
            1) CLEAN_INSTALL_SCOPE="full"; return 0 ;;
            2) CLEAN_INSTALL_SCOPE="driver"; return 0 ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *) warn "Ungültige Auswahl: $choice" ;;
        esac
    done
}

menu_choose_kernel() {
    local effective_mode="$MODE"
    local choice

    [[ "$effective_mode" == "auto" ]] && effective_mode="$MENU_DETECTED_MODE"
    if [[ "$effective_mode" == "lxc" ]]; then
        KERNEL_FLAVOR="auto"
        return 0
    fi

    while true; do
        menu_section "HOST-KERNELMODUL"
        if [[ "$RECOMMENDED_KERNEL" == "manual" ]]; then
            menu_item 1 "Automatisch" "Nicht möglich: GPU-Generation unbekannt"
        else
            menu_item 1 "Automatisch: $([[ "$RECOMMENDED_KERNEL" == "open" ]] && printf 'offen' || printf 'proprietär')  [Empfohlen]"
        fi
        menu_item 2 "Offenes NVIDIA-Kernelmodul"
        menu_item 3 "Proprietäres NVIDIA-Kernelmodul"
        menu_item 0 "Abbrechen"
        choice="$(menu_read 'Auswahl [1]: ')"
        choice="${choice:-1}"
        case "$choice" in
            1)
                if [[ "$RECOMMENDED_KERNEL" == "manual" ]]; then
                    warn "Wähle für die unbekannte GPU-Generation explizit offen oder proprietär."
                    continue
                fi
                KERNEL_FLAVOR="auto"
                return 0
                ;;
            2) KERNEL_FLAVOR="open"; return 0 ;;
            3) KERNEL_FLAVOR="proprietary"; return 0 ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *) warn "Ungültige Auswahl: $choice" ;;
        esac
    done
}

menu_choose_microsoft_fix() {
    local choice
    while true; do
        menu_section "MICROSOFT-APT-KOMPATIBILITÄT"
        menu_note "Bekannten Signed-By-Konflikt bei Bedarf automatisch korrigieren?"
        menu_item 1 "Ja" "Nur den eindeutig erkannten Konflikt sichern und beheben"
        menu_item 2 "Nein  [Standard]" "Microsoft-Paketquellen unverändert lassen"
        menu_item 0 "Abbrechen"
        choice="$(menu_read 'Auswahl [2]: ')"
        choice="${choice:-2}"
        case "$choice" in
            1|j|J|ja|JA|Ja) FIX_MICROSOFT_CONFLICT=1; return 0 ;;
            2|n|N|nein|NEIN|Nein) FIX_MICROSOFT_CONFLICT=0; return 0 ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *) warn "Ungültige Auswahl: $choice" ;;
        esac
    done
}

menu_choose_version_binding() {
    local choice
    while true; do
        menu_section "VERSIONSBINDUNG"
        menu_note "NVIDIA-Pakete nach erfolgreicher Installation auf der exakten Version halten?"
        menu_item 1 "Ja, mit apt-mark hold binden  [Empfohlen]" "Verhindert einen unbemerkten Host-/LXC-Versionsversatz"
        menu_item 2 "Nein" "Normale, unabhängige APT-Aktualisierungen erlauben"
        menu_item 0 "Abbrechen"
        choice="$(menu_read 'Auswahl [1]: ')"
        choice="${choice:-1}"
        case "$choice" in
            1|j|J|ja|JA|Ja) PIN_NVIDIA_PACKAGES=1; PIN_CHOICE_EXPLICIT=1; return 0 ;;
            2|n|N|nein|NEIN|Nein) PIN_NVIDIA_PACKAGES=0; PIN_CHOICE_EXPLICIT=1; return 0 ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *) warn "Ungültige Auswahl: $choice" ;;
        esac
    done
}

menu_choose_success_backup_policy() {
    local choice
    while true; do
        menu_section "ERFOLGSARTEFAKTE"
        menu_note "Was soll nach einer vollständig erfolgreichen Abschlussprüfung erhalten bleiben?"
        menu_item 1 "Sicherung und Installationslog entfernen  [Empfohlen]" "Der kompakte Abschlussbericht bleibt erhalten"
        menu_item 2 "Nur Sicherung behalten" "Installationslog entfernen; vollständige Erfolgssicherung behalten"
        menu_item 3 "Sicherung und Log behalten" "Alle erfolgreichen Diagnoseartefakte aufbewahren"
        menu_item 0 "Abbrechen"
        choice="$(menu_read 'Auswahl [1]: ')"
        choice="${choice:-1}"
        case "$choice" in
            1|j|J|ja|JA|Ja) KEEP_SUCCESS_BACKUP=0; DELETE_SUCCESS_LOGS=1; return 0 ;;
            2) KEEP_SUCCESS_BACKUP=1; DELETE_SUCCESS_LOGS=1; return 0 ;;
            3|n|N|nein|NEIN|Nein) KEEP_SUCCESS_BACKUP=1; DELETE_SUCCESS_LOGS=0; return 0 ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *) warn "Ungültige Auswahl: $choice" ;;
        esac
    done
}

menu_choose_final_autoremove() {
    local choice
    while true; do
        menu_section "APT-BEREINIGUNG AM ENDE"
        menu_item 1 "Sicheres apt autoremove --purge  [Empfohlen]" "Simulation, NVIDIA-Schutz, DEB-Rollbacksicherung und APT-/dpkg-Nachprüfung"
        menu_item 2 "Überspringen" "Nach der Installation keine verwaisten Pakete entfernen"
        menu_item 0 "Abbrechen"
        choice="$(menu_read 'Auswahl [1]: ')"
        choice="${choice:-1}"
        case "$choice" in
            1) FINAL_APT_AUTOREMOVE=1; return 0 ;;
            2) FINAL_APT_AUTOREMOVE=0; return 0 ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *) warn "Ungültige Auswahl: $choice" ;;
        esac
    done
}

menu_choose_transcode_smoke_test() {
    local choice
    while true; do
        menu_section "TRANSCODING-TEST"
        menu_note "Echten NVENC-/NVDEC-Hardware-Smoke-Test ausführen?"
        menu_item 1 "Automatisch  [Empfohlen]" "Ausführen, wenn FFmpeg und passende Codecs vorhanden sind"
        menu_item 2 "Zwingend" "Fehlendes FFmpeg oder ein Hardwarefehler blockiert den Abschluss"
        menu_item 3 "Überspringen" "Nur Bibliotheken und Codec-Registrierung prüfen"
        menu_item 0 "Abbrechen"
        choice="$(menu_read 'Auswahl [1]: ')"
        choice="${choice:-1}"
        case "$choice" in
            1) TRANSCODE_SMOKE_TEST="auto"; return 0 ;;
            2|j|J|ja|JA|Ja) TRANSCODE_SMOKE_TEST="yes"; return 0 ;;
            3|n|N|nein|NEIN|Nein) TRANSCODE_SMOKE_TEST="no"; return 0 ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *) warn "Ungültige Auswahl: $choice" ;;
        esac
    done
}

menu_choose_nvtop_management() {
    local choice
    while true; do
        menu_section "NVTOP-MONITORING"
        menu_note "nvtop installieren/reparieren und seinen echten interaktiven NVML-Start prüfen?"
        menu_item 1 "Installieren und prüfen  [Empfohlen]" "Fehlendes nvtop installieren; vorhandenes bei einem Startfehler sicher neu installieren"
        menu_item 2 "Vorhandenes nvtop automatisch prüfen" "Nur eine bereits vorhandene Installation testen und bei Bedarf reparieren"
        menu_item 3 "Überspringen" "nvtop weder installieren noch prüfen"
        menu_item 0 "Abbrechen"
        choice="$(menu_read 'Auswahl [1]: ')"
        choice="${choice:-1}"
        case "$choice" in
            1) NVTOP_MANAGEMENT="install"; return 0 ;;
            2) NVTOP_MANAGEMENT="auto"; return 0 ;;
            3) NVTOP_MANAGEMENT="skip"; return 0 ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *) warn "Ungültige Auswahl: $choice" ;;
        esac
    done
}

menu_choose_gpu_consumer_policy() {
    local choice effective_mode="${MODE:-auto}"
    [[ "$effective_mode" == "auto" ]] && effective_mode="$MENU_DETECTED_MODE"
    [[ "$effective_mode" == "host" ]] || { GPU_CONSUMER_POLICY="abort"; return 0; }
    while true; do
        menu_section "GPU-NUTZENDE DIENSTE"
        menu_note "Vorgehen, falls laufende Prozesse die Treiberwartung blockieren:"
        menu_item 1 "Sichere Dienste kontrolliert stoppen  [Empfohlen]" "Nur eindeutig erkannte, unkritische Dienste; danach wiederherstellen"
        menu_item 2 "Nichts stoppen" "Mit Prozess- und Dienstinformationen sicher abbrechen"
        menu_item 0 "Abbrechen"
        choice="$(menu_read 'Auswahl [1]: ')"
        choice="${choice:-1}"
        case "$choice" in
            1) GPU_CONSUMER_POLICY="stop-services"; return 0 ;;
            2) GPU_CONSUMER_POLICY="abort"; return 0 ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *) warn "Ungültige Auswahl: $choice" ;;
        esac
    done
}

menu_choose_initial_autoremove() {
    local choice effective_mode="${MODE:-auto}"
    [[ "$effective_mode" == "auto" ]] && effective_mode="$MENU_DETECTED_MODE"
    [[ "$effective_mode" == "host" ]] || { INITIAL_APT_AUTOREMOVE=0; return 0; }
    while true; do
        menu_section "APT-BEREINIGUNG ZU BEGINN"
        menu_item 1 "Sicheres apt autoremove --purge  [Empfohlen]" "Erst nach Simulation, Prüfung und vollständiger Rollback-Sicherung"
        menu_item 2 "Überspringen" "Vorhandene verwaiste Pakete unverändert lassen"
        menu_item 0 "Abbrechen"
        choice="$(menu_read 'Auswahl [1]: ')"
        choice="${choice:-1}"
        case "$choice" in
            1) INITIAL_APT_AUTOREMOVE=1; return 0 ;;
            2) INITIAL_APT_AUTOREMOVE=0; return 0 ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *) warn "Ungültige Auswahl: $choice" ;;
        esac
    done
}

menu_choose_automatic_repair() {
    local choice
    while true; do
        menu_section "AUTOMATISCHE FEHLERBEHEBUNG"
        menu_item 1 "Analysieren und sicher reparieren  [Empfohlen]" "APT/dpkg, Quellen, DKMS, Module, Geräte, NVML und Codec-Bibliotheken"
        menu_item 2 "Nur diagnostizieren" "Keine automatischen Reparaturversuche"
        menu_item 0 "Abbrechen"
        choice="$(menu_read 'Auswahl [1]: ')"
        choice="${choice:-1}"
        case "$choice" in
            1) AUTOMATIC_REPAIR=1; return 0 ;;
            2) AUTOMATIC_REPAIR=0; return 0 ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *) warn "Ungültige Auswahl: $choice" ;;
        esac
    done
}

menu_choose_lxc_host_version() {
    local effective_mode="${MODE:-$MENU_DETECTED_MODE}" value normalized
    [[ "$effective_mode" == "auto" ]] && effective_mode="$MENU_DETECTED_MODE"
    [[ "$effective_mode" == "lxc" && -z "$DETECTED_HOST_MODULE_VERSION" ]] || return 0

    menu_section "HOST-/LXC-VERSIONSABGLEICH"
    menu_note "Die geladene NVIDIA-Kernelmodulversion des Hosts ist im LXC nicht sichtbar."
    while true; do
        value="$(menu_read 'Exakte Host-Treiberversion, z. B. 610.43.02 (0 = Abbrechen): ')"
        case "$value" in
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
        esac
        normalized="$(normalize_driver_version "$value")"
        if is_valid_driver_version "$normalized"; then
            EXPECTED_HOST_VERSION="$normalized"
            refresh_hardware_detection lxc
            return 0
        fi
        warn "Ungültige Host-Treiberversion: ${value:-leer}"
    done
}

menu_choose_backup_retention() {
    local value
    while true; do
        menu_section "BACKUP-AUFBEWAHRUNG"
        menu_note "Fehler- und Abbruchsicherungen; Erfolgssicherungen folgen der vorherigen Auswahl."
        value="$(menu_read "Aufbewahrungszeit für Fehler-/Abbruchsicherungen in Tagen [$BACKUP_RETENTION_DAYS]: ")"
        value="${value:-$BACKUP_RETENTION_DAYS}"
        if [[ "$value" =~ ^[0-9]+$ ]]; then
            BACKUP_RETENTION_DAYS="$value"
            return 0
        fi
        warn "Ungültige Aufbewahrungszeit: $value"
    done
}

menu_choose_lxc_backend() {
    local choice
    while true; do
        menu_section "LXC-GERÄTEBACKEND"
        menu_item 1 "Automatisch  [Empfohlen]" "Natives Proxmox devN, bei Bedarf markierter manueller Fallback"
        menu_item 2 "Nur natives Proxmox devN" "Abbrechen, falls das native Backend nicht verfügbar ist"
        menu_item 3 "Manueller Fallback" "Markierte cgroup2- und Bind-Mount-Einträge"
        menu_item 0 "Abbrechen"
        choice="$(menu_read 'Auswahl [1]: ')"
        choice="${choice:-1}"
        case "$choice" in
            1) LXC_DEVICE_BACKEND="auto"; return 0 ;;
            2) LXC_DEVICE_BACKEND="native"; return 0 ;;
            3) LXC_DEVICE_BACKEND="manual"; return 0 ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *) warn "Ungültige Auswahl: $choice" ;;
        esac
    done
}

menu_select_backup() {
    local prompt="$1" choice index=1 directory selected
    local -a backups=()
    [[ -d "$BACKUP_ROOT" ]] || { warn "Es sind noch keine Sicherungen vorhanden."; return 1; }
    mapfile -t backups < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'nvidia-*' -printf '%T@\t%p\n' 2>/dev/null | sort -rn | cut -f2-)
    ((${#backups[@]})) || { warn "Es sind noch keine Sicherungen vorhanden."; return 1; }
    menu_section "VERFÜGBARE SICHERUNGEN"
    for directory in "${backups[@]}"; do
        menu_item "$index" "$(basename "$directory")" "$directory"
        index=$((index + 1))
    done
    menu_item 0 "Abbrechen"
    choice="$(menu_read "$prompt")"
    [[ "$choice" == "0" || "$choice" =~ ^[qQ]$ ]] && return 1
    [[ "$choice" =~ ^[0-9]+$ ]] || { warn "Ungültige Auswahl."; return 1; }
    choice=$((10#$choice))
    ((choice >= 1 && choice <= ${#backups[@]})) || return 1
    selected="${backups[choice - 1]}"
    menu_section "ROLLBACK BESTÄTIGEN"
    menu_danger_item 1 "Ausgewählte Sicherung zurückrollen" "$selected"
    menu_item 2 "Zurück  [Standard]"
    choice="$(menu_read 'Auswahl [2]: ')"
    choice="${choice:-2}"
    [[ "$choice" == "1" ]] || return 1
    ROLLBACK_REQUEST="$selected"
}

menu_select_pending_verification() {
    local choice index=1 directory phase reasons
    local -a pending=()
    [[ -d "$BACKUP_ROOT" ]] || { warn "Es sind keine ausstehenden Abschlussprüfungen vorhanden."; return 1; }
    mapfile -t pending < <(
        find "$BACKUP_ROOT" -mindepth 2 -maxdepth 2 -type f \
            -name pending-verification.env -printf '%T@\t%h\n' 2>/dev/null \
            | sort -rn | cut -f2-
    )
    ((${#pending[@]})) || { warn "Es sind keine ausstehenden Abschlussprüfungen vorhanden."; return 1; }
    menu_section "AUSSTEHENDE ABSCHLUSSPRÜFUNGEN"
    for directory in "${pending[@]}"; do
        phase="$(backup_transaction_phase "$directory" 2>/dev/null || printf unbekannt)"
        reasons="$(sed -n 's/^PENDING_REASONS=(//p' "$directory/pending-verification.env" 2>/dev/null | head -n1)"
        menu_item "$index" "$(basename "$directory")" "Status: $phase${reasons:+; Gründe gespeichert}"
        index=$((index + 1))
    done
    menu_item 0 "Abbrechen"
    choice="$(menu_read 'Auswahl [0]: ')"
    choice="${choice:-0}"
    [[ "$choice" == "0" || "$choice" =~ ^[qQ]$ ]] && return 1
    [[ "$choice" =~ ^[0-9]+$ ]] || { warn "Ungültige Auswahl."; return 1; }
    choice=$((10#$choice))
    ((choice >= 1 && choice <= ${#pending[@]})) || return 1
    FINALIZE_PENDING_REQUEST="${pending[choice - 1]}"
}

host_update_abandonment_is_eligible() {
    local directory="$1" setting field
    [[ "$MENU_DETECTED_MODE" == host ]] || return 1
    is_safe_backup_dir "$directory" || return 1
    [[ "$(backup_transaction_phase "$directory")" == rollback-fehlgeschlagen ]] || return 1
    [[ -f "$directory/resume.env" && ! -L "$directory/resume.env" \
       && -f "$directory/rollback-manifest.txt" && ! -L "$directory/rollback-manifest.txt" ]] || return 1
    grep -qxF 'Rolle: host' "$directory/rollback-manifest.txt" || return 1
    grep -qxF 'Aktion: update' "$directory/rollback-manifest.txt" || return 1
    # Eine beschädigte Rückkehrbasis niemals sourcen oder neu signieren.
    # Nur eindeutige literale Metadaten lesen; keine gespeicherten Befehle ausführen.
    for setting in MODE=host TRANSACTION_ACTION=update HOST_LXC_OPERATION=0 \
        CONFIGURE_LXC_GPU=0 INSTALL_LXC_USERSPACE_FROM_HOST=0; do
        field="${setting%%=*}"
        [[ "$(grep -c "^${field}=" "$directory/resume.env")" == 1 ]] || return 1
        grep -qxF "$setting" "$directory/resume.env" || return 1
    done
}

abandon_interrupted_host_update() {
    local directory="$1" archive audit
    ((GLOBAL_LOCK_ACQUIRED && CHECK_ONLY == 0 && DRY_RUN == 0 && ATTACH_ONLY == 0)) \
        || { warn "Aufgeben erfordert die globale Skriptsperre und einen verändernden Menüaufruf."; return 1; }
    [[ "$(id -u)" == 0 ]] || { warn "Das Aufgeben eines Host-Updates erfordert root."; return 1; }
    [[ "$ACTIVE_TRANSACTION_FILE" == "$BACKUP_ROOT/.active-transaction" \
       && -f "$ACTIVE_TRANSACTION_FILE" && ! -L "$ACTIVE_TRANSACTION_FILE" ]] \
        || { warn "Unsicherer oder fehlender Transaktionsmarker; keine Änderung."; return 1; }
    [[ "$(cat "$ACTIVE_TRANSACTION_FILE")" == "$directory" ]] \
        && host_update_abandonment_is_eligible "$directory" \
        || { warn "Nur eine eindeutig erkannte, fehlgeschlagene reine Host-Update-Transaktion darf aufgegeben werden."; return 1; }
    archive="$BACKUP_ROOT/.abandoned-transaction-${directory##*/}"
    [[ ! -e "$archive" && ! -L "$archive" ]] \
        || { warn "Archivierter Marker existiert bereits; er wird nicht überschrieben: $archive"; return 1; }

    log "Prüfe den aktuellen Host-Zustand vor dem Aufgeben des alten Versuchs ..."
    audit="$(dpkg --audit 2>&1)" \
        || { warn "dpkg-Prüfung fehlgeschlagen; der Marker bleibt aktiv: $audit"; return 1; }
    [[ -z "$audit" ]] || { warn "Unvollständiger Paketstatus; der Marker bleibt aktiv: $audit"; return 1; }
    apt-get check || { warn "APT-Abhängigkeiten sind nicht konsistent; der Marker bleibt aktiv."; return 1; }
    detect_driver_versions host
    [[ "$DETECTED_HOST_MODULE_LOADED" == 1 && -n "$DETECTED_HOST_MODULE_VERSION" \
       && "$DETECTED_INSTALLED_MODULE_VERSION" == "$DETECTED_HOST_MODULE_VERSION" \
       && "$DETECTED_PACKAGE_VERSION" == "$DETECTED_HOST_MODULE_VERSION" \
       && "$DETECTED_SMI_VERSION" == "$DETECTED_HOST_MODULE_VERSION" \
       && "$DETECTED_VERSION_STATE" == konsistent:* ]] \
        || { warn "Host-Treiber/NVML sind nicht eindeutig konsistent; der Marker bleibt aktiv. $DETECTED_VERSION_STATE"; return 1; }

    # Nach den Prüfungen nochmals validieren. Der Backup-Inhalt und dessen
    # ursprünglicher Rollback-/Prüfsummenstatus bleiben vollständig unverändert.
    [[ -f "$ACTIVE_TRANSACTION_FILE" && ! -L "$ACTIVE_TRANSACTION_FILE" \
       && "$(cat "$ACTIVE_TRANSACTION_FILE")" == "$directory" ]] \
        && host_update_abandonment_is_eligible "$directory" \
        || { warn "Transaktion wurde zwischenzeitlich verändert; keine Archivierung."; return 1; }
    mv -nT -- "$ACTIVE_TRANSACTION_FILE" "$archive" \
        || { warn "Marker konnte nicht archiviert werden; keine Freigabe für ein neues Update."; return 1; }
    [[ ! -e "$ACTIVE_TRANSACTION_FILE" && -f "$archive" && ! -L "$archive" \
       && "$(cat "$archive")" == "$directory" ]] \
        || { warn "Archivierung nicht bestätigt; ein neuer Vorgang bleibt gesperrt."; return 1; }
    INTERRUPTED_TRANSACTION_PENDING=0
    RESUME_REQUEST=0
    ROLLBACK_REQUEST=""
    ok "Alter Host-Updateversuch ausdrücklich aufgegeben; kein Rollback ausgeführt."
    log "Marker archiviert: $archive"
    log "Sicherung bleibt unverändert und vor automatischer Bereinigung geschützt: $directory"
    log "Für ein neues Host-Update jetzt Hauptmenüpunkt 12 wählen."
}

menu_handle_interrupted_transaction() {
    local directory="" choice confirm phase="" default_choice=1 recommended=""
    [[ -s "$ACTIVE_TRANSACTION_FILE" ]] || return 1
    directory="$(head -n1 "$ACTIVE_TRANSACTION_FILE" 2>/dev/null || true)"
    if ! is_safe_backup_dir "$directory"; then
        INTERRUPTED_TRANSACTION_PENDING=1
        warn "Der Transaktionsmarker ist ungültig. Schreibende Aktionen bleiben gesperrt, bis der Marker geprüft wurde."
        return 1
    fi
    phase="$(backup_transaction_phase "$directory" 2>/dev/null || true)"
    menu_section "UNTERBROCHENE TRANSAKTION"
    menu_note "Sicherung: $directory"
    if [[ "$phase" == "rollback-fehlgeschlagen" ]]; then
        default_choice=3
        recommended=" [empfohlen]"
        warn "Der letzte automatische Rollback war nicht vollständig erfolgreich. Führe zuerst über das Hauptmenü die Diagnose aus oder prüfe $directory/automatic-rollback.log."
    fi
    menu_item 1 "Mit denselben Einstellungen fortsetzen" "Geprüfte Sicherung und gespeicherten Zustand wiederverwenden"
    menu_item 2 "Geprüfte Sicherung zurückrollen" "Prüfsummen vor dem Rollback kontrollieren"
    menu_item 3 "Nur zum Hauptmenü gehen$recommended" "Schreibende Aktionen bleiben bis zur Entscheidung gesperrt"
    if host_update_abandonment_is_eligible "$directory"; then
        menu_item 4 "Fehlgeschlagenen Host-Updateversuch aufgeben" "Aktuellen Host prüfen; Marker archivieren, Sicherung behalten; kein Rollback"
    fi
    menu_item 0 "Abbrechen"
    choice="$(menu_read "Auswahl [$default_choice]: ")"
    choice="${choice:-$default_choice}"
    case "$choice" in
        1)
            load_interrupted_transaction \
                || die "Die Sicherung der unterbrochenen Installation ist unvollständig oder beschädigt."
            RESUME_REQUEST=1
            ASSUME_YES=1
            return 0
            ;;
        2)
            menu_section "ROLLBACK BESTÄTIGEN"
            menu_danger_item 1 "Unterbrochene Transaktion zurückrollen" "$directory"
            menu_item 2 "Zurück  [Standard]"
            confirm="$(menu_read 'Auswahl [2]: ')"
            confirm="${confirm:-2}"
            [[ "$confirm" == "1" ]] || { INTERRUPTED_TRANSACTION_PENDING=1; return 1; }
            ROLLBACK_REQUEST="$directory"
            return 0
            ;;
        3) INTERRUPTED_TRANSACTION_PENDING=1; return 1 ;;
        4)
            INTERRUPTED_TRANSACTION_PENDING=1
            host_update_abandonment_is_eligible "$directory" \
                || { warn "Aufgeben ist für diese Transaktion nicht verfügbar."; return 1; }
            menu_section "HOST-UPDATEVERSUCH AUFGEBEN"
            menu_note "Der aktuelle Host-Zustand wird nach erfolgreicher Prüfung als Ausgangspunkt akzeptiert."
            menu_note "Dies ist KEIN Rollback: frühere Konfigurationsänderungen werden nicht zurückgesetzt."
            menu_note "Die alte Sicherung bleibt unverändert. Ihre Prüfsummen werden nicht repariert oder umgangen."
            menu_danger_item 1 "Prüfen und alten Versuch ausdrücklich aufgeben"
            menu_item 2 "Zurück, Transaktion aktiv lassen  [Standard]"
            confirm="$(menu_read 'Auswahl [2]: ')"
            [[ "${confirm:-2}" == 1 ]] || return 1
            abandon_interrupted_host_update "$directory" || return 1
            return 1
            ;;
        0|q|Q) die "Vom Benutzer abgebrochen." ;;
        *) warn "Ungültige Auswahl: $choice"; INTERRUPTED_TRANSACTION_PENDING=1; return 1 ;;
    esac
}


# ---------------------- NVIDIA-GPU an LXC durchreichen ----------------------
AVAILABLE_GPU_DEVICES=()
AVAILABLE_GPU_LABELS=()
AVAILABLE_GPU_UUIDS=()
AVAILABLE_GPU_BUS_IDS=()

clear_target_gpu_selection() {
    TARGET_GPU_DEVICES=()
    TARGET_GPU_UUIDS=()
    TARGET_GPU_BUS_IDS=()
    TARGET_GPU_DEVICE="auto"
    TARGET_GPU_UUID=""
    TARGET_GPU_BUS_ID=""
    TARGET_GPU_SELECTION_SUMMARY="automatisch"
}

append_gpu_choice_by_index() {
    local index="$1" existing
    local device="${AVAILABLE_GPU_DEVICES[$index]}"

    for existing in "${TARGET_GPU_DEVICES[@]:-}"; do
        [[ "$existing" == "$device" ]] && return 0
    done
    TARGET_GPU_DEVICES+=("$device")
    TARGET_GPU_UUIDS+=("${AVAILABLE_GPU_UUIDS[$index]:-}")
    TARGET_GPU_BUS_IDS+=("${AVAILABLE_GPU_BUS_IDS[$index]:-}")
}

finalize_target_gpu_selection() {
    ((${#TARGET_GPU_DEVICES[@]})) || return 1
    TARGET_GPU_DEVICE="${TARGET_GPU_DEVICES[0]}"
    TARGET_GPU_UUID="${TARGET_GPU_UUIDS[0]:-}"
    TARGET_GPU_BUS_ID="${TARGET_GPU_BUS_IDS[0]:-}"
    TARGET_GPU_SELECTION_SUMMARY="$(join_by ', ' "${TARGET_GPU_DEVICES[@]}")"
}

select_gpu_choice_by_index() {
    clear_target_gpu_selection
    append_gpu_choice_by_index "$1"
    finalize_target_gpu_selection
}

normalize_pci_bus_id() {
    local value="${1^^}"
    value="${value#PCI:}"
    if [[ "$value" =~ ^[0-9A-F]{8}: ]]; then
        value="${value:4}"
    fi
    printf '%s' "$value"
}

refresh_gpu_device_choices() {
    local index name bus uuid device i info_file minor line
    local query_output=""

    AVAILABLE_GPU_DEVICES=()
    AVAILABLE_GPU_LABELS=()
    AVAILABLE_GPU_UUIDS=()
    AVAILABLE_GPU_BUS_IDS=()

    if command -v nvidia-smi >/dev/null 2>&1; then
        if query_output="$(nvidia-smi --query-gpu=index,name,pci.bus_id,uuid --format=csv,noheader 2>/dev/null)"; then
            while IFS=',' read -r index name bus uuid; do
                index="${index//[[:space:]]/}"
                name="${name#"${name%%[![:space:]]*}"}"
                name="${name%"${name##*[![:space:]]}"}"
                bus="${bus//[[:space:]]/}"
                uuid="${uuid//[[:space:]]/}"
                [[ "$index" =~ ^[0-9]+$ ]] || continue
                device="/dev/nvidia${index}"
                AVAILABLE_GPU_DEVICES+=("$device")
                AVAILABLE_GPU_LABELS+=("${name:-NVIDIA GPU $index}${bus:+ – PCI $bus}")
                AVAILABLE_GPU_UUIDS+=("$uuid")
                AVAILABLE_GPU_BUS_IDS+=("$bus")
            done <<<"$query_output"
        fi
    fi

    if ((${#AVAILABLE_GPU_DEVICES[@]} == 0)) && [[ -d /proc/driver/nvidia/gpus ]]; then
        for info_file in /proc/driver/nvidia/gpus/*/information; do
            [[ -r "$info_file" ]] || continue
            bus="${info_file%/information}"
            bus="${bus##*/}"
            minor="$(awk -F: '/^Device Minor:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$info_file")"
            uuid="$(awk -F: '/^GPU UUID:/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' "$info_file")"
            name="$(awk -F: '/^Model:/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' "$info_file")"
            [[ "$minor" =~ ^[0-9]+$ ]] || continue
            AVAILABLE_GPU_DEVICES+=("/dev/nvidia${minor}")
            AVAILABLE_GPU_LABELS+=("${name:-NVIDIA GPU $minor} – PCI $bus")
            AVAILABLE_GPU_UUIDS+=("$uuid")
            AVAILABLE_GPU_BUS_IDS+=("$bus")
        done
    fi

    if ((${#AVAILABLE_GPU_DEVICES[@]} == 0)) && command -v lspci >/dev/null 2>&1; then
        i=0
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            bus="${line%%[[:space:]]*}"
            name="$(sed -E 's/^[^ ]+[[:space:]]+[^:]+:[[:space:]]*//' <<<"$line")"
            name="$(sed -E 's/[[:space:]]*\[[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}\].*$//' <<<"$name")"
            AVAILABLE_GPU_DEVICES+=("/dev/nvidia${i}")
            AVAILABLE_GPU_LABELS+=("${name:-NVIDIA GPU $i} – PCI $bus; Device-Index wird beim Start stabil aufgelöst")
            AVAILABLE_GPU_UUIDS+=("")
            AVAILABLE_GPU_BUS_IDS+=("$bus")
            i=$((i + 1))
        done < <(lspci -Dnn 2>/dev/null | grep -iE 'NVIDIA.*\[(0300|0302|0380)\]|(VGA|3D|Display).*NVIDIA' || true)
    fi

    if ((${#AVAILABLE_GPU_DEVICES[@]} == 0)); then
        while IFS= read -r device; do
            [[ "$device" =~ ^/dev/nvidia[0-9]+$ ]] || continue
            index="${device#/dev/nvidia}"
            name="${DETECTED_GPU_MODELS[$index]:-NVIDIA GPU $index}"
            AVAILABLE_GPU_DEVICES+=("$device")
            AVAILABLE_GPU_LABELS+=("$name")
            AVAILABLE_GPU_UUIDS+=("")
            AVAILABLE_GPU_BUS_IDS+=("")
        done < <(find /dev -maxdepth 1 -type c -name 'nvidia[0-9]*' -print 2>/dev/null | sort -V)
    fi

    if ((${#AVAILABLE_GPU_DEVICES[@]} == 0)) && ((${#DETECTED_GPU_MODELS[@]})); then
        for ((i=0; i<${#DETECTED_GPU_MODELS[@]}; i++)); do
            AVAILABLE_GPU_DEVICES+=("/dev/nvidia${i}")
            AVAILABLE_GPU_LABELS+=("${DETECTED_GPU_MODELS[$i]} – Device wird nach Neustart erwartet")
            AVAILABLE_GPU_UUIDS+=("")
            AVAILABLE_GPU_BUS_IDS+=("")
        done
    fi

    if ((${#AVAILABLE_GPU_DEVICES[@]} == 0)) && [[ "$DETECTED_GPU_SUMMARY" != "nicht erkannt" ]]; then
        AVAILABLE_GPU_DEVICES+=("/dev/nvidia0")
        AVAILABLE_GPU_LABELS+=("$DETECTED_GPU_SUMMARY – Device wird nach Neustart erwartet")
        AVAILABLE_GPU_UUIDS+=("")
        AVAILABLE_GPU_BUS_IDS+=("")
    fi
}

validate_lxc_container_target() {
    [[ "$MODE" == "host" ]] || die "--attach-lxc ist ausschließlich im Host-Modus erlaubt."
    command -v pct >/dev/null 2>&1 || die "pct wurde nicht gefunden; LXC-Konfiguration ist nur auf einem Proxmox-Host möglich."
    [[ "$TARGET_LXC_ID" =~ ^[0-9]+$ ]] || die "Ungültige LXC-ID: ${TARGET_LXC_ID:-leer}."
    pct config "$TARGET_LXC_ID" >/dev/null 2>&1 \
        || die "LXC $TARGET_LXC_ID wurde auf diesem Proxmox-Host nicht gefunden."

    TARGET_LXC_NAME="$(pct config "$TARGET_LXC_ID" 2>/dev/null | awk -F': ' '$1 == "hostname" {print $2; exit}')"
    TARGET_LXC_NAME="${TARGET_LXC_NAME:-CT-${TARGET_LXC_ID}}"
}

validate_lxc_target() {
    local i selector matched bus
    validate_lxc_container_target

    refresh_gpu_device_choices
    ((${#AVAILABLE_GPU_DEVICES[@]})) \
        || die "Keine NVIDIA-GPU für die LXC-Freigabe erkannt."

    clear_target_gpu_selection
    if ((${#TARGET_GPU_SELECTORS[@]} == 0)); then
        if ((${#AVAILABLE_GPU_DEVICES[@]} == 1)); then
            append_gpu_choice_by_index 0
        else
            die "Mehrere NVIDIA-GPUs erkannt. Nutze --gpu-device, --gpu-uuid, --gpu-pci oder --all-gpus."
        fi
    else
        for selector in "${TARGET_GPU_SELECTORS[@]}"; do
            matched=0
            if [[ "$selector" == "all" ]]; then
                for ((i=0; i<${#AVAILABLE_GPU_DEVICES[@]}; i++)); do
                    append_gpu_choice_by_index "$i"
                done
                continue
            fi
            for ((i=0; i<${#AVAILABLE_GPU_DEVICES[@]}; i++)); do
                bus="$(normalize_pci_bus_id "${AVAILABLE_GPU_BUS_IDS[$i]:-}")"
                if [[ "$selector" == "${AVAILABLE_GPU_DEVICES[$i]}" \
                      || "$selector" == "${AVAILABLE_GPU_UUIDS[$i]:-}" \
                      || "$(normalize_pci_bus_id "$selector")" == "$bus" && -n "$bus" ]]; then
                    append_gpu_choice_by_index "$i"
                    matched=1
                    break
                fi
            done
            ((matched)) || die "GPU-Auswahl '$selector' wurde nicht gefunden."
        done
    fi

    ((${#TARGET_GPU_DEVICES[@]})) || die "Keine GPU wurde ausgewählt."
    finalize_target_gpu_selection

    for ((i=0; i<${#TARGET_GPU_DEVICES[@]}; i++)); do
        if [[ -z "${TARGET_GPU_UUIDS[$i]:-}" && -z "${TARGET_GPU_BUS_IDS[$i]:-}" ]]; then
            warn "Für ${TARGET_GPU_DEVICES[$i]} fehlt eine stabile UUID/PCI-ID; der Device-Index kann sich nach einem Neustart ändern."
        fi
    done
}

menu_choose_lxc_container() {
    local ctid
    local -a containers=()

    [[ "$MODE" == "host" || "$MENU_DETECTED_MODE" == "host" ]] \
        || die "Die LXC-Verwaltung vom Host ist nur auf einem Proxmox-Host verfügbar."
    command -v pct >/dev/null 2>&1 \
        || die "pct wurde nicht gefunden; die LXC-Verwaltung ist nur auf einem Proxmox-Host möglich."
    mapfile -t containers < <(pct list 2>/dev/null | awk 'NR > 1 && $1 ~ /^[0-9]+$/ {print $1}')
    ((${#containers[@]})) || die "Auf diesem Host wurden keine LXC-Container gefunden."

    menu_section "LXC AUSWÄHLEN"
    menu_note "Verfügbare Container:"
    pct list | sed 's/^/│        /'
    while true; do
        ctid="$(menu_read 'LXC-ID (0 = Abbrechen): ')"
        [[ "$ctid" != "0" && "$ctid" != "q" && "$ctid" != "Q" ]] \
            || die "Vom Benutzer abgebrochen."
        if [[ "$ctid" =~ ^[0-9]+$ ]] && pct config "$ctid" >/dev/null 2>&1; then
            TARGET_LXC_ID="$ctid"
            TARGET_LXC_NAME="$(pct config "$ctid" 2>/dev/null | awk -F': ' '$1 == "hostname" {print $2; exit}')"
            TARGET_LXC_NAME="${TARGET_LXC_NAME:-CT-${ctid}}"
            return 0
        fi
        warn "LXC $ctid wurde nicht gefunden."
    done
}

menu_choose_lxc_userspace_from_host() {
    local choice
    ((CONFIGURE_LXC_GPU)) || return 0
    while true; do
        menu_section "LXC-SOFTWARE"
        menu_item 1 "GPU und NVIDIA-Bibliotheken einrichten  [Empfohlen]" "Exakt passend zum geladenen Host-Kernelmodul"
        menu_item 2 "Nur GPU-Geräte zuweisen" "Pakete und APT im LXC unverändert lassen"
        menu_item 0 "Abbrechen"
        choice="$(menu_read 'Auswahl [1]: ')"
        choice="${choice:-1}"
        case "$choice" in
            1) INSTALL_LXC_USERSPACE_FROM_HOST=1; return 0 ;;
            2) INSTALL_LXC_USERSPACE_FROM_HOST=0; return 0 ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *) warn "Ungültige Auswahl: $choice" ;;
        esac
    done
}

menu_choose_lxc_runtime_policy() {
    local state choice
    ((INSTALL_LXC_USERSPACE_FROM_HOST)) || return 0
    state="$(pct status "$TARGET_LXC_ID" 2>/dev/null | awk '{print $2}')"
    case "$state" in
        stopped)
            while true; do
                menu_section "CONTAINER-ZUSTAND"
                menu_note "LXC $TARGET_LXC_ID ist gestoppt."
                menu_item 1 "Temporär starten  [Empfohlen]" "Einrichten, prüfen und anschließend wieder herunterfahren"
                menu_item 0 "Abbrechen" "Container bleibt gestoppt"
                choice="$(menu_read 'Auswahl [1]: ')"
                choice="${choice:-1}"
                case "$choice" in
                    1) LXC_TEMPORARY_START_ALLOWED=1; return 0 ;;
                    0|q|Q) die "Vom Benutzer abgebrochen; LXC $TARGET_LXC_ID bleibt gestoppt." ;;
                    *) warn "Ungültige Auswahl: $choice" ;;
                esac
            done
            ;;
        running)
            if ((CONFIGURE_LXC_GPU)); then
                while true; do
                    menu_section "CONTAINER-NEUSTART"
                    menu_note "Neue GPU-Geräte werden in einem laufenden LXC erst nach einem Neustart sichtbar."
                    menu_item 1 "Kontrolliert neu starten  [Empfohlen]" "Danach Geräte, NVML und Transcoding vollständig prüfen"
                    menu_item 2 "Neustart verschieben" "Bibliotheken jetzt installieren; LXC später selbst neu starten"
                    menu_item 0 "Abbrechen"
                    choice="$(menu_read 'Auswahl [1]: ')"
                    choice="${choice:-1}"
                    case "$choice" in
                        1) LXC_RESTART_RUNNING_ALLOWED=1; return 0 ;;
                        2) LXC_RESTART_RUNNING_ALLOWED=0; return 0 ;;
                        0|q|Q) die "Vom Benutzer abgebrochen." ;;
                        *) warn "Ungültige Auswahl: $choice" ;;
                    esac
                done
            fi
            ;;
        *) die "Zustand von LXC $TARGET_LXC_ID konnte nicht sicher bestimmt werden." ;;
    esac
}

menu_choose_lxc_passthrough() {
    local effective_mode="$MODE"
    local required="${1:-0}"
    local choice index

    [[ "$effective_mode" == "auto" ]] && effective_mode="$MENU_DETECTED_MODE"
    if [[ "$effective_mode" != "host" ]]; then
        CONFIGURE_LXC_GPU=0
        TARGET_LXC_ID=""
        TARGET_LXC_NAME=""
        TARGET_GPU_DEVICE="auto"
        TARGET_GPU_UUID=""
        TARGET_GPU_BUS_ID=""
        return 0
    fi

    if ! command -v pct >/dev/null 2>&1; then
        if ((required)); then
            die "pct wurde nicht gefunden; die GPU-Freigabe ist nur auf einem Proxmox-Host möglich."
        fi
        warn "pct wurde nicht gefunden; die optionale LXC-GPU-Freigabe wird übersprungen."
        CONFIGURE_LXC_GPU=0
        return 0
    fi

    if ((required)); then
        CONFIGURE_LXC_GPU=1
    else
        while true; do
            menu_section "OPTIONALE LXC-GPU-FREIGABE"
            menu_item 1 "Ja" "LXC und eine oder mehrere GPUs auswählen"
            menu_item 2 "Nein  [Standard]" "Nur die gewählte Host-Aktion ausführen"
            menu_item 0 "Abbrechen"
            choice="$(menu_read 'Auswahl [2]: ')"
            choice="${choice:-2}"
            case "$choice" in
                1|j|J|ja|JA|Ja) CONFIGURE_LXC_GPU=1; break ;;
                2|n|N|nein|NEIN|Nein)
                    CONFIGURE_LXC_GPU=0
                    TARGET_LXC_ID=""
                    TARGET_LXC_NAME=""
                    TARGET_GPU_DEVICE="auto"
                    TARGET_GPU_UUID=""
                    TARGET_GPU_BUS_ID=""
                    return 0
                    ;;
                0|q|Q) die "Vom Benutzer abgebrochen." ;;
                *) warn "Ungültige Auswahl: $choice" ;;
            esac
        done
    fi

    menu_choose_lxc_container

    refresh_gpu_device_choices
    ((${#AVAILABLE_GPU_DEVICES[@]})) || die "Keine NVIDIA-GPU für die LXC-Freigabe erkannt."

    if ((${#AVAILABLE_GPU_DEVICES[@]} == 1)); then
        select_gpu_choice_by_index 0
        ok "GPU ausgewählt: $TARGET_GPU_DEVICE (${AVAILABLE_GPU_LABELS[0]})"
        return 0
    fi

    menu_section "NVIDIA-GPU AUSWÄHLEN"
    for ((index=0; index<${#AVAILABLE_GPU_DEVICES[@]}; index++)); do
        menu_item "$((index + 1))" "${AVAILABLE_GPU_DEVICES[$index]}$([[ $index -eq 0 ]] && printf '  [Standard]')" \
            "${AVAILABLE_GPU_LABELS[$index]}"
    done
    menu_item a "Alle GPUs"
    menu_item 0 "Abbrechen"

    while true; do
        choice="$(menu_read 'Auswahl, mehrere mit Komma [1]: ')"
        choice="${choice:-1}"
        if [[ "$choice" =~ ^([aA]|alle|ALLE)$ ]]; then
            clear_target_gpu_selection
            for ((index=0; index<${#AVAILABLE_GPU_DEVICES[@]}; index++)); do
                append_gpu_choice_by_index "$index"
            done
            TARGET_GPU_SELECTORS=(all)
            finalize_target_gpu_selection
            return 0
        fi
        [[ "$choice" == "0" ]] && die "Vom Benutzer abgebrochen."
        if [[ "$choice" =~ ^[0-9]+([[:space:]]*,[[:space:]]*[0-9]+)*$ ]]; then
            clear_target_gpu_selection
            TARGET_GPU_SELECTORS=()
            while IFS= read -r index; do
                index="${index//[[:space:]]/}"
                index=$((10#$index))
                if ((index < 1 || index > ${#AVAILABLE_GPU_DEVICES[@]})); then
                    clear_target_gpu_selection
                    break
                fi
                append_gpu_choice_by_index "$((index - 1))"
                TARGET_GPU_SELECTORS+=("${AVAILABLE_GPU_DEVICES[$((index - 1))]}")
            done < <(tr ',' '\n' <<<"$choice")
            if ((${#TARGET_GPU_DEVICES[@]})); then
                finalize_target_gpu_selection
                return 0
            fi
        fi
        warn "Ungültige Auswahl: $choice"
    done
}

menu_choose_device_permissions() {
    local choice value default_video_gid=44 state

    ((CONFIGURE_LXC_GPU)) || return 0
    state="$(pct status "$TARGET_LXC_ID" 2>/dev/null | awk '{print $2}' || true)"
    if [[ "$state" == "running" ]]; then
        value="$(pct exec "$TARGET_LXC_ID" -- getent group video 2>/dev/null \
            | awk -F: 'NF >= 3 && $3 ~ /^[0-9]+$/ {print $3; exit}' || true)"
        [[ "$value" =~ ^[0-9]+$ ]] && default_video_gid="$value"
    fi
    while true; do
        menu_section "GERÄTEBERECHTIGUNGEN IM LXC"
        menu_note "GPU, nvidiactl, UVM, UVM-Tools und vorhandene nvidia-caps erhalten dieselbe Zuordnung."
        menu_item 1 "Proxmox-/Transcoding-Standard  [Empfohlen]" "Host-Modus erben; video-GID: $default_video_gid (typisch 44)"
        menu_item 2 "Gesamter Container" "mode=0666; keine feste UID/GID"
        menu_item 3 "Nur root" "mode=0600"
        menu_item 4 "Benutzerdefiniert" "mode, UID und GID selbst festlegen"
        menu_item 0 "Abbrechen"
        choice="$(menu_read 'Auswahl [1]: ')"
        choice="${choice:-1}"
        case "$choice" in
            1)
                LXC_DEVICE_MODE="inherit"
                LXC_DEVICE_UID=""
                LXC_DEVICE_GID="$default_video_gid"
                return 0
                ;;
            2)
                LXC_DEVICE_MODE="0666"
                LXC_DEVICE_UID=""
                LXC_DEVICE_GID=""
                return 0
                ;;
            3)
                LXC_DEVICE_MODE="0600"
                LXC_DEVICE_UID="0"
                LXC_DEVICE_GID="0"
                return 0
                ;;
            4)
                value="$(menu_read 'Dateimodus, z. B. 0660: ')"
                [[ "$value" =~ ^0[0-7]{3}$ ]] || { warn "Der Modus muss vierstellig oktal sein."; continue; }
                LXC_DEVICE_MODE="$value"
                value="$(menu_read 'UID oder leer für Proxmox-Vorgabe: ')"
                [[ -z "$value" || "$value" =~ ^[0-9]+$ ]] || { warn "Ungültige UID."; continue; }
                LXC_DEVICE_UID="$value"
                value="$(menu_read 'GID oder leer für Proxmox-Vorgabe: ')"
                [[ -z "$value" || "$value" =~ ^[0-9]+$ ]] || { warn "Ungültige GID."; continue; }
                LXC_DEVICE_GID="$value"
                return 0
                ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *) warn "Ungültige Auswahl: $choice" ;;
        esac
    done
}

menu_mode_label() {
    case "$MODE" in
        host) printf 'Host (%s)' "${OS_LABEL:-Proxmox/Ubuntu}" ;;
        lxc)  printf '%s-LXC' "${OS_LABEL:-Debian/Ubuntu}" ;;
        auto)
            case "$MENU_DETECTED_MODE" in
                host) printf 'Automatisch (Host erkannt: %s)' "${OS_LABEL:-Proxmox/Ubuntu}" ;;
                lxc)  printf 'Automatisch (LXC erkannt)' ;;
                *)    printf 'Automatisch (noch nicht eindeutig erkannt)' ;;
            esac
            ;;
    esac
}

menu_backend_label() {
    case "${LXC_DEVICE_BACKEND:-auto}" in
        auto) printf 'automatisch (nativ bevorzugt)' ;;
        native) printf 'nur nativ' ;;
        manual) printf 'manueller Fallback' ;;
    esac
}

menu_transcode_label() {
    case "${TRANSCODE_SMOKE_TEST:-auto}" in
        auto) printf 'automatisch' ;;
        yes) printf 'zwingend' ;;
        no) printf 'überspringen' ;;
    esac
}

menu_nvtop_label() {
    case "${NVTOP_MANAGEMENT:-auto}" in
        install) printf 'installieren/reparieren und echt prüfen' ;;
        auto)    printf 'vorhandene Installation prüfen/reparieren' ;;
        skip)    printf 'überspringen' ;;
    esac
}

menu_init_theme() {
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        MENU_RESET=$'\033[0m'
        MENU_BOLD=$'\033[1m'
        MENU_BLUE=$'\033[1;34m'
        MENU_CYAN=$'\033[1;36m'
        MENU_GREEN=$'\033[1;32m'
        MENU_YELLOW=$'\033[1;33m'
        MENU_RED=$'\033[1;31m'
        MENU_DIM=$'\033[2m'
    else
        MENU_RESET=""
        MENU_BOLD=""
        MENU_BLUE=""
        MENU_CYAN=""
        MENU_GREEN=""
        MENU_YELLOW=""
        MENU_RED=""
        MENU_DIM=""
    fi
}

menu_rule() {
    printf '%s%s%s\n' "$MENU_BLUE" '────────────────────────────────────────────────────────────────────────' "$MENU_RESET"
}

menu_section() {
    printf '\n%s┌─ %s%s\n' "$MENU_CYAN" "$1" "$MENU_RESET"
}

menu_item() {
    local key="$1" label="$2" detail="${3:-}"
    printf '│  %s[%2s]%s  %s\n' "$MENU_GREEN" "$key" "$MENU_RESET" "$label"
    [[ -z "$detail" ]] || printf '│        %s↳ %s%s\n' "$MENU_DIM" "$detail" "$MENU_RESET"
}

menu_note() {
    local text="${1:-}"
    printf '│        %s%s%s\n' "$MENU_DIM" "$text" "$MENU_RESET"
}

menu_danger_item() {
    local key="$1" label="$2" detail="${3:-}"
    printf '│  %s[%2s]  %s%s\n' "$MENU_RED" "$key" "$label" "$MENU_RESET"
    [[ -z "$detail" ]] || printf '│        %s↳ %s%s\n' "$MENU_DIM" "$detail" "$MENU_RESET"
}

menu_render_header() {
    menu_rule
    printf '%s%s  NVIDIA GPU & LXC SETUP%s                         %sv%s%s\n' \
        "$MENU_BOLD" "$MENU_BLUE" "$MENU_RESET" "$MENU_DIM" "$SCRIPT_VERSION" "$MENU_RESET"
    menu_rule
    printf '  %-13s %s (%s)\n' 'System' "$OS_LABEL" "$DISTRO"
    printf '  %-13s %s\n' 'Rolle' "$(menu_mode_label)"
    printf '  %-13s %s\n' 'GPU' "$DETECTED_GPU_SUMMARY"
    printf '  %-13s %s\n' 'Treiber' "$DETECTED_VERSION_STATE"
    menu_rule
}

interactive_menu() {
    local action operation value candidate
    local effective_mode

    menu_init_theme
    MENU_DETECTED_MODE="$(menu_detect_mode)"
    if menu_handle_interrupted_transaction; then
        return 0
    fi
    refresh_hardware_detection "$MENU_DETECTED_MODE"

    while true; do
        REQUESTED_VERSION="auto"
        MODE="auto"
        KERNEL_FLAVOR="auto"
        FIX_MICROSOFT_CONFLICT=0
        ASSUME_YES=0
        CHECK_ONLY=0
        DIAGNOSE_ALL=0
        ATTACH_ONLY=0
        DRY_RUN=0
        UNINSTALL_REQUEST=0
        CLEANUP_BACKUPS_REQUEST=0
        FINALIZE_PENDING_REQUEST=""
        KEEP_SUCCESS_BACKUP=0
        DELETE_SUCCESS_LOGS=1
        SUCCESS_BACKUP_CLEANUP_BLOCKED=0
        TRANSCODE_SMOKE_TEST="auto"
        NVTOP_MANAGEMENT="auto"
        GPU_CONSUMER_POLICY="abort"
        STOPPED_GPU_CONSUMERS=()
        INITIAL_APT_AUTOREMOVE=0
        FINAL_APT_AUTOREMOVE=1
        AUTOMATIC_REPAIR=1
        REPAIR_ONLY_REQUEST=0
        CLEAN_INSTALL_SCOPE="full"
        TRANSACTION_ACTION="install"
        UPDATE_ONLY=0
        EXPECTED_HOST_VERSION=""
        PENDING_VERIFICATION_REASONS=()
        PIN_NVIDIA_PACKAGES=0
        PIN_CHOICE_EXPLICIT=0
        CONFIGURE_LXC_GPU=0
        INSTALL_LXC_USERSPACE_FROM_HOST=0
        HOST_LXC_OPERATION=0
        TARGET_LXC_ID=""
        TARGET_LXC_NAME=""
        TARGET_GPU_DEVICE="auto"
        TARGET_GPU_UUID=""
        TARGET_GPU_BUS_ID=""
        TARGET_GPU_SELECTORS=()
        TARGET_GPU_DEVICES=()
        TARGET_GPU_UUIDS=()
        TARGET_GPU_BUS_IDS=()
        LXC_DEVICE_MODE="inherit"
        LXC_DEVICE_UID=""
        LXC_DEVICE_GID="44"
        LXC_DEVICE_BACKEND="auto"
        LXC_TEMPORARY_START_ALLOWED=0
        LXC_RESTART_RUNNING_ALLOWED=0
        LXC_ORIGINAL_STATE=""
        LXC_RUNTIME_TOUCHED=0
        LXC_DEVICE_SYNC_RESTART_DONE=0
        LXC_REMOTE_SUCCESS_BACKUP=""
        LXC_REMOTE_BACKUP_CLEANUP_PENDING=0

        printf '\n'
        menu_render_header
        printf '\n%sWas möchtest du machen?%s  %sENTER wählt Punkt 1%s\n' \
            "$MENU_BOLD" "$MENU_RESET" "$MENU_DIM" "$MENU_RESET"
        menu_section "INSTALLATION AUF DIESEM SYSTEM"
        menu_item 1 "NVIDIA sauber installieren oder aktualisieren  [Standard]" "Host: Treiber und DKMS; LXC: ausschließlich Userspace-Bibliotheken"
        menu_section "LXC VOM PROXMOX-HOST VERWALTEN"
        if command -v pct >/dev/null 2>&1; then
            menu_item 2 "LXC vollständig einrichten" "GPU-Geräte zuweisen, Bibliotheken installieren und Funktion prüfen"
            menu_item 3 "Nur GPU-Geräte an einen LXC durchreichen" "Keine Treiber-, Paket- oder APT-Änderungen"
            menu_item 4 "Nur NVIDIA-Bibliotheken im LXC installieren" "Ausführung vollständig vom Host über pct"
        else
            menu_note "Nicht verfügbar: Dieses System stellt kein Proxmox-pct bereit."
        fi
        menu_section "DIAGNOSE · REPARATUR · SIMULATION"
        menu_item 5 "Diagnose und Versionsabgleich" "Host und NVIDIA-LXC übersichtlich prüfen"
        menu_item 6 "Automatische Fehleranalyse und Behebung" "APT, dpkg, DKMS, Module und NVIDIA-Laufzeit sicher nachbessern"
        menu_item 7 "Dry-Run" "Installation und Konfiguration ohne Änderungen simulieren"
        menu_section "SICHERUNGEN · ABSCHLUSSPRÜFUNG"
        menu_item 8 "Ausstehende Abschlussprüfung fortsetzen" "Laufzeit erneut prüfen und gespeicherte bzw. konservative Sicherungsrichtlinie anwenden"
        menu_item 9 "Sicherung zurückrollen" "Prüfsummen vor dem Rollback kontrollieren"
        menu_item 10 "Alte Sicherungen bereinigen" "Aufbewahrungszeit frei festlegen"
        menu_section "ENTFERNEN"
        if [[ "$MENU_DETECTED_MODE" == "host" ]] && command -v pct >/dev/null 2>&1; then
            menu_danger_item 11 "NVIDIA vollständig entfernen" "Treiber, Bibliotheken, CUDA-/Container-Toolkit und verwaltete LXC-Einträge"
        elif [[ "$MENU_DETECTED_MODE" == "lxc" ]]; then
            menu_danger_item 11 "NVIDIA im LXC vollständig entfernen" "Userspace-Bibliotheken, CUDA-/Container-Toolkit und LXC-interne Konfiguration; Host-Zuweisung bleibt unverändert"
        else
            menu_danger_item 11 "NVIDIA vollständig entfernen" "Treiber, Bibliotheken, CUDA-/Container-Toolkit und lokale NVIDIA-Konfiguration"
        fi
        printf '\n'
        menu_section "UPDATES"
        menu_item 12 "NVIDIA-Pakete auf diesem System aktualisieren" "Neueste passende Version abfragen; vorhandenen Stack ohne pauschale Neuinstallation aktualisieren und exakt pinnen"
        if command -v pct >/dev/null 2>&1; then
            menu_item 13 "NVIDIA-Pakete in einem LXC aktualisieren" "Vom Host aus; Bibliotheken exakt zum geladenen Host-Modul, CUDA/Container-Pakete separat"
        fi
        menu_item 14 "NVIDIA-Update nur simulieren" "Lokalen APT-Cache verwenden; keine Paket-, Hold- oder Systemänderungen"
        menu_item 0 "Beenden"
        menu_rule
        operation="$(menu_read 'Auswahl [1]: ')"
        operation="${operation:-1}"
        case "$operation" in
            1) operation="install" ;;
            2|3|4)
                command -v pct >/dev/null 2>&1 \
                    || { warn "Diese Auswahl ist nur auf einem Proxmox-Host mit pct verfügbar."; continue; }
                case "$operation" in
                    2) operation="lxc-complete" ;;
                    3) operation="attach-only" ;;
                    4) operation="lxc-userspace" ;;
                esac
                ;;
            5) operation="check" ;;
            6) operation="repair" ;;
            7) operation="dry-run" ;;
            8)
                menu_select_pending_verification && { ASSUME_YES=1; return 0; }
                continue
                ;;
            9)
                menu_select_backup 'Sicherung auswählen: ' && return 0
                continue
                ;;
            10)
                value="$(menu_read "Aufbewahrung in Tagen [$BACKUP_RETENTION_DAYS]: ")"
                candidate="${value:-$BACKUP_RETENTION_DAYS}"
                [[ "$candidate" =~ ^[0-9]+$ ]] \
                    || { warn "Ungültige Aufbewahrungszeit."; continue; }
                BACKUP_RETENTION_DAYS=$((10#$candidate))
                menu_section "BACKUP-BEREINIGUNG BESTÄTIGEN"
                menu_note "Entfernt abgeschlossene Sicherungen, die älter als $BACKUP_RETENTION_DAYS Tage sind; aktive und ausstehende Prüfungen bleiben geschützt."
                menu_danger_item 1 "Bereinigung starten"
                menu_item 2 "Zurück  [Standard]"
                value="$(menu_read 'Auswahl [2]: ')"
                value="${value:-2}"
                [[ "$value" == "1" ]] || continue
                CLEANUP_BACKUPS_REQUEST=1
                ASSUME_YES=1
                return 0
                ;;
            11) operation="uninstall" ;;
            12) operation="update" ;;
            13)
                command -v pct >/dev/null 2>&1 || { warn "Nur auf einem Proxmox-Host verfügbar."; continue; }
                operation="lxc-update"
                ;;
            14) operation="update-preview" ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *)
                warn "Ungültige Auswahl: $operation"
                continue
                ;;
        esac

        if ((INTERRUPTED_TRANSACTION_PENDING)) \
           && [[ "$operation" != "check" && "$operation" != "dry-run" && "$operation" != "update-preview" ]]; then
            warn "Wegen der unterbrochenen Transaktion sind nur Diagnose und Dry-Run zulässig. Öffne die Wiederanlauf-Auswahl ..."
            if menu_handle_interrupted_transaction; then
                return 0
            fi
            continue
        fi

        if [[ "$operation" == "attach-only" || "$operation" == "lxc-complete" \
              || "$operation" == "lxc-userspace" || "$operation" == "lxc-update" ]]; then
            MODE="host"
        else
            menu_choose_mode
        fi

        effective_mode="$MODE"
        [[ "$effective_mode" == "auto" ]] && effective_mode="$MENU_DETECTED_MODE"
        refresh_hardware_detection "$effective_mode"
        if [[ "$effective_mode" == "lxc" && ("$operation" == "install" || "$operation" == "dry-run" || "$operation" == "repair" || "$operation" == "update" || "$operation" == "update-preview") ]]; then
            menu_choose_lxc_host_version
        fi

        case "$operation" in
            update|lxc-update|update-preview)
                UPDATE_ONLY=1
                TRANSACTION_ACTION="$operation"
                REQUESTED_VERSION=auto
                CLEAN_INSTALL_SCOPE=full
                PIN_NVIDIA_PACKAGES=1
                PIN_CHOICE_EXPLICIT=1
                INITIAL_APT_AUTOREMOVE=0
                if [[ "$operation" == update-preview ]]; then
                    DRY_RUN=1
                    FINAL_APT_AUTOREMOVE=0
                elif [[ "$operation" == lxc-update ]]; then
                    HOST_LXC_OPERATION=1
                    INSTALL_LXC_USERSPACE_FROM_HOST=1
                    CONFIGURE_LXC_GPU=0
                    menu_choose_lxc_container
                    menu_choose_lxc_runtime_policy
                else
                    menu_choose_gpu_consumer_policy
                fi
                if [[ "$operation" != update-preview ]]; then
                    menu_choose_automatic_repair
                    menu_choose_final_autoremove
                    menu_choose_transcode_smoke_test
                    menu_choose_nvtop_management
                fi
                ;;
            install)
                TRANSACTION_ACTION="install"
                menu_choose_version
                menu_choose_clean_install_scope
                menu_choose_kernel
                menu_choose_microsoft_fix
                menu_choose_version_binding
                menu_choose_automatic_repair
                menu_choose_gpu_consumer_policy
                menu_choose_initial_autoremove
                menu_choose_final_autoremove
                menu_choose_lxc_passthrough
                if ((CONFIGURE_LXC_GPU)); then
                    menu_choose_lxc_backend
                    menu_choose_lxc_userspace_from_host
                fi
                menu_choose_device_permissions
                ((INSTALL_LXC_USERSPACE_FROM_HOST)) && menu_choose_lxc_runtime_policy
                menu_choose_transcode_smoke_test
                menu_choose_nvtop_management
                menu_choose_final_autoremove
                ;;
            lxc-complete)
                TRANSACTION_ACTION="lxc-complete"
                HOST_LXC_OPERATION=1
                CONFIGURE_LXC_GPU=1
                INSTALL_LXC_USERSPACE_FROM_HOST=1
                menu_choose_lxc_passthrough 1
                menu_choose_clean_install_scope
                menu_choose_lxc_backend
                menu_choose_device_permissions
                menu_choose_version_binding
                menu_choose_automatic_repair
                menu_choose_lxc_runtime_policy
                menu_choose_transcode_smoke_test
                menu_choose_nvtop_management
                menu_choose_final_autoremove
                ;;
            attach-only)
                TRANSACTION_ACTION="attach"
                ATTACH_ONLY=1
                menu_choose_lxc_passthrough 1
                menu_choose_lxc_backend
                menu_choose_device_permissions
                ;;
            lxc-userspace)
                TRANSACTION_ACTION="lxc-userspace"
                HOST_LXC_OPERATION=1
                INSTALL_LXC_USERSPACE_FROM_HOST=1
                CONFIGURE_LXC_GPU=0
                menu_choose_lxc_container
                menu_choose_clean_install_scope
                menu_choose_version_binding
                menu_choose_automatic_repair
                menu_choose_lxc_runtime_policy
                menu_choose_transcode_smoke_test
                menu_choose_nvtop_management
                menu_choose_final_autoremove
                ;;
            dry-run)
                DRY_RUN=1
                TRANSACTION_ACTION="dry-run"
                menu_choose_version
                menu_choose_clean_install_scope
                menu_choose_kernel
                menu_choose_microsoft_fix
                menu_choose_version_binding
                menu_choose_automatic_repair
                menu_choose_gpu_consumer_policy
                menu_choose_initial_autoremove
                menu_choose_lxc_passthrough
                if ((CONFIGURE_LXC_GPU)); then
                    menu_choose_lxc_backend
                    menu_choose_lxc_userspace_from_host
                fi
                menu_choose_device_permissions
                ;;
            repair)
                TRANSACTION_ACTION="repair"
                REPAIR_ONLY_REQUEST=1
                AUTOMATIC_REPAIR=1
                menu_choose_version
                menu_choose_kernel
                menu_choose_gpu_consumer_policy
                menu_choose_transcode_smoke_test
                menu_choose_nvtop_management
                ;;
            check)
                CHECK_ONLY=1
                [[ "$effective_mode" == "host" ]] && DIAGNOSE_ALL=1
                ASSUME_YES=1
                return 0
                ;;
            uninstall)
                TRANSACTION_ACTION="uninstall"
                UNINSTALL_REQUEST=1
                ;;
        esac

        case "$operation" in
            install|update|lxc-update|lxc-complete|attach-only|lxc-userspace|uninstall|repair)
                menu_choose_success_backup_policy
                menu_choose_backup_retention
                ;;
        esac

        printf '\nGewählte Einstellungen:\n'
        if ((UPDATE_ONLY)); then
            if ((DRY_RUN)); then
                printf '  Vorgang:              NVIDIA-Update-Vorschau ohne Systemänderungen\n'
            else
                printf '  Vorgang:              NVIDIA-Paketupdate ohne pauschale Neuinstallation\n'
            fi
            printf '  Ausführungsort:       %s%s\n' "$(menu_mode_label)" "${TARGET_LXC_ID:+ → LXC $TARGET_LXC_ID}"
            if ((DRY_RUN)); then printf '  Zielversion:          aus vorhandenen Paketlisten (Cache)\n';
            else printf '  Zielversion:          nach Aktualisierung der Paketlisten ermitteln\n'; fi
            printf '  LXC-Grenze:           exakt wie geladenes Host-Kernelmodul\n'
            printf '  Paketumfang:          vorhandene NVIDIA-/CUDA-/Container-Komponenten und benötigte Abhängigkeiten\n'
            if ((DRY_RUN)); then printf '  Versionsbindung:      nur Vorschau; keine Holds oder Pins ändern\n';
            else printf '  Versionsbindung:      exakte DEB-Versionen pinnen und halten\n'; fi
            printf '  GPU-Zuweisung:        bleibt unverändert\n'
            printf '  Systemupgrade:        nein\n'
            if ((DRY_RUN == 0)); then
                printf '  GPU-Dienste:          %s\n' "$GPU_CONSUMER_POLICY"
                printf '  Abschlussbereinigung: %s\n' "$([[ "$FINAL_APT_AUTOREMOVE" == 1 ]] && printf 'sicheres apt autoremove' || printf 'aus')"
                printf '  Fehlerbehebung:       %s\n' "$([[ "$AUTOMATIC_REPAIR" == 1 ]] && printf 'sichere Reparaturen aktiv' || printf 'nur Diagnose')"
            fi
        elif [[ "$operation" == "attach-only" ]]; then
            printf '  Vorgang:              nur GPU an LXC durchreichen\n'
            printf '  Ausführungsort:       Proxmox-Host\n'
            printf '  Erkannte GPU(s):      %s\n' "$DETECTED_GPU_SUMMARY"
            printf '  LXC-GPU-Freigabe:     %s (%s) ← %s\n' \
                "$TARGET_LXC_ID" "$TARGET_LXC_NAME" "$TARGET_GPU_SELECTION_SUMMARY"
            printf '  LXC-Gerätebackend:    %s\n' "$(menu_backend_label)"
            printf '  Zugriff im LXC:       mode=%s%s%s\n' "$LXC_DEVICE_MODE" \
                "${LXC_DEVICE_UID:+, uid=$LXC_DEVICE_UID}" "${LXC_DEVICE_GID:+, gid=$LXC_DEVICE_GID}"
            printf '  Treiber/Pakete/APT:   bleiben unverändert\n'
        elif [[ "$operation" == "lxc-complete" || "$operation" == "lxc-userspace" ]]; then
            if [[ "$operation" == "lxc-complete" ]]; then
                printf '  Vorgang:              LXC vollständig vom Host einrichten\n'
                printf '  GPU-Freigabe:         %s ← %s\n' "$TARGET_LXC_ID" "$TARGET_GPU_SELECTION_SUMMARY"
                printf '  Gerätebackend:        %s\n' "$(menu_backend_label)"
            else
                printf '  Vorgang:              NVIDIA-Bibliotheken im LXC vom Host installieren\n'
            fi
            printf '  Ausführungsort:       Proxmox-Host → LXC %s (%s)\n' "$TARGET_LXC_ID" "$TARGET_LXC_NAME"
            printf '  Zielversion:          exakt wie geladenes Host-Kernelmodul\n'
            printf '  Ursprungszustand:     %s (wird wiederhergestellt)\n' \
                "$(pct status "$TARGET_LXC_ID" 2>/dev/null | awk '{print $2}' || printf unbekannt)"
            ((PIN_NVIDIA_PACKAGES)) \
                && printf '  Versionsbindung:      ja (auch im LXC)\n' \
                || printf '  Versionsbindung:      nein\n'
            [[ "$CLEAN_INSTALL_SCOPE" == "full" ]] \
                && printf '  Neuinstallation:      gesamter vorhandener NVIDIA-Userspace-/CUDA-/Container-Stack\n' \
                || printf '  Neuinstallation:      nur NVIDIA-Userspace-Bibliotheken\n'
            printf '  LXC-Kernel/DKMS:      garantiert unverändert\n'
            ((FINAL_APT_AUTOREMOVE)) \
                && printf '  Abschlussbereinigung: im LXC simuliert und rollbackfähig\n' \
                || printf '  Abschlussbereinigung: im LXC übersprungen\n'
        elif [[ "$operation" == "uninstall" ]]; then
            printf '  Vorgang:              NVIDIA vollständig entfernen\n'
            printf '  Ausführungsort:       %s\n' "$(menu_mode_label)"
            if [[ "$effective_mode" == "lxc" ]]; then
                printf '  Pakete:               NVIDIA-Userspace, CUDA-Toolkit und NVIDIA Container Toolkit entfernen\n'
                printf '  Konfiguration:        nur LXC-interne NVIDIA-Container-/CDI-Konfiguration entfernen\n'
                printf '  Host-GPU-Zuweisung:   bleibt unverändert\n'
            else
                printf '  Pakete:               Treiber, CUDA-Toolkit und NVIDIA Container Toolkit entfernen\n'
                printf '  Konfiguration:        NVIDIA-Container-/CDI- und verwaltete LXC-Einträge entfernen\n'
            fi
            printf '  Nutzdaten:            Projekte, Medien, Volumes und Anwendungsdaten bleiben erhalten\n'
            [[ "$effective_mode" == "host" ]] \
                && printf '  LXC-Einträge:         alle vom Skript verwalteten Einträge entfernen\n'
            printf '  Sicherung/Rollback:   wird vor der Änderung erstellt und geprüft\n'
        elif [[ "$operation" == "repair" ]]; then
            printf '  Vorgang:              automatische Fehleranalyse und sichere Reparatur\n'
            printf '  Ausführungsort:       %s\n' "$(menu_mode_label)"
            printf '  Erkannte GPU(s):      %s\n' "$DETECTED_GPU_SUMMARY"
            printf '  Installierter Stand:  %s\n' "$DETECTED_VERSION_STATE"
            printf '  Paket-Reparatur:      beschädigte installierte Pakete ggf. exakt neu einspielen\n'
        else
            if [[ "$operation" == "dry-run" ]]; then
                printf '  Vorgang:              Dry-Run ohne Änderungen\n'
            elif [[ "$effective_mode" == "lxc" ]]; then
                printf '  Vorgang:              NVIDIA-Userspace sauber installieren/aktualisieren\n'
            else
                printf '  Vorgang:              Treiber sauber installieren/aktualisieren\n'
            fi
            printf '  Ausführungsort:       %s\n' "$(menu_mode_label)"
            printf '  Erkannte GPU(s):      %s\n' "$DETECTED_GPU_SUMMARY"
            printf '  Installierter Stand:  %s\n' "$DETECTED_VERSION_STATE"
            case "$REQUESTED_VERSION" in
                auto)          printf '  NVIDIA-Version:       automatisch (%s)\n' "$RECOMMENDED_VERSION" ;;
                610|610.43.02) printf '  NVIDIA-Version:       610.43.02\n' ;;
                595|595.71.05) printf '  NVIDIA-Version:       595.71.05\n' ;;
                *)             printf '  NVIDIA-Version:       %s\n' "$REQUESTED_VERSION" ;;
            esac
            if [[ "$effective_mode" != "lxc" ]]; then
                case "$KERNEL_FLAVOR" in
                    auto)
                        printf '  Host-Kernelmodul:     automatisch (%s)\n' \
                            "$([[ "$RECOMMENDED_KERNEL" == "open" ]] && printf 'offen' || printf 'proprietär')"
                        ;;
                    open)        printf '  Host-Kernelmodul:     offen\n' ;;
                    proprietary) printf '  Host-Kernelmodul:     proprietär\n' ;;
                esac
            else
                printf '  Host-Kernelmodul:     entfällt im LXC\n'
            fi
            ((FIX_MICROSOFT_CONFLICT)) \
                && printf '  Microsoft-Konflikt:   automatisch beheben\n' \
                || printf '  Microsoft-Konflikt:   nicht verändern\n'
            ((PIN_NVIDIA_PACKAGES)) \
                && printf '  Versionsbindung:      ja (apt-mark hold)\n' \
                || printf '  Versionsbindung:      nein\n'
            if [[ "$effective_mode" == "host" ]]; then
                [[ "$GPU_CONSUMER_POLICY" == "stop-services" ]] \
                    && printf '  GPU-Dienste:          eindeutig erkannte Dienste stoppen/wiederherstellen\n' \
                    || printf '  GPU-Dienste:          bei Belegung nur melden und abbrechen\n'
                ((INITIAL_APT_AUTOREMOVE)) \
                    && printf '  Anfangsbereinigung:   apt autoremove --purge, simuliert und rollbackfähig\n' \
                    || printf '  Anfangsbereinigung:   nein\n'
            fi
            ((FINAL_APT_AUTOREMOVE)) \
                && printf '  Abschlussbereinigung: apt autoremove --purge, simuliert und rollbackfähig\n' \
                || printf '  Abschlussbereinigung: nein\n'
            ((AUTOMATIC_REPAIR)) \
                && printf '  Fehlerbehebung:       automatische Analyse und sichere Reparatur aktiv\n' \
                || printf '  Fehlerbehebung:       nur Diagnose\n'
            if ((CONFIGURE_LXC_GPU)); then
                printf '  LXC-GPU-Freigabe:     %s (%s) ← %s\n' \
                    "$TARGET_LXC_ID" "$TARGET_LXC_NAME" "$TARGET_GPU_SELECTION_SUMMARY"
                printf '  LXC-Gerätebackend:    %s\n' "$(menu_backend_label)"
                ((INSTALL_LXC_USERSPACE_FROM_HOST)) \
                    && printf '  LXC-Userspace:        wird ebenfalls vom Host installiert\n'
            else
                printf '  LXC-GPU-Freigabe:     nein\n'
            fi
            if [[ "$effective_mode" == "lxc" ]]; then
                [[ "$CLEAN_INSTALL_SCOPE" == "full" ]] \
                    && printf '  Bereinigung:          kompletter NVIDIA-Userspace-/CUDA-/Container-Stack wird neu installiert\n' \
                    || printf '  Bereinigung:          nur NVIDIA-Userspace-Bibliotheken werden neu installiert\n'
            else
                [[ "$CLEAN_INSTALL_SCOPE" == "full" ]] \
                    && printf '  Bereinigung:          kompletter NVIDIA-/CUDA-/Container-Stack wird neu installiert\n' \
                    || printf '  Bereinigung:          nur NVIDIA-Treiberstack wird neu installiert\n'
            fi
        fi
        if [[ "$operation" == "install" || "$operation" == "lxc-complete" \
              || "$operation" == "lxc-userspace" || "$operation" == "repair" || "$operation" == "update" || "$operation" == "lxc-update" ]]; then
            printf '  Transcoding-Test:     %s\n' "$(menu_transcode_label)"
            printf '  nvtop-Monitoring:     %s\n' "$(menu_nvtop_label)"
        fi
        if [[ "$operation" == "install" || "$operation" == "lxc-complete" \
              || "$operation" == "attach-only" || "$operation" == "lxc-userspace" \
              || "$operation" == "uninstall" || "$operation" == "repair" || "$operation" == "update" || "$operation" == "lxc-update" ]]; then
            ((KEEP_SUCCESS_BACKUP)) \
                && printf '  Erfolgssicherung:     behalten\n' \
                || printf '  Erfolgssicherung:     nach vollständiger Prüfung automatisch entfernen\n'
            ((DELETE_SUCCESS_LOGS)) \
                && printf '  Erfolgslog:           nach gespeichertem Abschlussbericht automatisch entfernen\n' \
                || printf '  Erfolgslog:           behalten\n'
            printf '  Fehler-Backups:       %s Tage aufbewahren\n' "$BACKUP_RETENTION_DAYS"
        fi

        printf '\n'
        menu_section "BESTÄTIGUNG"
        if [[ "$operation" == "attach-only" ]]; then
            menu_item 1 "GPU-Freigabe starten"
        elif [[ "$operation" == "lxc-complete" || "$operation" == "lxc-userspace" ]]; then
            menu_item 1 "LXC-Verwaltung vom Host starten"
        elif [[ "$operation" == "dry-run" || "$operation" == "update-preview" ]]; then
            menu_item 1 "Dry-Run starten"
        elif ((UPDATE_ONLY)); then
            menu_item 1 "NVIDIA-Update prüfen und starten"
        elif [[ "$operation" == "uninstall" ]]; then
            if [[ "$effective_mode" == "lxc" ]]; then
                menu_note "Entfernt NVIDIA-Userspace, CUDA-/Container-Toolkit und LXC-interne Konfiguration; die GPU-Zuweisung auf dem Proxmox-Host und persönliche Nutzdaten bleiben unverändert."
            else
                menu_note "Entfernt auch CUDA-/NVIDIA-Container-Toolkit-Pakete und deren verwaltete Konfiguration; persönliche Nutzdaten bleiben erhalten."
            fi
            menu_danger_item 1 "Vollständige Entfernung starten"
        elif [[ "$operation" == "repair" ]]; then
            menu_item 1 "Fehleranalyse und sichere Reparatur starten"
        else
            menu_item 1 "Installation starten"
        fi
        if [[ "$operation" == "uninstall" ]]; then
            menu_item 2 "Zur Hauptauswahl  [Standard]"
            menu_item 0 "Skript beenden"
            action="$(menu_read 'Auswahl [2]: ')"
            action="${action:-2}"
        else
            menu_item 2 "Zur Hauptauswahl"
            menu_item 0 "Skript beenden"
            action="$(menu_read 'Auswahl [1]: ')"
            action="${action:-1}"
        fi
        case "$action" in
            1)
                ASSUME_YES=1
                return 0
                ;;
            2) continue ;;
            0|q|Q) die "Vom Benutzer abgebrochen." ;;
            *) warn "Ungültige Auswahl: $action" ;;
        esac
    done
}

# Sichert ein installiertes Paket als verifizierte DEB-Datei. Falls die exakt
# installierte Version nicht mehr in den aktuellen APT-Quellen oder im lokalen
# Paketcache liegt, wird sie aus dem installierten Zustand rekonstruiert. Das
# hierfuer benoetigte dpkg-repack wird bei Bedarf nur heruntergeladen und in
# einem temporaeren Verzeichnis ausgepackt, aber nicht installiert.
rollback_deb_matches() {
    local file="$1" package="$2" version="$3" architecture="$4"
    local expected_package actual_package actual_version actual_architecture

    [[ -s "$file" ]] || return 1
    expected_package="${package%%:*}"
    actual_package="$(dpkg-deb -f "$file" Package 2>/dev/null || true)"
    actual_version="$(dpkg-deb -f "$file" Version 2>/dev/null || true)"
    actual_architecture="$(dpkg-deb -f "$file" Architecture 2>/dev/null || true)"

    [[ "$actual_package" == "$expected_package" ]] || return 1
    debian_versions_equal "$actual_version" "$version" || return 1
    [[ "$actual_architecture" == "$architecture" ]] || return 1
}

stage_verified_rollback_deb_from_directory() {
    local directory="$1" package="$2" version="$3" architecture="$4" destination="$5"
    local file copied staged

    [[ -d "$directory" ]] || return 1
    while IFS= read -r -d '' file; do
        rollback_deb_matches "$file" "$package" "$version" "$architecture" || continue
        copied="$destination/$(basename -- "$file")"
        staged="$destination/.$(basename -- "$file").partial.$$"
        cp -a -- "$file" "$staged" || return 1
        if ! rollback_deb_matches "$staged" "$package" "$version" "$architecture"; then
            rm -f -- "$staged"
            return 1
        fi
        mv -f -- "$staged" "$copied" || {
            rm -f -- "$staged"
            return 1
        }
        if ! rollback_deb_matches "$copied" "$package" "$version" "$architecture"; then
            rm -f -- "$copied"
            return 1
        fi
        return 0
    done < <(find "$directory" -maxdepth 1 -type f -name '*.deb' -print0 2>/dev/null)
    return 1
}

stage_trusted_reinstall_package_deb() {
    local package="$1" version="$2" architecture="$3" destination="$4"
    local scratch_parent scratch

    mkdir -p "$destination" || return 1
    scratch_parent="${TMP_DIR:-${TMPDIR:-/tmp}}"
    scratch="$(mktemp -d "$scratch_parent/nvidia-clean-reinstall.XXXXXX")" || return 1
    chmod 0700 "$scratch"
    if (cd "$scratch" \
        && run_apt_get download "${package}=${version}" >download.log 2>&1) \
        && stage_verified_rollback_deb_from_directory \
            "$scratch" "$package" "$version" "$architecture" "$destination"; then
        rm -rf -- "$scratch"
        return 0
    fi
    if stage_verified_rollback_deb_from_directory /var/cache/apt/archives \
            "$package" "$version" "$architecture" "$destination"; then
        rm -rf -- "$scratch"
        return 0
    fi
    rm -rf -- "$scratch"
    return 1
}

prepare_debian_lxc_nvidia_smi_payload() {
    local package="nvidia-driver-cuda" candidate architecture payload_dir verify_root file
    local -a payloads=()

    [[ "$MODE" == "lxc" && "$DISTRO" == "debian13" ]] || return 0
    candidate="$(official_target_package_version "$package" || true)"
    [[ -n "$candidate" ]] \
        || die "Die echte nvidia-smi-Binärdatei ist für Debian 13 und Treiber $TARGET_VERSION nicht eindeutig aus dem offiziellen NVIDIA-Repository verfügbar."
    architecture="$(dpkg --print-architecture 2>/dev/null || true)"
    [[ -n "$architecture" ]] || die "Die Debian-Architektur für den nvidia-smi-Payload konnte nicht bestimmt werden."
    payload_dir="$BACKUP_DIR/lxc-smi-payload"
    mkdir -p "$payload_dir"
    stage_trusted_reinstall_package_deb "$package" "$candidate" "$architecture" "$payload_dir" \
        || die "Der echte nvidia-smi-Payload $package=$candidate konnte nicht als geprüftes Original-DEB vorgeladen werden."
    while IFS= read -r -d '' file; do
        rollback_deb_matches "$file" "$package" "$candidate" "$architecture" \
            && payloads+=("$file")
    done < <(find "$payload_dir" -maxdepth 1 -type f -name '*.deb' -print0 2>/dev/null || true)
    ((${#payloads[@]} == 1)) \
        || die "Der nvidia-smi-Payload ist nach dem Download nicht eindeutig prüfbar."

    verify_root="$(mktemp -d "$TMP_DIR/nvidia-smi-payload-check.XXXXXX")"
    dpkg-deb -x "${payloads[0]}" "$verify_root" \
        || die "Der nvidia-smi-Payload kann nicht sicher entpackt werden."
    [[ -x "$verify_root/usr/bin/nvidia-smi" ]] \
        || die "$package=$candidate enthält keine ausführbare /usr/bin/nvidia-smi-Datei."
    sha256sum "$verify_root/usr/bin/nvidia-smi" >"$BACKUP_DIR/lxc-smi-payload.sha256"
    rm -rf -- "$verify_root"

    LXC_SMI_PAYLOAD_DEB="${payloads[0]}"
    LXC_SMI_PAYLOAD_VERSION="$candidate"
    {
        printf 'Paket\tVersion\tDatei\n'
        printf '%s\t%s\t%s\n' "$package" "$candidate" "$(basename -- "$LXC_SMI_PAYLOAD_DEB")"
    } >"$BACKUP_DIR/lxc-smi-payload-source.tsv"
    refresh_backup_checksums
    ok "Echte nvidia-smi-Binärdatei für Debian 13 aus $package=$candidate vorab geprüft."
}

install_debian_lxc_nvidia_smi_payload_if_needed() {
    local extract_root metadata_tmp expected_hash actual_hash owner recorded_version recorded_hash

    [[ "$MODE" == "lxc" && "$DISTRO" == "debian13" ]] || return 0
    if command -v nvidia-smi >/dev/null 2>&1; then
        ((UPDATE_ONLY)) || return 0
        owner="$(dpkg-query -S /usr/bin/nvidia-smi 2>/dev/null || true)"
        [[ -z "$owner" ]] || return 0
        [[ -r /var/lib/nvidia-driver-setup/lxc-nvidia-smi-payload.env ]] \
            || die "Vorhandenes unpaketiertes nvidia-smi besitzt keinen Herkunftsnachweis; Update ersetzt es nicht blind."
        recorded_version="$(awk -F= '$1 == "SOURCE_VERSION" {print $2}' /var/lib/nvidia-driver-setup/lxc-nvidia-smi-payload.env)"
        recorded_hash="$(awk -F= '$1 == "PAYLOAD_SHA256" {print $2}' /var/lib/nvidia-driver-setup/lxc-nvidia-smi-payload.env)"
        actual_hash="$(sha256sum /usr/bin/nvidia-smi | awk '{print $1}')"
        [[ "$actual_hash" == "$recorded_hash" ]] || die "Verwaltetes nvidia-smi wurde nachträglich verändert; Update verweigert das Überschreiben."
        debian_versions_equal "$recorded_version" "$LXC_SMI_PAYLOAD_VERSION" && return 0
    fi
    [[ -n "$LXC_SMI_PAYLOAD_DEB" && -s "$LXC_SMI_PAYLOAD_DEB" ]] \
        || die "Das Debian-13-Paket nvidia-smi ist nur ein Übergangspaket und der vorbereitete echte Binärpayload fehlt."

    extract_root="$(mktemp -d "$TMP_DIR/nvidia-smi-payload-install.XXXXXX")"
    dpkg-deb -x "$LXC_SMI_PAYLOAD_DEB" "$extract_root" \
        || die "Der vorbereitete nvidia-smi-Payload konnte nicht entpackt werden."
    [[ -x "$extract_root/usr/bin/nvidia-smi" ]] \
        || die "Der vorbereitete Payload enthält keine ausführbare nvidia-smi-Datei."
    expected_hash="$(sha256sum "$extract_root/usr/bin/nvidia-smi" | awk '{print $1}')"
    install -D -m 0755 "$extract_root/usr/bin/nvidia-smi" /usr/bin/nvidia-smi
    actual_hash="$(sha256sum /usr/bin/nvidia-smi | awk '{print $1}')"
    [[ "$actual_hash" == "$expected_hash" ]] \
        || die "Die installierte nvidia-smi-Datei stimmt nicht mit dem geprüften offiziellen Payload überein."
    rm -rf -- "$extract_root"

    mkdir -p /var/lib/nvidia-driver-setup
    metadata_tmp="$(mktemp /var/lib/nvidia-driver-setup/.lxc-nvidia-smi-payload.XXXXXX)"
    {
        printf 'SOURCE_PACKAGE=%q\n' nvidia-driver-cuda
        printf 'SOURCE_VERSION=%q\n' "$LXC_SMI_PAYLOAD_VERSION"
        printf 'PAYLOAD_SHA256=%q\n' "$actual_hash"
        printf 'TARGET_FILE=%q\n' /usr/bin/nvidia-smi
    } >"$metadata_tmp"
    chmod 0644 "$metadata_tmp"
    mv -f -- "$metadata_tmp" /var/lib/nvidia-driver-setup/lxc-nvidia-smi-payload.env
    command -v nvidia-smi >/dev/null 2>&1 \
        || die "nvidia-smi ist trotz installiertem geprüftem Payload nicht im PATH verfügbar."
    ok "Debian-13-Übergangspaket ergänzt: echte nvidia-smi-Binärdatei aus dem offiziellen NVIDIA-Payload installiert."
}

stage_exact_installed_package_deb() {
    local package="$1" version="$2" destination="$3"
    local base architecture scratch_parent scratch repack_bin="" helper_perl5lib=""
    local helper_deb perl_dir repack_status=1
    local -a repack_args=() helper_perl_dirs=()

    base="${package%%:*}"
    architecture="$(dpkg-query -W -f='${Architecture}' "$package" 2>/dev/null || true)"
    [[ -n "$architecture" ]] || {
        warn "Architektur von $package konnte fuer die Rollback-Sicherung nicht bestimmt werden."
        return 1
    }

    mkdir -p "$destination" || return 1
    scratch_parent="${TMP_DIR:-${TMPDIR:-/tmp}}"
    [[ -d "$scratch_parent" ]] || return 1
    scratch="$(mktemp -d "$scratch_parent/nvidia-deb-backup.XXXXXX")" || return 1
    chmod 0700 "$scratch"
    mkdir -p "$scratch/apt-download" "$scratch/repack-output" "$scratch/helper-download" "$scratch/helper-root"

    # Zuerst die unveraenderte Archivdatei aus der konfigurierten Paketquelle.
    if (cd "$scratch/apt-download" \
        && run_apt_get download "${package}=${version}" >"$scratch/apt-download.log" 2>&1) \
        && stage_verified_rollback_deb_from_directory \
            "$scratch/apt-download" "$package" "$version" "$architecture" "$destination"; then
        rm -rf -- "$scratch"
        return 0
    fi

    # Danach einen eventuell noch vorhandenen lokalen APT-Cache verwenden.
    if stage_verified_rollback_deb_from_directory \
        /var/cache/apt/archives "$package" "$version" "$architecture" "$destination"; then
        rm -rf -- "$scratch"
        return 0
    fi

    warn "$package=$version ist nicht mehr als exakte Archivdatei verfuegbar; rekonstruiere das installierte Paket lokal."
    if command -v dpkg-repack >/dev/null 2>&1; then
        repack_bin="$(command -v dpkg-repack)"
    else
        log "Lade dpkg-repack samt benoetigten Abhaengigkeiten temporaer herunter (keine Installation)."
        mkdir -p "$scratch/helper-download/partial"
        # Reiner Helferdownload: eine leere, schreibgeschützte Statusansicht
        # verhindert, dass kaputte NVIDIA-Abhängigkeiten die Sicherung blockieren.
        # Es wird die gesamte Helfer-Abhängigkeitsmenge geladen und nur entpackt;
        # die echte dpkg-Datenbank und ihr Installationszustand bleiben unberührt.
        if ! run_apt_get --simulate -o Debug::NoLocking=1 \
            -o Dir::State::status=/dev/null -o Dir::Cache::pkgcache= \
            -o Dir::Cache::srcpkgcache= --no-install-recommends \
            install dpkg-repack >"$scratch/helper-simulation.log" 2>&1; then
            warn "Der temporaere dpkg-repack-Abhaengigkeitsplan konnte nicht simuliert werden."
            cat "$scratch/helper-simulation.log" >&2
            [[ -z "${BACKUP_DIR:-}" ]] || cp "$scratch/helper-simulation.log" "$BACKUP_DIR/rollback-helper-simulation-error.log"
            rm -rf -- "$scratch"
            return 1
        fi
        if ! run_apt_get --download-only -y -o Debug::NoLocking=1 \
            -o Dir::State::status=/dev/null -o Dir::Cache::pkgcache= \
            -o Dir::Cache::srcpkgcache= \
            -o Dir::Cache::archives="$scratch/helper-download/" --no-install-recommends \
            install dpkg-repack >"$scratch/helper-download.log" 2>&1; then
            warn "dpkg-repack konnte nicht temporaer aus den aktiven APT-Quellen geladen werden."
            cat "$scratch/helper-download.log" >&2
            [[ -z "${BACKUP_DIR:-}" ]] || cp "$scratch/helper-download.log" "$BACKUP_DIR/rollback-helper-download-error.log"
            rm -rf -- "$scratch"
            return 1
        fi
        while IFS= read -r -d '' helper_deb; do
            dpkg-deb -x "$helper_deb" "$scratch/helper-root" \
                >>"$scratch/helper-extract.log" 2>&1 || {
                    rm -rf -- "$scratch"
                    return 1
                }
        done < <(find "$scratch/helper-download" -maxdepth 1 -type f -name '*.deb' -print0)
        repack_bin="$scratch/helper-root/usr/bin/dpkg-repack"
        shopt -s nullglob
        for perl_dir in \
            "$scratch/helper-root/usr/share/perl5" \
            "$scratch/helper-root/usr/share/perl/"* \
            "$scratch/helper-root/usr/lib/"*/perl5/* \
            "$scratch/helper-root/usr/lib/"*/perl/*; do
            [[ -d "$perl_dir" ]] && helper_perl_dirs+=("$perl_dir")
        done
        shopt -u nullglob
        helper_perl5lib="$(join_by : "${helper_perl_dirs[@]}")"
        [[ -z "${PERL5LIB:-}" ]] || helper_perl5lib+="${helper_perl5lib:+:}$PERL5LIB"
        [[ -x "$repack_bin" ]] || {
            warn "Das temporaer geladene dpkg-repack ist unvollstaendig."
            rm -rf -- "$scratch"
            return 1
        }
    fi

    repack_args=(--arch="$architecture" --tag=none)
    if [[ -n "$helper_perl5lib" ]]; then
        (cd "$scratch/repack-output" \
            && PERL5LIB="$helper_perl5lib" "$repack_bin" "${repack_args[@]}" "$package" \
                >"$scratch/dpkg-repack.log" 2>&1) && repack_status=0
        if ((repack_status != 0)) && [[ "$package" != "$base" ]]; then
            (cd "$scratch/repack-output" \
                && PERL5LIB="$helper_perl5lib" "$repack_bin" "${repack_args[@]}" "$base" \
                    >>"$scratch/dpkg-repack.log" 2>&1) && repack_status=0
        fi
    else
        (cd "$scratch/repack-output" \
            && "$repack_bin" "${repack_args[@]}" "$package" \
                >"$scratch/dpkg-repack.log" 2>&1) && repack_status=0
        if ((repack_status != 0)) && [[ "$package" != "$base" ]]; then
            (cd "$scratch/repack-output" \
                && "$repack_bin" "${repack_args[@]}" "$base" \
                    >>"$scratch/dpkg-repack.log" 2>&1) && repack_status=0
        fi
    fi

    if ((repack_status == 0)) \
        && stage_verified_rollback_deb_from_directory \
            "$scratch/repack-output" "$package" "$version" "$architecture" "$destination"; then
        ok "Rollback-Paket lokal rekonstruiert und verifiziert: $package=$version ($architecture)"
        rm -rf -- "$scratch"
        return 0
    fi

    warn "Die lokale Rekonstruktion von $package=$version ist fehlgeschlagen oder ihre Metadaten stimmen nicht exakt."
    rm -rf -- "$scratch"
    return 1
}

update_repository_is_trusted() {
    local source="$1" package="$2"
    case "$source" in
        https://developer.download.nvidia.com/compute/cuda/repos/"$DISTRO"/x86_64[\ /]*) return 0 ;;
        https://nvidia.github.io/libnvidia-container/stable/deb/*)
            [[ "$package" =~ ^(libnvidia-container|nvidia-container-|nvidia-docker2) ]] && return 0 ;;
    esac
    if [[ "$package" =~ $NVIDIA_INDEPENDENT_OPTIONAL_REGEX ]]; then
        case "$source" in
            https://deb.debian.org/debian[\ /]*|http://deb.debian.org/debian[\ /]*|https://security.debian.org/debian-security[\ /]*|http://security.debian.org/debian-security[\ /]*|http://archive.ubuntu.com/ubuntu[\ /]*|https://archive.ubuntu.com/ubuntu[\ /]*|http://security.ubuntu.com/ubuntu[\ /]*|https://security.ubuntu.com/ubuntu[\ /]*) return 0 ;;
        esac
    fi
    return 1
}

latest_nvidia_update_version() {
    local package="$1" driver="${2:-}" exact="${3:-}" output name version source best="" item
    local -a foreign=()
    output="$(apt-cache "${BOOTSTRAP_APT_OPTIONS[@]}" -o Dir::Cache::pkgcache= \
        -o Dir::Cache::srcpkgcache= madison "$package")" || return 1
    while IFS='|' read -r name version source; do
        version="${version//[[:space:]]/}"
        source="${source#${source%%[![:space:]]*}}"
        [[ "$version" =~ ^[0-9][0-9A-Za-z.+:~_-]*$ ]] || continue
        [[ -z "$exact" ]] || debian_versions_equal "$version" "$exact" || continue
        [[ -z "$driver" || "$(normalize_driver_version "$version")" == "$driver" ]] || continue
        if ! update_repository_is_trusted "$source" "$package"; then
            foreign+=("$version"); continue
        fi
        if [[ -z "$best" ]] || dpkg --compare-versions "$version" gt "$best"; then best="$version"; fi
    done <<<"$output"
    [[ -n "$best" ]] || return 1
    for item in "${foreign[@]}"; do
        if debian_versions_equal "$best" "$item"; then
            warn "$package=$best wird auch von einer fremden Quelle angeboten; Herkunft nicht eindeutig." >&2
            return 1
        fi
    done
    printf '%s' "$best"
}

select_nvidia_update_target() {
    local candidate
    if [[ "$MODE" == lxc ]]; then
        is_valid_driver_version "${DETECTED_HOST_MODULE_VERSION:-}" \
            || die "LXC-Update: Das geladene Host-Kernelmodul ist nicht sicher bekannt."
        TARGET_VERSION="$DETECTED_HOST_MODULE_VERSION"
        if ((RESUME_REQUEST)) && [[ "$REQUESTED_VERSION" != "$TARGET_VERSION" ]]; then
            die "LXC-Update kann nicht fortgesetzt werden: Der Host entspricht nicht mehr der gesicherten Zielversion $REQUESTED_VERSION. Zuerst Rollback wählen."
        fi
        if [[ -n "$EXPECTED_HOST_VERSION" && "$EXPECTED_HOST_VERSION" != "$TARGET_VERSION" ]]; then
            die "LXC-Update: Host-Version hat sich geändert; keine Paketänderung."
        fi
        log "LXC-Update bleibt exakt beim geladenen Host-Modul $TARGET_VERSION. Für einen neueren Treiber zuerst den Host aktualisieren."
    elif ((RESUME_REQUEST)); then
        is_valid_driver_version "$REQUESTED_VERSION" || die "Dem fortgesetzten Update fehlt seine feste Zielversion."
        TARGET_VERSION="$REQUESTED_VERSION"
    else
        candidate="$(latest_nvidia_update_version "$(driver_version_probe_package "$MODE")")" \
            || die "Keine eindeutig offizielle NVIDIA-Updateversion verfügbar. Paketquellen prüfen."
        TARGET_VERSION="$(normalize_driver_version "$candidate")"
        is_valid_driver_version "$TARGET_VERSION" || die "Unlesbare NVIDIA-Updateversion: $candidate"
    fi
    [[ "$GPU_COMPATIBILITY" == modern ]] \
        || die "Für diese GPU ist kein sicher automatisch auswählbarer moderner Updatezweig bekannt."
    ((10#${TARGET_VERSION%%.*} >= 590)) || die "Der ermittelte Updatezweig wird nicht unterstützt."
    REQUESTED_VERSION="$TARGET_VERSION"
    RECOMMENDED_VERSION="$TARGET_VERSION"
}

build_nvidia_update_plan() {
    local package current status candidate mapped base suffix old_driver branch found=0
    local -a changes=()
    NVIDIA_UPDATE_SPECS=(); NVIDIA_UPDATE_REMOVALS=(); NVIDIA_UPDATE_NEEDED=0
    EXPECTED_PACKAGE_VERSIONS=()
    query_managed_nvidia_package_states full >"$BACKUP_DIR/nvidia-update-inventory.tsv"
    while IFS=$'\t' read -r package current status; do
        [[ -n "$package" ]] || continue
        case "${status:1:1}" in n|c) continue ;; esac
        dpkg_status_is_healthy_installed "$status" \
            || die "Updatebasis ist beschädigt: $package. Bitte zuerst Reparatur oder saubere Neuinstallation wählen."
        if [[ "$MODE" == lxc && "$package" =~ $LXC_FORBIDDEN_PACKAGE_REGEX ]]; then
            die "Updatebasis enthält ein unzulässiges LXC-Hostpaket: $package. Zuerst saubere LXC-Neuinstallation wählen."
        fi
        if [[ "$package" == nvidia-driver-pinning* ]]; then
            append_unique NVIDIA_UPDATE_REMOVALS "$package"
            continue
        fi
        [[ ! "$package" =~ ^(cuda-repo-|nvidia-driver-local-repo-) ]] \
            || die "Ein lokales NVIDIA-Repository ist installiert. Zuerst die Paketquellen bereinigen."
        mapped="$package"; candidate=""
        if [[ "$package" =~ $NVIDIA_DRIVER_REGEX && ! "$package" =~ $NVIDIA_INDEPENDENT_OPTIONAL_REGEX ]]; then
            found=1
            candidate="$(latest_nvidia_update_version "$mapped" "$TARGET_VERSION" || true)"
            if [[ -z "$candidate" && ! "$package" =~ $NVIDIA_INDEPENDENT_OPTIONAL_REGEX ]]; then
                base="${package%%:*}"; suffix=""
                [[ "$package" != *:* ]] || suffix=":${package##*:}"
                old_driver="$(normalize_driver_version "$current")"; branch="${old_driver%%.*}"
                if [[ "$branch" =~ ^[0-9]{3}$ && "$base" == *"-$branch"* ]]; then
                    mapped="${base/-$branch/-${TARGET_VERSION%%.*}}$suffix"
                    candidate="$(latest_nvidia_update_version "$mapped" "$TARGET_VERSION" || true)"
                    if [[ -z "$candidate" ]]; then
                        mapped="${base/-$branch/}$suffix"
                        candidate="$(latest_nvidia_update_version "$mapped" "$TARGET_VERSION" || true)"
                    fi
                fi
            fi
        fi
        if [[ -z "$candidate" ]] && { [[ ! "$package" =~ $NVIDIA_DRIVER_REGEX ]] \
             || [[ "$package" =~ $NVIDIA_INDEPENDENT_OPTIONAL_REGEX ]]; }; then
            mapped="$package"
            candidate="$(latest_nvidia_update_version "$mapped" || true)"
        fi
        [[ -n "$candidate" ]] \
            || die "Kein eindeutiges Update für $package=$current zu $TARGET_VERSION. Es wird nicht stillschweigend entfernt; nutze bei einem Paketlayoutwechsel die saubere Neuinstallation."
        if dpkg --compare-versions "$candidate" lt "$current"; then
            die "Update würde $package von $current auf $candidate zurückstufen. Dafür bewusst die Neuinstallation verwenden."
        fi
        if [[ "$mapped" != "$package" ]]; then
            append_unique NVIDIA_UPDATE_REMOVALS "$package"
        fi
        append_unique NVIDIA_UPDATE_SPECS "$mapped=$candidate"
        EXPECTED_PACKAGE_VERSIONS["$mapped"]="$candidate"
        changes+=("$package"$'\t'"$current"$'\t'"$mapped"$'\t'"$candidate")
        if [[ "$mapped" != "$package" ]] || ! debian_versions_equal "$candidate" "$current"; then NVIDIA_UPDATE_NEEDED=1; fi
    done <"$BACKUP_DIR/nvidia-update-inventory.tsv"
    ((found && ${#NVIDIA_UPDATE_SPECS[@]})) || die "Kein installierter NVIDIA-Treiberstack gefunden. Zuerst die Installation wählen."
    # Ersetzt alte Pinning-Pakete durch die eigene, vollständige Paketbindung.
    ((${#NVIDIA_UPDATE_REMOVALS[@]} == 0)) || NVIDIA_UPDATE_NEEDED=1
    COMMON_DRIVER_DEBIAN_VERSION="$(latest_nvidia_update_version "$(driver_version_probe_package "$MODE")" "$TARGET_VERSION" || true)"
    EXACT_DRIVER_PACKAGE_SPECS=("${NVIDIA_UPDATE_SPECS[@]}")
    printf '%s\n' "${changes[@]}" >"$BACKUP_DIR/nvidia-update-changes.tsv"
    save_nvidia_update_plan
}

save_nvidia_update_plan() {
    local package version
    # Erst nach vollständiger Prüfung aufrufen: ein abgebrochener Entwurf
    # darf keine bereits gehashte Rückkehr-/Fortsetzungsdatei verändern.
    : >"$BACKUP_DIR/nvidia-update-targets.tsv"
    : >"$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv"
    for package in "${!EXPECTED_PACKAGE_VERSIONS[@]}"; do
        version="${EXPECTED_PACKAGE_VERSIONS[$package]}"
        printf '%s\t%s\n' "$package" "$version" >>"$BACKUP_DIR/nvidia-update-targets.tsv"
        if [[ "$package" =~ $NVIDIA_INDEPENDENT_OPTIONAL_REGEX || ! "$package" =~ $NVIDIA_DRIVER_REGEX ]]; then
            printf '%s\t%s\n' "$package" "$version" >>"$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv"
        fi
    done
    printf '%s\n' "${NVIDIA_UPDATE_REMOVALS[@]}" | sed '/^$/d' >"$BACKUP_DIR/nvidia-update-removals.txt"
    refresh_backup_checksums
}

write_nvidia_update_preferences() {
    local destination="$1" spec package version
    : >"$destination"
    for spec in "${NVIDIA_UPDATE_SPECS[@]}"; do
        package="${spec%%=*}"; version="${spec#*=}"
        [[ "$package" =~ ^[a-z0-9][a-z0-9+.-]*(:[a-z0-9-]+)?$ \
           && "$version" =~ ^[0-9][0-9A-Za-z.+:~_-]*$ ]] || die "Ungültiger exakter Update-Pin: $spec"
        printf 'Package: %s\nPin: version %s\nPin-Priority: 1001\n\n' "$package" "$version" >>"$destination"
    done
}

canonical_nvidia_update_package() {
    if [[ "$1" == *:* ]]; then printf '%s' "$1";
    else printf '%s:%s' "$1" "$(dpkg --print-architecture)"; fi
}

nvidia_update_expected_key() {
    local identity key
    identity="$(canonical_nvidia_update_package "$1")"
    for key in "${!EXPECTED_PACKAGE_VERSIONS[@]}"; do
        if [[ "$(canonical_nvidia_update_package "$key")" == "$identity" ]]; then
            printf '%s' "$key"
            return 0
        fi
    done
    return 1
}

include_nvidia_update_dependencies() {
    local package version candidate key driver
    while IFS=$'\t' read -r package version; do
        package_is_managed_nvidia_package "$package" || continue
        [[ "$package" != nvidia-driver-pinning* ]] || die "Updateplan zieht ein konkurrierendes Pinning-Paket nach."
        key="$(nvidia_update_expected_key "$package" || true)"
        if [[ -n "$key" ]]; then
            debian_versions_equal "$version" "${EXPECTED_PACKAGE_VERSIONS[$key]}" \
                || die "APT weicht von der festen Updateversion für $package ab."
            candidate="$(latest_nvidia_update_version "$package" "" "$version" || true)"
        else
            driver=""
            if [[ "$package" =~ $NVIDIA_DRIVER_REGEX && ! "$package" =~ $NVIDIA_INDEPENDENT_OPTIONAL_REGEX ]]; then driver="$TARGET_VERSION"; fi
            candidate="$(latest_nvidia_update_version "$package" "$driver" || true)"
        fi
        [[ -n "$candidate" ]] && debian_versions_equal "$candidate" "$version" \
            || die "NVIDIA-Abhängigkeit $package=$version ist nicht eindeutig in der geprüften Zielversion verfügbar."
        if [[ -z "$key" ]]; then
            NVIDIA_UPDATE_SPECS+=("$package=$version"); EXPECTED_PACKAGE_VERSIONS["$package"]="$version"
        fi
    done < <(parse_apt_install_plan "$1")
    EXACT_DRIVER_PACKAGE_SPECS=("${NVIDIA_UPDATE_SPECS[@]}")
    save_nvidia_update_plan
}

assert_nvidia_update_plan() {
    local file="$1" approved="${2:-}" package allowed explicit version key
    assert_apt_simulation_policy "$file" install
    while IFS= read -r package; do
        explicit=0
        for allowed in "${NVIDIA_UPDATE_REMOVALS[@]}"; do
            [[ "$(canonical_nvidia_update_package "$allowed")" != "$(canonical_nvidia_update_package "$package")" ]] || explicit=1
        done
        ((explicit)) || die "Update würde ein nicht zur Ablösung vorgesehenes Paket entfernen: $package. Plan: $file"
    done < <(parse_apt_plan_packages Remv "$file")
    while IFS=$'\t' read -r package version; do
        package_is_managed_nvidia_package "$package" || continue
        key="$(nvidia_update_expected_key "$package" || true)"
        [[ -n "$key" ]] && debian_versions_equal "$version" "${EXPECTED_PACKAGE_VERSIONS[$key]}" \
            || die "APT-Plan enthält eine nicht freigegebene NVIDIA-Paketversion: $package=$version."
    done < <(parse_apt_install_plan "$file")
    if [[ "$MODE" == lxc ]]; then
        while IFS= read -r package; do
            [[ ! "$package" =~ $LXC_FORBIDDEN_PACKAGE_REGEX ]] \
                || die "Update würde ein Host-/DKMS-Paket im LXC konfigurieren: $package"
        done < <(parse_apt_plan_packages Conf "$file")
    fi
    if [[ -n "$approved" ]]; then
        [[ -r "$approved" ]] || die "Gesicherter Updateplan fehlt: $approved"
        cmp -s <(awk '$1 == "Inst" || $1 == "Conf" || $1 == "Remv" || $1 == "Purg"' "$file" | sort) \
               <(awk '$1 == "Inst" || $1 == "Conf" || $1 == "Remv" || $1 == "Purg"' "$approved" | sort) \
            || die "APT-Updateplan hat sich seit der Freigabe geändert. Keine Installation ausgeführt."
    fi
}

install_nvidia_update_packages() {
    local NVIDIA_UPDATE_ACTIVE_PLAN="${NVIDIA_UPDATE_APPROVED_PLAN:-}" package
    local -a specs=("${NVIDIA_UPDATE_SPECS[@]}")
    for package in "${NVIDIA_UPDATE_REMOVALS[@]}"; do specs+=("$package-"); done
    DEBIAN_FRONTEND=noninteractive apt_mutate \
        "${NVIDIA_UPDATE_APT_OPTIONS[@]}" install -V -y --no-install-recommends --no-download "${specs[@]}"
}

verify_nvidia_update_packages() {
    local package expected actual status key
    for package in "${!EXPECTED_PACKAGE_VERSIONS[@]}"; do
        expected="${EXPECTED_PACKAGE_VERSIONS[$package]}"
        actual="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
        status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null || true)"
        dpkg_status_is_healthy_installed "$status" && debian_versions_equal "$actual" "$expected" \
            || die "Updateprüfung fehlgeschlagen: $package=$actual ($status), erwartet $expected."
    done
    for package in "${NVIDIA_UPDATE_REMOVALS[@]}"; do
        status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null || true)"
        case "${status:1:1}" in ''|n|c) ;; *) die "Abgelöstes NVIDIA-Paket ist weiterhin aktiv: $package" ;; esac
    done
    query_managed_nvidia_package_states full >"$BACKUP_DIR/nvidia-update-inventory-after.txt"
    while IFS=$'\t' read -r package actual status; do
        case "${status:1:1}" in ''|n|c) continue ;; esac
        key="$(nvidia_update_expected_key "$package" || true)"
        [[ -n "$key" ]] && dpkg_status_is_healthy_installed "$status" \
            && debian_versions_equal "$actual" "${EXPECTED_PACKAGE_VERSIONS[$key]}" \
            || die "Unerwarteter NVIDIA-Paketstand nach Update: $package=$actual ($status)."
    done <"$BACKUP_DIR/nvidia-update-inventory-after.txt"
    run_apt_get check >"$BACKUP_DIR/update-apt-check.log" 2>&1 || die "APT ist nach dem Update inkonsistent."
    dpkg --audit >"$BACKUP_DIR/update-dpkg-audit.log" 2>&1 || die "dpkg-Prüfung nach Update fehlgeschlagen."
    [[ ! -s "$BACKUP_DIR/update-dpkg-audit.log" ]] || die "Unvollständige Pakete nach dem Update."
    ok "Alle geplanten NVIDIA-Updateversionen exakt geprüft."
}

run_nvidia_package_update() {
    local package version simulation="$BACKUP_DIR/nvidia-update-simulation.log" kernel module_version
    local -a install_args=() held=()
    remove_runfile_installation
    audit_nvidia_repository_configuration 1 || die "Update benötigt eindeutige offizielle NVIDIA-Quellen. Zuerst Quellen reparieren oder saubere Installation wählen."
    apt_mutate -o APT::Update::Error-Mode=any update
    dpkg --audit >"$BACKUP_DIR/update-dpkg-before.log" 2>&1 || die "dpkg-Prüfung vor Update fehlgeschlagen."
    [[ ! -s "$BACKUP_DIR/update-dpkg-before.log" ]] || die "Vor dem Update zuerst den beschädigten Paketstatus reparieren."
    select_nvidia_update_target
    if ((RESUME_REQUEST)); then
        load_nvidia_update_plan
        NVIDIA_UPDATE_NEEDED=0
    else
        build_nvidia_update_plan
    fi
    log "Updateziel: $TARGET_VERSION. Geplante Paketversionen:"
    cat "$BACKUP_DIR/nvidia-update-changes.tsv"
    if ((ASSUME_YES == 0)); then
        read -r -p 'Diesen Updateplan ausführen und exakt pinnen? [j/N]: ' ANSWER
        [[ "$ANSWER" =~ ^([jJ]|[jJ][aA])$ ]] || die "Update vom Benutzer abgebrochen."
    fi
    write_resume_state
    refresh_backup_checksums
    write_nvidia_update_preferences "$BACKUP_DIR/nvidia-update-preferences.pref"
    # Nur die Zielpakete übersteuern. Übrige Hauptpräferenzen und alle
    # preferences.d-Regeln bleiben in der privaten Planungsansicht wirksam.
    [[ ! -r /etc/apt/preferences ]] || cat /etc/apt/preferences >>"$BACKUP_DIR/nvidia-update-preferences.pref"
    refresh_backup_checksums
    NVIDIA_UPDATE_APT_OPTIONS=(-o "Dir::Etc::preferences=$BACKUP_DIR/nvidia-update-preferences.pref")
    install_args=("${NVIDIA_UPDATE_SPECS[@]}")
    for package in "${NVIDIA_UPDATE_REMOVALS[@]}"; do install_args+=("$package-"); done
    apt_simulate_readonly "${NVIDIA_UPDATE_APT_OPTIONS[@]}" install -V --allow-change-held-packages \
        --no-install-recommends "${install_args[@]}" >"$simulation" 2>&1 \
        || die "NVIDIA-Update ist nicht gemeinsam auflösbar. Keine Pakete entfernt. Details: $simulation"
    # Auch neu benötigte NVIDIA-Abhängigkeiten gehören zur exakten Bindung.
    include_nvidia_update_dependencies "$simulation"
    assert_nvidia_update_plan "$simulation"
    # Wiederholte Ausführung aktualisiert keine bereits aktuellen Pakete.
    if [[ -n "$(parse_apt_install_plan "$simulation")" || -n "$(parse_apt_plan_packages Remv "$simulation")" ]]; then NVIDIA_UPDATE_NEEDED=1; fi
    if ((NVIDIA_UPDATE_NEEDED)); then
        prepare_debian_lxc_nvidia_smi_payload
        extend_rollback_packages_from_simulation "$simulation"
        # Belegte Geräte vor dem Updatepaket-Download prüfen. Nicht sicher
        # zuordenbare GPU-Prozesse werden weiterhin nicht beendet.
        check_gpu_consumers
        DEBIAN_FRONTEND=noninteractive run_apt_get "${NVIDIA_UPDATE_APT_OPTIONS[@]}" install -V -y \
            --download-only --allow-change-held-packages --no-install-recommends "${install_args[@]}" \
            || die "Updatepakete konnten nicht vollständig vorgeladen werden."
        refresh_backup_checksums
        mapfile -t held < <(list_managed_nvidia_holds)
        ((${#held[@]} == 0)) || release_and_verify_package_holds "${held[@]}"
        # Die explizite Aufnahme neuer Abhängigkeiten kann die Textdarstellung
        # des Plans ändern. Daher nochmals prüfen, bevor er freigegeben wird.
        install_args=("${NVIDIA_UPDATE_SPECS[@]}")
        for package in "${NVIDIA_UPDATE_REMOVALS[@]}"; do install_args+=("$package-"); done
        apt_simulate_readonly "${NVIDIA_UPDATE_APT_OPTIONS[@]}" install -V -y --no-install-recommends \
            --no-download "${install_args[@]}" >"$BACKUP_DIR/nvidia-update-approved.log" 2>&1 \
            || die "Abschließende Update-Simulation fehlgeschlagen."
        assert_nvidia_update_plan "$BACKUP_DIR/nvidia-update-approved.log"
        cmp -s <(nvidia_update_plan_signature "$simulation") \
            <(nvidia_update_plan_signature "$BACKUP_DIR/nvidia-update-approved.log") \
            || die "Der Updateplan hat sich nach dem Vorabdownload geändert. Keine Paketinstallation ausgeführt."
        extend_rollback_packages_from_simulation "$BACKUP_DIR/nvidia-update-approved.log"
        NVIDIA_UPDATE_APPROVED_PLAN="$BACKUP_DIR/nvidia-update-approved.log"
        install_nvidia_update_packages
        # Debian 13: auch den vom Skript verwalteten Übergangspaket-Payload
        # aktualisieren; eine fremde oder paketverwaltete Binärdatei nicht ersetzen.
        install_debian_lxc_nvidia_smi_payload_if_needed
        ldconfig
        if [[ "$MODE" == host ]]; then
            kernel="$(uname -r)"
            dkms status -m nvidia -v "$TARGET_VERSION" -k "$kernel" >"$BACKUP_DIR/update-dkms.log" 2>&1 || true
            grep -q ': installed' "$BACKUP_DIR/update-dkms.log" || die "DKMS für $TARGET_VERSION/$kernel ist nicht installiert."
            module_version="$(modinfo -F version -k "$kernel" nvidia 2>/dev/null || true)"
            [[ "$module_version" == "$TARGET_VERSION" ]] || die "Installierte Moduldatei entspricht nicht dem Updateziel."
        fi
    else
        ok "Alle NVIDIA-Pakete sind bereits aktuell. Keine Paket-Neuinstallation erforderlich."
    fi
    verify_nvidia_update_packages
    begin_config_mutation
    write_nvidia_update_preferences "$BACKUP_DIR/nvidia-update-final.pref"
    refresh_backup_checksums
    install -m 0644 "$BACKUP_DIR/nvidia-update-final.pref" /etc/apt/preferences.d/00-nvidia-driver-setup-update-pin.pref
    NVIDIA_UPDATE_APT_OPTIONS=()
    PIN_NVIDIA_PACKAGES=1
    apply_nvidia_version_binding
    verify_nvidia_update_binding
    refresh_backup_checksums
}

load_nvidia_update_plan() {
    local package version
    [[ -s "$BACKUP_DIR/nvidia-update-targets.tsv" && -r "$BACKUP_DIR/nvidia-update-removals.txt" ]] \
        || die "Gesicherter Updateplan fehlt. Fortsetzen verweigert; zuerst Rollback wählen."
    NVIDIA_UPDATE_SPECS=(); EXPECTED_PACKAGE_VERSIONS=()
    while IFS=$'\t' read -r package version; do
        [[ "$package" =~ ^[a-z0-9][a-z0-9+.-]*(:[a-z0-9-]+)?$ \
            && "$version" =~ ^[0-9][0-9A-Za-z.+:~_-]*$ ]] || die "Gesicherter Updateplan enthält ungültige Paketdaten."
        NVIDIA_UPDATE_SPECS+=("$package=$version"); EXPECTED_PACKAGE_VERSIONS["$package"]="$version"
    done <"$BACKUP_DIR/nvidia-update-targets.tsv"
    mapfile -t NVIDIA_UPDATE_REMOVALS <"$BACKUP_DIR/nvidia-update-removals.txt"
    EXACT_DRIVER_PACKAGE_SPECS=("${NVIDIA_UPDATE_SPECS[@]}")
}

verify_nvidia_update_binding() {
    local package version held matched
    local -a holds=()
    mapfile -t holds < <(list_apt_holds)
    for package in "${!EXPECTED_PACKAGE_VERSIONS[@]}"; do
        version="$(apt-cache -o Dir::Cache::pkgcache= -o Dir::Cache::srcpkgcache= policy "$package" | awk '$1 == "Candidate:" {print $2}')"
        debian_versions_equal "$version" "${EXPECTED_PACKAGE_VERSIONS[$package]}" \
            || die "Eine bestehende APT-Präferenz übersteuert den neuen Pin für $package. Fremde Regeln werden nicht überschrieben."
        matched=0
        for held in "${holds[@]}"; do
            if [[ "$(canonical_nvidia_update_package "$held")" == "$(canonical_nvidia_update_package "$package")" ]]; then matched=1; break; fi
        done
        ((matched)) || die "Exakte NVIDIA-Versionsbindung unvollständig: Hold für $package fehlt."
    done
}

nvidia_update_plan_signature() {
    local event package version
    while IFS=$'\t' read -r event package version; do
        printf '%s\t%s\t%s\n' "$event" "$(canonical_nvidia_update_package "$package")" "$version"
    done < <(awk '
        $1 == "Inst" || $1 == "Conf" || $1 == "Remv" || $1 == "Purg" {
            version=""
            if (($1 == "Inst" || $1 == "Conf") && match($0, /\([^[:space:]]+/))
                version=substr($0, RSTART + 1, RLENGTH - 1)
            print $1 "\t" $2 "\t" version
        }' "$1") | sort -u
}

run_nvidia_update_dry_run() (
    # Nur kurzlebige Planungsdateien; keine Systemlogs, Paketlisten-Updates,
    # Holds, Downloads, Dienste oder persistenten Konfigurationen verändern.
    ROLLBACK_READY=0; MUTATION_STARTED=0
    PACKAGE_MUTATION_ALLOWED=0; CONFIG_MUTATION_ALLOWED=0
    BACKUP_DIR="$(mktemp -d)"
    trap 'rm -rf -- "$BACKUP_DIR"' EXIT
    trap - ERR HUP INT TERM
    refresh_backup_checksums() { :; }
    audit_nvidia_repository_configuration 1 || die "Paketquellen sind nicht eindeutig."
    select_nvidia_update_target
    build_nvidia_update_plan
    write_nvidia_update_preferences "$BACKUP_DIR/preferences"
    [[ ! -r /etc/apt/preferences ]] || cat /etc/apt/preferences >>"$BACKUP_DIR/preferences"
    local package
    local -a specs=("${NVIDIA_UPDATE_SPECS[@]}")
    for package in "${NVIDIA_UPDATE_REMOVALS[@]}"; do specs+=("$package-"); done
    log "UPDATE-VORSCHAU: vorhandener APT-Cache, kein Abruf neuer Paketlisten. Der echte Lauf ermittelt die Version erneut."
    cat "$BACKUP_DIR/nvidia-update-changes.tsv"
    apt_simulate_readonly -o "Dir::Etc::preferences=$BACKUP_DIR/preferences" install -V \
        --allow-change-held-packages --no-install-recommends "${specs[@]}" >"$BACKUP_DIR/plan.txt" 2>&1 \
        || die "Update-Simulation fehlgeschlagen; keine Systemänderungen."
    include_nvidia_update_dependencies "$BACKUP_DIR/plan.txt"
    assert_nvidia_update_plan "$BACKUP_DIR/plan.txt"
    cat "$BACKUP_DIR/plan.txt"
    ok "Update-Vorschau erfolgreich: keine Pakete, Holds oder Systemkonfigurationen verändert."
)

run_safe_autoremove_phase() {
    local phase="${1:-final}" description="${2:-am Ende der Installation}"
    local simulation="$BACKUP_DIR/${phase}-autoremove-simulation.txt"
    local manifest="$BACKUP_DIR/${phase}-autoremove-packages.txt"
    local package version status audit_output
    # Bash-Lokale gelten auch im aufgerufenen apt_mutate; nach Rückkehr
    # verfällt diese Freigabe automatisch und wird nicht global exportiert.
    local APT_AUTOREMOVE_APPROVED_PLAN=""
    local -a removals=()

    log "Simuliere apt autoremove --purge $description ..."
    apt_simulate_readonly autoremove --purge >"$simulation" \
        || die "Die apt-autoremove-Simulation $description ist fehlgeschlagen; es wurde nichts entfernt. Details: $simulation"
    mapfile -t removals < <(parse_apt_plan_packages Remv "$simulation")
    if ((${#removals[@]} == 0)); then
        : >"$manifest"
        refresh_backup_checksums
        ok "APT meldet $description keine sicher entfernbaren verwaisten Pakete."
        return 0
    fi

    printf '%s\n' "${removals[@]}" | sort -u >"$manifest"
    assert_apt_simulation_policy "$simulation" autoremove "${removals[@]}"
    if [[ "$phase" == "final" ]]; then
        for package in "${removals[@]}"; do
            if package_is_managed_nvidia_package "$package"; then
                die "Abschluss-Autoremove abgebrochen: APT würde das verwaltete NVIDIA-/CUDA-Paket $package entfernen. Details: $simulation"
            fi
        done
    fi
    for package in "${removals[@]}"; do
        status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null || true)"
        version="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
        [[ -n "$version" ]] && dpkg_status_is_healthy_installed "$status" \
            || die "Autoremove-Rollback kann den installierten Stand von $package nicht sicher bestimmen."
        if ! grep -qF "${package}"$'\t'"${version}" "$BACKUP_DIR/nvidia-package-versions.tsv"; then
            log "Sichere Autoremove-Rollback-Paket: $package=$version"
            stage_installed_package_deb "$package" "$version" \
                || die "Autoremove abgebrochen: $package=$version konnte nicht für den Rollback gesichert werden."
            printf '%s\t%s\n' "$package" "$version" >>"$BACKUP_DIR/nvidia-package-versions.tsv"
        fi
    done
    sort -u -o "$BACKUP_DIR/nvidia-package-versions.tsv" "$BACKUP_DIR/nvidia-package-versions.tsv"
    refresh_backup_checksums
    log "Führe geprüftes apt autoremove --purge $description aus: ${removals[*]}"
    APT_AUTOREMOVE_APPROVED_PLAN="$simulation"
    DEBIAN_FRONTEND=noninteractive apt_mutate autoremove --purge -y
    run_apt_get check >/dev/null \
        || die "APT meldet nach dem Autoremove einen inkonsistenten Abhängigkeitszustand."
    audit_output="$(dpkg --audit 2>/dev/null || true)"
    [[ -z "$audit_output" ]] \
        || die "dpkg meldet nach dem Autoremove unvollständige Pakete: $audit_output"
    ok "Sicheres apt autoremove --purge $description erfolgreich abgeschlossen."
}

run_initial_safe_autoremove() {
    ((INITIAL_APT_AUTOREMOVE)) || return 0
    [[ "$MODE" == "host" ]] || return 0
    run_safe_autoremove_phase initial "zu Beginn der Host-Wartung"
}

run_final_safe_autoremove() {
    ((FINAL_APT_AUTOREMOVE)) || return 0
    [[ "${TRANSACTION_ACTION:-install}" == install || "${TRANSACTION_ACTION:-install}" == update ]] || return 0
    ((ATTACH_ONLY == 0 && HOST_LXC_OPERATION == 0 && REPAIR_ONLY_REQUEST == 0)) || return 0
    run_safe_autoremove_phase final "am Ende der Installation"
}


# ------------------------------ Argumente ------------------------------------
while (($#)); do
    case "$1" in
        --version)
            [[ $# -ge 2 ]] || die "Nach --version fehlt ein Wert."
            REQUESTED_VERSION="$2"
            shift 2
            ;;
        --mode)
            [[ $# -ge 2 ]] || die "Nach --mode fehlt ein Wert."
            MODE="$2"
            shift 2
            ;;
        --kernel)
            [[ $# -ge 2 ]] || die "Nach --kernel fehlt ein Wert."
            KERNEL_FLAVOR="$2"
            shift 2
            ;;
        --fix-microsoft-conflict)
            FIX_MICROSOFT_CONFLICT=1
            shift
            ;;
        --no-microsoft-fix)
            FIX_MICROSOFT_CONFLICT=0
            shift
            ;;
        --host-version)
            [[ $# -ge 2 ]] || die "Nach --host-version fehlt ein Wert."
            EXPECTED_HOST_VERSION="$(normalize_driver_version "$2")"
            [[ -n "$EXPECTED_HOST_VERSION" ]] || die "Ungültige Host-Version: $2"
            shift 2
            ;;
        --check-only)
            CHECK_ONLY=1
            shift
            ;;
        --update)
            UPDATE_ONLY=1
            TRANSACTION_ACTION=update
            shift
            ;;
        --update-lxc)
            [[ $# -ge 2 ]] || die "Nach --update-lxc fehlt die LXC-ID."
            UPDATE_ONLY=1
            TRANSACTION_ACTION=lxc-update
            HOST_LXC_OPERATION=1
            INSTALL_LXC_USERSPACE_FROM_HOST=1
            MODE=host
            TARGET_LXC_ID="$2"
            shift 2
            ;;
        --diagnose-all)
            DIAGNOSE_ALL=1
            CHECK_ONLY=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --rollback)
            [[ $# -ge 2 ]] || die "Nach --rollback fehlt das Sicherungsverzeichnis."
            ROLLBACK_REQUEST="$2"
            shift 2
            ;;
        --resume)
            RESUME_REQUEST=1
            shift
            ;;
        --finalize-pending)
            [[ $# -ge 2 ]] || die "Nach --finalize-pending fehlt das Sicherungsverzeichnis."
            FINALIZE_PENDING_REQUEST="$2"
            shift 2
            ;;
        --uninstall)
            UNINSTALL_REQUEST=1
            TRANSACTION_ACTION="uninstall"
            shift
            ;;
        --cleanup-backups)
            CLEANUP_BACKUPS_REQUEST=1
            shift
            ;;
        --retention-days)
            [[ $# -ge 2 ]] || die "Nach --retention-days fehlt die Anzahl der Tage."
            BACKUP_RETENTION_DAYS="$2"
            shift 2
            ;;
        --delete-success-backup)
            KEEP_SUCCESS_BACKUP=0
            shift
            ;;
        --keep-success-backup)
            KEEP_SUCCESS_BACKUP=1
            shift
            ;;
        --delete-success-logs)
            DELETE_SUCCESS_LOGS=1
            shift
            ;;
        --keep-success-logs)
            DELETE_SUCCESS_LOGS=0
            shift
            ;;
        --transcode-test)
            TRANSCODE_SMOKE_TEST="yes"
            shift
            ;;
        --no-transcode-test)
            TRANSCODE_SMOKE_TEST="no"
            shift
            ;;
        --nvtop)
            [[ $# -ge 2 ]] || die "Nach --nvtop fehlt auto, install oder skip."
            NVTOP_MANAGEMENT="$2"
            shift 2
            ;;
        --stop-gpu-services)
            GPU_CONSUMER_POLICY="stop-services"
            shift
            ;;
        --no-stop-gpu-services)
            GPU_CONSUMER_POLICY="abort"
            shift
            ;;
        --initial-autoremove)
            INITIAL_APT_AUTOREMOVE=1
            shift
            ;;
        --no-initial-autoremove)
            INITIAL_APT_AUTOREMOVE=0
            shift
            ;;
        --final-autoremove)
            FINAL_APT_AUTOREMOVE=1
            shift
            ;;
        --no-final-autoremove)
            FINAL_APT_AUTOREMOVE=0
            shift
            ;;
        --auto-repair)
            AUTOMATIC_REPAIR=1
            shift
            ;;
        --no-auto-repair)
            AUTOMATIC_REPAIR=0
            shift
            ;;
        --repair-only)
            REPAIR_ONLY_REQUEST=1
            AUTOMATIC_REPAIR=1
            TRANSACTION_ACTION="repair"
            shift
            ;;
        --clean-scope)
            [[ $# -ge 2 ]] || die "Nach --clean-scope fehlt full oder driver."
            CLEAN_INSTALL_SCOPE="$2"
            shift 2
            ;;
        --machine-readable-result)
            MACHINE_READABLE_RESULT=1
            shift
            ;;
        --pin-packages)
            PIN_NVIDIA_PACKAGES=1
            PIN_CHOICE_EXPLICIT=1
            shift
            ;;
        --no-pin-packages)
            PIN_NVIDIA_PACKAGES=0
            PIN_CHOICE_EXPLICIT=1
            shift
            ;;
        --attach-lxc)
            [[ $# -ge 2 ]] || die "Nach --attach-lxc fehlt eine CTID."
            CONFIGURE_LXC_GPU=1
            TARGET_LXC_ID="$2"
            shift 2
            ;;
        --attach-only)
            [[ $# -ge 2 ]] || die "Nach --attach-only fehlt eine CTID."
            ATTACH_ONLY=1
            CONFIGURE_LXC_GPU=1
            TARGET_LXC_ID="$2"
            shift 2
            ;;
        --manage-lxc)
            [[ $# -ge 2 ]] || die "Nach --manage-lxc fehlt eine CTID."
            HOST_LXC_OPERATION=1
            CONFIGURE_LXC_GPU=1
            INSTALL_LXC_USERSPACE_FROM_HOST=1
            TARGET_LXC_ID="$2"
            MODE="host"
            TRANSACTION_ACTION="lxc-complete"
            shift 2
            ;;
        --lxc-userspace-only)
            [[ $# -ge 2 ]] || die "Nach --lxc-userspace-only fehlt eine CTID."
            HOST_LXC_OPERATION=1
            CONFIGURE_LXC_GPU=0
            INSTALL_LXC_USERSPACE_FROM_HOST=1
            TARGET_LXC_ID="$2"
            MODE="host"
            TRANSACTION_ACTION="lxc-userspace"
            shift 2
            ;;
        --install-lxc-userspace)
            INSTALL_LXC_USERSPACE_FROM_HOST=1
            shift
            ;;
        --start-stopped-lxc)
            LXC_TEMPORARY_START_ALLOWED=1
            shift
            ;;
        --restart-running-lxc)
            LXC_RESTART_RUNNING_ALLOWED=1
            shift
            ;;
        --gpu-device)
            [[ $# -ge 2 ]] || die "Nach --gpu-device fehlt ein Wert."
            TARGET_GPU_DEVICE="$2"
            [[ "$2" == "auto" ]] || TARGET_GPU_SELECTORS+=("$2")
            shift 2
            ;;
        --gpu-uuid)
            [[ $# -ge 2 ]] || die "Nach --gpu-uuid fehlt eine UUID."
            TARGET_GPU_SELECTORS+=("$2")
            shift 2
            ;;
        --gpu-pci)
            [[ $# -ge 2 ]] || die "Nach --gpu-pci fehlt eine PCI-Adresse."
            TARGET_GPU_SELECTORS+=("$2")
            shift 2
            ;;
        --all-gpus)
            TARGET_GPU_SELECTORS+=(all)
            shift
            ;;
        --device-mode)
            [[ $# -ge 2 ]] || die "Nach --device-mode fehlt ein Modus."
            LXC_DEVICE_MODE="$2"
            DEVICE_PERMISSIONS_EXPLICIT=1
            shift 2
            ;;
        --device-uid)
            [[ $# -ge 2 ]] || die "Nach --device-uid fehlt ein Wert."
            LXC_DEVICE_UID="$([[ "$2" == "inherit" ]] && printf '' || printf '%s' "$2")"
            DEVICE_PERMISSIONS_EXPLICIT=1
            shift 2
            ;;
        --device-gid)
            [[ $# -ge 2 ]] || die "Nach --device-gid fehlt ein Wert."
            LXC_DEVICE_GID="$([[ "$2" == "inherit" ]] && printf '' || printf '%s' "$2")"
            DEVICE_PERMISSIONS_EXPLICIT=1
            shift 2
            ;;
        --lxc-backend)
            [[ $# -ge 2 ]] || die "Nach --lxc-backend fehlt auto, native oder manual."
            LXC_DEVICE_BACKEND="$2"
            shift 2
            ;;
        -y|--yes)
            ASSUME_YES=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unbekannte Option: $1"
            ;;
    esac
done

command -v dpkg >/dev/null 2>&1 || die "dpkg wurde nicht gefunden."
command -v apt-get >/dev/null 2>&1 || die "apt-get wurde nicht gefunden."
[[ "$(dpkg --print-architecture)" == "amd64" ]] || die "Unterstützt wird nur amd64."
detect_distribution_profile
acquire_global_lock

if ((ORIGINAL_ARGC == 0)); then
    interactive_menu
fi

if persistent_install_log_requested; then
    [[ $EUID -eq 0 ]] \
        || die "Verändernde Aktionen und deren dauerhaftes Installationslog erfordern root."
    start_persistent_install_log \
        || die "Das dauerhafte Installationslog unter $COMPLETION_REPORT_ROOT konnte nicht sicher angelegt werden; es wurde noch nichts verändert."
fi

if [[ -n "$ROLLBACK_REQUEST" ]]; then
    ((ORIGINAL_ARGC == 0 || ORIGINAL_ARGC == 2)) \
        || die "--rollback muss allein mit genau einem Sicherungsverzeichnis verwendet werden."
    [[ $EUID -eq 0 ]] || die "Ein Rollback muss als root ausgeführt werden."
    [[ -d "$ROLLBACK_REQUEST" && -x "$ROLLBACK_REQUEST/rollback.sh" \
          && -f "$ROLLBACK_REQUEST/rollback-manifest.txt" ]] \
        || die "Ungültige NVIDIA-Sicherung: $ROLLBACK_REQUEST"
    verify_backup_checksums "$ROLLBACK_REQUEST" \
        || die "Rollback verweigert: Sicherung unvollständig oder Prüfsumme fehlerhaft."
    BACKUP_DIR="$ROLLBACK_REQUEST"
    rollback_rc=0
    if [[ -r "$ROLLBACK_REQUEST/resume.env" ]]; then
        # Nur nach erfolgreicher Prüfsummenprüfung laden. Dadurch kennt auch ein
        # später manueller Rollback die zugehörige Remote-LXC-Teiltransaktion.
        load_resume_state_file "$ROLLBACK_REQUEST/resume.env" \
            || die "Rollback verweigert: inkompatibler Fortsetzungszustand."
        BACKUP_DIR="$ROLLBACK_REQUEST"
    fi
    if [[ -z "${LXC_REMOTE_SUCCESS_BACKUP:-}" \
          && "${TARGET_LXC_ID:-}" =~ ^[0-9]+$ \
          && -r "$ROLLBACK_REQUEST/lxc-${TARGET_LXC_ID}-userspace-install.log" ]]; then
        mapfile -t RECOVERED_REMOTE_RESULTS < <(
            sed -n 's/^NVIDIA_SETUP_RESULT=//p' \
                "$ROLLBACK_REQUEST/lxc-${TARGET_LXC_ID}-userspace-install.log" | tr -d '\r'
        )
        mapfile -t RECOVERED_REMOTE_BACKUPS < <(
            sed -n 's/^NVIDIA_SETUP_BACKUP=//p' \
                "$ROLLBACK_REQUEST/lxc-${TARGET_LXC_ID}-userspace-install.log" | tr -d '\r'
        )
        if ((${#RECOVERED_REMOTE_RESULTS[@]} == 1 && ${#RECOVERED_REMOTE_BACKUPS[@]} == 1)) \
           && [[ "${RECOVERED_REMOTE_RESULTS[0]}" == "success" \
                 || "${RECOVERED_REMOTE_RESULTS[0]}" == "pending" ]] \
           && [[ "${RECOVERED_REMOTE_BACKUPS[0]}" =~ ^/opt/nvidia-backup/nvidia-[A-Za-z0-9._-]+$ ]]; then
            LXC_REMOTE_RESULT="${RECOVERED_REMOTE_RESULTS[0]}"
            LXC_REMOTE_SUCCESS_BACKUP="${RECOVERED_REMOTE_BACKUPS[0]}"
            LXC_REMOTE_BACKUP_CLEANUP_PENDING=1
            warn "LXC-Rollbackkandidat aus dem Host-Transaktionsprotokoll erkannt; er wird vor der Ausführung vollständig im LXC geprüft."
        fi
    fi
    if [[ -n "${LXC_REMOTE_SUCCESS_BACKUP:-}" ]]; then
        rollback_remote_lxc_transaction || rollback_rc=1
    fi
    "$ROLLBACK_REQUEST/rollback.sh" manual || rollback_rc=$?
    restore_runtime_state_from_backup "$ROLLBACK_REQUEST" || rollback_rc=1
    ((rollback_rc == 0)) \
        || die "Der manuelle Rollback oder die Wiederherstellung der Laufzeitzustände ist fehlgeschlagen."
    write_transaction_phase manuell-zurueckgerollt
    clear_transaction_marker
    exit 0
fi

if ((RESUME_REQUEST)); then
    ((ORIGINAL_ARGC == 0 || ORIGINAL_ARGC == 1 \
       || (ORIGINAL_ARGC == 2 && MACHINE_READABLE_RESULT))) \
        || die "--resume darf nur allein oder mit --machine-readable-result verwendet werden."
    [[ $EUID -eq 0 ]] || die "Fortsetzen erfordert root."
    [[ -n "$RESUME_SOURCE_BACKUP" ]] || load_interrupted_transaction \
        || die "Keine vollständig prüfbare unterbrochene Transaktion gefunden."
    ASSUME_YES=1
fi

if [[ -n "$FINALIZE_PENDING_REQUEST" ]]; then
    ((ORIGINAL_ARGC == 0 || ORIGINAL_ARGC == 2 \
        || (ORIGINAL_ARGC == 3 && LXC_TEMPORARY_START_ALLOWED))) \
        || die "--finalize-pending darf nur optional mit --start-stopped-lxc kombiniert werden."
    [[ $EUID -eq 0 ]] || die "Die nachgelagerte Abschlussprüfung erfordert root."
fi

if ((CLEANUP_BACKUPS_REQUEST)); then
    [[ $EUID -eq 0 ]] || die "Das Bereinigen von Sicherungen erfordert root."
    cleanup_old_backups "$BACKUP_RETENTION_DAYS"
    ok "Sicherungsbereinigung abgeschlossen (Aufbewahrung: $BACKUP_RETENTION_DAYS Tage)."
    exit 0
fi

if [[ -s "$ACTIVE_TRANSACTION_FILE" ]] && ((RESUME_REQUEST == 0)) \
   && [[ -z "$ROLLBACK_REQUEST" && -z "$FINALIZE_PENDING_REQUEST" ]] \
   && ((CHECK_ONLY == 0 && DRY_RUN == 0)); then
    die "Eine unterbrochene Transaktion ist aktiv. Nutze das Menü oder --resume/--rollback, bevor du eine neue Änderung startest."
fi

if ((CHECK_ONLY == 0 && DRY_RUN == 0)); then
    [[ $EUID -eq 0 ]] || die "Für Installation oder LXC-Konfiguration muss das Skript als root ausgeführt werden."
fi

case "$REQUESTED_VERSION" in
    auto|610|610.43.02|595|595.71.05) ;;
    *) is_valid_driver_version "$REQUESTED_VERSION" \
        || die "--version muss auto, 595, 610 oder eine vollständige Version wie 610.43.02 sein." ;;
esac

case "$MODE" in
    auto|host|lxc) ;;
    *) die "--mode muss auto, host oder lxc sein." ;;
esac

case "$KERNEL_FLAVOR" in
    auto|open|proprietary) ;;
    *) die "--kernel muss auto, open oder proprietary sein." ;;
esac

case "$LXC_DEVICE_BACKEND" in
    auto|native|manual) ;;
    *) die "--lxc-backend muss auto, native oder manual sein." ;;
esac

[[ "$BACKUP_RETENTION_DAYS" =~ ^[0-9]+$ ]] \
    || die "--retention-days muss eine nichtnegative Ganzzahl sein."

[[ -z "$EXPECTED_HOST_VERSION" ]] || is_valid_driver_version "$EXPECTED_HOST_VERSION" \
    || die "--host-version muss eine vollständige Version wie 610.43.02 sein."

case "$TRANSCODE_SMOKE_TEST" in
    auto|yes|no) ;;
    *) die "Interner Fehler: Transcoding-Testmodus muss auto, yes oder no sein." ;;
esac
case "$NVTOP_MANAGEMENT" in
    auto|install|skip) ;;
    *) die "--nvtop muss auto, install oder skip sein." ;;
esac
case "$GPU_CONSUMER_POLICY" in
    abort|stop-services) ;;
    *) die "Interner Fehler: GPU-Verbraucherrichtlinie ist ungültig." ;;
esac
case "$CLEAN_INSTALL_SCOPE" in
    full|driver) ;;
    *) die "--clean-scope muss full oder driver sein." ;;
esac
[[ "$INITIAL_APT_AUTOREMOVE" =~ ^[01]$ ]] \
    || die "Interner Fehler: Anfangs-Autoremove muss 0 oder 1 sein."
[[ "$FINAL_APT_AUTOREMOVE" =~ ^[01]$ ]] \
    || die "Interner Fehler: Abschluss-Autoremove muss 0 oder 1 sein."
[[ "$DELETE_SUCCESS_LOGS" =~ ^[01]$ ]] \
    || die "Interner Fehler: Erfolgslog-Richtlinie muss 0 oder 1 sein."
[[ "$AUTOMATIC_REPAIR" =~ ^[01]$ ]] \
    || die "Interner Fehler: automatische Reparatur muss 0 oder 1 sein."
if ((REPAIR_ONLY_REQUEST && AUTOMATIC_REPAIR == 0)); then
    die "--repair-only kann nicht mit --no-auto-repair kombiniert werden."
fi

if ((CONFIGURE_LXC_GPU == 0 && ${#TARGET_GPU_SELECTORS[@]} > 0)); then
    die "GPU-Auswahloptionen sind nur zusammen mit --attach-lxc oder --attach-only zulässig."
fi
if ((CONFIGURE_LXC_GPU == 0 && DEVICE_PERMISSIONS_EXPLICIT)); then
    die "Geräteberechtigungen sind nur zusammen mit --attach-lxc oder --attach-only zulässig."
fi

if ((CHECK_ONLY && DRY_RUN)); then
    die "--check-only/--diagnose-all und --dry-run können nicht gemeinsam verwendet werden."
fi
if ((ATTACH_ONLY && CHECK_ONLY)); then
    die "--attach-only und --check-only können nicht gemeinsam verwendet werden."
fi
if ((ATTACH_ONLY && INSTALL_LXC_USERSPACE_FROM_HOST)); then
    die "--attach-only garantiert unveränderte Pakete und darf nicht mit einer LXC-Userspace-Installation kombiniert werden."
fi
if ((UNINSTALL_REQUEST && (CHECK_ONLY || ATTACH_ONLY || DRY_RUN || RESUME_REQUEST))); then
    die "--uninstall kann nicht mit Check-, Attach-, Dry-Run- oder Resume-Modi kombiniert werden."
fi
if ((REPAIR_ONLY_REQUEST && (CHECK_ONLY || ATTACH_ONLY || DRY_RUN || UNINSTALL_REQUEST \
                             || HOST_LXC_OPERATION || CONFIGURE_LXC_GPU \
                             || INSTALL_LXC_USERSPACE_FROM_HOST || INITIAL_APT_AUTOREMOVE))); then
    die "--repair-only kann nicht mit Check-, LXC-Verwaltungs-, Dry-Run-, Deinstallations- oder Autoremove-Modi kombiniert werden."
fi

if ((UPDATE_ONLY)); then
    ((CHECK_ONLY == 0 && ATTACH_ONLY == 0 && UNINSTALL_REQUEST == 0 && REPAIR_ONLY_REQUEST == 0 \
       && CONFIGURE_LXC_GPU == 0 && INITIAL_APT_AUTOREMOVE == 0)) \
        || die "Update kann nicht mit Check, Attach, Neu-Zuweisung, Reparatur, Deinstallation oder Anfangsbereinigung kombiniert werden."
    CLEAN_INSTALL_SCOPE=full
    PIN_NVIDIA_PACKAGES=1
    if ((HOST_LXC_OPERATION)); then TRANSACTION_ACTION=lxc-update; else TRANSACTION_ACTION=update; fi
fi

if ((ATTACH_ONLY && CONFIGURE_LXC_GPU == 0)); then
    die "--attach-only benötigt eine LXC-ID."
fi
if ((INSTALL_LXC_USERSPACE_FROM_HOST)) && [[ -z "$TARGET_LXC_ID" ]]; then
    die "Für die LXC-Userspace-Installation muss ein Ziel-LXC ausgewählt werden."
fi
if ((INSTALL_LXC_USERSPACE_FROM_HOST)) && [[ "$MODE" != "host" ]]; then
    die "Die LXC-Userspace-Installation vom Host erfordert --mode host."
fi
if ((HOST_LXC_OPERATION && (CHECK_ONLY || ATTACH_ONLY || DRY_RUN || UNINSTALL_REQUEST))); then
    die "Die vollständige Host-LXC-Verwaltung kann nicht mit Check-, Attach-only-, Dry-Run- oder Deinstallationsmodi kombiniert werden."
fi
if ((LXC_TEMPORARY_START_ALLOWED || LXC_RESTART_RUNNING_ALLOWED)) \
   && ((INSTALL_LXC_USERSPACE_FROM_HOST == 0)) \
   && [[ -z "$FINALIZE_PENDING_REQUEST" ]]; then
    die "Container-Startoptionen sind nur zusammen mit einer LXC-Userspace-Installation zulässig."
fi

[[ "$LXC_DEVICE_MODE" == "inherit" || "$LXC_DEVICE_MODE" =~ ^0[0-7]{3}$ ]] \
    || die "--device-mode muss inherit oder vierstellig oktal sein, z. B. 0660."
[[ -z "$LXC_DEVICE_UID" || "$LXC_DEVICE_UID" =~ ^[0-9]+$ ]] \
    || die "--device-uid muss eine Zahl oder inherit sein."
[[ -z "$LXC_DEVICE_GID" || "$LXC_DEVICE_GID" =~ ^[0-9]+$ ]] \
    || die "--device-gid muss eine Zahl oder inherit sein."

# -------------------------- Systemerkennung ----------------------------------
if [[ "$MODE" == "auto" ]]; then
    if ((IS_PROXMOX_HOST)); then
        MODE="host"
    elif [[ "$(systemd-detect-virt --container 2>/dev/null || true)" == "lxc" ]] \
         || grep -qa 'container=lxc' /proc/1/environ 2>/dev/null; then
        MODE="lxc"
    elif [[ "$OS_ID" == "ubuntu" ]]; then
        MODE="host"
    else
        die "Rolle nicht sicher erkannt. Nutze --mode host oder --mode lxc."
    fi
fi

if ((UPDATE_ONLY)) && [[ "$MODE" == host && "$REQUESTED_VERSION" != auto ]] \
   && ((HOST_LXC_OPERATION == 0 && RESUME_REQUEST == 0)); then
    die "Host-Update ermittelt stets die neueste Version. --version weglassen oder für eine gezielte Version die Installation verwenden."
fi

if [[ "$MODE" == "host" ]]; then
    if [[ "$OS_ID" == "debian" ]] && ((IS_PROXMOX_HOST == 0)); then
        warn "Debian-Host-Modus gewählt, aber pveversion fehlt. Für einen normalen Debian-Host muss die Kernel-/Repository-Konfiguration besonders geprüft werden."
    fi
else
    if ((IS_PROXMOX_HOST)); then
        die "LXC-Modus darf nicht auf dem Proxmox-Host ausgeführt werden."
    fi
fi

if [[ "$MODE" == "lxc" ]] \
   && { [[ "$GPU_CONSUMER_POLICY" != "abort" ]] || ((INITIAL_APT_AUTOREMOVE)); }; then
    die "Automatisches Stoppen von Host-Diensten und das Anfangs-Autoremove sind nur im Host-Modus zulässig."
fi

if [[ "$MODE" != "lxc" && -n "$EXPECTED_HOST_VERSION" ]]; then
    die "--host-version ist ausschließlich im LXC-Modus zulässig."
fi

# GPU und vorhandene Version vor jeglicher Änderung prüfen. Die automatische
# Auswahl wird danach aufgelöst und nochmals auf Host/LXC-Kompatibilität geprüft.
refresh_hardware_detection "$MODE"

if ((CONFIGURE_LXC_GPU)); then
    validate_lxc_target
elif ((HOST_LXC_OPERATION)); then
    validate_lxc_container_target
fi

if ((CHECK_ONLY)); then
    printf '\n'
    log "Skriptversion:      $SCRIPT_VERSION"
    log "Distribution:       $OS_LABEL ($DISTRO)"
    log "Rolle:              $MODE"
    print_detection_summary
    if ((${#DETECTED_GPU_GENERATIONS[@]})); then
        printf '  Generation(en):      %s\n' "$(join_by ', ' "${DETECTED_GPU_GENERATIONS[@]}")"
    fi
    if ((${#DETECTED_GPU_PCI_IDS[@]})); then
        printf '  PCI-ID(s):           %s\n' "$(join_by ', ' "${DETECTED_GPU_PCI_IDS[@]}")"
    fi
    run_diagnostic_summary "$MODE"
    printf '\nEs wurden keine Pakete oder Konfigurationsdateien verändert.\n'
    ((DIAGNOSTIC_ERROR_COUNT == 0)) && exit 0
    exit 2
fi

resolve_target_selection() {
if [[ "$MODE" == "lxc" && -n "$EXPECTED_HOST_VERSION" \
      && "$DETECTED_HOST_MODULE_SOURCE" != "--host-version (nicht lokal verifiziert)" \
      && "$DETECTED_HOST_MODULE_VERSION" != "$EXPECTED_HOST_VERSION" ]]; then
    die "--host-version $EXPECTED_HOST_VERSION widerspricht der erkannten geladenen Host-Version ${DETECTED_HOST_MODULE_VERSION:-unbekannt}."
fi

case "$RECOMMENDED_VERSION" in
    legacy-580)
        die "Erkannte GPU(s): $DETECTED_GPU_SUMMARY. Maxwell/Pascal/Volta benötigen NVIDIA 580; Kepler benötigt 470. Dieses Skript installiert bewusst weder 595 noch 610 auf Legacy-GPUs."
        ;;
    unsupported-host-version)
        if [[ "$REQUESTED_VERSION" == "auto" ]]; then
            die "Der LXC sieht Host-Kernelmodul ${DETECTED_HOST_MODULE_VERSION:-unbekannt}. Installiere im LXC exakt dieselbe Version; sie wird von diesem Skript derzeit nicht angeboten."
        fi
        ;;
    host-version-required)
        die "Die geladene NVIDIA-Version des Hosts ist im LXC nicht sichtbar. Übergib die vollständige Version explizit mit --host-version, z. B. 610.43.02."
        ;;
esac

case "$REQUESTED_VERSION" in
    auto)
        is_valid_driver_version "$RECOMMENDED_VERSION" \
            || die "Für die erkannte Hardware konnte keine unterstützte automatische Zielversion bestimmt werden."
        TARGET_VERSION="$RECOMMENDED_VERSION"
        ;;
    610|610.43.02) TARGET_VERSION="610.43.02" ;;
    595|595.71.05) TARGET_VERSION="595.71.05" ;;
    *)
        TARGET_VERSION="$(normalize_driver_version "$REQUESTED_VERSION")"
        is_valid_driver_version "$TARGET_VERSION" \
            || die "Ungültige NVIDIA-Zielversion: $REQUESTED_VERSION"
        ;;
esac

if [[ "$MODE" == "lxc" && -n "$DETECTED_HOST_MODULE_VERSION" ]]; then
    if [[ "$DETECTED_HOST_MODULE_VERSION" != "$TARGET_VERSION" ]]; then
        die "Host/LXC-Mismatch verhindert: Host-Kernelmodul $DETECTED_HOST_MODULE_VERSION, ausgewählte LXC-Version $TARGET_VERSION. Beide müssen exakt gleich sein."
    fi
fi

if [[ "$MODE" == "host" ]]; then
    if [[ "$KERNEL_FLAVOR" == "auto" && "$RECOMMENDED_KERNEL" == "manual" ]]; then
        die "Die GPU-Generation ist nicht eindeutig erkannt. Wähle --kernel open nur für Turing oder neuer, sonst --kernel proprietary."
    fi
    [[ "$KERNEL_FLAVOR" == "auto" ]] && KERNEL_FLAVOR="$RECOMMENDED_KERNEL"
else
    KERNEL_FLAVOR="not-applicable"
fi

if [[ "$MODE" == "host" && "$GPU_COMPATIBILITY" == "modern" && "$KERNEL_FLAVOR" == "proprietary" ]]; then
    warn "Für Turing und neuere GPUs empfiehlt NVIDIA das offene Kernelmodul. Die manuell gewählte proprietäre Variante wird trotzdem verwendet."
fi

if [[ "$TARGET_VERSION" != "$RECOMMENDED_VERSION" ]] \
   && is_valid_driver_version "$RECOMMENDED_VERSION"; then
    warn "Manuell gewählt: $TARGET_VERSION; automatisch empfohlen wäre $RECOMMENDED_VERSION."
fi
}

print_action_summary() {
    printf '\n'
    log "Skriptversion:      $SCRIPT_VERSION"
    log "Distribution:       $OS_LABEL ($DISTRO)"
    log "Rolle:              $MODE"
    log "Erkannte GPU(s):     $DETECTED_GPU_SUMMARY"
    if ((${#DETECTED_GPU_GENERATIONS[@]})); then
        log "GPU-Generation(en): $(join_by ', ' "${DETECTED_GPU_GENERATIONS[@]}")"
    fi
    log "Installierter Stand: $DETECTED_VERSION_STATE"
    log "Empfehlung:         $RECOMMENDED_VERSION ($RECOMMENDATION_REASON)"
    log "Zielversion:        $TARGET_VERSION"
    if ((UPDATE_ONLY)); then
        log "Aktion:             NVIDIA-Paketupdate; Zielversion wird nach frischem Repository-Abgleich festgelegt"
    elif ((REPAIR_ONLY_REQUEST)); then
        log "Aktion:             sichere Reparatur ohne vollständige Paket-Neuinstallation"
    elif [[ "$CLEAN_INSTALL_SCOPE" == "full" ]]; then
        if [[ "$MODE" == "lxc" ]]; then
            log "Neuinstallation:    gesamter paketverwalteter NVIDIA-Userspace-/CUDA-/Container-Stack; Kernel/DKMS ausgeschlossen"
        else
            log "Neuinstallation:    gesamter paketverwalteter NVIDIA-/CUDA-/Container-Stack"
        fi
    else
        if [[ "$MODE" == "lxc" ]]; then
            log "Neuinstallation:    NVIDIA-Userspace-Bibliotheken; CUDA/Container bleiben installiert; Kernel/DKMS ausgeschlossen"
        else
            log "Neuinstallation:    NVIDIA-Treiber-/Userspace-Stack; CUDA/Container bleiben installiert"
        fi
    fi
    ((AUTOMATIC_REPAIR)) \
        && log "Fehlerbehebung:    automatische Analyse und sichere Reparatur aktiv" \
        || log "Fehlerbehebung:    nur Diagnose"
    log "nvtop-Monitoring:   $(menu_nvtop_label)"
    [[ "$MODE" == "host" ]] && log "Kernelmodul:         $KERNEL_FLAVOR"
    if ((CONFIGURE_LXC_GPU)); then
        log "LXC-GPU-Freigabe:  CT $TARGET_LXC_ID ($TARGET_LXC_NAME) ← $TARGET_GPU_SELECTION_SUMMARY"
    fi
}

run_dry_run() {
    local package version status candidate common_candidate="" all_exact=1 residual residual_count=0
    local package_base architecture_suffix current_driver old_major target_major mapped mapped_base
    local -a planned_packages=()
    local -a planned_exact_specs=()
    local -a planned_removals=()
    local -a auxiliary_specs=()
    local -a optional_independent_specs=()
    local -a optional_plan=()

    if ((ATTACH_ONLY)); then
        printf '\n\033[1;36mDRY-RUN – reine LXC-GPU-Freigabe ohne Änderungen.\033[0m\n'
        printf '  CT %s (%s) ← %s\n' "$TARGET_LXC_ID" "$TARGET_LXC_NAME" "$TARGET_GPU_SELECTION_SUMMARY"
        printf '  mode=%s%s%s\n' "$LXC_DEVICE_MODE" \
            "${LXC_DEVICE_UID:+,uid=$LXC_DEVICE_UID}" "${LXC_DEVICE_GID:+,gid=$LXC_DEVICE_GID}"
        printf '  Bestehende Pfade würden aktualisiert, Duplikate und frühere verwaltete GPU-Pfade entfernt.\n'
        run_diagnostic_summary "$MODE"
        printf '\nDry-Run abgeschlossen: keine Paket-, Treiber- oder Konfigurationsänderungen.\n'
        return 0
    fi

    resolve_target_selection
    build_target_package_profile
    planned_packages=("${PREFLIGHT_DRIVER_PACKAGES[@]}")
    target_major="${TARGET_VERSION%%.*}"

    # Die Vorschau muss dieselben bereits installierten optionalen Komponenten
    # berücksichtigen wie die echte Transaktion. Sie bleibt dabei strikt
    # schreibgeschützt: Es werden weder DEBs heruntergeladen noch Dateien
    # angelegt. Unklare Abbildungen werden als Blocker gemeldet.
    while IFS=$'\t' read -r package version status; do
        dpkg_status_is_healthy_installed "$status" || continue
        if [[ ! "$package" =~ $NVIDIA_DRIVER_REGEX \
              && ! "$package" =~ $NVIDIA_REPOSITORY_PACKAGE_REGEX \
              && "$package" != nvidia-driver-pinning* ]]; then
            continue
        fi
        if [[ "$package" == nvidia-driver-pinning* \
              || "$package" =~ $NVIDIA_REPOSITORY_PACKAGE_REGEX ]]; then
            optional_plan+=("$package=$version -> Repository-Bootstrap wird ersetzt")
            continue
        fi
        if package_profile_contains "$package" "${planned_packages[@]}"; then
            optional_plan+=("$package=$version -> bereits im Zielprofil")
            continue
        fi
        if [[ "$MODE" == "lxc" && "$package" =~ $LXC_FORBIDDEN_PACKAGE_REGEX ]]; then
            optional_plan+=("$package=$version -> im LXC absichtlich entfernt (Kernel/DKMS/Host-Hilfsprogramm verboten)")
            continue
        fi
        if [[ "$MODE" == "host" \
              && "$package" =~ ^((linux-(modules|objects|signatures)-nvidia)([-:].*)?|nvidia-(dkms|kernel|open)([-:].*)?)$ ]]; then
            optional_plan+=("$package=$version -> durch das gewählte Host-Kernelprofil ersetzt")
            continue
        fi
        candidate="$(official_target_package_version "$package" || true)"
        if [[ -n "$candidate" ]]; then
            append_unique planned_packages "$package"
            optional_plan+=("$package=$version -> $package=$candidate")
            continue
        fi

        if [[ "$package" =~ $NVIDIA_INDEPENDENT_OPTIONAL_REGEX ]]; then
            optional_independent_specs+=("${package}=${version}")
            optional_plan+=("$package=$version -> eigenes Versionsschema; frisch aus Original-DEB installieren")
            continue
        fi

        package_base="${package%%:*}"
        architecture_suffix=""
        [[ "$package" != *:* ]] || architecture_suffix=":${package##*:}"
        current_driver="$(normalize_driver_version "$version")"
        old_major="${current_driver%%.*}"
        mapped_base="$package_base"
        if [[ "$old_major" =~ ^[0-9]{3}$ && "$package_base" == *"-${old_major}"* ]]; then
            mapped_base="${package_base/-${old_major}/-${target_major}}"
        fi
        mapped="${mapped_base}${architecture_suffix}"
        if [[ "$mapped" != "$package" ]]; then
            candidate="$(official_target_package_version "$mapped" || true)"
            if [[ -n "$candidate" ]]; then
                append_unique planned_packages "$mapped"
                optional_plan+=("$package=$version -> $mapped=$candidate")
                continue
            fi
        fi

        if [[ "$CLEAN_INSTALL_SCOPE" == "full" ]]; then
            optional_plan+=("$package=$version -> veraltete Komponente wird kontrolliert entfernt")
        else
            optional_plan+=("$package=$version -> BLOCKER: keine eindeutige Zielabbildung")
            warn "Zusätzliche NVIDIA-Komponente $package=$version kann nicht eindeutig auf Treiber $TARGET_VERSION abgebildet werden. Ohne vollständige Neuinstallation würde der echte Lauf vor dem Purge abbrechen."
            all_exact=0
        fi
    done < <(dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' 2>/dev/null || true)

    print_action_summary
    printf '\n\033[1;36mDRY-RUN – es werden keine Dateien oder Pakete verändert.\033[0m\n'
    audit_nvidia_repository_configuration || warn "Gemischte NVIDIA-Quellen müssten vor einer Installation bereinigt werden."
    if [[ "$CLEAN_INSTALL_SCOPE" == "full" ]]; then
        mapfile -t planned_removals < <(
            dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null \
                | awk '$2 !~ /^un/ {print $1}' \
                | grep -E "$NVIDIA_DRIVER_REGEX|$NVIDIA_AUXILIARY_REGEX|^(cuda-repo-|nvidia-driver-local-repo-)" \
                | sort -u || true
        )
        while IFS=$'\t' read -r package version status; do
            if dpkg_status_is_healthy_installed "$status" \
               && [[ "$package" =~ $NVIDIA_AUXILIARY_REGEX \
                     && ! "$package" =~ $NVIDIA_DRIVER_REGEX ]]; then
                auxiliary_specs+=("${package}=${version}")
            fi
        done < <(dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' 2>/dev/null || true)
    else
        mapfile -t planned_removals < <(
            dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null \
                | awk '$2 !~ /^un/ {print $1}' \
                | grep -E "$NVIDIA_DRIVER_REGEX|^(cuda-repo-|nvidia-driver-local-repo-)" \
                | sort -u || true
        )
    fi
    if ((${#planned_removals[@]})); then
        printf '  Geplante NVIDIA-Bereinigung: %s\n' "${planned_removals[*]}"
        if apt_simulate_readonly purge "${planned_removals[@]}" >/dev/null 2>&1; then
            ok "APT-Bereinigungssimulation erfolgreich."
        else
            warn "APT-Bereinigungssimulation fehlgeschlagen; es wurde nichts verändert."
        fi
    else
        printf '  Geplante NVIDIA-Bereinigung: kein vorhandener Treiberstack\n'
    fi
    while IFS= read -r -d '' residual; do
        residual_count=$((residual_count + 1))
    done < <(collect_unowned_legacy_nvidia_residuals)
    printf '  Unverwaltete NVIDIA-Altdateien: %s würden gesichert und entfernt.\n' "$residual_count"
    if [[ "$CLEAN_INSTALL_SCOPE" == "full" ]]; then
        printf '  Zusatzstack: %s CUDA-/Container-Pakete würden exakt gesichert, entfernt und neu installiert.\n' "${#auxiliary_specs[@]}"
    else
        printf '  Bewusst erhalten: CUDA-Toolkit, libnvidia-container und aktive LXC-Gerätezuweisungen.\n'
    fi
    printf '  Repository-Plan: NVIDIA-Local-/Netzwerk-Duplikate entfernen und ausschließlich das offizielle Netzwerk-Repository verwenden.\n'

    if [[ "$MODE" == "host" ]]; then
        printf '  Host-Pakete: %s\n' "${planned_packages[*]}"
        printf '  Kernel/DKMS: wird ausschließlich auf dem Host geplant.\n'
    else
        printf '  LXC-Userspace-Pakete: %s\n' "${planned_packages[*]}"
        printf '  Kernel/DKMS: im LXC ausdrücklich ausgeschlossen.\n'
    fi

    if ((${#optional_plan[@]})); then
        printf '  Zusätzliche NVIDIA-Komponenten:\n'
        printf '    %s\n' "${optional_plan[@]}"
    fi

    printf '\nAPT-Kandidaten:\n'
    for package in "${planned_packages[@]}"; do
        candidate="$(official_target_package_version "$package" || true)"
        printf '  %-28s %s\n' "$package" "${candidate:-nicht verfügbar}"
        if [[ -z "$candidate" ]]; then
            warn "$package: Zielversion $TARGET_VERSION ist nicht eindeutig aus der offiziellen NVIDIA-Quelle verfügbar."
            all_exact=0
        else
            planned_exact_specs+=("${package}=${candidate}")
        fi
        if [[ -z "$common_candidate" ]]; then
            common_candidate="$candidate"
        elif ! debian_versions_equal "$candidate" "$common_candidate"; then
            warn "$package: vollständige DEB-Version $candidate weicht von $common_candidate ab."
            all_exact=0
        fi
    done
    ((all_exact)) \
        && ok "Alle direkten NVIDIA-Zielpakete sind in exakt derselben DEB-Version $common_candidate verfügbar."
    if apt_simulate_readonly install -V --no-install-recommends \
            "${planned_exact_specs[@]}" "${optional_independent_specs[@]}" >/dev/null 2>&1; then
        ok "APT-Installationssimulation erfolgreich."
    else
        warn "APT kann den Installationsplan mit den aktuell eingerichteten Quellen nicht vollständig simulieren."
    fi
    if ((${#auxiliary_specs[@]} || ${#optional_independent_specs[@]})); then
        if apt_simulate_readonly install -V --reinstall --allow-downgrades \
                --no-install-recommends "${auxiliary_specs[@]}" \
                "${optional_independent_specs[@]}" >/dev/null 2>&1; then
            ok "Exakte optionale NVIDIA-/CUDA-/Container-Zusatzpakete sind für die Neuinstallation verfügbar."
        else
            warn "Mindestens ein optionales NVIDIA-/CUDA-/Container-Zusatzpaket ist nicht exakt wieder installierbar. Der echte Lauf würde vor dem Purge abbrechen."
        fi
    fi

    if ((CONFIGURE_LXC_GPU)); then
        printf '\nGeplante LXC-Gerätefreigabe:\n'
        printf '  CT %s (%s) ← %s\n' "$TARGET_LXC_ID" "$TARGET_LXC_NAME" "$TARGET_GPU_SELECTION_SUMMARY"
        printf '  mode=%s%s%s\n' "$LXC_DEVICE_MODE" \
            "${LXC_DEVICE_UID:+,uid=$LXC_DEVICE_UID}" "${LXC_DEVICE_GID:+,gid=$LXC_DEVICE_GID}"
        printf '  Backend: %s (native Proxmox-Zuweisung wird bei auto bevorzugt)\n' "$LXC_DEVICE_BACKEND"
        printf '  Bestehende Pfade werden aktualisiert; doppelte verwaltete devN-Einträge würden entfernt.\n'
    fi
    if ((INSTALL_LXC_USERSPACE_FROM_HOST)); then
        printf '\nGeplante Host-gesteuerte LXC-Installation:\n'
        printf '  Das Skript würde über pct in LXC %s (%s) ausgeführt.\n' "$TARGET_LXC_ID" "$TARGET_LXC_NAME"
        printf '  Der LXC erhielte nur exakt passende Userspace-Bibliotheken; Kernel und DKMS blieben ausgeschlossen.\n'
        printf '  Ein gestoppter LXC würde im Dry-Run nicht gestartet und ein laufender nicht neu gestartet.\n'
    fi
    if ((FINAL_APT_AUTOREMOVE)); then
        printf '\nGeplante Abschlussbereinigung:\n'
        if apt_simulate_readonly autoremove --purge >/dev/null 2>&1; then
            ok "APT-Abschluss-Autoremove lässt sich ohne Änderungen simulieren."
        else
            warn "APT kann das Abschluss-Autoremove derzeit nicht simulieren; der echte Lauf würde vor jeder Entfernung sicher abbrechen."
        fi
    fi
    run_diagnostic_summary "$MODE"
    printf '\nDry-Run abgeschlossen: keine Paket-, Treiber- oder Konfigurationsänderungen.\n'
}

select_repair_target_baseline() {
    ((REPAIR_ONLY_REQUEST)) && [[ "$REQUESTED_VERSION" == "auto" ]] || return 0
    if [[ "$MODE" == "lxc" ]]; then
        if is_valid_driver_version "${EXPECTED_HOST_VERSION:-}"; then
            REQUESTED_VERSION="$EXPECTED_HOST_VERSION"
        elif is_valid_driver_version "${DETECTED_HOST_MODULE_VERSION:-}"; then
            REQUESTED_VERSION="$DETECTED_HOST_MODULE_VERSION"
        else
            die "Für die LXC-Reparatur ist keine sicher erkannte Host-Kernelmodulversion verfügbar."
        fi
        log "LXC-Reparatur richtet sich zwingend nach dem Host-Kernelmodul $REQUESTED_VERSION."
        return 0
    fi
    [[ "${DETECTED_VERSION_STATE:-}" != Mismatch:\ mehrere\ installierte* ]] \
        || die "Mehrere installierte NVIDIA-Treiberstände können nicht als sichere Reparaturbasis verwendet werden. Wähle die saubere Neuinstallation."
    if is_valid_driver_version "${DETECTED_PACKAGE_VERSION:-}"; then
        REQUESTED_VERSION="$DETECTED_PACKAGE_VERSION"
    elif is_valid_driver_version "${DETECTED_INSTALLED_MODULE_VERSION:-}"; then
        REQUESTED_VERSION="$DETECTED_INSTALLED_MODULE_VERSION"
    elif is_valid_driver_version "${DETECTED_HOST_MODULE_VERSION:-}"; then
        REQUESTED_VERSION="$DETECTED_HOST_MODULE_VERSION"
    else
        die "Für die Reparatur wurde kein kohärenter installierter NVIDIA-Basisstand erkannt. Nutze die saubere Neuinstallation."
    fi
    log "Reparatur bleibt bewusst auf dem installierten Stand $REQUESTED_VERSION; es findet kein Treiberupgrade statt."
}

run_driver_installation() {
select_repair_target_baseline
resolve_target_selection
build_target_package_profile
print_action_summary
preflight_direct_lxc_runtime_devices
PACKAGE_MUTATION_ALLOWED=1
CONFIG_MUTATION_ALLOWED=1

if ((ASSUME_YES == 0)); then
    if ((UPDATE_ONLY)); then
        printf '\nDas Skript prüft neue NVIDIA-Paketversionen und aktualisiert den vorhandenen Stack ohne pauschale Deinstallation.\n'
    elif ((REPAIR_ONLY_REQUEST)); then
        printf '\nDas Skript sichert den Zustand und versucht ausschließlich sichere APT-/dpkg-/DKMS-/Laufzeitreparaturen.\n'
        printf 'Eine vollständige NVIDIA-Paket-Neuinstallation findet dabei nicht statt.\n'
    else
        printf '\nDas Skript entfernt den vorhandenen NVIDIA-Treiberstack vollständig und installiert ihn neu.\n'
    fi
    read -r -p "Fortfahren? [j/N]: " ANSWER
    [[ "$ANSWER" =~ ^([jJ]|[jJ][aA])$ ]] || die "Vom Benutzer abgebrochen."
fi

# -------------------------- Sperren und Sicherung -----------------------------
check_package_manager_lock() {
    local lock
    local busy=0

    for lock in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock; do
        [[ -e "$lock" ]] || continue
        if command -v fuser >/dev/null 2>&1 && fuser "$lock" >/dev/null 2>&1; then
            warn "Paketverwaltung ist aktiv: $lock"
            busy=1
        fi
    done

    ((busy == 0)) || die "Beende zuerst laufende apt/dpkg-Prozesse und starte das Skript erneut."
}

stage_installed_package_deb() {
    stage_exact_installed_package_deb "$1" "$2" "$BACKUP_DIR/rollback-debs"
}

generate_rollback_script() {
    {
        printf '%s\n' '#!/usr/bin/env bash' 'set -uo pipefail' "IFS=\$'\\n\\t'"
        printf 'BACKUP_ROOT=%q\n' "$BACKUP_DIR"
        printf 'NVIDIA_REGEX=%q\n' "$NVIDIA_DRIVER_REGEX"
        printf 'NVIDIA_AUX_REGEX=%q\n' "$NVIDIA_AUXILIARY_REGEX"
        printf 'ROLLBACK_COVERAGE=%q\n' "$ROLLBACK_COVERAGE"
        printf 'ROLLBACK_ROLE=%q\n' "$MODE"
        printf 'ROLLBACK_LXC_FORBIDDEN_REGEX=%q\n' "$LXC_FORBIDDEN_PACKAGE_REGEX"
        declare -f rollback_package_allowed rollback_role_plan_allowed rollback_removal_plan_allowed
        cat <<'EOF_ROLLBACK'
mode="${1:-manual}"
rc=0
printf '[rollback] Modus: %s\n' "$mode"
[[ $EUID -eq 0 ]] || { printf '[rollback] root erforderlich.\n' >&2; exit 1; }
[[ -s "$BACKUP_ROOT/backup-checksums.sha256" ]] \
    || { printf '[rollback] Prüfsummenmanifest fehlt.\n' >&2; exit 2; }
(cd "$BACKUP_ROOT" && sha256sum -c --quiet backup-checksums.sha256) \
    || { printf '[rollback] Sicherung ist unvollständig oder beschädigt.\n' >&2; exit 2; }
shopt -s nullglob
for deb in "$BACKUP_ROOT"/rollback-debs/*.deb; do
    relative=".${deb#"$BACKUP_ROOT"}"
    awk -v expected="$relative" '$2 == expected { found = 1 } END { exit !found }' \
        "$BACKUP_ROOT/backup-checksums.sha256" \
        || { printf '[rollback] Nicht manifestierte Paketdatei: %s\n' "$deb" >&2; exit 2; }
done
shopt -u nullglob

rollback_plan_has_critical_removal() {
    awk '$1 == "Remv" || $1 == "Purg" {package=$2; sub(/:.*/, "", package); print package}' "$1" \
        | grep -Eq '^(proxmox-ve|pve-manager|pve-container|proxmox-default-kernel|proxmox-kernel-helper|proxmox-kernel-|pve-kernel-|proxmox-headers-|pve-headers-|linux-image-|linux-headers-|systemd|systemd-sysv|init|openssh-server|apt|dpkg|fileflows)'
}

while IFS=$'\t' read -r existed path; do
    [[ -n "$path" ]] || continue
    case "$path" in
        /etc/apt/sources.list|/etc/apt/sources.list.d|/etc/apt/preferences.d|/etc/modprobe.d|\
        /usr/share/keyrings/cuda-archive-keyring.gpg|/var/lib/extrepo/keys/nvidia-cuda.asc|\
        /etc/apt/keyrings/nvidia-cuda.asc|/etc/apt/keyrings/cuda-archive-keyring.gpg|\
        /usr/share/keyrings/nvidia-cuda-keyring.gpg|\
        /etc/modules-load.d/nvidia-lxc.conf|/etc/nvidia-container-runtime|\
        /etc/cdi/nvidia.yaml|/etc/pve/lxc/[0-9]*.conf|\
        /usr/local/sbin/nvidia-lxc-device-sync-[0-9]*.sh|\
        /etc/systemd/system/nvidia-lxc-device-sync-[0-9]*.service|\
        /run/systemd/system/nvidia-lxc-device-sync-[0-9]*.service|\
        /var/lib/nvidia-lxc-device-sync/[0-9]*.devices|\
        /usr/bin/nvidia-smi|/var/lib/nvidia-driver-setup/lxc-nvidia-smi-payload.env)
            rm -rf -- "$path" || rc=1
            ;;
        *)
            printf '[rollback] Unsicherer Pfad im Manifest: %s\n' "$path" >&2
            rc=1
            ;;
    esac
done <"$BACKUP_ROOT/config-paths.tsv"
tar -C / -xpf "$BACKUP_ROOT/config-snapshot.tar" || rc=1

# Die ursprünglichen Quellen können schon vor der Installation widersprüchlich
# gewesen sein. Paket-Rollback mit geprüfter Ansicht, Originaldateien behalten.
rollback_apt_options=()
if [[ -f "$BACKUP_ROOT/apt-bootstrap/ready" ]]; then
    rollback_apt_options=(
        -o "Dir::Etc::sourcelist=$BACKUP_ROOT/apt-bootstrap/sources.list"
        -o "Dir::Etc::sourceparts=$BACKUP_ROOT/apt-bootstrap/sources.list.d"
    )
    if [[ -f "$BACKUP_ROOT/apt-bootstrap/apt.conf" ]]; then
        export APT_CONFIG="$BACKUP_ROOT/apt-bootstrap/apt.conf"
    fi
fi
if command -v apt-mark >/dev/null 2>&1; then
    mapfile -t current_holds < <(apt-mark "${rollback_apt_options[@]}" showhold 2>/dev/null \
        | grep -E "$NVIDIA_REGEX|$NVIDIA_AUX_REGEX" || true)
    ((${#current_holds[@]})) && apt-mark "${rollback_apt_options[@]}" unhold "${current_holds[@]}" >/dev/null 2>&1 || true
fi

mapfile -t baseline_names < <(awk -F'\t' '{print $1}' "$BACKUP_ROOT/packages-before.txt")
mapfile -t planned_names < <(sed '/^$/d' "$BACKUP_ROOT/packages-planned-by-transaction.txt" 2>/dev/null || true)
mapfile -t current_names < <(
    dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null \
        | awk 'substr($2, 2, 1) != "n" {print $1}' | sort -u || true
)
extras=()
for package in "${current_names[@]:-}"; do
    if ! rollback_package_allowed "$package"; then
        extras+=("$package")
        ROLLBACK_COVERAGE="normalized-lxc"
        continue
    fi
    found=0
    for baseline in "${baseline_names[@]:-}"; do
        [[ "$package" == "$baseline" ]] && { found=1; break; }
    done
    ((found)) && continue
    package_base="${package%%:*}"
    planned_match=0
    for planned in "${planned_names[@]:-}"; do
        planned_base="${planned%%:*}"
        if [[ "$package" == "$planned" || "$package_base" == "$planned_base" ]]; then
            planned_match=1
            break
        fi
    done
    if ((planned_match)); then
        extras+=("$package")
    else
        printf '[rollback] Bewahre spaeter unabhaengig installiertes Paket: %s\n' "$package"
    fi
done
if ((${#extras[@]})); then
    if DEBIAN_FRONTEND=noninteractive apt-get "${rollback_apt_options[@]}" -s purge "${extras[@]}" \
        >"$BACKUP_ROOT/rollback-purge-simulation.log"; then
        if rollback_plan_has_critical_removal "$BACKUP_ROOT/rollback-purge-simulation.log" \
           || ! rollback_role_plan_allowed "$BACKUP_ROOT/rollback-purge-simulation.log" \
           || ! rollback_removal_plan_allowed "$BACKUP_ROOT/rollback-purge-simulation.log" "${extras[@]}"; then
            printf '[rollback] Unsicherer Purge-Plan erkannt; keine Paketentfernung.\n' >&2
            rc=1
        else
            DEBIAN_FRONTEND=noninteractive apt-get "${rollback_apt_options[@]}" purge -y "${extras[@]}" || rc=1
        fi
    else
        printf '[rollback] Purge-Simulation fehlgeschlagen; keine Pakete entfernt.\n' >&2
        rc=1
    fi
fi

shopt -s nullglob
debs=()
: >"$BACKUP_ROOT/rollback-role-excluded.tsv"
for deb in "$BACKUP_ROOT"/rollback-debs/*.deb; do
    package="$(dpkg-deb -f "$deb" Package)" || { rc=1; continue; }
    if rollback_package_allowed "$package"; then
        debs+=("$deb")
    else
        printf '%s\t%s\n' "$package" "$deb" >>"$BACKUP_ROOT/rollback-role-excluded.tsv"
        ROLLBACK_COVERAGE="normalized-lxc"
        printf '[rollback] Host-Paket bleibt im LXC entfernt: %s\n' "$package"
    fi
done
shopt -u nullglob
if ((${#debs[@]})); then
    if DEBIAN_FRONTEND=noninteractive apt-get "${rollback_apt_options[@]}" -s install --allow-downgrades "${debs[@]}" \
        >"$BACKUP_ROOT/rollback-install-simulation.log"; then
        if rollback_plan_has_critical_removal "$BACKUP_ROOT/rollback-install-simulation.log" \
           || ! rollback_role_plan_allowed "$BACKUP_ROOT/rollback-install-simulation.log" \
           || ! rollback_removal_plan_allowed "$BACKUP_ROOT/rollback-install-simulation.log"; then
            printf '[rollback] Unsicherer Installationsplan erkannt; keine Paketinstallation.\n' >&2
            rc=1
        else
            DEBIAN_FRONTEND=noninteractive apt-get "${rollback_apt_options[@]}" install -y --allow-downgrades \
                --allow-change-held-packages "${debs[@]}" || rc=1
        fi
    else
        printf '[rollback] Installationssimulation fehlgeschlagen; keine Pakete installiert.\n' >&2
        rc=1
    fi
fi

if [[ -s "$BACKUP_ROOT/legacy-residuals.list0" \
      && -f "$BACKUP_ROOT/legacy-residuals.tar" ]]; then
    legacy_paths_safe=1
    while IFS= read -r -d '' path; do
        case "$path" in
            /etc/nvidia|/etc/nvidia/*|/var/lib/nvidia|/var/lib/nvidia/*|\
            /var/cache/nvidia|/var/cache/nvidia/*|\
            /run/nvidia|/run/nvidia/*|/run/nvidia-persistenced|/run/nvidia-persistenced/*|\
            /usr/local/nvidia|/usr/local/nvidia/*|/usr/lib/nvidia|/usr/lib/nvidia/*|\
            /usr/lib/x86_64-linux-gnu/nvidia|/usr/lib/x86_64-linux-gnu/nvidia/*|\
            /usr/share/nvidia|/usr/share/nvidia/*|/var/lib/dkms/nvidia*|/usr/src/nvidia-*|\
            /etc/modprobe.d/*nvidia*|/etc/modprobe.d/blacklist-nouveau.conf|\
            /etc/ld.so.conf.d/*nvidia*|/etc/OpenCL/vendors/*nvidia*|\
            /etc/vulkan/icd.d/*nvidia*|/etc/vulkan/implicit_layer.d/*nvidia*|\
            /usr/share/vulkan/icd.d/*nvidia*|/usr/share/vulkan/implicit_layer.d/*nvidia*|\
            /usr/share/glvnd/egl_vendor.d/*nvidia*|/etc/X11/xorg.conf|\
            /etc/X11/xorg.conf.d/*nvidia*|/etc/udev/rules.d/*nvidia*|\
            /etc/systemd/system/nvidia*.service|/etc/systemd/system/*/nvidia*.service|\
            /usr/lib/systemd/system/nvidia*.service|/lib/systemd/system/nvidia*.service|\
            /usr/local/lib/libnvidia*|/usr/local/lib/libcuda*|/usr/local/lib/libnvcuvid*|\
            /usr/local/lib64/libnvidia*|/usr/local/lib64/libcuda*|/usr/local/lib64/libnvcuvid*|\
            /usr/lib/x86_64-linux-gnu/libnvidia*|/usr/lib/x86_64-linux-gnu/libcuda*|\
            /usr/lib/x86_64-linux-gnu/libnvcuvid*|/lib/x86_64-linux-gnu/libnvidia*|\
            /lib/x86_64-linux-gnu/libcuda*|/lib/x86_64-linux-gnu/libnvcuvid*|\
            /usr/local/bin/nvidia-smi|/usr/local/bin/nvidia-modprobe|\
            /usr/local/bin/nvidia-settings|/usr/local/bin/nvidia-xconfig|\
            /usr/local/bin/nvidia-persistenced|/usr/local/bin/nvidia-uninstall|\
            /usr/bin/nvidia-smi|/usr/bin/nvidia-uninstall|\
            /var/lib/nvidia-driver-setup/lxc-nvidia-smi-payload.env|/var/log/nvidia-installer.log|\
            /var/log/nvidia-uninstall.log) ;;
            *)
                printf '[rollback] Unsicherer NVIDIA-Restpfad im Archiv: %s\n' "$path" >&2
                legacy_paths_safe=0
                ;;
        esac
    done <"$BACKUP_ROOT/legacy-residuals.list0"
    if ((legacy_paths_safe)); then
        tar -C / -xpf "$BACKUP_ROOT/legacy-residuals.tar" || rc=1
    else
        rc=1
    fi
fi

while IFS=$'\t' read -r package expected; do
    [[ -n "$package" ]] || continue
    rollback_package_allowed "$package" || continue
    actual="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
    status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null || true)"
    if ! dpkg --compare-versions "${actual:-0}" eq "$expected" \
       || [[ ${#status} -lt 2 || "${status:1:1}" != "i" || "${status:2:1}" == "R" ]]; then
        printf '[rollback] Paketfehler %s: Version=%s Status=%s, erwartet=%s/ii\n' \
            "$package" "${actual:-fehlt}" "${status:-fehlt}" "$expected" >&2
        rc=1
    fi
done <"$BACKUP_ROOT/nvidia-package-versions.tsv"

if [[ "${ROLLBACK_ROLE:-host}" == lxc ]]; then
    if ! dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' \
        >"$BACKUP_ROOT/rollback-lxc-final-states.tsv"; then
        rc=1
    else
        while IFS=$'\t' read -r package status; do
            [[ "${status:1:1}" != n ]] || continue
            if ! rollback_package_allowed "$package"; then
                printf '[rollback] Unzulässiges LXC-Paket verblieben: %s (%s)\n' "$package" "$status" >&2
                rc=1
            fi
        done <"$BACKUP_ROOT/rollback-lxc-final-states.tsv"
    fi
fi

if command -v apt-mark >/dev/null 2>&1; then
    mapfile -t baseline_holds <"$BACKUP_ROOT/apt-holds-before.txt"
    for package in "${baseline_holds[@]}"; do
        rollback_package_allowed "$package" || continue
        apt-mark "${rollback_apt_options[@]}" hold "$package" >/dev/null 2>&1 || rc=1
    done
fi
if [[ "${ROLLBACK_ROLE:-host}" == host ]]; then
    command -v update-initramfs >/dev/null 2>&1 && update-initramfs -u || true
fi
command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true
if [[ "$ROLLBACK_COVERAGE" == "normalized-lxc" ]]; then
    printf '[rollback] Rollenreiner LXC-Zustand wiederhergestellt; ursprüngliche Host-/DKMS-Pakete bleiben gesichert, aber entfernt (Status=%s).\n' "$rc"
elif [[ "$ROLLBACK_COVERAGE" == "exact" ]]; then
    printf '[rollback] Exakter Ausgangszustand wiederhergestellt (Status=%s).\n' "$rc"
else
    printf '[rollback] Gesunde Pakete und Konfigurationen wiederhergestellt; bereits zuvor unvollständige dpkg-Zustände wurden sicher normalisiert (Status=%s).\n' "$rc"
fi
exit "$rc"
EOF_ROLLBACK
    } >"$BACKUP_DIR/rollback.sh"
    chmod 0700 "$BACKUP_DIR/rollback.sh"
}

prepare_transaction_rollback() {
    local path rel package version ctid architecture
    local -a paths=(
        /etc/apt/sources.list
        /etc/apt/sources.list.d
        /etc/apt/preferences.d
        /usr/share/keyrings/cuda-archive-keyring.gpg
        /var/lib/extrepo/keys/nvidia-cuda.asc
        /etc/apt/keyrings/nvidia-cuda.asc
        /etc/apt/keyrings/cuda-archive-keyring.gpg
        /usr/share/keyrings/nvidia-cuda-keyring.gpg
        /etc/modprobe.d
        /etc/modules-load.d/nvidia-lxc.conf
        /etc/nvidia-container-runtime
        /etc/cdi/nvidia.yaml
        /usr/bin/nvidia-smi
        /var/lib/nvidia-driver-setup/lxc-nvidia-smi-payload.env
    )
    local -a existing=()

    if ((CONFIGURE_LXC_GPU)); then
        append_unique paths "/etc/pve/lxc/${TARGET_LXC_ID}.conf"
        append_unique paths "/usr/local/sbin/nvidia-lxc-device-sync-${TARGET_LXC_ID}.sh"
        append_unique paths "/etc/systemd/system/nvidia-lxc-device-sync-${TARGET_LXC_ID}.service"
        append_unique paths "/var/lib/nvidia-lxc-device-sync/${TARGET_LXC_ID}.devices"
    fi
    if [[ "$MODE" == "host" ]]; then
        while IFS= read -r -d '' path; do append_unique paths "$path"; done \
            < <(find /usr/local/sbin -maxdepth 1 -type f -name 'nvidia-lxc-device-sync-*.sh' -print0 2>/dev/null || true)
        while IFS= read -r -d '' path; do append_unique paths "$path"; done \
            < <(find /etc/systemd/system -maxdepth 1 -type f -name 'nvidia-lxc-device-sync-*.service' -print0 2>/dev/null || true)
        while IFS= read -r -d '' path; do append_unique paths "$path"; done \
            < <(find /var/lib/nvidia-lxc-device-sync -maxdepth 1 -type f -name '*.devices' -print0 2>/dev/null || true)
        while IFS= read -r -d '' path; do
            grep -qE '(^dev[0-9]+:[[:space:]]+((path=)?/dev/nvidia)|^# BEGIN NVIDIA-DRIVER-SETUP MANAGED DEVICES$)' "$path" \
                && append_unique paths "$path"
        done < <(find /etc/pve/lxc -maxdepth 1 -type f -name '*.conf' -print0 2>/dev/null || true)
        : >"$BACKUP_DIR/lxc-states-before.tsv"
        for path in "${paths[@]}"; do
            [[ "$path" =~ ^/etc/pve/lxc/([0-9]+)\.conf$ ]] || continue
            ctid="${BASH_REMATCH[1]}"
            printf '%s\t%s\n' "$ctid" \
                "$(pct status "$ctid" 2>/dev/null | awk '{print $2}' || printf unknown)" \
                >>"$BACKUP_DIR/lxc-states-before.tsv"
        done
    fi
    : >"$BACKUP_DIR/config-paths.tsv"
    for path in "${paths[@]}"; do
        if [[ -e "$path" ]]; then
            printf '1\t%s\n' "$path" >>"$BACKUP_DIR/config-paths.tsv"
            rel="${path#/}"
            existing+=("$rel")
        else
            printf '0\t%s\n' "$path" >>"$BACKUP_DIR/config-paths.tsv"
        fi
    done
    if ((${#existing[@]})); then
        tar -C / -cpf "$BACKUP_DIR/config-snapshot.tar" "${existing[@]}"
    else
        tar -C / -cpf "$BACKUP_DIR/config-snapshot.tar" --files-from /dev/null
    fi

    mkdir -p "$BACKUP_DIR/rollback-debs" "$BACKUP_DIR/full-reinstall-debs" \
        "$BACKUP_DIR/optional-driver-reinstall-debs"
    : >"$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv"
    : >"$BACKUP_DIR/lxc-forbidden-packages-removed.tsv"
    query_managed_nvidia_package_states "$CLEAN_INSTALL_SCOPE" \
        | sort -u >"$BACKUP_DIR/nvidia-package-states-before.tsv"
    awk -F'\t' 'substr($3, 2, 1) == "i" && substr($3, 3, 1) != "R" {print $1 "\t" $2}' \
        "$BACKUP_DIR/nvidia-package-states-before.tsv" \
        | sort -u >"$BACKUP_DIR/nvidia-package-versions.tsv"
    awk -F'\t' 'substr($3, 2, 1) != "i" || substr($3, 3, 1) == "R" {print}' \
        "$BACKUP_DIR/nvidia-package-states-before.tsv" \
        | sort -u >"$BACKUP_DIR/nvidia-non-ii-states-before.tsv"
    if [[ -s "$BACKUP_DIR/nvidia-non-ii-states-before.tsv" ]]; then
        ROLLBACK_COVERAGE="normalized"
        warn "Bereits vor dem Lauf waren NVIDIA-/CUDA-Pakete nicht vollständig installiert. Sie werden bereinigt; ein Rollback stellt gesunde Pakete exakt wieder her und normalisiert diese vorbestehenden Fehlerzustände."
    else
        ROLLBACK_COVERAGE="exact"
    fi
    if [[ "$CLEAN_INSTALL_SCOPE" == "full" ]]; then
        while IFS=$'\t' read -r package version status; do
            if dpkg_status_is_healthy_installed "$status" \
               && [[ "$package" =~ $NVIDIA_AUXILIARY_REGEX \
                     && ! "$package" =~ $NVIDIA_DRIVER_REGEX ]]; then
                printf '%s\t%s\n' "$package" "$version"
            fi
        done <"$BACKUP_DIR/nvidia-package-states-before.tsv" \
            | sort -u >"$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv"
    fi

    while IFS=$'\t' read -r package version; do
        [[ -n "$package" && -n "$version" ]] || continue
        log "Sichere Rollback-Paket: $package=$version"
        stage_installed_package_deb "$package" "$version" \
            || die "Rollback nicht sicher möglich: $package=$version konnte nicht als .deb gesichert werden. Es wurde noch nichts verändert."
    done <"$BACKUP_DIR/nvidia-package-versions.tsv"

    while IFS=$'\t' read -r package version; do
        [[ -n "$package" && -n "$version" ]] || continue
        if [[ "$MODE" == "lxc" && "$package" =~ $LXC_FORBIDDEN_PACKAGE_REGEX ]]; then
            printf '%s\t%s\n' "$package" "$version" \
                >>"$BACKUP_DIR/lxc-forbidden-packages-removed.tsv"
            continue
        fi
        if ((UPDATE_ONLY == 0)); then
            architecture="$(dpkg-query -W -f='${Architecture}' "$package" 2>/dev/null || true)"
            [[ -n "$architecture" ]] \
                || die "Architektur des Zusatzpakets $package konnte nicht bestimmt werden."
            stage_trusted_reinstall_package_deb "$package" "$version" "$architecture" \
                "$BACKUP_DIR/full-reinstall-debs" \
                || die "Saubere Neuinstallation nicht garantiert: Das unveränderte Original-DEB $package=$version ist weder im offiziellen APT-Archiv noch im lokalen Paketcache verfügbar. Eine lokale dpkg-repack-Rekonstruktion wird ausschließlich für den Rollback, niemals für die Neuinstallation verwendet."
        fi
    done <"$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv"

    generate_rollback_script
    {
        printf 'Skriptversion: %s\n' "$SCRIPT_VERSION"
        printf 'Erstellt: %s\n' "$(date --iso-8601=seconds)"
        printf 'Distribution: %s (%s)\n' "$OS_LABEL" "$DISTRO"
        printf 'Rolle: %s\n' "$MODE"
        printf 'Aktion: %s\n' "$TRANSACTION_ACTION"
        printf 'Zielversion: %s\n' "${TARGET_VERSION:-nicht zutreffend}"
        printf 'Neuinstallationsumfang: %s\n' "$CLEAN_INSTALL_SCOPE"
        printf 'Rollback-Abdeckung: %s\n' "$ROLLBACK_COVERAGE"
        if [[ "$ROLLBACK_COVERAGE" != "exact" ]]; then
            printf 'Hinweis: Vorbestehende nicht-ii-dpkg-Zustände werden nicht künstlich rekonstruiert, sondern sicher normalisiert.\n'
        fi
        printf 'DEB-Paketversion vorab: %s\n' "${DETECTED_PACKAGE_DEBIAN_VERSION:-nicht installiert}"
        printf 'NVIDIA-Pakete: %s\n' "$(wc -l <"$BACKUP_DIR/nvidia-package-versions.tsv")"
        printf 'CUDA-/Container-Zusatzpakete: %s\n' "$(wc -l <"$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv")"
        printf 'Konfigurationspfade: %s\n' "${#paths[@]}"
        printf 'Betroffene Dateien:\n'
        printf '  %s\n' "${paths[@]}"
    } >"$BACKUP_DIR/rollback-manifest.txt"
    ROLLBACK_READY=1
    mark_transaction_active
    if [[ "$ROLLBACK_COVERAGE" == "exact" ]]; then
        ok "Vollständige NVIDIA-Rückkehrbasis vorbereitet: $BACKUP_DIR/rollback.sh"
    else
        warn "Rollback-Basis vorbereitet (normalisierte Abdeckung wegen vorbestehender dpkg-Fehler): $BACKUP_DIR/rollback.sh"
    fi
}

extend_rollback_packages_from_simulation() {
    local simulation_file="$1" package version status coverage_changed=0 manifest_tmp
    local additions="$BACKUP_DIR/rollback-upgrades.tsv"

    awk '
        ($1 == "Inst" || $1 == "Remv" || $1 == "Purg") && $3 ~ /^\[/ {
            version = $3
            gsub(/^\[|\]$/, "", version)
            print $2 "\t" version
        }
    ' "$simulation_file" | sort -u >"$additions"

    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        version="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
        status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null || true)"
        if [[ -n "$version" ]] && dpkg_status_is_healthy_installed "$status"; then
            printf '%s\t%s\n' "$package" "$version" >>"$additions"
        elif [[ -n "$version" && "${status:0:2}" != "un" ]]; then
            printf '%s\t%s\t%s\n' "$package" "$version" "$status" \
                >>"$BACKUP_DIR/nvidia-non-ii-states-before.tsv"
            ROLLBACK_COVERAGE="normalized"
            coverage_changed=1
        fi
    done < <(parse_apt_plan_packages Remv "$simulation_file")
    sort -u -o "$additions" "$additions"

    while IFS=$'\t' read -r package version; do
        [[ -n "$package" && -n "$version" ]] || continue
        if grep -qF "${package}"$'\t'"${version}" "$BACKUP_DIR/nvidia-package-versions.tsv"; then
            continue
        fi
        status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null || true)"
        if ! dpkg_status_is_healthy_installed "$status"; then
            if [[ "${status:0:2}" != "un" ]]; then
                printf '%s\t%s\t%s\n' "$package" "$version" "$status" \
                    >>"$BACKUP_DIR/nvidia-non-ii-states-before.tsv"
                ROLLBACK_COVERAGE="normalized"
                coverage_changed=1
            fi
            continue
        fi
        log "Sichere zusätzliches Upgrade-Rollback: $package=$version"
        stage_installed_package_deb "$package" "$version" \
            || die "Rollback für geplantes Upgrade $package=$version konnte nicht gesichert werden."
        printf '%s\t%s\n' "$package" "$version" >>"$BACKUP_DIR/nvidia-package-versions.tsv"
        refresh_backup_checksums
    done <"$additions"
    sort -u -o "$BACKUP_DIR/nvidia-package-versions.tsv" "$BACKUP_DIR/nvidia-package-versions.tsv"
    if ((coverage_changed)); then
        sort -u -o "$BACKUP_DIR/nvidia-non-ii-states-before.tsv" \
            "$BACKUP_DIR/nvidia-non-ii-states-before.tsv"
        manifest_tmp="$(mktemp "$BACKUP_DIR/.rollback-manifest.XXXXXX")"
        awk -v coverage="$ROLLBACK_COVERAGE" '
            /^Rollback-Abdeckung:/ { print "Rollback-Abdeckung: " coverage; next }
            { print }
        ' "$BACKUP_DIR/rollback-manifest.txt" >"$manifest_tmp"
        mv -f -- "$manifest_tmp" "$BACKUP_DIR/rollback-manifest.txt"
        generate_rollback_script
        write_resume_state
    fi
    # Auch das abschließende Sortieren und ein neuer Plan ohne zusätzliche
    # Pakete verändern gesicherte Dateien. Vor dem nächsten Abbruchpunkt muss
    # das Manifest den endgültigen Stand enthalten, nicht den letzten Schleifendurchlauf.
    refresh_backup_checksums
}

capture_packages_normalized_by_dpkg() {
    local package version status added=0
    local normalized_file="$BACKUP_DIR/nvidia-packages-normalized-before-purge.tsv"
    : >"$normalized_file"

    while IFS=$'\t' read -r package version status; do
        dpkg_status_is_healthy_installed "$status" || continue
        if grep -qF "${package}"$'\t'"${version}" "$BACKUP_DIR/nvidia-package-versions.tsv"; then
            continue
        fi
        log "Sichere durch dpkg normalisiertes Paket vor der Bereinigung: $package=$version"
        stage_installed_package_deb "$package" "$version" \
            || die "Rollback-Sicherung des normalisierten Pakets $package=$version ist fehlgeschlagen."
        printf '%s\t%s\n' "$package" "$version" >>"$BACKUP_DIR/nvidia-package-versions.tsv"
        printf '%s\t%s\t%s\n' "$package" "$version" "$status" >>"$normalized_file"
        added=$((added + 1))

        if [[ "$CLEAN_INSTALL_SCOPE" == "full" \
              && "$package" =~ $NVIDIA_AUXILIARY_REGEX \
              && ! "$package" =~ $NVIDIA_DRIVER_REGEX \
              && ! ("$MODE" == "lxc" && "$package" =~ $LXC_FORBIDDEN_PACKAGE_REGEX) ]]; then
            printf '%s\t%s\n' "$package" "$version" \
                >>"$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv"
        fi
    done < <(query_managed_nvidia_package_states "$CLEAN_INSTALL_SCOPE" | sort -u)

    if ((added)); then
        sort -u -o "$BACKUP_DIR/nvidia-package-versions.tsv" "$BACKUP_DIR/nvidia-package-versions.tsv"
        sort -u -o "$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv" \
            "$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv"
        printf 'Nach sicherer dpkg-Normalisierung zusätzlich gesicherte Pakete: %s\n' "$added" \
            >>"$BACKUP_DIR/rollback-manifest.txt"
        refresh_backup_checksums
    else
        rm -f -- "$normalized_file"
    fi
}

ensure_auxiliary_reinstall_payloads() {
    local package version architecture file already_staged
    [[ "$CLEAN_INSTALL_SCOPE" == "full" ]] || return 0

    while IFS=$'\t' read -r package version; do
        [[ -n "$package" && -n "$version" ]] || continue
        if [[ "$MODE" == "lxc" && "$package" =~ $LXC_FORBIDDEN_PACKAGE_REGEX ]]; then
            continue
        fi
        architecture="$(transaction_package_architecture "$package" "$version" || true)"
        [[ -n "$architecture" ]] \
            || die "Architektur des Zusatzpakets $package konnte nicht bestimmt werden."
        already_staged=0
        while IFS= read -r -d '' file; do
            if rollback_deb_matches "$file" "$package" "$version" "$architecture"; then
                already_staged=1
                break
            fi
        done < <(find "$BACKUP_DIR/full-reinstall-debs" -maxdepth 1 -type f -name '*.deb' -print0 2>/dev/null || true)
        ((already_staged)) && continue
        stage_trusted_reinstall_package_deb "$package" "$version" "$architecture" \
            "$BACKUP_DIR/full-reinstall-debs" \
            || die "Zusatzpaket $package=$version ist nach der Repository-Prüfung nicht als unverändertes Original-DEB für die saubere Neuinstallation verfügbar."
    done <"$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv"
    refresh_backup_checksums
}

check_package_manager_lock
TMP_DIR="$(mktemp -d)"
chmod 0700 "$TMP_DIR"

if ((RESUME_REQUEST)); then
    is_safe_backup_dir "$BACKUP_DIR" || die "Unsicheres Fortsetzungsverzeichnis: $BACKUP_DIR"
    verify_backup_checksums "$BACKUP_DIR" \
        || die "Fortsetzen verweigert: Die ursprüngliche Sicherung ist beschädigt oder unvollständig."
    ROLLBACK_READY=1
    MUTATION_STARTED=1
    write_transaction_phase fortgesetzt
    ok "Unterbrochene Transaktion wird mit ihrer ursprünglichen Rückkehrbasis fortgesetzt: $BACKUP_DIR"
else
    create_backup_dir driver
    prepare_nvidia_apt_source_view

if [[ -f "$0" ]]; then
    cp -a -- "$0" "$BACKUP_DIR/script-used.sh"
    sha256sum "$0" >"$BACKUP_DIR/script-used.sha256"
fi

[[ -e /etc/apt/sources.list ]] && cp -a /etc/apt/sources.list "$BACKUP_DIR/"
[[ -d /etc/apt/sources.list.d ]] && cp -a /etc/apt/sources.list.d "$BACKUP_DIR/"
[[ -d /etc/apt/preferences.d ]] && cp -a /etc/apt/preferences.d "$BACKUP_DIR/"
[[ -d /etc/modprobe.d ]] && cp -a /etc/modprobe.d "$BACKUP_DIR/"
[[ -d /var/lib/dkms ]] && find /var/lib/dkms -maxdepth 2 -type d -iname 'nvidia*' \
    -print >"$BACKUP_DIR/dkms-nvidia-before.txt" 2>/dev/null || true
apt-mark "${BOOTSTRAP_APT_OPTIONS[@]}" showhold >"$BACKUP_DIR/apt-holds-before.txt" 2>/dev/null || true
dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' 2>/dev/null \
    | awk -F'\t' 'substr($3, 2, 1) == "i" && substr($3, 3, 1) != "R" {print $1 "\t" $2}' \
    >"$BACKUP_DIR/packages-before.txt" || true
if ((CONFIGURE_LXC_GPU)); then
    cp -a "/etc/pve/lxc/${TARGET_LXC_ID}.conf" "$BACKUP_DIR/lxc-${TARGET_LXC_ID}.conf.before"
    [[ -e /etc/modules-load.d/nvidia-lxc.conf ]] \
        && cp -a /etc/modules-load.d/nvidia-lxc.conf "$BACKUP_DIR/nvidia-lxc.modules-load.before"
    [[ -e "/usr/local/sbin/nvidia-lxc-device-sync-${TARGET_LXC_ID}.sh" ]] \
        && cp -a "/usr/local/sbin/nvidia-lxc-device-sync-${TARGET_LXC_ID}.sh" "$BACKUP_DIR/"
    [[ -e "/etc/systemd/system/nvidia-lxc-device-sync-${TARGET_LXC_ID}.service" ]] \
        && cp -a "/etc/systemd/system/nvidia-lxc-device-sync-${TARGET_LXC_ID}.service" "$BACKUP_DIR/"
fi
dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' \
    | grep -Ei '(^|\t)(nvidia|libnvidia|libcuda|libnvcuvid|cuda-(drivers|compat|mps))' \
    >"$BACKUP_DIR/nvidia-packages-before.txt" 2>/dev/null || true
{
    printf 'Skriptversion: %s\n' "$SCRIPT_VERSION"
    printf 'Distribution: %s (%s)\n' "$OS_LABEL" "$DISTRO"
    printf 'Rolle: %s\n' "$MODE"
    printf 'GPU(s): %s\n' "$DETECTED_GPU_SUMMARY"
    printf 'PCI-ID(s): %s\n' "$(IFS=','; printf '%s' "${DETECTED_GPU_PCI_IDS[*]:-}")"
    printf 'Generation(en): %s\n' "$(IFS=','; printf '%s' "${DETECTED_GPU_GENERATIONS[*]:-}")"
    printf 'Kernelmodul vor Installation: %s\n' "${DETECTED_HOST_MODULE_VERSION:-nicht erkannt}"
    printf 'Kernelmodulquelle: %s\n' "${DETECTED_HOST_MODULE_SOURCE:-nicht erkannt}"
    printf 'Paketversion vor Installation: %s\n' "${DETECTED_PACKAGE_VERSION:-nicht installiert}"
    printf 'nvidia-smi vor Installation: %s\n' "${DETECTED_SMI_VERSION:-nicht verfügbar}"
    printf 'Empfehlung: %s\n' "$RECOMMENDED_VERSION"
    printf 'Begründung: %s\n' "$RECOMMENDATION_REASON"
    printf 'Gewählte Zielversion: %s\n' "$TARGET_VERSION"
    if ((CONFIGURE_LXC_GPU)); then
        printf 'LXC-GPU-Freigabe: CT %s (%s) <- %s\n' "$TARGET_LXC_ID" "$TARGET_LXC_NAME" "$TARGET_GPU_SELECTION_SUMMARY"
    fi
} >"$BACKUP_DIR/hardware-and-version-detection-before.txt"
assert_no_unrelated_broken_dpkg_states "$CLEAN_INSTALL_SCOPE"
prepare_transaction_rollback
fi
apply_nvidia_apt_source_view
MUTATION_STARTED=1
ok "Sicherung erstellt: $BACKUP_DIR"
if ((UPDATE_ONLY)); then
    log "Updateablauf: Rückkehrbasis gesichert; neue Versionen prüfen, Pakete vorladen, Holds lösen und vorhandenen Stack aktualisieren."
else
    log "Neuinstallationsablauf: Rückkehrbasis gesichert; Zielpakete vorab prüfen, NVIDIA-Altbestand vollständig bereinigen, anschließend frisch installieren."
fi

# ---------------------- Konfliktprüfungen vorab -------------------------------
remove_forbidden_lxc_packages_before_repair() {
    ((UPDATE_ONLY == 0)) || return 0
    local simulation="$BACKUP_DIR/lxc-forbidden-preconfigure-purge-simulation.txt"
    local package canonical event before round=0 remaining
    local -a installed=() forbidden=() planned_installs=()
    local -A present=() selected=()

    [[ "$MODE" == "lxc" ]] || return 0
    mapfile -t installed < <(
        dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null \
            | awk '$2 !~ /^un/ {print $1}' | sort -u || true
    )
    for package in "${installed[@]}"; do
        [[ -n "$package" ]] || continue
        present["$package"]=1
        if [[ "$package" =~ $LXC_FORBIDDEN_PACKAGE_REGEX ]]; then
            forbidden+=("$package")
            selected["$package"]=1
        fi
    done
    ((${#forbidden[@]})) || return 0
    [[ "${LXC_TARGET_PREFLIGHT_PASSED:-0}" == 1 ]] \
        || die "LXC-Vorbereinigung verweigert: der vollständige NVIDIA-Zielplan wurde noch nicht erfolgreich simuliert. Vorhandene Pakete bleiben installiert."
    warn "Entferne unzulässige LXC-Kernel-/DKMS-/Treiber-/Host-Hilfspakete nach erfolgreicher Zielplan-Simulation: ${forbidden[*]}"

    # dpkg --purge darf keinen APT-Plan voraussetzen, der zusätzlich Pakete
    # installiert oder aktualisiert. Altbestände wie nvidia-settings und
    # libxnvctrl0 stattdessen in die Entfernung aufnehmen und erneut simulieren.
    # Die Menge wächst nur um vorhandene NVIDIA-Pakete; ohne Fortschritt wird
    # abgebrochen. Damit endet die Schleife spätestens nach dem lokalen Inventar.
    while true; do
        round=$((round + 1))
        apt_simulate_readonly purge "${forbidden[@]}" >"$simulation" 2>&1 || {
            cat "$simulation" >&2
            die "Die sichere Vorabentfernung unzulässiger LXC-Pakete kann nicht simuliert werden. Es wurde noch kein Paket konfiguriert. Details: $simulation"
        }
        cp -- "$simulation" "$BACKUP_DIR/lxc-preconfigure-purge-attempt-${round}.txt"
        before=${#forbidden[@]}
        while IFS=$'\t' read -r event package; do
            [[ -n "$package" ]] || continue
            canonical="$package"
            if [[ -z "${present[$canonical]:-}" ]]; then
                canonical="$(dpkg-query -W -f='${binary:Package}' "$package" 2>/dev/null || true)"
            fi
            [[ -n "$canonical" && -n "${present[$canonical]:-}" ]] || continue
            [[ -z "${selected[$canonical]:-}" ]] || continue
            if [[ "$canonical" =~ $NVIDIA_DRIVER_REGEX \
                  || "$canonical" =~ $LXC_FORBIDDEN_PACKAGE_REGEX \
                  || ("$CLEAN_INSTALL_SCOPE" == "full" && "$canonical" =~ $NVIDIA_AUXILIARY_REGEX) ]]; then
                if ((REPAIR_ONLY_REQUEST)) && [[ ! "$canonical" =~ $LXC_FORBIDDEN_PACKAGE_REGEX ]]; then
                    die "Die LXC-Vorbereinigung müsste zusätzlich $canonical entfernen. Wähle die saubere Neuinstallation, damit dieser Userspace anschließend wieder eingerichtet und geprüft wird. Details: $simulation"
                fi
                forbidden+=("$canonical")
                selected["$canonical"]=1
                log "LXC-Vorbereinigung nimmt die NVIDIA-Abhängigkeit $canonical in den Entfernungsplan auf ($event)."
            fi
        done < <(awk '$1 == "Inst" || $1 == "Remv" || $1 == "Purg" {print $1 "\t" $2}' "$simulation")
        ((${#forbidden[@]} > before)) && continue
        mapfile -t planned_installs < <(parse_apt_plan_packages Inst "$simulation")
        ((${#planned_installs[@]} == 0)) \
            || die "Die LXC-Vorbereinigung benötigt weiterhin Installationen/Upgrades statt einer reinen Entfernung: ${planned_installs[*]}. Es wurde kein Paket entfernt. Details: $simulation"
        break
    done

    # Die normale Policy bleibt aktiv: kritische/fremde Entfernungen und
    # unzulässige LXC-Installationen werden weiterhin abgelehnt.
    assert_apt_simulation_policy "$simulation" purge "${forbidden[@]}"
    printf '%s\n' "${forbidden[@]}" | sort -u >"$BACKUP_DIR/lxc-preconfigure-purge-packages.txt"
    extend_rollback_packages_from_simulation "$simulation" \
        || die "Die Rollback-Basis für die LXC-Vorbereinigung konnte nicht vervollständigt werden; es wurde kein Paket entfernt."
    refresh_backup_checksums \
        || die "Die LXC-Vorbereinigung konnte nicht vollständig im Prüfsummenmanifest gesichert werden; es wurde kein Paket entfernt."
    dpkg_mutate --purge "${forbidden[@]}" \
        || die "Unzulässige LXC-Kernel-/DKMS-/Host-Hilfspakete konnten vor der Paket-Reparatur nicht entfernt werden."
    remaining="$(dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null \
        | awk '$2 !~ /^un/ {print $1}' | grep -E "$LXC_FORBIDDEN_PACKAGE_REGEX" || true)"
    [[ -z "$remaining" ]] \
        || die "Nach der LXC-Vorbereinigung sind weiterhin unzulässige Pakete vorhanden: $remaining"
    record_repair_action "Unzulässige LXC-Kernel-/DKMS-/Treiber-/Host-Hilfspakete nach erfolgreichem Zielplan entfernt"
}

check_gpu_consumers() {
    [[ "$MODE" == "host" ]] || return 0

    if command -v systemctl >/dev/null 2>&1 \
       && systemctl is-active --quiet nvidia-persistenced.service 2>/dev/null; then
        NVIDIA_PERSISTENCED_WAS_ACTIVE=1
        systemctl stop nvidia-persistenced.service 2>/dev/null || true
    fi

    local smi_output=""
    local smi_rc=127
    local smi_pids=""
    local device_pids=""
    local pids=""
    local pid target cgroup remaining="" attempt
    local -a targets=() unresolved=()

    # nvidia-smi kann nach einem Treiberwechsel bis zum Neustart mit einem
    # NVML-/Treiberbibliotheks-Mismatch fehlschlagen. Fehlermeldungen dürfen
    # niemals als PIDs interpretiert werden; akzeptiert werden nur Ziffern.
    if command -v nvidia-smi >/dev/null 2>&1; then
        # Erwartbare nvidia-smi-Fehler müssen Teil einer Bedingung sein. Ein
        # bloßes "set +e" verhindert bei aktivem ERR-Trap nicht zuverlässig,
        # dass der Trap aus einer Command-Substitution heraus ausgelöst wird.
        if smi_output="$(nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits 2>&1)"; then
            smi_rc=0
        else
            smi_rc=$?
        fi

        printf 'Exit-Code: %s\n%s\n' "$smi_rc" "$smi_output" \
            >"$BACKUP_DIR/nvidia-smi-process-query.txt"

        if ((smi_rc == 0)); then
            smi_pids="$(awk '$1 ~ /^[0-9]+$/ {print $1}' <<<"$smi_output" | sort -nu)"
        else
            warn "nvidia-smi konnte NVML nicht abfragen. Prüfe belegte NVIDIA-Geräte stattdessen direkt über /dev/nvidia*."
        fi
    fi

    # Fallback und zusätzliche Kontrolle: Prozesse ermitteln, die eines der
    # NVIDIA-Geräte geöffnet haben. fuser schreibt PIDs nach stdout.
    if command -v fuser >/dev/null 2>&1 && compgen -G '/dev/nvidia*' >/dev/null; then
        device_pids="$(fuser /dev/nvidia* 2>/dev/null \
            | tr ' ' '\n' \
            | sed -nE 's/^([0-9]+).*/\1/p' \
            | sort -nu || true)"
    fi

    pids="$(printf '%s\n%s\n' "$smi_pids" "$device_pids" \
        | awk '/^[0-9]+$/' \
        | sort -nu)"

    if [[ -n "$pids" ]]; then
        {
            printf 'Erkannte Host-PIDs:\n%s\n\n' "$pids"
            printf 'Prozessdetails:\n'
            ps -o pid=,ppid=,user=,comm=,args= -p "$(paste -sd, <<<"$pids")" 2>/dev/null || true
            printf '\nZuordnung:\n'
            while IFS= read -r pid; do
                [[ "$pid" =~ ^[0-9]+$ ]] || continue
                cgroup="$(read_gpu_consumer_pid_cgroup "$pid" 2>/dev/null || true)"
                if target="$(resolve_gpu_consumer_target "$pid" 2>/dev/null)"; then
                    append_unique targets "$target"
                    printf 'PID %s -> %s\n' "$pid" "$target"
                else
                    unresolved+=("$pid")
                    printf 'PID %s -> nicht sicher zuordenbar\n' "$pid"
                fi
                printf '  cgroup: %s\n' "$(tr '\n' ' ' <<<"$cgroup")"
            done <<<"$pids"
        } >"$BACKUP_DIR/nvidia-processes-blocking-install.txt"

        warn "Auf der GPU laufen noch Prozesse mit den Host-PIDs: $(tr '\n' ' ' <<<"$pids")"
        [[ "$GPU_CONSUMER_POLICY" == "stop-services" ]] \
            || die "Automatisches Stoppen ist nicht aktiviert. Wähle es im Menü oder nutze --stop-gpu-services. Details: $BACKUP_DIR/nvidia-processes-blocking-install.txt"
        ((${#unresolved[@]} == 0)) \
            || die "Nicht alle GPU-Prozesse konnten einem sicheren Systemdienst zugeordnet werden: ${unresolved[*]}. Es wird nichts automatisch beendet. Details: $BACKUP_DIR/nvidia-processes-blocking-install.txt"

        for target in "${targets[@]}"; do
            gpu_consumer_target_is_active "$target" || continue
            append_unique STOPPED_GPU_CONSUMERS "$target"
            write_resume_state
            refresh_backup_checksums
            stop_gpu_consumer_target "$target" \
                || die "GPU-Dienst konnte nicht kontrolliert gestoppt werden: $target"
        done

        for attempt in {1..15}; do
            remaining="$(collect_gpu_consumer_pids || true)"
            [[ -z "$remaining" ]] && break
            sleep 1
        done
        [[ -z "$remaining" ]] \
            || die "Nach dem kontrollierten Dienststopp belegen weiterhin Prozesse die GPU: $(tr '\n' ' ' <<<"$remaining"). Details: $BACKUP_DIR/nvidia-processes-blocking-install.txt"
        ok "GPU nutzende Dienste wurden kontrolliert gestoppt und werden nach der Wartung wiederhergestellt."
    fi

    if ((smi_rc != 0)) && [[ -z "$device_pids" ]]; then
        warn "Keine geöffneten /dev/nvidia*-Geräte gefunden. Die Installation wird trotz nicht verfügbarer NVML-Abfrage fortgesetzt."
    fi
}

remove_runfile_installation() {
    local uninstaller=""

    if command -v nvidia-uninstall >/dev/null 2>&1; then
        uninstaller="$(command -v nvidia-uninstall)"
    elif [[ -x /usr/bin/nvidia-uninstall ]]; then
        uninstaller="/usr/bin/nvidia-uninstall"
    fi

    [[ -n "$uninstaller" ]] || return 0

    # Von einem Debian-Paket verwaltete Dateien werden später über APT entfernt.
    if dpkg-query -S "$uninstaller" >/dev/null 2>&1; then
        return 0
    fi

    warn "Eine NVIDIA-Runfile-Installation wurde erkannt: $uninstaller"
    die "Eine Runfile-Installation kann ohne den ursprünglichen Installer und ein vollständiges Dateimanifest nicht garantiert zurückgerollt werden. Entferne sie bewusst mit '$uninstaller', prüfe das Ergebnis und starte dieses Skript danach erneut. Es wurde keine Runfile-Datei verändert."
}

if ((UPDATE_ONLY)); then
    run_nvidia_package_update
    return 0
fi

check_gpu_consumers
run_automatic_preinstall_repair

if ((REPAIR_ONLY_REQUEST)); then
    run_standalone_automatic_repair
    return 0
fi


run_initial_safe_autoremove

# -------------------------- APT-Quellen bereinigen ----------------------------
refresh_source_file_list() {
    APT_SOURCE_FILES=()
    [[ -f /etc/apt/sources.list ]] && APT_SOURCE_FILES+=(/etc/apt/sources.list)
    local file
    for file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [[ -f "$file" ]] && APT_SOURCE_FILES+=("$file")
    done
}

clean_list_lines() {
    local file="$1"
    local regex="$2"
    local tmp
    tmp="$(mktemp "$TMP_DIR/apt-list.XXXXXX")"

    awk -v re="$regex" '$0 !~ re' "$file" >"$tmp"

    if cmp -s "$file" "$tmp"; then
        rm -f "$tmp"
    elif [[ ! -s "$tmp" ]] || ! grep -q '[^[:space:]]' "$tmp"; then
        rm -f "$file" "$tmp"
        log "APT-Datei entfernt: $file"
    else
        cat "$tmp" >"$file"
        rm -f "$tmp"
        log "APT-Datei bereinigt: $file"
    fi
}

clean_deb822_stanzas() {
    local file="$1"
    local regex="$2"
    local tmp
    tmp="$(mktemp "$TMP_DIR/apt-deb822.XXXXXX")"

    awk -v RS='' -v ORS='\n\n' -v re="$regex" '$0 !~ re' "$file" >"$tmp"

    if cmp -s "$file" "$tmp"; then
        rm -f "$tmp"
    elif [[ ! -s "$tmp" ]] || ! grep -q '[^[:space:]]' "$tmp"; then
        rm -f "$file" "$tmp"
        log "APT-Datei entfernt: $file"
    else
        cat "$tmp" >"$file"
        rm -f "$tmp"
        log "APT-Datei bereinigt: $file"
    fi
}

clean_apt_entries() {
    local regex="$1"
    local file

    refresh_source_file_list
    for file in "${APT_SOURCE_FILES[@]}"; do
        [[ -f "$file" ]] || continue
        grep -Eq "$regex" "$file" || continue
        case "$file" in
            *.sources) clean_deb822_stanzas "$file" "$regex" ;;
            *)         clean_list_lines "$file" "$regex" ;;
        esac
    done
}

repair_microsoft_signed_by_conflict() {
    local official=0
    local legacy=0
    local file tmp

    refresh_source_file_list
    for file in "${APT_SOURCE_FILES[@]}"; do
        grep -qF '/usr/share/keyrings/microsoft-prod.gpg' "$file" 2>/dev/null && official=1
        grep -qF '/etc/apt/keyrings/microsoft.gpg' "$file" 2>/dev/null && legacy=1
    done

    ((official == 1 && legacy == 1)) || return 0
    warn "Microsoft-Repository doppelt mit verschiedenen Signed-By-Schlüsseln eingetragen."

    for file in "${APT_SOURCE_FILES[@]}"; do
        [[ -f "$file" ]] || continue
        grep -q 'packages\.microsoft\.com' "$file" || continue
        grep -qF '/etc/apt/keyrings/microsoft.gpg' "$file" || continue
        tmp="$(mktemp "$TMP_DIR/microsoft-source.XXXXXX")"

        case "$file" in
            *.sources)
                awk -v RS='' -v ORS='\n\n' \
                    '!( $0 ~ /packages\.microsoft\.com/ && $0 ~ /\/etc\/apt\/keyrings\/microsoft\.gpg/ )' \
                    "$file" >"$tmp"
                ;;
            *)
                awk \
                    '!( $0 ~ /packages\.microsoft\.com/ && $0 ~ /\/etc\/apt\/keyrings\/microsoft\.gpg/ )' \
                    "$file" >"$tmp"
                ;;
        esac

        if [[ ! -s "$tmp" ]] || ! grep -q '[^[:space:]]' "$tmp"; then
            rm -f "$file" "$tmp"
            log "Microsoft-Duplikat entfernt: $file"
        else
            cat "$tmp" >"$file"
            rm -f "$tmp"
            log "Microsoft-Duplikat bereinigt: $file"
        fi
    done

    if ! grep -RqsF '/etc/apt/keyrings/microsoft.gpg' \
        /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
        rm -f /etc/apt/keyrings/microsoft.gpg
    fi
}

audit_nvidia_repository_configuration \
    || warn "Gemischte NVIDIA-Quellen werden durch die gesicherte Neuinitialisierung ersetzt."
log "Entferne alle bisherigen NVIDIA-CUDA-Netzwerk- und Local-Repository-Einträge ..."
clean_apt_entries 'developer\.download\.nvidia\.com/compute/cuda/repos|file:/var/(cuda-repo|nvidia-driver-local-repo)|/var/(cuda-repo|nvidia-driver-local-repo)'

if ((FIX_MICROSOFT_CONFLICT)); then
    repair_microsoft_signed_by_conflict
fi

# Nur NVIDIA-CUDA-Schlüssel entfernen; libnvidia-container bleibt unberührt.
rm -f \
    /var/lib/extrepo/keys/nvidia-cuda.asc \
    /etc/apt/keyrings/nvidia-cuda.asc \
    /etc/apt/keyrings/cuda-archive-keyring.gpg \
    /usr/share/keyrings/nvidia-cuda-keyring.gpg

# Alte manuelle NVIDIA/CUDA-Pins entfernen. Noch paketverwaltete Conffiles
# bleiben bis zum kontrollierten Paketaustausch erhalten, damit dpkg garantiert
# keine interaktive Frage wegen einer zuvor gelöschten Konfigurationsdatei stellt.
remove_obsolete_nvidia_pin_files

rm -f /var/lib/apt/lists/*developer.download.nvidia.com* \
      /var/lib/apt/lists/*cuda*Packages* 2>/dev/null || true

# ----------------------- Paketstatus vorbereiten ------------------------------
log "Prüfe den dpkg-Grundzustand ..."
if ! dpkg_mutate --configure -a; then
    die "Der vorhandene dpkg-Zustand ist nicht repariert. Es wurden noch keine NVIDIA-Pakete entfernt; behebe zuerst die gemeldeten dpkg-Fehler."
fi
capture_packages_normalized_by_dpkg

log "Aktualisiere die verbleibenden Paketquellen ..."
apt_mutate update
DEBIAN_FRONTEND=noninteractive apt_mutate install -y --no-upgrade --no-install-recommends \
    ca-certificates curl gnupg

install_running_kernel_headers() {
    local kernel
    local candidate
    local candidates=()

    kernel="$(uname -r)"
    if [[ -e "/lib/modules/${kernel}/build/Makefile" ]]; then
        ok "Kernel-Header für $kernel vorhanden."
        return 0
    fi

    candidates+=("proxmox-headers-${kernel}")
    candidates+=("pve-headers-${kernel}")
    candidates+=("linux-headers-${kernel}")

    for candidate in "${candidates[@]}"; do
        if apt-cache show "$candidate" >/dev/null 2>&1; then
            log "Installiere Kernel-Header vor dem Treiberwechsel: $candidate"
            DEBIAN_FRONTEND=noninteractive apt_mutate install -y --no-upgrade "$candidate"
            [[ -e "/lib/modules/${kernel}/build/Makefile" ]] \
                || die "Header installiert, aber /lib/modules/${kernel}/build fehlt."
            return 0
        fi
    done

    die "Keine Header für den laufenden Kernel $kernel gefunden. Aktualisiere ${OS_LABEL:-das Betriebssystem}, starte den neuesten Kernel und führe das Skript erneut aus."
}

if [[ "$MODE" == "host" ]]; then
    log "Prüfe Build-Werkzeuge und Header vor dem Treiberwechsel ..."
    DEBIAN_FRONTEND=noninteractive apt_mutate install -y --no-upgrade --no-install-recommends \
        dkms build-essential pciutils
    install_running_kernel_headers

    if command -v mokutil >/dev/null 2>&1; then
        mokutil --sb-state >"$BACKUP_DIR/secure-boot-state.txt" 2>&1 || true
        if grep -qi 'SecureBoot enabled' "$BACKUP_DIR/secure-boot-state.txt"; then
            warn "Secure Boot ist aktiv. Prüfe nach der Installation die DKMS-Modulsignatur und MOK-Einbindung."
        fi
    fi
fi

# Baseline merken, damit später keine schon vorher verwaisten Pakete entfernt werden.
get_autoremove_candidates() {
    apt-get -s autoremove --purge 2>/dev/null \
        | awk '$1 == "Remv" || $1 == "Purg" {print $2}' \
        | sort -u
}
mapfile -t BASELINE_AUTOREMOVE < <(get_autoremove_candidates)
printf '%s\n' "${BASELINE_AUTOREMOVE[@]:-}" >"$BACKUP_DIR/autoremove-baseline.txt"

# ---------------------- NVIDIA-Pakete ermitteln -------------------------------
# Treiberpakete und – bei vollständigem Umfang – der vorhandene paketverwaltete
# CUDA-/Container-Zusatzstack werden getrennt behandelt. Zusatzpakete behalten
# ihre eigene vollständige DEB-Version und werden nie mit TARGET_VERSION verglichen.
get_installed_nvidia_driver_packages() {
    dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null \
        | awk '$2 !~ /^un/ {print $1}' \
        | grep -E "$NVIDIA_DRIVER_REGEX" \
        | grep -Ev '^nvidia-driver-pinning([:-]|$)' \
        | sort -u \
        || true
}

get_installed_repo_packages() {
    dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null \
        | awk '$2 !~ /^un/ {print $1}' \
        | grep -E "$NVIDIA_REPOSITORY_PACKAGE_REGEX" \
        | sort -u \
        || true
}

get_installed_auxiliary_nvidia_packages() {
    [[ "$CLEAN_INSTALL_SCOPE" == "full" ]] || return 0
    query_managed_nvidia_package_states full \
        | cut -f1 \
        | grep -E "$NVIDIA_AUXILIARY_REGEX" \
        | grep -Ev "$NVIDIA_DRIVER_REGEX" \
        | sort -u \
        || true
}

mapfile -t NVIDIA_PACKAGES < <(get_installed_nvidia_driver_packages)
mapfile -t AUXILIARY_PACKAGES < <(get_installed_auxiliary_nvidia_packages)
mapfile -t REPO_PACKAGES < <(
    get_installed_repo_packages | grep -Ev '^cuda-keyring(:.*)?$' || true
)

# apt-mark Holds können Upgrade/Downgrade verhindern. Die zentrale
# Paketklassifizierung verhindert, dass z. B. libnvoptix, libnvsdm oder
# xserver-xorg-video-nvidia durch eine abweichende Präfixliste übersehen werden.
mapfile -t NVIDIA_HOLDS < <(list_managed_nvidia_holds)
if ((${#NVIDIA_HOLDS[@]})); then
    release_and_verify_package_holds "${NVIDIA_HOLDS[@]}"
fi

# ---------------- Repository- und Installations-Preflight ---------------------
# Dieser Block muss vor dem ersten Treiber-Purge erfolgreich sein. So bleibt der
# vorhandene Stack installiert, falls Repository, Pinning oder Zielpakete fehlen.
KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/${DISTRO}/x86_64/cuda-keyring_1.1-1_all.deb"
KEYRING_FILE="$TMP_DIR/cuda-keyring.deb"

log "Prüfe das offizielle NVIDIA-Repository für $DISTRO ..."
curl --fail --location --retry 3 --retry-delay 2 \
    --output "$KEYRING_FILE" "$KEYRING_URL"
sha256sum "$KEYRING_FILE" >"$BACKUP_DIR/cuda-keyring.sha256"

[[ "$(dpkg-deb -f "$KEYRING_FILE" Package 2>/dev/null)" == "cuda-keyring" ]] \
    || die "Der Repository-Download ist kein cuda-keyring-Paket."
[[ "$(dpkg-deb -f "$KEYRING_FILE" Version 2>/dev/null)" == "1.1-1" ]] \
    || die "Unerwartete cuda-keyring-Version im Repository-Download."
[[ "$(dpkg-deb -f "$KEYRING_FILE" Architecture 2>/dev/null)" == "all" ]] \
    || die "Unerwartete Architektur des cuda-keyring-Pakets."

DEBIAN_FRONTEND=noninteractive apt_mutate install -y --reinstall \
    -o Dpkg::Options::="--force-confmiss" "$KEYRING_FILE"
NVIDIA_REPO_KEYRING="/usr/share/keyrings/cuda-archive-keyring.gpg"
NVIDIA_REPO_SOURCE="/etc/apt/sources.list.d/cuda-${DISTRO}-x86_64.list"
[[ -s "$NVIDIA_REPO_KEYRING" ]] \
    || die "Das installierte cuda-keyring hat $NVIDIA_REPO_KEYRING nicht bereitgestellt."
ensure_official_nvidia_repository_source "$DISTRO" "$NVIDIA_REPO_KEYRING" "$NVIDIA_REPO_SOURCE" \
    || die "Die offizielle NVIDIA-Paketquelle konnte nicht sicher wiederhergestellt werden."
apt_mutate update
audit_nvidia_repository_configuration 1 \
    || die "Nach der Repository-Neueinrichtung sind weiterhin gemischte NVIDIA-Paketquellen aktiv."
prepare_debian_lxc_nvidia_smi_payload
ensure_auxiliary_reinstall_payloads

# Noch bevor ein vorhandenes Pinning-Paket ersetzt wird, muss APT die gewählte
# Paketkombination grundsätzlich lösen können. Dadurch werden insbesondere
# Conflicts wie nvidia-driver-cuda zusammen mit dem Debian-Einzelpaket
# nvidia-smi erkannt, solange der bisherige Paketstand noch unverändert ist.
build_target_package_profile
extend_target_profile_with_existing_optional_driver_packages
PREPIN_EXACT_DRIVER_PACKAGE_SPECS=()
PREPIN_COMMON_DRIVER_DEBIAN_VERSION=""
for package in "${PREFLIGHT_DRIVER_PACKAGES[@]}"; do
    [[ -n "$package" ]] || continue
    candidate="$(official_target_package_version "$package" || true)"
    [[ -n "$candidate" ]] \
        || die "$package ist für Treiber $TARGET_VERSION nicht eindeutig in der offiziellen NVIDIA-Paketquelle verfügbar; es wurde noch kein NVIDIA-Treiberpaket entfernt."
    if [[ -z "$PREPIN_COMMON_DRIVER_DEBIAN_VERSION" ]]; then
        PREPIN_COMMON_DRIVER_DEBIAN_VERSION="$candidate"
    elif ! debian_versions_equal "$candidate" "$PREPIN_COMMON_DRIVER_DEBIAN_VERSION"; then
        die "Die NVIDIA-Zielpakete besitzen vor dem Purge unterschiedliche vollständige DEB-Versionen: $package=$candidate, Referenz=$PREPIN_COMMON_DRIVER_DEBIAN_VERSION."
    fi
    PREPIN_EXACT_DRIVER_PACKAGE_SPECS+=("${package}=${candidate}")
done
APT_PROFILE_SOLVER_SIMULATION="$BACKUP_DIR/profile-solver-simulation-before-pinning.txt"
prepare_clean_install_apt_view
PREPIN_AUXILIARY_DEBS=("${OPTIONAL_DRIVER_REINSTALL_DEBS[@]}")
while IFS= read -r -d '' package; do
    append_unique PREPIN_AUXILIARY_DEBS "$package"
done < <(find "$BACKUP_DIR/full-reinstall-debs" -maxdepth 1 -type f -name '*.deb' -print0)
simulate_clean_target "$APT_PROFILE_SOLVER_SIMULATION" \
    "${PREPIN_EXACT_DRIVER_PACKAGE_SPECS[@]}" "${PREPIN_AUXILIARY_DEBS[@]}"
if [[ "$MODE" == "lxc" ]]; then
    LXC_TARGET_PREFLIGHT_PASSED=1
    remove_forbidden_lxc_packages_before_repair
fi

PIN_PACKAGE="nvidia-driver-pinning-${TARGET_VERSION}"
PIN_POLICY_FILE="$BACKUP_DIR/apt-policy-${PIN_PACKAGE}.txt"
apt-cache policy "$PIN_PACKAGE" >"$PIN_POLICY_FILE"
PIN_DEBIAN_VERSION="$(awk '$1 == "Candidate:" {print $2; exit}' "$PIN_POLICY_FILE")"
PIN_MADISON_OUTPUT="$(apt-cache madison "$PIN_PACKAGE" 2>/dev/null || true)"
if [[ -n "$PIN_DEBIAN_VERSION" && "$PIN_DEBIAN_VERSION" != "(none)" \
      && "$(normalize_driver_version "$PIN_DEBIAN_VERSION")" == "$TARGET_VERSION" \
      && "$PIN_MADISON_OUTPUT" == *"$PIN_DEBIAN_VERSION"* \
      && "$PIN_MADISON_OUTPUT" == *"developer.download.nvidia.com"* ]] \
   && ! grep -F "$PIN_DEBIAN_VERSION" <<<"$PIN_MADISON_OUTPUT" \
        | grep -vq 'developer.download.nvidia.com'; then
    log "Installiere exaktes NVIDIA-Pinning vor dem Treiberwechsel: $PIN_PACKAGE=$PIN_DEBIAN_VERSION"
    DEBIAN_FRONTEND=noninteractive apt_mutate \
        -o Dpkg::Options::=--force-confmiss \
        -o Dpkg::Options::=--force-confnew \
        install -V --purge --reinstall -y \
        "${PIN_PACKAGE}=${PIN_DEBIAN_VERSION}"
    PIN_ACTIVE_FILE="$(dpkg-query -L "$PIN_PACKAGE" 2>/dev/null \
        | awk '/^\/etc\/apt\/preferences\.d\// {print; exit}')"
    [[ -n "$PIN_ACTIVE_FILE" && -s "$PIN_ACTIVE_FILE" ]] \
        || die "Das exakte Pinning-Paket $PIN_PACKAGE wurde installiert, aber seine aktive APT-Präferenzdatei fehlt."
else
    warn "$PIN_PACKAGE ist nicht eindeutig verfügbar; verwende stattdessen eine transaktionale APT-Versionspräferenz."
    PIN_PACKAGE=""
    PIN_DEBIAN_VERSION=""
    install_temporary_version_preference
fi

build_target_package_profile
extend_target_profile_with_existing_optional_driver_packages

PREFLIGHT_CANDIDATE_PACKAGES=(
    "${PREFLIGHT_DRIVER_PACKAGES[@]}"
)

EXPECTED_PACKAGE_VERSIONS=()
COMMON_DRIVER_DEBIAN_VERSION=""
for package in "${PREFLIGHT_CANDIDATE_PACKAGES[@]}"; do
    [[ -n "$package" ]] || continue
    policy_file="$BACKUP_DIR/apt-policy-${package//:/_}.txt"
    apt-cache policy "$package" >"$policy_file"
    candidate="$(awk '$1 == "Candidate:" {print $2; exit}' "$policy_file")"
    [[ "$(normalize_driver_version "$candidate")" == "$TARGET_VERSION" ]] \
        || die "APT-Kandidat für $package ist '${candidate:-nicht vorhanden}', erwartet wurde $TARGET_VERSION."
    EXPECTED_PACKAGE_VERSIONS["$package"]="$candidate"
    if [[ -z "$COMMON_DRIVER_DEBIAN_VERSION" ]]; then
        COMMON_DRIVER_DEBIAN_VERSION="$candidate"
    elif ! debian_versions_equal "$candidate" "$COMMON_DRIVER_DEBIAN_VERSION"; then
        die "NVIDIA-Pakete sind nicht in derselben vollständigen DEB-Version verfügbar: $package=$candidate, Referenz=$COMMON_DRIVER_DEBIAN_VERSION."
    fi

    madison_output="$(apt-cache madison "$package" 2>/dev/null || true)"
    if [[ "$madison_output" != *"$TARGET_VERSION"* \
          || "$madison_output" != *"developer.download.nvidia.com"* ]]; then
        die "$package $TARGET_VERSION wurde nicht eindeutig im offiziellen NVIDIA-Repository gefunden."
    fi
    if grep -F "$TARGET_VERSION" <<<"$madison_output" \
        | grep -vq 'developer.download.nvidia.com'; then
        die "$package $TARGET_VERSION wird gleichzeitig aus einer fremden Paketquelle angeboten. Gemischte NVIDIA-Paketquellen werden verhindert."
    fi
done

EXACT_DRIVER_PACKAGE_SPECS=()
for package in "${PREFLIGHT_DRIVER_PACKAGES[@]}"; do
    EXACT_DRIVER_PACKAGE_SPECS+=("${package}=${EXPECTED_PACKAGE_VERSIONS[$package]}")
done
AUXILIARY_REINSTALL_DEBS=("${OPTIONAL_DRIVER_REINSTALL_DEBS[@]}")
if [[ "$CLEAN_INSTALL_SCOPE" == "full" ]]; then
    while IFS= read -r -d '' package; do
        append_unique AUXILIARY_REINSTALL_DEBS "$package"
    done < <(find "$BACKUP_DIR/full-reinstall-debs" -maxdepth 1 -type f -name '*.deb' -print0 2>/dev/null || true)
fi
{
    printf 'Ziel-Treiberversion: %s\n' "$TARGET_VERSION"
    printf 'Vollständige DEB-Version: %s\n' "$COMMON_DRIVER_DEBIAN_VERSION"
    for package in "${PREFLIGHT_DRIVER_PACKAGES[@]}"; do
        printf '%s\t%s\tEpoch=%s\tUpstream=%s\tRevision=%s\n' \
            "$package" "${EXPECTED_PACKAGE_VERSIONS[$package]}" \
            "$(debian_version_epoch "${EXPECTED_PACKAGE_VERSIONS[$package]}")" \
            "$(debian_version_upstream "${EXPECTED_PACKAGE_VERSIONS[$package]}")" \
            "$(debian_version_revision "${EXPECTED_PACKAGE_VERSIONS[$package]}")"
    done
} >"$BACKUP_DIR/exact-package-versions.tsv"

APT_INSTALL_SIMULATION="$BACKUP_DIR/install-simulation-before-purge.txt"
prepare_clean_install_apt_view
simulate_clean_target "$APT_INSTALL_SIMULATION" \
    "${EXACT_DRIVER_PACKAGE_SPECS[@]}" "${AUXILIARY_REINSTALL_DEBS[@]}"
extend_rollback_packages_from_simulation "$APT_INSTALL_SIMULATION"

if ((${#AUXILIARY_REINSTALL_DEBS[@]})); then
    FULL_STACK_INSTALL_SIMULATION="$BACKUP_DIR/full-stack-install-simulation-before-purge.txt"
    cp -- "$APT_INSTALL_SIMULATION" "$FULL_STACK_INSTALL_SIMULATION"
    ok "Exakte Wiederinstallation von ${#AUXILIARY_REINSTALL_DEBS[@]} CUDA-/Container-Zusatzpaketen vorab simuliert."
fi

log "Lade den vollständigen Zielstack einschließlich Abhängigkeiten vor der Bereinigung ..."
DEBIAN_FRONTEND=noninteractive run_apt_get "${CLEAN_APT_OPTIONS[@]}" \
    install -V -y --download-only --reinstall --fix-broken \
    --allow-downgrades --no-install-recommends \
    "${EXACT_DRIVER_PACKAGE_SPECS[@]}" "${AUXILIARY_REINSTALL_DEBS[@]}" \
    || die "Zielpakete konnten nicht vollständig vorab geladen werden. Hauptbereinigung wurde nicht gestartet."
refresh_backup_checksums
ok "Repository, Pinning, Zielversion und Installationssimulation sind geprüft."

# ------------------------ Sichere Purge-Simulation ----------------------------
parse_removed_packages() {
    awk '$1 == "Remv" || $1 == "Purg" {print $2}' | sort -u
}

assert_no_critical_removals() {
    local simulation_file="$1"
    local critical_regex='^(proxmox-ve|pve-manager|pve-container|proxmox-default-kernel|proxmox-kernel-helper|proxmox-kernel-[^[:space:]]+|pve-kernel-[^[:space:]]+|proxmox-headers-[^[:space:]]+|pve-headers-[^[:space:]]+|linux-image-[^[:space:]]+|linux-headers-[^[:space:]]+|systemd|systemd-sysv|init|openssh-server|apt|dpkg|fileflows)$'
    local bad

    bad="$(parse_removed_packages <"$simulation_file" | grep -E "$critical_regex" || true)"
    if [[ -n "$bad" ]]; then
        cat "$simulation_file" >"$BACKUP_DIR/unsafe-purge-simulation.txt"
        die "APT würde kritische Pakete entfernen: $(tr '\n' ' ' <<<"$bad"). Simulation: $BACKUP_DIR/unsafe-purge-simulation.txt"
    fi
}

assert_no_unexpected_removals() {
    local simulation_file="$1"
    shift
    local requested=("$@")
    local removed package expected
    local unexpected=()

    while IFS= read -r removed; do
        [[ -n "$removed" ]] || continue
        expected=0
        for package in "${requested[@]}"; do
            if [[ "$removed" == "$package" ]]; then
                expected=1
                break
            fi
        done
        ((expected)) && continue

        # Das neu installierte Pinning darf beim Treiber-Purge nicht wieder
        # entfernt werden. Alle anderen automatisch mitentfernten Pakete müssen
        # eindeutig zum NVIDIA-Treiberstack gehören.
        if [[ "$removed" == nvidia-driver-pinning* ]]; then
            unexpected+=("$removed")
        elif [[ "$removed" =~ $NVIDIA_DRIVER_REGEX ]]; then
            continue
        elif [[ "$CLEAN_INSTALL_SCOPE" == "full" \
               && "$removed" =~ $NVIDIA_AUXILIARY_REGEX ]]; then
            continue
        elif [[ "$removed" =~ ^(cuda-keyring|cuda-repo-|nvidia-driver-local-repo-) ]]; then
            continue
        else
            unexpected+=("$removed")
        fi
    done < <(parse_removed_packages <"$simulation_file")

    if ((${#unexpected[@]})); then
        cp "$simulation_file" "$BACKUP_DIR/unsafe-unexpected-removals.txt"
        printf '%s\n' "${unexpected[@]}" >"$BACKUP_DIR/unexpected-removals.txt"
        die "APT würde zusätzliche, nicht zum NVIDIA-Stack gehörende Pakete entfernen: ${unexpected[*]}. Details: $BACKUP_DIR/unsafe-unexpected-removals.txt"
    fi
}

purge_packages_safely() {
    local label="$1"
    shift
    local packages=("$@")
    local sim

    ((${#packages[@]})) || return 0
    sim="$(mktemp "$TMP_DIR/purge.XXXXXX")"

    # Nochmals unmittelbar vor jeder Purge-Transaktion prüfen. Damit werden
    # auch nach dem Preflight neu gesetzte Holds und Pakete mit Architektur-
    # Suffix (z. B. libnvoptix1:amd64) zuverlässig behandelt.
    release_and_verify_package_holds "${packages[@]}"

    log "Simuliere Bereinigung: $label"
    apt-get -s purge "${packages[@]}" >"$sim"
    assert_clean_purge_plan "$sim" "${packages[@]}"
    assert_no_critical_removals "$sim"
    assert_no_unexpected_removals "$sim" "${packages[@]}"
    cp "$sim" "$BACKUP_DIR/purge-simulation-${label// /_}.txt"

    log "Entferne: ${packages[*]}"
    DEBIAN_FRONTEND=noninteractive apt_mutate purge -y "${packages[@]}"
    rm -f "$sim"
}

remove_runfile_installation
if [[ "$MODE" == "host" ]] && command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet nvidia-persistenced.service 2>/dev/null; then
        NVIDIA_PERSISTENCED_WAS_ACTIVE=1
    fi
    systemctl stop nvidia-persistenced.service 2>/dev/null || true
fi

# Eine einzige Paketmenge verhindert Zwischenzustände, in denen CUDA-/Treiber-
# Metapakete die gerade entfernten alten Bibliotheken erneut anfordern.
write_transaction_phase altbestand-entfernen
purge_packages_safely "gesamter-nvidia-altbestand" "${CLEAN_REMOVE_PACKAGES[@]}"
# Kein allgemeines apt -f install/dpkg --configure -a zwischen Purge und
# Neuinstallation: zuerst den vollständig geprüften Zielstack einspielen.

# Eine Reparatur kann bei ungewöhnlichen Abhängigkeiten erneut NVIDIA-Pakete
# eingespielt haben. Vor der Neuinstallation wird deshalb nochmals kontrolliert.
mapfile -t REMAINING_NVIDIA_PACKAGES < <(
    {
        get_installed_nvidia_driver_packages
        get_installed_auxiliary_nvidia_packages
        get_installed_repo_packages | grep -Ev '^cuda-keyring(:.*)?$' || true
    } | sort -u
)
if ((${#REMAINING_NVIDIA_PACKAGES[@]})); then
    warn "Nach dem Purge sind noch NVIDIA-Reste vorhanden; kontrollierter zweiter Bereinigungsdurchlauf."
    purge_packages_safely "nvidia-restpakete" "${REMAINING_NVIDIA_PACKAGES[@]}"
fi

# Bekannter Altfehler bei früheren Debian/NVIDIA-Paketen.
if dpkg-query -W -f='${db:Status-Abbrev}' glx-diversions 2>/dev/null | grep -qv '^un'; then
    if dpkg-query -W -f='${db:Status-Abbrev}' nvidia-alternative 2>/dev/null | grep -qv '^un'; then
        warn "Alte glx-diversions/nvidia-alternative-Kombination gefunden; bereinige sie."
        purge_packages_safely "alte-glx-diversions" glx-diversions nvidia-alternative
    fi
fi

# Nur Pakete entfernen, die erst durch die NVIDIA-Bereinigung neu verwaist wurden.
is_in_baseline() {
    local needle="$1"
    local item
    for item in "${BASELINE_AUTOREMOVE[@]}"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

cleanup_new_orphans() {
    local round
    local candidates=()
    local candidate
    local filtered=()
    local sim

    for round in 1 2 3; do
        mapfile -t candidates < <(get_autoremove_candidates)
        filtered=()
        for candidate in "${candidates[@]}"; do
            [[ -n "$candidate" ]] || continue
            is_in_baseline "$candidate" && continue
            filtered+=("$candidate")
        done

        ((${#filtered[@]})) || break

        sim="$(mktemp "$TMP_DIR/orphan-purge.XXXXXX")"
        apt-get -s purge "${filtered[@]}" >"$sim"
        assert_no_critical_removals "$sim"
        cp "$sim" "$BACKUP_DIR/orphan-cleanup-round-${round}.txt"
        rm -f "$sim"

        log "Entferne neu entstandene verwaiste Abhängigkeiten (Runde $round): ${filtered[*]}"
        DEBIAN_FRONTEND=noninteractive apt_mutate purge -y "${filtered[@]}"
    done
}
# Verwaiste Abhängigkeiten erst NACH der Neuinstallation bereinigen. Sonst
# entfernt autoremove auch Bibliotheken, die der vorab geprüfte Plan benötigt.

# Alte, nicht mehr paketverwaltete Pins entfernen; der soeben installierte
# exakte NVIDIA-Pin bleibt dadurch zwingend erhalten.
remove_obsolete_nvidia_pin_files

# Host und LXC beginnen anschließend beide von einer nachweislich sauberen
# NVIDIA-Treiber-/Userspace-Basis. Paketverwaltete Reste werden per purge
# entfernt; unverwaltete Altdateien werden vollständig gesichert und danach
# gelöscht. Beim Umfang "full" wurden CUDA-/Container-Pakete ebenfalls
# entfernt und liegen bereits als exakt verifizierte lokale DEBs zur
# Wiederinstallation bereit. Aktive LXC-Zuweisungen bleiben erhalten.
mapfile -t REMAINING_BEFORE_CLEAN_INSTALL < <(
    {
        get_installed_nvidia_driver_packages
        get_installed_auxiliary_nvidia_packages
        get_installed_repo_packages | grep -Ev '^cuda-keyring(:.*)?$' || true
    } | sort -u
)
((${#REMAINING_BEFORE_CLEAN_INSTALL[@]} == 0)) \
    || die "Vor der Neuinstallation sind weiterhin alte NVIDIA-/CUDA-/Repository-Pakete vorhanden: ${REMAINING_BEFORE_CLEAN_INSTALL[*]}"
quarantine_legacy_nvidia_residuals
find /var/lib/dkms -depth -type d -iname 'nvidia*' -empty -delete 2>/dev/null || true
find /usr/src -depth -type d -iname 'nvidia-*' -empty -delete 2>/dev/null || true
{
    printf 'Rolle: %s\n' "$MODE"
    printf 'Alte NVIDIA-Treiber-/Userspace-Pakete: 0\n'
    printf 'Quarantänisierte unverwaltete Dateien: %s\n' \
        "$(wc -l <"$BACKUP_DIR/legacy-residuals.txt")"
    if [[ "$CLEAN_INSTALL_SCOPE" == "full" ]]; then
        printf 'Zusatzstack: CUDA-/Container-Pakete vollständig entfernt und für exakte Neuinstallation vorgemerkt\n'
    else
        printf 'Bewusst erhalten: CUDA-Toolkit, libnvidia-container und aktive LXC-Gerätezuweisungen\n'
    fi
} >"$BACKUP_DIR/clean-install-baseline.txt"
LEGACY_ARCHIVE_STATUS="nicht erforderlich"
[[ ! -f "$BACKUP_DIR/legacy-residuals.tar" ]] || LEGACY_ARCHIVE_STATUS="legacy-residuals.tar"
{
    printf 'Quarantänisierte NVIDIA-Altdateien: %s\n' \
        "$(wc -l <"$BACKUP_DIR/legacy-residuals.txt")"
    printf 'Altdatei-Archiv: %s\n' "$LEGACY_ARCHIVE_STATUS"
} >>"$BACKUP_DIR/rollback-manifest.txt"
refresh_backup_checksums
ok "Saubere NVIDIA-Neuinstallationsbasis für $MODE geprüft."
write_transaction_phase zielstack-installieren
# Die Modellkopie hat nur die Vorprüfung ermöglicht. Unmittelbar vor der
# Installation nochmals gegen die echte, jetzt bereinigte Paketdatenbank prüfen.
CLEAN_APT_OPTIONS=()
simulate_clean_target "$BACKUP_DIR/install-simulation-after-purge.txt" \
    "${EXACT_DRIVER_PACKAGE_SPECS[@]}" "${AUXILIARY_REINSTALL_DEBS[@]}"

# ---------------------------- Host-Installation -------------------------------
if [[ "$MODE" == "host" ]]; then
    if ! lspci -nn | grep -qiE 'NVIDIA.*(VGA|3D|Display)|((VGA|3D|Display).*)NVIDIA'; then
        warn "Keine NVIDIA-GPU über lspci erkannt. Die Installation wird trotzdem fortgesetzt."
    fi

    cat >/etc/modprobe.d/blacklist-nouveau.conf <<'EOF_NOUVEAU'
# Erstellt durch nvidia-driver-setup-v2.13.3.sh
blacklist nouveau
options nouveau modeset=0
EOF_NOUVEAU

    systemctl stop nvidia-persistenced.service 2>/dev/null || true

    log "Installiere Compute-only-Treiber und Laufzeitbibliotheken exakt als ${COMMON_DRIVER_DEBIAN_VERSION}: ${PREFLIGHT_DRIVER_PACKAGES[*]}"
    install_clean_target_stack

    dpkg_mutate --configure -a

    # Das Paket-Trigger-Skript aktualisiert bereits das relevante initramfs.
    # Hier nur den aktuell laufenden Kernel aktualisieren, statt alle alten
    # installierten Kernel erneut zu verarbeiten.
    RUNNING_KERNEL="$(uname -r)"
    update-initramfs -u -k "$RUNNING_KERNEL"

    # DKMS-Ausgabe zuerst in eine Datei schreiben. Eine direkte Pipeline mit
    # grep -q kann zusammen mit `set -o pipefail` fälschlich als Fehler gelten,
    # wenn der Produzent der Pipeline vorzeitig mit SIGPIPE beendet wird.
    DKMS_STATUS_FILE="$BACKUP_DIR/dkms-status-after.txt"
    dkms status >"$DKMS_STATUS_FILE" 2>&1 || true

    DKMS_RUNNING_STATUS="$(
        dkms status -m nvidia -v "$TARGET_VERSION" -k "$RUNNING_KERNEL" 2>&1 || true
    )"
    printf '%s\n' "$DKMS_RUNNING_STATUS" >"$BACKUP_DIR/dkms-running-kernel.txt"

    if [[ "$DKMS_RUNNING_STATUS" != *": installed"* ]] && ((AUTOMATIC_REPAIR)); then
        warn "DKMS ist für den laufenden Kernel noch nicht vollständig installiert; starte einen automatischen DKMS-Reparaturversuch."
        dkms autoinstall -k "$RUNNING_KERNEL" >"$BACKUP_DIR/dkms-auto-repair.txt" 2>&1 || true
        command -v depmod >/dev/null 2>&1 && depmod -a "$RUNNING_KERNEL" || true
        DKMS_RUNNING_STATUS="$(dkms status -m nvidia -v "$TARGET_VERSION" -k "$RUNNING_KERNEL" 2>&1 || true)"
        printf '%s\n' "$DKMS_RUNNING_STATUS" >"$BACKUP_DIR/dkms-running-kernel-after-auto-repair.txt"
    fi
    if [[ "$DKMS_RUNNING_STATUS" != *": installed"* ]]; then
        capture_nvidia_diagnostic_bundle dkms-fehler
        die "Das NVIDIA-DKMS-Modul $TARGET_VERSION ist für den laufenden Kernel $RUNNING_KERNEL nicht als installiert registriert. Siehe $BACKUP_DIR/dkms-running-kernel.txt und $DKMS_STATUS_FILE"
    fi

    MODULE_VERSION="$(modinfo -F version -k "$RUNNING_KERNEL" nvidia 2>/dev/null | head -n1 || true)"
    if [[ "$MODULE_VERSION" != "$TARGET_VERSION" ]] && ((AUTOMATIC_REPAIR)); then
        warn "Die NVIDIA-Moduldatei hat noch nicht den Zielstand; aktualisiere Modulabhängigkeiten und initramfs erneut."
        command -v depmod >/dev/null 2>&1 && depmod -a "$RUNNING_KERNEL" || true
        update-initramfs -u -k "$RUNNING_KERNEL" >"$BACKUP_DIR/initramfs-auto-repair.txt" 2>&1 || true
        MODULE_VERSION="$(modinfo -F version -k "$RUNNING_KERNEL" nvidia 2>/dev/null | head -n1 || true)"
    fi
    if [[ "$MODULE_VERSION" != "$TARGET_VERSION" ]]; then
        capture_nvidia_diagnostic_bundle modulversion-fehler
        die "Das NVIDIA-Modul für $RUNNING_KERNEL hat Version '${MODULE_VERSION:-nicht gefunden}', erwartet wurde $TARGET_VERSION."
    fi

    ok "DKMS-Modul $TARGET_VERSION für $RUNNING_KERNEL installiert."

    : >"$BACKUP_DIR/other-kernel-module-check.txt"
    for module_dir in /lib/modules/*; do
        [[ -d "$module_dir" ]] || continue
        kernel="${module_dir##*/}"
        [[ "$kernel" != "$RUNNING_KERNEL" ]] || continue
        [[ -e "/boot/vmlinuz-${kernel}" ]] || continue
        module_version="$(modinfo -F version -k "$kernel" nvidia 2>/dev/null | head -n1 || true)"
        printf '%s\t%s\n' "$kernel" "${module_version:-nicht gefunden}" \
            >>"$BACKUP_DIR/other-kernel-module-check.txt"
        if [[ "$module_version" != "$TARGET_VERSION" ]]; then
            warn "Für den zusätzlich installierten Kernel $kernel wurde kein NVIDIA-Modul $TARGET_VERSION gefunden. Boote bis zur Klärung weiterhin $RUNNING_KERNEL."
        fi
    done

    ok "Host-Treiber installiert."
    log "Der Neustartbedarf wird anhand von geladenem Modul und installierter Version ermittelt."

# ----------------------------- LXC-Installation -------------------------------
else
    # Im LXC darf kein DKMS-/Kernelmodul installiert sein.
    mapfile -t WRONG_LXC_PACKAGES < <(
        dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null \
            | awk '$2 !~ /^un/ {print $1}' \
            | grep -E "$LXC_FORBIDDEN_PACKAGE_REGEX" \
            | sort -u \
            || true
    )
    if ((${#WRONG_LXC_PACKAGES[@]})); then
        purge_packages_safely "falsche-lxc-kernelpakete" "${WRONG_LXC_PACKAGES[@]}"
    fi

    LXC_USERSPACE_PACKAGES=("${PROFILE_USERSPACE_PACKAGES[@]}")
    log "Installiere ausschließlich NVIDIA-Userspace-Bibliotheken und Werkzeuge im LXC: ${LXC_USERSPACE_PACKAGES[*]}"
    install_clean_target_stack
    install_debian_lxc_nvidia_smi_payload_if_needed
    ldconfig

    [[ ! -e /lib/modules/"$(uname -r)"/build ]] \
        || warn "Im LXC ist ein Kernel-Build-Verzeichnis sichtbar. Das Skript hat trotzdem kein DKMS installiert."
fi

reinstall_auxiliary_nvidia_stack() {
    local package expected actual status verify_file
    ((${#AUXILIARY_REINSTALL_DEBS[@]})) || return 0
    log "Prüfe den gemeinsam mit dem Treiber frisch installierten NVIDIA-/CUDA-/Container-Zusatzstack ..."
    dpkg_mutate --configure -a
    : >"$BACKUP_DIR/auxiliary-package-integrity-after.txt"
    while IFS=$'\t' read -r package expected; do
        [[ -n "$package" && -n "$expected" ]] || continue
        if [[ "$MODE" == "lxc" && "$package" =~ $LXC_FORBIDDEN_PACKAGE_REGEX ]]; then
            continue
        fi
        actual="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
        status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null || true)"
        dpkg_status_is_healthy_installed "$status" \
            || die "Zusatzpaket $package ist nach der Neuinstallation nicht vollständig installiert."
        debian_versions_equal "$actual" "$expected" \
            || die "Zusatzpaket $package hat '$actual', erwartet wurde exakt '$expected'."
        verify_file="$BACKUP_DIR/auxiliary-verify-${package//[:\/]/_}.txt"
        if ! dpkg -V "$package" >"$verify_file" 2>&1 || [[ -s "$verify_file" ]]; then
            cat "$verify_file" >>"$BACKUP_DIR/auxiliary-package-integrity-after.txt"
            die "Zusatzpaket $package weicht direkt nach der sauberen Neuinstallation von seinem verifizierten Original-DEB ab. Details: $verify_file"
        fi
        rm -f -- "$verify_file"
    done <"$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv"
    ok "Optionaler NVIDIA-/CUDA-/Container-Zusatzstack vollständig in den vorgesehenen exakten Versionen neu installiert."
}

reinstall_auxiliary_nvidia_stack
run_automatic_postinstall_repair

# ------------------------------ Abschlussprüfung ------------------------------
verify_package_version() {
    local package="$1"
    local installed status normalized expected=""
    installed="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
    status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null || true)"
    normalized="$(normalize_driver_version "$installed")"

    dpkg_status_is_healthy_installed "$status" \
        || die "$package ist nicht vollständig installiert (Status: ${status:-nicht vorhanden})."
    expected="${EXPECTED_PACKAGE_VERSIONS[$package]:-}"
    if [[ -n "$expected" ]]; then
        debian_versions_equal "$installed" "$expected" \
            || die "$package hat DEB-Version '${installed:-nicht installiert}', erwartet exakt '$expected'."
    else
        [[ "$normalized" == "$TARGET_VERSION" ]] \
            || die "$package hat Version '${installed:-nicht installiert}', erwartet Treiberstand $TARGET_VERSION."
    fi
    ok "$package: $installed"
}

verify_package_installed() {
    local package="$1" expected="${2:-}" status version
    status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null || true)"
    version="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
    dpkg_status_is_healthy_installed "$status" \
        || die "$package ist nicht vollständig installiert (Status: ${status:-nicht vorhanden})."
    if [[ -n "$expected" ]]; then
        debian_versions_equal "$version" "$expected" \
            || die "$package hat DEB-Version '${version:-nicht installiert}', erwartet exakt '$expected'."
    fi
    ok "$package: $version"
}

verify_debian_lxc_nvidia_smi_payload() {
    local owner metadata=/var/lib/nvidia-driver-setup/lxc-nvidia-smi-payload.env
    local recorded_version recorded_hash actual_hash

    [[ "$MODE" == "lxc" && "$DISTRO" == "debian13" ]] || return 0
    [[ -x /usr/bin/nvidia-smi ]] \
        || die "Die echte nvidia-smi-Binärdatei fehlt trotz erfolgreicher Debian-13-Paketinstallation."
    owner="$(dpkg-query -S /usr/bin/nvidia-smi 2>/dev/null | head -n1 || true)"
    if [[ -n "$owner" ]]; then
        ok "nvidia-smi wird direkt von einem installierten DEB bereitgestellt: ${owner%%:*}"
        return 0
    fi
    [[ -r "$metadata" ]] \
        || die "Die unpaketierte nvidia-smi-Datei besitzt keinen prüfbaren Herkunftsnachweis."
    recorded_version="$(awk -F= '$1 == "SOURCE_VERSION" {print $2; exit}' "$metadata")"
    recorded_hash="$(awk -F= '$1 == "PAYLOAD_SHA256" {print $2; exit}' "$metadata")"
    actual_hash="$(sha256sum /usr/bin/nvidia-smi | awk '{print $1}')"
    debian_versions_equal "$recorded_version" "$LXC_SMI_PAYLOAD_VERSION" \
        || die "Der installierte nvidia-smi-Payload stammt aus '$recorded_version', erwartet wurde exakt '$LXC_SMI_PAYLOAD_VERSION'."
    [[ "$recorded_hash" =~ ^[0-9a-fA-F]{64}$ && "$actual_hash" == "$recorded_hash" ]] \
        || die "Die nvidia-smi-Binärdatei stimmt nicht mit ihrem offiziellen Payload-Prüfnachweis überein."
    ok "nvidia-smi-Payload: $LXC_SMI_PAYLOAD_VERSION, Prüfsumme und Herkunft verifiziert"
}

printf '\n'
log "Prüfe installierte NVIDIA-Komponenten ..."
if [[ -n "${PIN_PACKAGE:-}" ]]; then
    verify_package_installed "$PIN_PACKAGE" "$PIN_DEBIAN_VERSION"
elif [[ -n "${TEMPORARY_VERSION_PREFERENCE:-}" ]]; then
    [[ -s "$TEMPORARY_VERSION_PREFERENCE" ]] \
        || die "Die temporäre APT-Versionspräferenz fehlt vor der Abschlussprüfung."
    ok "Transaktionale APT-Versionspräferenz war bis zur Paketprüfung aktiv."
fi
for package in "${VERIFY_USERSPACE_PACKAGES[@]}"; do
    verify_package_version "$package"
done
for package in "${VERIFY_OPTIONAL_DRIVER_PACKAGES[@]}"; do
    verify_package_version "$package"
done
verify_all_installed_nvidia_driver_versions

if [[ "$MODE" == "host" ]]; then
    for package in "${VERIFY_HOST_PACKAGES[@]}"; do
        verify_package_version "$package"
    done
else
    verify_debian_lxc_nvidia_smi_payload
    mapfile -t FORBIDDEN_LXC_KERNEL_PACKAGES < <(
        dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null \
            | awk '$2 !~ /^un/ {print $1}' \
            | grep -E "$LXC_FORBIDDEN_PACKAGE_REGEX" \
            | sort -u \
            || true
    )
    if ((${#FORBIDDEN_LXC_KERNEL_PACKAGES[@]})); then
        printf '%s\n' "${FORBIDDEN_LXC_KERNEL_PACKAGES[@]}" \
            >"$BACKUP_DIR/forbidden-lxc-packages.txt"
        die "Im LXC sind weiterhin unzulässige NVIDIA-Kernel-/DKMS-/Host-Hilfspakete installiert: ${FORBIDDEN_LXC_KERNEL_PACKAGES[*]}"
    fi
fi

}

apply_nvidia_version_binding() {
    local package installed status
    local -a bind_packages=()
    ((PIN_NVIDIA_PACKAGES)) || return 0
    if ((UPDATE_ONLY)) && ((${#NVIDIA_UPDATE_SPECS[@]})); then
        for package in "${NVIDIA_UPDATE_SPECS[@]}"; do append_unique bind_packages "${package%%=*}"; done
        apt_mark_mutate hold "${bind_packages[@]}"
        list_apt_holds >"$BACKUP_DIR/nvidia-packages-held-after.txt"
        for package in "${bind_packages[@]}"; do
            grep -qxF "$package" "$BACKUP_DIR/nvidia-packages-held-after.txt" \
                || grep -qxF "${package%%:*}" "$BACKUP_DIR/nvidia-packages-held-after.txt" \
                || die "Versionsbindung fehlgeschlagen: $package ist nicht gehalten."
        done
        ok "Alle geplanten NVIDIA-/CUDA-/Container-Pakete sind exakt gepinnt und gehalten."
        return 0
    fi
    while IFS=$'\t' read -r package installed; do
        [[ -n "$package" && "$(normalize_driver_version "$installed")" == "$TARGET_VERSION" ]] \
            && append_unique bind_packages "$package"
    done < <(
        dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' 2>/dev/null \
            | awk -F'\t' -v re="$NVIDIA_DRIVER_REGEX" 'substr($3, 2, 1) == "i" && substr($3, 3, 1) != "R" && $1 ~ re {print $1 "\t" $2}'
    )
    if [[ -r "$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv" ]]; then
        while IFS=$'\t' read -r package installed; do
            [[ "$package" =~ $NVIDIA_OPTIONAL_DRIVER_REGEX ]] || continue
            status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null || true)"
            dpkg_status_is_healthy_installed "$status" && append_unique bind_packages "$package"
        done <"$BACKUP_DIR/auxiliary-nvidia-package-versions.tsv"
    fi
    [[ -z "${PIN_PACKAGE:-}" ]] || append_unique bind_packages "$PIN_PACKAGE"
    ((${#bind_packages[@]})) || return 0
    apt_mark_mutate hold "${bind_packages[@]}"
    printf '%s\n' "${bind_packages[@]}" >"$BACKUP_DIR/nvidia-packages-held-after.txt"
    ok "NVIDIA-Pakete wurden auf der geprüften DEB-Version $COMMON_DRIVER_DEBIAN_VERSION gehalten."
}

remove_temporary_version_pin() {
    if [[ -n "${TEMPORARY_VERSION_PREFERENCE:-}" ]]; then
        case "$TEMPORARY_VERSION_PREFERENCE" in
            /etc/apt/preferences.d/nvidia-driver-setup-transaction.pref)
                rm -f -- "$TEMPORARY_VERSION_PREFERENCE"
                ok "Temporäre APT-Versionspräferenz entfernt."
                TEMPORARY_VERSION_PREFERENCE=""
                ;;
            *) die "Unsicherer temporärer APT-Pin-Pfad: $TEMPORARY_VERSION_PREFERENCE" ;;
        esac
    fi
    ((PIN_NVIDIA_PACKAGES == 0)) || return 0
    [[ -n "${PIN_PACKAGE:-}" ]] || return 0
    if dpkg-query -W -f='${db:Status-Abbrev}' "$PIN_PACKAGE" 2>/dev/null \
        | grep -qE '^.i([^R]|$)'; then
        log "Entferne das nur für die Transaktion benötigte NVIDIA-Pinning-Paket."
        DEBIAN_FRONTEND=noninteractive apt_mutate purge -y "$PIN_PACKAGE"
    fi
}

write_shell_array_assignment() {
    local file="$1" name="$2"
    shift 2
    {
        printf '%s=(' "$name"
        printf ' %q' "$@"
        printf ' )\n'
    } >>"$file"
}

# ------------------------- LXC-Gerätefreigabe --------------------------------
lxc_sync_log_has_native_hotplug_collision() {
    local sync_log="$1"
    [[ -r "$sync_log" ]] \
        && grep -qE 'unable to hotplug dev[0-9]+: failed to mknod .+: File exists' "$sync_log"
}

print_lxc_device_sync_log_excerpt() {
    local sync_log="$1"
    [[ -r "$sync_log" ]] || return 0
    warn "Auszug aus der Proxmox-Gerätesynchronisation:"
    tail -n 20 "$sync_log" | sed 's/^/  | /' >&2 || true
}

run_lxc_device_sync_with_recovery() {
    local helper="$1" sync_log="$2" helper_rc=0 state

    if "$helper" >"$sync_log" 2>&1; then
        return 0
    else
        helper_rc=$?
    fi
    ((helper_rc != 75)) || return 75

    if [[ "$LXC_DEVICE_BACKEND" == "native" ]] \
       && lxc_sync_log_has_native_hotplug_collision "$sync_log"; then
        state="$(lxc_current_state 2>/dev/null || true)"
        if [[ "$state" != "running" ]]; then
            return "$helper_rc"
        fi
        if ((LXC_RESTART_RUNNING_ALLOWED == 0)); then
            return 76
        fi

        warn "Proxmox meldet einen vorhandenen nativen Passthrough-Knoten. Konfiguriere die Geräte während des bereits freigegebenen kontrollierten LXC-Neustarts offline."
        if [[ "$LXC_ORIGINAL_STATE" != "running" && "$LXC_ORIGINAL_STATE" != "stopped" ]]; then
            LXC_ORIGINAL_STATE="$state"
        fi
        LXC_RUNTIME_TOUCHED=1
        record_lxc_runtime_state || return 1
        {
            printf '[nvidia-lxc-sync] Hotplug-Kollision erkannt; kontrollierter Offline-Wiederholungsversuch.\n'
            shutdown_lxc_controlled
        } >>"$sync_log" 2>&1 || return 1

        if "$helper" >>"$sync_log" 2>&1; then
            :
        else
            helper_rc=$?
            return "$helper_rc"
        fi
        {
            pct start "$TARGET_LXC_ID"
            wait_for_lxc_exec
        } >>"$sync_log" 2>&1 || return 1
        LXC_DEVICE_SYNC_RESTART_DONE=1
        record_lxc_runtime_state || return 1
        ok "Native NVIDIA-Geräte nach kontrolliertem Offline-Neustart kollisionsfrei synchronisiert."
        return 0
    fi
    return "$helper_rc"
}

configure_nvidia_lxc_passthrough() {
    local ctid="$TARGET_LXC_ID"
    local helper="/usr/local/sbin/nvidia-lxc-device-sync-${ctid}.sh"
    local service="nvidia-lxc-device-sync-${ctid}.service"
    local pct_help=""
    local helper_rc=0

    ((CONFIGURE_LXC_GPU)) || return 0
    validate_lxc_target

    pct_help="$(pct help set 2>&1 || true)"
    case "$LXC_DEVICE_BACKEND" in
        auto)
            if [[ "$pct_help" == *'--dev[n]'* ]]; then
                LXC_DEVICE_BACKEND="native"
            else
                LXC_DEVICE_BACKEND="manual"
                warn "Native Proxmox-devN-Zuweisung fehlt; verwende den dynamisch erzeugten manuellen Fallback."
            fi
            ;;
        native)
            [[ "$pct_help" == *'--dev[n]'* ]] \
                || die "Der gewählte native devN-Backend wird von diesem Proxmox-Stand nicht unterstützt."
            ;;
        manual) ;;
    esac
    log "LXC-Gerätebackend: $LXC_DEVICE_BACKEND"

    begin_config_mutation
    cat >/etc/modules-load.d/nvidia-lxc.conf <<'EOF_NVIDIA_LXC_MODULES'
# NVIDIA-Geräte für Proxmox-LXC-Compute/Transcoding
nvidia
nvidia_uvm
EOF_NVIDIA_LXC_MODULES

    cat >"$helper" <<EOF_SYNC_HEAD
#!/usr/bin/env bash
set -Eeuo pipefail
CTID="$ctid"
BACKEND="$LXC_DEVICE_BACKEND"
DEVICE_MODE="$LXC_DEVICE_MODE"
DEVICE_UID="$LXC_DEVICE_UID"
DEVICE_GID="$LXC_DEVICE_GID"
CONFIG_FILE="/etc/pve/lxc/${ctid}.conf"
MANAGED_STATE="/var/lib/nvidia-lxc-device-sync/${ctid}.devices"
EOF_SYNC_HEAD
    write_shell_array_assignment "$helper" GPU_FALLBACKS "${TARGET_GPU_DEVICES[@]}"
    write_shell_array_assignment "$helper" GPU_UUIDS "${TARGET_GPU_UUIDS[@]}"
    write_shell_array_assignment "$helper" GPU_BUS_IDS "${TARGET_GPU_BUS_IDS[@]}"

    cat >>"$helper" <<'EOF_SYNC_BODY'
log() { printf '[nvidia-lxc-sync] %s\n' "$*"; }

[[ -f "$CONFIG_FILE" ]] || { log "LXC-Konfiguration fehlt: $CONFIG_FILE"; exit 1; }
if [[ "$BACKEND" == "native" ]]; then
    command -v pct >/dev/null 2>&1 || { log "pct wurde nicht gefunden."; exit 1; }
fi

# Device-Nodes erzeugen, sofern der Treiber bereits geladen werden kann.
modprobe nvidia >/dev/null 2>&1 || true
modprobe nvidia_uvm >/dev/null 2>&1 || true
if command -v nvidia-modprobe >/dev/null 2>&1; then
    nvidia-modprobe -u -c=0 >/dev/null 2>&1 || true
fi

normalize_bus() {
    local value="${1^^}"
    [[ "$value" =~ ^[0-9A-F]{8}: ]] && value="${value:4}"
    printf '%s' "$value"
}

append_unique_device() {
    local value="$1" existing
    for existing in "${GPU_DEVICES[@]:-}"; do
        [[ "$existing" == "$value" ]] && return 0
    done
    GPU_DEVICES+=("$value")
}

nvidia_smi_query() {
    if [[ "${NVIDIA_LXC_TEST_ALLOW_REGULAR:-0}" == "1" ]] \
       && command -v nvidia_smi_test >/dev/null 2>&1; then
        nvidia_smi_test "$@"
    else
        command nvidia-smi "$@"
    fi
}

GPU_QUERY=""
if command -v nvidia-smi >/dev/null 2>&1 \
   || { [[ "${NVIDIA_LXC_TEST_ALLOW_REGULAR:-0}" == "1" ]] \
        && command -v nvidia_smi_test >/dev/null 2>&1; }; then
    GPU_QUERY="$(nvidia_smi_query --query-gpu=index,uuid,pci.bus_id --format=csv,noheader 2>/dev/null || true)"
fi
GPU_DEVICES=()
for ((selection=0; selection<${#GPU_FALLBACKS[@]}; selection++)); do
    fallback="${GPU_FALLBACKS[$selection]}"
    wanted_uuid="${GPU_UUIDS[$selection]:-}"
    wanted_bus="$(normalize_bus "${GPU_BUS_IDS[$selection]:-}")"
    resolved=""
    while IFS=',' read -r index uuid bus; do
        index="${index//[[:space:]]/}"
        uuid="${uuid//[[:space:]]/}"
        bus="$(normalize_bus "${bus//[[:space:]]/}")"
        [[ "$index" =~ ^[0-9]+$ ]] || continue
        if [[ -n "$wanted_uuid" && "$uuid" == "$wanted_uuid" ]] \
           || [[ -z "$wanted_uuid" && -n "$wanted_bus" && "$bus" == "$wanted_bus" ]]; then
            resolved="/dev/nvidia${index}"
            break
        fi
    done <<<"$GPU_QUERY"
    append_unique_device "${resolved:-$fallback}"
done

device_exists() {
    [[ -c "$1" ]] || [[ "${NVIDIA_LXC_TEST_ALLOW_REGULAR:-0}" == "1" ]]
}

all_required_nodes_exist() {
    local path
    device_exists /dev/nvidiactl && device_exists /dev/nvidia-uvm || return 1
    for path in "${GPU_DEVICES[@]}"; do
        device_exists "$path" || return 1
    done
}

# Bei einem gerade erfolgten Treiberwechsel sind die neuen Nodes eventuell erst
# nach dem Host-Neustart verfügbar. Beim Boot wartet der Dienst kurz auf udev.
for _ in $(seq 1 60); do
    all_required_nodes_exist && break
    [[ "${NVIDIA_LXC_TEST_ALLOW_REGULAR:-0}" == "1" ]] && break
    sleep 1
done

for required in "${GPU_DEVICES[@]}" /dev/nvidiactl /dev/nvidia-uvm; do
    device_exists "$required" || { log "Benötigtes Gerät fehlt: $required"; exit 75; }
done

slots_for_path() {
    pct config "$CTID" 2>/dev/null | awk -F': ' -v wanted="$1" '
        $1 ~ /^dev[0-9]+$/ {
            count = split($2, fields, ",")
            for (i = 1; i <= count; i++) {
                if (fields[i] == wanted || fields[i] == "path=" wanted) {
                    slot = $1
                    sub(/^dev/, "", slot)
                    print slot
                    break
                }
            }
        }
    '
}

next_free_slot() {
    local config slot
    config="$(pct config "$CTID" 2>/dev/null)"
    for ((slot=0; slot<=255; slot++)); do
        if ! grep -qE "^dev${slot}:" <<<"$config"; then
            printf '%s' "$slot"
            return 0
        fi
    done
    return 1
}

device_spec() {
    local path="$1" spec="$path"
    [[ "$DEVICE_MODE" == "inherit" ]] || spec+=",mode=${DEVICE_MODE}"
    [[ -n "$DEVICE_UID" ]] && spec+=",uid=${DEVICE_UID}"
    [[ -n "$DEVICE_GID" ]] && spec+=",gid=${DEVICE_GID}"
    printf '%s' "$spec"
}

path_is_desired() {
    local wanted="$1" path
    for path in "${DESIRED_DEVICES[@]}"; do
        [[ "$path" == "$wanted" ]] && return 0
    done
    return 1
}

remove_path_entries() {
    local path="$1" slot
    while IFS= read -r slot; do
        [[ "$slot" =~ ^[0-9]+$ ]] || continue
        log "Entferne veralteten verwalteten Eintrag dev${slot}: $path"
        pct set "$CTID" --delete "dev${slot}"
    done < <(slots_for_path "$path")
}

ensure_device() {
    local path="$1" slot keep="" spec
    local -a slots=()
    device_exists "$path" || return 0
    mapfile -t slots < <(slots_for_path "$path")
    if ((${#slots[@]})); then
        keep="${slots[0]}"
    else
        keep="$(next_free_slot)" || { log "Kein freier devN-Slot."; exit 1; }
    fi
    spec="$(device_spec "$path")"
    log "Setze $path als dev${keep}: $spec"
    pct set "$CTID" "--dev${keep}" "$spec"
    for slot in "${slots[@]:1}"; do
        log "Entferne doppelten Eintrag dev${slot}: $path"
        pct set "$CTID" --delete "dev${slot}"
    done
}

DESIRED_DEVICES=("${GPU_DEVICES[@]}" /dev/nvidiactl /dev/nvidia-uvm)
for optional in /dev/nvidia-uvm-tools; do
    device_exists "$optional" && DESIRED_DEVICES+=("$optional")
done

if [[ -d /dev/nvidia-caps ]]; then
    while IFS= read -r cap; do
        device_exists "$cap" && DESIRED_DEVICES+=("$cap")
    done < <(find /dev/nvidia-caps -maxdepth 1 -type c -name 'nvidia-cap*' -print 2>/dev/null | sort -V || true)
fi

if [[ "$BACKEND" == "manual" ]]; then
    begin_marker="# BEGIN NVIDIA-DRIVER-SETUP MANAGED DEVICES"
    end_marker="# END NVIDIA-DRIVER-SETUP MANAGED DEVICES"
    config_tmp="$(mktemp "${CONFIG_FILE}.nvidia.XXXXXX")"
    awk -v begin="$begin_marker" -v end="$end_marker" '
        $0 == begin { managed = 1; next }
        $0 == end { managed = 0; next }
        managed { next }
        /^dev[0-9]+:/ && /(^|[=:,[:space:]])(path=)?\/dev\/nvidia/ { next }
        /^lxc\.mount\.entry:[[:space:]]+\/dev\/nvidia/ { next }
        { print }
    ' "$CONFIG_FILE" >"$config_tmp"
    {
        printf '%s\n' "$begin_marker"
        printf '# Dynamisch erzeugt; angeforderte Sicht: mode=%s uid=%s gid=%s\n' \
            "$DEVICE_MODE" "${DEVICE_UID:-inherit}" "${DEVICE_GID:-inherit}"
        for path in "${DESIRED_DEVICES[@]}"; do
            if [[ "${NVIDIA_LXC_TEST_ALLOW_REGULAR:-0}" == "1" ]]; then
                major=195
                minor=0
            else
                major_hex="$(stat -Lc '%t' "$path")"
                minor_hex="$(stat -Lc '%T' "$path")"
                major=$((16#$major_hex))
                minor=$((16#$minor_hex))
            fi
            printf 'lxc.cgroup2.devices.allow: c %s:%s rwm\n' "$major" "$minor"
            printf 'lxc.mount.entry: %s %s none bind,optional,create=file 0 0\n' \
                "$path" "${path#/}"
        done
        printf '%s\n' "$end_marker"
    } >>"$config_tmp"
    chmod --reference="$CONFIG_FILE" "$config_tmp" 2>/dev/null || true
    chown --reference="$CONFIG_FILE" "$config_tmp" 2>/dev/null || true
    mv -f "$config_tmp" "$CONFIG_FILE"
    mkdir -p "$(dirname "$MANAGED_STATE")"
    printf '%s\n' "${DESIRED_DEVICES[@]}" >"${MANAGED_STATE}.tmp"
    mv -f "${MANAGED_STATE}.tmp" "$MANAGED_STATE"
    log "${#GPU_DEVICES[@]} GPU(s) über manuellen cgroup2/mount-Fallback für LXC $CTID synchronisiert."
    if [[ "$DEVICE_MODE" != "0666" || -n "$DEVICE_UID" || -n "$DEVICE_GID" ]]; then
        log "Hinweis: mode/uid/gid werden nur vom nativen Proxmox-devN-Backend isoliert umgesetzt; der Fallback übernimmt die Host-Geräterechte."
    fi
    exit 0
fi

# Bei nativer Zuordnung alte manuelle Blöcke entfernen, damit kein Gerät doppelt
# über devN und lxc.mount.entry eingebunden wird.
if grep -q '^# BEGIN NVIDIA-DRIVER-SETUP MANAGED DEVICES$' "$CONFIG_FILE"; then
    config_tmp="$(mktemp "${CONFIG_FILE}.nvidia.XXXXXX")"
    awk '
        /^# BEGIN NVIDIA-DRIVER-SETUP MANAGED DEVICES$/ { managed = 1; next }
        /^# END NVIDIA-DRIVER-SETUP MANAGED DEVICES$/ { managed = 0; next }
        !managed { print }
    ' "$CONFIG_FILE" >"$config_tmp"
    chmod --reference="$CONFIG_FILE" "$config_tmp" 2>/dev/null || true
    chown --reference="$CONFIG_FILE" "$config_tmp" 2>/dev/null || true
    mv -f "$config_tmp" "$CONFIG_FILE"
fi

if [[ -f "$MANAGED_STATE" ]]; then
    while IFS= read -r previous; do
        [[ -n "$previous" ]] || continue
        path_is_desired "$previous" || remove_path_entries "$previous"
    done <"$MANAGED_STATE"
else
    # Migration von älteren Skriptversionen ohne Statusdatei: alle nativen
    # NVIDIA-Einträge normalisieren. Gewünschte gemeinsame Geräte bleiben
    # erhalten, veraltete GPU- und modeset-Einträge werden entfernt.
    while IFS= read -r previous; do
        [[ -n "$previous" ]] || continue
        path_is_desired "$previous" || remove_path_entries "$previous"
    done < <(
        pct config "$CTID" 2>/dev/null | awk -F': ' '
            $1 ~ /^dev[0-9]+$/ {
                count = split($2, fields, ",")
                for (i = 1; i <= count; i++) {
                    if (fields[i] ~ /^(path=)?\/dev\/nvidia/) {
                        sub(/^path=/, "", fields[i])
                        print fields[i]
                    }
                }
            }
        ' | sort -u
    )
fi
for desired in "${DESIRED_DEVICES[@]}"; do
    ensure_device "$desired"
done
mkdir -p "$(dirname "$MANAGED_STATE")"
printf '%s\n' "${DESIRED_DEVICES[@]}" >"${MANAGED_STATE}.tmp"
mv -f "${MANAGED_STATE}.tmp" "$MANAGED_STATE"
log "${#GPU_DEVICES[@]} GPU(s) und gemeinsame NVIDIA-Geräte für LXC $CTID sind synchronisiert."
EOF_SYNC_BODY

    chmod 0755 "$helper"

    cat >"/etc/systemd/system/${service}" <<EOF_SYNC_SERVICE
[Unit]
Description=NVIDIA-Geräte an Proxmox-LXC $ctid durchreichen
After=systemd-modules-load.service pve-cluster.service
Before=pve-guests.service
Wants=pve-cluster.service
ConditionPathExists=/etc/pve/lxc/${ctid}.conf
StartLimitIntervalSec=300
StartLimitBurst=12

[Service]
Type=oneshot
ExecStart=$helper
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF_SYNC_SERVICE

    systemctl daemon-reload
    systemctl enable "$service" >/dev/null

    # Sofort versuchen. Fehlen die Nodes wegen des noch ausstehenden Host-
    # Neustarts, übernimmt der aktivierte Dienst automatisch beim nächsten Boot.
    helper_rc=0
    local sync_log="$BACKUP_DIR/lxc-${ctid}-gpu-sync-now.log"
    if run_lxc_device_sync_with_recovery "$helper" "$sync_log"; then
        LXC_GPU_CONFIGURED=1
        ok "NVIDIA-GPU-Freigabe für LXC $ctid ($TARGET_LXC_NAME) konfiguriert."
    else
        helper_rc=$?
        if ((helper_rc == 75)); then
            LXC_GPU_DEFERRED=1
            warn "Die NVIDIA-Geräte sind noch nicht vollständig verfügbar. Die LXC-Freigabe wird nach dem Host-Neustart automatisch eingerichtet."
            warn "Details: $sync_log"
        elif ((helper_rc == 76)); then
            print_lxc_device_sync_log_excerpt "$sync_log"
            die "Proxmox konnte die native GPU-Zuweisung im laufenden LXC wegen eines bereits vorhandenen Passthrough-Knotens nicht hotpluggen. Erlaube im Menü den kontrollierten LXC-Neustart und starte den Vorgang erneut."
        else
            print_lxc_device_sync_log_excerpt "$sync_log"
            die "Die LXC-Gerätekonfiguration ist mit Exit-Code $helper_rc fehlgeschlagen. Details: $sync_log"
        fi
    fi

    pct config "$ctid" >"$BACKUP_DIR/lxc-${ctid}.conf.after-current" 2>/dev/null || true
    {
        printf 'LXC: %s (%s)\n' "$ctid" "$TARGET_LXC_NAME"
        printf 'Ausgewählte GPUs: %s\n' "$TARGET_GPU_SELECTION_SUMMARY"
        printf 'GPU-UUIDs: %s\n' "$(join_by ', ' "${TARGET_GPU_UUIDS[@]}")"
        printf 'GPU-PCI-Bus-IDs: %s\n' "$(join_by ', ' "${TARGET_GPU_BUS_IDS[@]}")"
        printf 'Geräteberechtigung: mode=%s%s%s\n' "$LXC_DEVICE_MODE" \
            "${LXC_DEVICE_UID:+,uid=$LXC_DEVICE_UID}" "${LXC_DEVICE_GID:+,gid=$LXC_DEVICE_GID}"
        printf 'Backend: %s\n' "$LXC_DEVICE_BACKEND"
        printf 'LXC-Zustand vor Änderung: %s\n' \
            "$(awk -F'\t' -v id="$ctid" '$1 == id {print $2; exit}' "$BACKUP_DIR/lxc-states-before.tsv" 2>/dev/null || printf unbekannt)"
        printf 'Sync-Helfer: %s\n' "$helper"
        printf 'Systemd-Dienst: %s\n' "$service"
        printf 'Sofort konfiguriert: %s\n' "$LXC_GPU_CONFIGURED"
        printf 'Nach Neustart ausstehend: %s\n' "$LXC_GPU_DEFERRED"
    } >"$BACKUP_DIR/lxc-${ctid}-gpu-passthrough.txt"

    if [[ "$(pct status "$ctid" 2>/dev/null | awk '{print $2}')" == "running" ]]; then
        warn "LXC $ctid läuft. Neue Geräte werden erst nach dessen Neustart sichtbar."
    fi
    if ((ATTACH_ONLY)); then
        warn "Starte LXC $ctid neu, damit die neue Gerätefreigabe sichtbar wird."
    elif ((INSTALL_LXC_USERSPACE_FROM_HOST)); then
        log "Die exakt passenden NVIDIA-Bibliotheken werden im nächsten Schritt automatisch vom Host im LXC eingerichtet."
    else
        warn "Zuerst den Proxmox-Host neu starten und danach die identische NVIDIA-Version im LXC installieren."
    fi
}

resync_all_nvidia_lxc_devices() {
    local helper rc
    [[ "$MODE" == "host" ]] || return 0
    while IFS= read -r -d '' helper; do
        [[ -x "$helper" ]] || continue
        begin_config_mutation
        rc=0
        if "$helper" >>"$BACKUP_DIR/all-lxc-device-resync.log" 2>&1; then
            log "Dynamische NVIDIA-Gerätenummern neu erkannt: $helper"
        else
            rc=$?
            if ((rc == 75)); then
                warn "NVIDIA-Nodes sind noch nicht vollständig da; der zugehörige Boot-Dienst synchronisiert nach dem Neustart: $helper"
            else
                warn "LXC-Gerätesynchronisierung fehlgeschlagen (Exit $rc): $helper"
            fi
        fi
    done < <(find /usr/local/sbin -maxdepth 1 -type f -name 'nvidia-lxc-device-sync-*.sh' -print0 2>/dev/null || true)
}

prepare_attach_only_rollback() {
    local path rel
    local -a paths=(
        "/etc/pve/lxc/${TARGET_LXC_ID}.conf"
        /etc/modules-load.d/nvidia-lxc.conf
        "/usr/local/sbin/nvidia-lxc-device-sync-${TARGET_LXC_ID}.sh"
        "/etc/systemd/system/nvidia-lxc-device-sync-${TARGET_LXC_ID}.service"
        "/var/lib/nvidia-lxc-device-sync/${TARGET_LXC_ID}.devices"
    )
    local -a existing=()

    : >"$BACKUP_DIR/config-paths.tsv"
    for path in "${paths[@]}"; do
        if [[ -e "$path" ]]; then
            printf '1\t%s\n' "$path" >>"$BACKUP_DIR/config-paths.tsv"
            rel="${path#/}"
            existing+=("$rel")
        else
            printf '0\t%s\n' "$path" >>"$BACKUP_DIR/config-paths.tsv"
        fi
    done
    tar -C / -cpf "$BACKUP_DIR/config-snapshot.tar" "${existing[@]}"
    {
        printf '%s\n' '#!/usr/bin/env bash' 'set -uo pipefail'
        printf 'BACKUP_ROOT=%q\n' "$BACKUP_DIR"
        cat <<'EOF_ATTACH_ROLLBACK'
rc=0
[[ $EUID -eq 0 ]] || { printf 'root erforderlich.\n' >&2; exit 1; }
[[ -s "$BACKUP_ROOT/backup-checksums.sha256" ]] \
    || { printf 'Prüfsummenmanifest fehlt.\n' >&2; exit 2; }
(cd "$BACKUP_ROOT" && sha256sum -c --quiet backup-checksums.sha256) \
    || { printf 'Sicherung unvollständig oder beschädigt.\n' >&2; exit 2; }
while IFS=$'\t' read -r existed path; do
    [[ -n "$path" ]] || continue
    case "$path" in
        /etc/pve/lxc/[0-9]*.conf|/etc/modules-load.d/nvidia-lxc.conf|\
        /usr/local/sbin/nvidia-lxc-device-sync-[0-9]*.sh|\
        /etc/systemd/system/nvidia-lxc-device-sync-[0-9]*.service|\
        /var/lib/nvidia-lxc-device-sync/[0-9]*.devices)
            rm -rf -- "$path" || rc=1
            ;;
        *) printf 'Unsicherer Rollback-Pfad: %s\n' "$path" >&2; rc=1 ;;
    esac
done <"$BACKUP_ROOT/config-paths.tsv"
tar -C / -xpf "$BACKUP_ROOT/config-snapshot.tar" || rc=1
command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true
exit "$rc"
EOF_ATTACH_ROLLBACK
    } >"$BACKUP_DIR/rollback.sh"
    chmod 0700 "$BACKUP_DIR/rollback.sh"
    {
        printf 'Skriptversion: %s\n' "$SCRIPT_VERSION"
        printf 'Typ: LXC-GPU-Konfiguration\n'
        printf 'Erstellt: %s\n' "$(date --iso-8601=seconds)"
        printf 'Distribution: %s (%s)\n' "$OS_LABEL" "$DISTRO"
        printf 'LXC: %s\n' "$TARGET_LXC_ID"
        printf 'LXC-Zustand vorher: %s\n' \
            "$(pct status "$TARGET_LXC_ID" 2>/dev/null | awk '{print $2}' || printf unknown)"
        printf 'Betroffene Dateien: %s\n' "${paths[*]}"
    } >"$BACKUP_DIR/rollback-manifest.txt"
    ROLLBACK_READY=1
    mark_transaction_active
    MUTATION_STARTED=1
}

prepare_attach_only_backup() {
    local timestamp

    if ((RESUME_REQUEST)); then
        is_safe_backup_dir "$BACKUP_DIR" || die "Unsicheres Fortsetzungsverzeichnis: $BACKUP_DIR"
        verify_backup_checksums "$BACKUP_DIR" \
            || die "Fortsetzen verweigert: LXC-Sicherung beschädigt oder unvollständig."
        ROLLBACK_READY=1
        MUTATION_STARTED=1
        write_transaction_phase fortgesetzt
        return 0
    fi

    if ((ASSUME_YES == 0)); then
        if ((INSTALL_LXC_USERSPACE_FROM_HOST)); then
            printf '\nDer Host richtet LXC %s ein und startet darin die abgesicherte NVIDIA-Userspace-Installation.\n' "$TARGET_LXC_ID"
            printf 'Host-Treiber und Host-Pakete bleiben dabei unverändert.\n'
        else
            printf '\nEs werden nur die NVIDIA-Gerätefreigabe und der zugehörige Sync-Dienst eingerichtet.\n'
            printf 'Treiber, APT-Quellen und Pakete bleiben unverändert.\n'
        fi
        read -r -p "Fortfahren? [j/N]: " ANSWER
        [[ "$ANSWER" =~ ^([jJ]|[jJ][aA])$ ]] || die "Vom Benutzer abgebrochen."
    fi

    if ((INSTALL_LXC_USERSPACE_FROM_HOST)); then
        create_backup_dir lxc-host-managed
    else
        create_backup_dir attach
    fi

    if [[ -f "$0" ]]; then
        cp -a -- "$0" "$BACKUP_DIR/script-used.sh"
        sha256sum "$0" >"$BACKUP_DIR/script-used.sha256"
    fi
    cp -a "/etc/pve/lxc/${TARGET_LXC_ID}.conf" \
        "$BACKUP_DIR/lxc-${TARGET_LXC_ID}.conf.before"
    printf '%s\t%s\n' "$TARGET_LXC_ID" \
        "$(pct status "$TARGET_LXC_ID" 2>/dev/null | awk '{print $2}' || printf unknown)" \
        >"$BACKUP_DIR/lxc-states-before.tsv"
    [[ -e /etc/modules-load.d/nvidia-lxc.conf ]] \
        && cp -a /etc/modules-load.d/nvidia-lxc.conf \
            "$BACKUP_DIR/nvidia-lxc.modules-load.before"
    [[ -e "/usr/local/sbin/nvidia-lxc-device-sync-${TARGET_LXC_ID}.sh" ]] \
        && cp -a "/usr/local/sbin/nvidia-lxc-device-sync-${TARGET_LXC_ID}.sh" "$BACKUP_DIR/"
    [[ -e "/etc/systemd/system/nvidia-lxc-device-sync-${TARGET_LXC_ID}.service" ]] \
        && cp -a "/etc/systemd/system/nvidia-lxc-device-sync-${TARGET_LXC_ID}.service" "$BACKUP_DIR/"
    [[ -e "/var/lib/nvidia-lxc-device-sync/${TARGET_LXC_ID}.devices" ]] \
        && cp -a "/var/lib/nvidia-lxc-device-sync/${TARGET_LXC_ID}.devices" "$BACKUP_DIR/"

    prepare_attach_only_rollback

    {
        printf 'Skriptversion: %s\n' "$SCRIPT_VERSION"
        if ((INSTALL_LXC_USERSPACE_FROM_HOST)); then
            printf 'Modus: LXC vom Proxmox-Host verwalten\n'
        else
            printf 'Modus: nur GPU einbinden\n'
        fi
        printf 'LXC: %s (%s)\n' "$TARGET_LXC_ID" "$TARGET_LXC_NAME"
        printf 'GPU-Geräte: %s\n' "$TARGET_GPU_SELECTION_SUMMARY"
        printf 'GPU-UUIDs: %s\n' "$(join_by ', ' "${TARGET_GPU_UUIDS[@]}")"
        printf 'GPU-PCI-Bus-IDs: %s\n' "$(join_by ', ' "${TARGET_GPU_BUS_IDS[@]}")"
        printf 'Geräteberechtigung: mode=%s%s%s\n' "$LXC_DEVICE_MODE" \
            "${LXC_DEVICE_UID:+,uid=$LXC_DEVICE_UID}" "${LXC_DEVICE_GID:+,gid=$LXC_DEVICE_GID}"
    } >"$BACKUP_DIR/attach-only-selection.txt"

    ok "LXC-Konfiguration gesichert: $BACKUP_DIR"
}

# ---------------- LXC vollständig vom Proxmox-Host verwalten -----------------
resolve_host_lxc_target_version() {
    local candidate="${TARGET_VERSION:-}"
    if ((HOST_LXC_OPERATION)) && [[ -n "${DETECTED_HOST_MODULE_VERSION:-}" \
          && -n "${DETECTED_PACKAGE_VERSION:-}" \
          && "$DETECTED_HOST_MODULE_VERSION" != "$DETECTED_PACKAGE_VERSION" ]]; then
        die "Der Host ist noch nicht konsistent: geladenes Modul $DETECTED_HOST_MODULE_VERSION, installiertes Paket $DETECTED_PACKAGE_VERSION. Starte zuerst den Host neu; erst danach wird ein LXC eingerichtet."
    fi
    if ((HOST_LXC_OPERATION)) && [[ -n "${DETECTED_HOST_MODULE_VERSION:-}" \
          && -n "${DETECTED_INSTALLED_MODULE_VERSION:-}" \
          && "$DETECTED_HOST_MODULE_VERSION" != "$DETECTED_INSTALLED_MODULE_VERSION" ]]; then
        die "Der Host verwendet noch Modul $DETECTED_HOST_MODULE_VERSION, auf dem Datenträger liegt $DETECTED_INSTALLED_MODULE_VERSION. Starte zuerst den Host neu."
    fi
    if [[ -z "$candidate" ]]; then
        candidate="${DETECTED_HOST_MODULE_VERSION:-}"
    fi
    if [[ -z "$candidate" ]]; then
        candidate="${DETECTED_INSTALLED_MODULE_VERSION:-}"
    fi
    if [[ -z "$candidate" ]]; then
        candidate="${DETECTED_PACKAGE_VERSION:-}"
    fi
    [[ -n "$candidate" ]] \
        || die "Keine sichere NVIDIA-Version auf dem Host erkannt. Installiere oder prüfe zuerst den Host-Treiber und starte den Host bei Bedarf neu."
    is_valid_driver_version "$candidate" \
        || die "Die erkannte Host-Treiberversion '$candidate' hat kein gültiges NVIDIA-Versionsformat."
    TARGET_VERSION="$candidate"
    REQUESTED_VERSION="$candidate"
}

lxc_current_state() {
    pct status "$TARGET_LXC_ID" 2>/dev/null | awk '{print $2}'
}

wait_for_lxc_exec() {
    local attempt
    for attempt in {1..30}; do
        if [[ "$(lxc_current_state)" == "running" ]] \
           && pct exec "$TARGET_LXC_ID" -- true >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

shutdown_lxc_controlled() {
    pct shutdown "$TARGET_LXC_ID" --timeout 60 --forceStop 1
}

record_lxc_runtime_state() {
    [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]] || return 0
    printf '%s\t%s\t%s\n' "$TARGET_LXC_ID" "$LXC_ORIGINAL_STATE" \
        "$(date --iso-8601=seconds)" >"$BACKUP_DIR/lxc-runtime-orchestration.tsv"
    write_resume_state
    refresh_backup_checksums
}

prepare_lxc_runtime_from_host() {
    local state
    state="$(lxc_current_state)"
    [[ "$state" == "running" || "$state" == "stopped" ]] \
        || die "Zustand von LXC $TARGET_LXC_ID konnte nicht sicher bestimmt werden."
    if ((LXC_RUNTIME_TOUCHED)) \
       && [[ "$LXC_ORIGINAL_STATE" == "running" || "$LXC_ORIGINAL_STATE" == "stopped" ]]; then
        log "Fortsetzung: Ursprünglicher LXC-Zustand bleibt unverändert gespeichert: $LXC_ORIGINAL_STATE"
    else
        LXC_ORIGINAL_STATE="$state"
    fi

    if [[ "$state" == "stopped" ]]; then
        ((LXC_TEMPORARY_START_ALLOWED)) \
            || die "LXC $TARGET_LXC_ID ist gestoppt. Er wird ohne ausdrückliche Freigabe nicht gestartet. Nutze das Menü oder --start-stopped-lxc."
        LXC_RUNTIME_TOUCHED=1
        record_lxc_runtime_state
        log "Starte LXC $TARGET_LXC_ID ausdrücklich temporär für die Userspace-Installation ..."
        pct start "$TARGET_LXC_ID"
        wait_for_lxc_exec \
            || die "LXC $TARGET_LXC_ID wurde gestartet, ist aber nicht rechtzeitig für pct exec bereit."
    elif ((CONFIGURE_LXC_GPU && LXC_RESTART_RUNNING_ALLOWED \
            && LXC_DEVICE_SYNC_RESTART_DONE == 0)); then
        LXC_RUNTIME_TOUCHED=1
        record_lxc_runtime_state
        log "Starte LXC $TARGET_LXC_ID kontrolliert neu, damit die GPU-Geräte sichtbar werden ..."
        shutdown_lxc_controlled
        pct start "$TARGET_LXC_ID"
        wait_for_lxc_exec \
            || die "LXC $TARGET_LXC_ID ist nach dem kontrollierten Neustart nicht rechtzeitig bereit."
    fi
}

cleanup_remote_lxc_script() {
    local state
    ((LXC_REMOTE_SCRIPT_PENDING)) || return 0
    command -v pct >/dev/null 2>&1 || return 0
    [[ "${TARGET_LXC_ID:-}" =~ ^[0-9]+$ \
       && "$LXC_REMOTE_SCRIPT_PATH" =~ ^/root/\.nvidia-driver-setup-host-managed-[A-Za-z0-9._-]+\.sh$ ]] \
        || return 1
    state="$(lxc_current_state 2>/dev/null || true)"
    [[ "$state" == "running" ]] || return 0
    pct exec "$TARGET_LXC_ID" -- rm -f -- "$LXC_REMOTE_SCRIPT_PATH" >/dev/null 2>&1 \
        || return 1
    ! pct exec "$TARGET_LXC_ID" -- test -e "$LXC_REMOTE_SCRIPT_PATH" >/dev/null 2>&1 \
        || return 1
    LXC_REMOTE_SCRIPT_PENDING=0
    if [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]]; then
        write_resume_state || return 1
        refresh_backup_checksums || return 1
    fi
}

restore_lxc_runtime_state() {
    local state rc=0
    ((LXC_RUNTIME_TOUCHED)) || return 0
    command -v pct >/dev/null 2>&1 || return 0
    [[ -n "${TARGET_LXC_ID:-}" ]] || return 0
    state="$(lxc_current_state 2>/dev/null || true)"
    case "$LXC_ORIGINAL_STATE:$state" in
        stopped:running)
            log "Stelle den ursprünglichen Zustand wieder her: LXC $TARGET_LXC_ID wird heruntergefahren."
            shutdown_lxc_controlled >/dev/null 2>&1 \
                || { warn "LXC $TARGET_LXC_ID konnte nicht wieder in den gestoppten Zustand versetzt werden."; rc=1; }
            ;;
        running:stopped)
            log "Stelle den ursprünglichen Zustand wieder her: LXC $TARGET_LXC_ID wird gestartet."
            if pct start "$TARGET_LXC_ID" >/dev/null 2>&1; then
                wait_for_lxc_exec >/dev/null 2>&1 \
                    || { warn "LXC $TARGET_LXC_ID wurde gestartet, ist aber noch nicht per pct exec erreichbar."; rc=1; }
            else
                warn "LXC $TARGET_LXC_ID konnte nicht wieder gestartet werden."
                rc=1
            fi
            ;;
    esac
    ((rc)) || LXC_RUNTIME_TOUCHED=0
    return "$rc"
}

is_safe_remote_backup_path() {
    local path="${1:-}"
    [[ "$path" =~ ^/opt/nvidia-backup/nvidia-[A-Za-z0-9._-]+$ ]]
}

PARSED_MACHINE_RESULT=""
PARSED_MACHINE_BACKUP=""

parse_single_machine_result_log() {
    local log_file="$1"
    local -a results=() backups=() failure_codes=() rollback_states=()
    PARSED_MACHINE_RESULT=""
    PARSED_MACHINE_BACKUP=""
    [[ -r "$log_file" ]] || return 1
    mapfile -t results < <(sed -n 's/^NVIDIA_SETUP_RESULT=//p' "$log_file" | tr -d '\r')
    mapfile -t backups < <(sed -n 's/^NVIDIA_SETUP_BACKUP=//p' "$log_file" | tr -d '\r')
    ((${#results[@]} == 1 && ${#backups[@]} == 1)) || {
        warn "Maschinenlesbares LXC-Ergebnis ist mehrdeutig oder unvollständig."
        return 1
    }
    if [[ "${results[0]}" == failed ]]; then
        mapfile -t failure_codes < <(sed -n 's/^NVIDIA_SETUP_EXIT_CODE=//p' "$log_file" | tr -d '\r')
        mapfile -t rollback_states < <(sed -n 's/^NVIDIA_SETUP_ROLLBACK_STATUS=//p' "$log_file" | tr -d '\r')
        ((${#failure_codes[@]} == 1 && ${#rollback_states[@]} == 1)) || return 1
        [[ "${failure_codes[0]}" =~ ^[1-9][0-9]{0,2}$ ]] || return 1
        case "${rollback_states[0]}" in not-needed|completed|failed) ;; *) return 1 ;; esac
        [[ -z "${backups[0]}" ]] || is_safe_remote_backup_path "${backups[0]}" || return 1
        PARSED_MACHINE_RESULT=failed
        PARSED_MACHINE_BACKUP="${backups[0]}"
        warn "LXC-Installation fehlgeschlagen (Exit ${failure_codes[0]}, Rollback: ${rollback_states[0]}). Die Fehlersicherung wird nicht als Erfolg behandelt oder entfernt."
        return 2
    fi
    case "${results[0]}" in success|pending) ;; *) return 1 ;; esac
    is_safe_remote_backup_path "${backups[0]}" || return 1
    PARSED_MACHINE_RESULT="${results[0]}"
    PARSED_MACHINE_BACKUP="${backups[0]}"
}

verify_remote_lxc_transaction_result() {
    local result="$1" directory="$2" status phase
    is_safe_remote_backup_path "$directory" || return 1
    pct exec "$TARGET_LXC_ID" -- test -d "$directory" >/dev/null 2>&1 || return 1
    pct exec "$TARGET_LXC_ID" -- test -x "$directory/rollback.sh" >/dev/null 2>&1 || return 1
    pct exec "$TARGET_LXC_ID" -- sh -c '
        directory=$1
        cd "$directory" || exit 1
        test -s backup-checksums.sha256 || exit 1
        sha256sum -c --quiet backup-checksums.sha256
    ' sh "$directory" >/dev/null 2>&1 || return 1
    status="$(pct exec "$TARGET_LXC_ID" -- tail -n1 \
        "$directory/transaction-status" 2>/dev/null | tr -d '\r' || true)"
    phase="${status#*$'\t'}"
    [[ "$status" == *$'\t'* && "$phase" == "abgeschlossen" ]] || return 1
    case "$result" in
        pending)
            pct exec "$TARGET_LXC_ID" -- test -f \
                "$directory/pending-verification.env" >/dev/null 2>&1 || return 1
            pct exec "$TARGET_LXC_ID" -- awk -v expected='./pending-verification.env' \
                '$2 == expected { found = 1 } END { exit !found }' \
                "$directory/backup-checksums.sha256" >/dev/null 2>&1 || return 1
            ;;
        success)
            ! pct exec "$TARGET_LXC_ID" -- test -e \
                "$directory/pending-verification.env" >/dev/null 2>&1 || return 1
            ;;
        *) return 1 ;;
    esac
    return 0
}

persist_remote_lxc_transaction_result() {
    local result="$1" directory="$2"
    LXC_REMOTE_RESULT="$result"
    LXC_REMOTE_SUCCESS_BACKUP="$directory"
    LXC_REMOTE_BACKUP_CLEANUP_PENDING=1
    write_resume_state || return 1
    refresh_backup_checksums
}

recover_remote_lxc_result_from_install_log() {
    local allow_unverified="${1:-0}" log_file state
    [[ -z "${LXC_REMOTE_SUCCESS_BACKUP:-}" ]] || return 0
    [[ "${TARGET_LXC_ID:-}" =~ ^[0-9]+$ ]] || return 1
    is_safe_backup_dir "${BACKUP_DIR:-}" || return 1
    log_file="$BACKUP_DIR/lxc-${TARGET_LXC_ID}-userspace-install.log"
    parse_single_machine_result_log "$log_file" || return 1
    state="$(lxc_current_state 2>/dev/null || true)"
    if [[ "$state" == "running" ]]; then
        verify_remote_lxc_transaction_result "$PARSED_MACHINE_RESULT" "$PARSED_MACHINE_BACKUP" \
            || return 1
        printf '%s\t%s\t%s\n' "$(date --iso-8601=seconds)" \
            "$PARSED_MACHINE_RESULT" "$PARSED_MACHINE_BACKUP" \
            >"$BACKUP_DIR/remote-result-recovered.tsv"
        persist_remote_lxc_transaction_result "$PARSED_MACHINE_RESULT" "$PARSED_MACHINE_BACKUP"
        warn "Verifizierte LXC-Rollbackbasis nach einer unterbrochenen Host-Verankerung aus dem Transaktionsprotokoll wiederhergestellt."
        return 0
    fi
    ((allow_unverified)) || return 1
    LXC_REMOTE_RESULT="$PARSED_MACHINE_RESULT"
    LXC_REMOTE_SUCCESS_BACKUP="$PARSED_MACHINE_BACKUP"
    LXC_REMOTE_BACKUP_CLEANUP_PENDING=1
    warn "LXC-Rollbackkandidat aus dem Host-Protokoll erkannt; vollständige Prüfung erfolgt erst nach einem ausdrücklich erlaubten Start des LXC."
    return 0
}

remove_completed_remote_lxc_backup() {
    local directory="$1" status phase active=""

    is_safe_remote_backup_path "$directory" || {
        warn "LXC-Erfolgssicherung wird nicht entfernt: unsicherer Pfad '$directory'."
        return 1
    }
    status="$(pct exec "$TARGET_LXC_ID" -- tail -n1 \
        "$directory/transaction-status" 2>/dev/null || true)"
    phase="${status#*$'\t'}"
    [[ "$status" == *$'\t'* && "$phase" == "abgeschlossen" ]] || {
        warn "LXC-Erfolgssicherung wird nicht entfernt: Transaktionsstatus ist '${phase:-unbekannt}'."
        return 1
    }
    active="$(pct exec "$TARGET_LXC_ID" -- head -n1 \
        /opt/nvidia-backup/.active-transaction 2>/dev/null || true)"
    [[ "$active" != "$directory" ]] || {
        warn "LXC-Erfolgssicherung wird nicht entfernt: Sie ist noch als aktiv markiert."
        return 1
    }
    pct exec "$TARGET_LXC_ID" -- rm -rf -- "$directory" >/dev/null 2>&1
}

cleanup_deferred_remote_backup_after_host_success() {
    local state
    ((LXC_REMOTE_BACKUP_CLEANUP_PENDING)) || return 0
    [[ -n "${LXC_REMOTE_SUCCESS_BACKUP:-}" ]] || {
        block_success_backup_cleanup "LXC-Sicherungspfad konnte nicht verifiziert werden"
        return 0
    }
    if ((KEEP_SUCCESS_BACKUP)); then
        log "LXC-Erfolgssicherung wird auf Wunsch behalten: $LXC_REMOTE_SUCCESS_BACKUP"
        return 0
    fi
    if ((SUCCESS_BACKUP_CLEANUP_BLOCKED)); then
        warn "LXC-Sicherung bleibt bis zur gemeinsamen Host-/LXC-Abschlussprüfung erhalten: $LXC_REMOTE_SUCCESS_BACKUP"
        return 0
    fi
    state="$(lxc_current_state 2>/dev/null || true)"
    if [[ "$state" != "running" ]]; then
        block_success_backup_cleanup "LXC $TARGET_LXC_ID ist für die nachgelagerte Sicherungsbereinigung nicht gestartet"
        warn "LXC $TARGET_LXC_ID bleibt gestoppt; seine Erfolgssicherung wird beim nächsten ausdrücklich gestarteten Abschlusscheck entfernt."
        return 0
    fi
    if remove_completed_remote_lxc_backup "$LXC_REMOTE_SUCCESS_BACKUP"; then
        ok "LXC-Erfolgssicherung nach Abschluss der Host-Transaktion entfernt: $LXC_REMOTE_SUCCESS_BACKUP"
        LXC_REMOTE_BACKUP_CLEANUP_PENDING=0
        LXC_REMOTE_SUCCESS_BACKUP=""
    else
        block_success_backup_cleanup "LXC-Erfolgssicherung konnte nicht sicher entfernt werden"
    fi
}

run_remote_lxc_recovery_if_needed() {
    local marker choice installed resume_log remote_result remote_backup
    marker="$(pct exec "$TARGET_LXC_ID" -- head -n1 \
        /opt/nvidia-backup/.active-transaction 2>/dev/null || true)"
    [[ -n "$marker" ]] || return 1

    if ((UPDATE_ONLY && RESUME_REQUEST == 0)); then
        die "Im LXC ist noch eine frühere Transaktion aktiv. Zuerst über die LXC-Verwaltung fortsetzen oder zurückrollen, dann das Update erneut wählen. Ein Update startet keine frühere Neuinstallation automatisch."
    fi
    warn "Im LXC $TARGET_LXC_ID wurde eine unterbrochene NVIDIA-Transaktion erkannt: $marker"
    if ((ORIGINAL_ARGC == 0 || RESUME_REQUEST)); then
        if ((RESUME_REQUEST)); then
            choice=1
        else
            menu_section "UNTERBROCHENE LXC-TRANSAKTION"
            menu_item 1 "Im LXC vom Host aus fortsetzen  [Empfohlen]"
            menu_item 2 "Im LXC zurückrollen und danach neu einrichten"
            menu_item 0 "Abbrechen"
            choice="$(menu_read 'Auswahl [1]: ')"
            choice="${choice:-1}"
        fi
    else
        die "Behebe die unterbrochene LXC-Transaktion zuerst interaktiv vom Host aus."
    fi

    case "$choice" in
        1)
            resume_log="$BACKUP_DIR/lxc-${TARGET_LXC_ID}-userspace-resume.log"
            if ! pct exec "$TARGET_LXC_ID" -- env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
                    "$LXC_REMOTE_SCRIPT_PATH" --resume --machine-readable-result \
                    2>&1 | tee "$resume_log"; then
                die "Die unterbrochene NVIDIA-Installation in LXC $TARGET_LXC_ID konnte nicht fortgesetzt werden."
            fi
            parse_single_machine_result_log "$resume_log" \
                || die "Die LXC-Fortsetzung lieferte keinen eindeutigen Ergebnis-/Backup-Marker."
            remote_result="$PARSED_MACHINE_RESULT"
            remote_backup="$PARSED_MACHINE_BACKUP"
            [[ "$remote_backup" == "$marker" ]] \
                || die "Die LXC-Fortsetzung meldete eine andere Sicherung als den zuvor aktiven Transaktionspfad."
            verify_remote_lxc_transaction_result "$remote_result" "$remote_backup" \
                || die "LXC-Ergebnis, Pending-Zustand, Transaktionsphase oder Prüfsummen sind nach der Fortsetzung inkonsistent."
            persist_remote_lxc_transaction_result "$remote_result" "$remote_backup" \
                || die "Die verifizierte LXC-Rollbackbasis konnte nicht im Host-Zustand verankert werden."
            installed="$(pct exec "$TARGET_LXC_ID" -- dpkg-query -W -f='${Version}' \
                libnvidia-compute 2>/dev/null \
                || pct exec "$TARGET_LXC_ID" -- dpkg-query -W -f='${Version}' libnvidia-ml1 2>/dev/null \
                || true)"
            if [[ "$(normalize_driver_version "$installed")" == "$TARGET_VERSION" ]]; then
                return 0
            fi
            return 1
            ;;
        2)
            pct exec "$TARGET_LXC_ID" -- env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
                "$LXC_REMOTE_SCRIPT_PATH" --rollback "$marker" \
                || die "Der Rollback der unterbrochenen NVIDIA-Installation in LXC $TARGET_LXC_ID ist fehlgeschlagen."
            return 1
            ;;
        0|q|Q) die "Vom Benutzer abgebrochen." ;;
        *) die "Ungültige Auswahl für die LXC-Wiederherstellung: $choice" ;;
    esac
}

run_remote_lxc_transcode_smoke_test() {
    local mode="${TRANSCODE_SMOKE_TEST:-auto}"
    local remote_dir="/tmp/nvidia-transcode-smoke-${SCRIPT_VERSION}-$$"
    local host_prefix="$BACKUP_DIR/lxc-${TARGET_LXC_ID}"

    [[ "$mode" != "no" ]] || {
        log "LXC-Transcoding-Smoke-Test wurde bewusst übersprungen."
        return 2
    }
    if ! pct exec "$TARGET_LXC_ID" -- sh -c 'command -v ffmpeg >/dev/null 2>&1'; then
        if [[ "$mode" == "yes" ]]; then
            warn "FFmpeg fehlt im LXC $TARGET_LXC_ID; der zwingend gewählte Transcoding-Test ist nicht möglich."
            return 1
        fi
        log "FFmpeg fehlt im LXC $TARGET_LXC_ID; automatischer Transcoding-Test übersprungen."
        return 2
    fi
    if ! pct exec "$TARGET_LXC_ID" -- ffmpeg -hide_banner -encoders 2>/dev/null \
        | grep -q 'h264_nvenc' \
       || ! pct exec "$TARGET_LXC_ID" -- ffmpeg -hide_banner -decoders 2>/dev/null \
        | grep -q 'h264_cuvid'; then
        warn "FFmpeg im LXC $TARGET_LXC_ID enthält nicht gleichzeitig h264_nvenc und h264_cuvid."
        return 1
    fi

    pct exec "$TARGET_LXC_ID" -- mkdir -p "$remote_dir"
    if ! pct exec "$TARGET_LXC_ID" -- ffmpeg -hide_banner -loglevel error -y \
        -f lavfi -i "$TRANSCODE_SMOKE_SOURCE" -frames:v 10 -an \
        -c:v h264_nvenc -preset p1 "$remote_dir/nvenc-smoke.mp4" \
        >"${host_prefix}-nvenc-smoke.log" 2>&1; then
        pct exec "$TARGET_LXC_ID" -- rm -rf -- "$remote_dir" >/dev/null 2>&1 || true
        report_transcode_failure_log "NVENC-Fehlerausgabe aus LXC $TARGET_LXC_ID" \
            "${host_prefix}-nvenc-smoke.log"
        warn "NVENC-Smoke-Test im LXC ist fehlgeschlagen: ${host_prefix}-nvenc-smoke.log"
        return 1
    fi
    if ! pct exec "$TARGET_LXC_ID" -- ffmpeg -hide_banner -loglevel error \
        -c:v h264_cuvid -i "$remote_dir/nvenc-smoke.mp4" -f null - \
        >"${host_prefix}-nvdec-smoke.log" 2>&1; then
        pct exec "$TARGET_LXC_ID" -- rm -rf -- "$remote_dir" >/dev/null 2>&1 || true
        report_transcode_failure_log "NVDEC-Fehlerausgabe aus LXC $TARGET_LXC_ID" \
            "${host_prefix}-nvdec-smoke.log"
        warn "NVDEC-Smoke-Test im LXC ist fehlgeschlagen: ${host_prefix}-nvdec-smoke.log"
        return 1
    fi
    pct exec "$TARGET_LXC_ID" -- rm -rf -- "$remote_dir" >/dev/null 2>&1 || true
    ok "Echter NVENC-/NVDEC-Transcoding-Test in LXC $TARGET_LXC_ID erfolgreich."
    return 0
}

classify_nvml_failure_text() {
    local text="${1,,}"
    case "$text" in
        *execvp*nvidia-smi*|*nvidia-smi*not\ found*|*nvidia-smi*no\ such\ file*)
            printf 'Das Debian-Paket ist vorhanden, aber die ausführbare nvidia-smi-Datei fehlt oder liegt nicht im PATH.'
            ;;
        *driver/library\ version\ mismatch*|*api\ mismatch*)
            printf 'Host-Kernelmodul und LXC-Bibliotheken verwenden unterschiedliche Laufzeitstaende.'
            ;;
        *insufficient\ permissions*|*permission\ denied*|*operation\ not\ permitted*)
            printf 'Die NVIDIA-Geraete sind sichtbar, aber Berechtigungen oder die LXC-cgroup-Freigabe blockieren den Zugriff.'
            ;;
        *no\ devices\ were\ found*|*no\ devices*)
            printf 'Im LXC ist keine nutzbare GPU sichtbar; GPU-Auswahl und /dev/nvidiaN-Zuweisung muessen neu synchronisiert werden.'
            ;;
        *unknown\ error*)
            printf 'NVML meldet einen unbekannten Geraetefehler; meist ist die laufende LXC-Geraetezuweisung nach einer dynamischen Neunummerierung veraltet.'
            ;;
        *couldn*t\ communicate*|*failed\ to\ initialize\ nvml*)
            printf 'NVML kann den Host-Treiber nicht erreichen; Host-Modul, Kontrollgeraete und LXC-Zugriff muessen gemeinsam geprueft werden.'
            ;;
        *)
            printf 'NVML ist nicht funktionsfaehig; die genaue Ursache steht im zugehoerigen nvidia-smi-Protokoll.'
            ;;
    esac
}

write_lxc_nvml_failure_analysis() {
    local input_file="$1"
    local analysis_file="$BACKUP_DIR/lxc-${TARGET_LXC_ID}-nvml-analysis.txt"
    local detail_file="$BACKUP_DIR/lxc-${TARGET_LXC_ID}-nvml-runtime-details.txt"
    local raw="" classification

    [[ -r "$input_file" ]] && raw="$(tr '\n' ' ' <"$input_file" | sed 's/[[:space:]]\+/ /g' || true)"
    classification="$(classify_nvml_failure_text "$raw")"
    pct exec "$TARGET_LXC_ID" -- sh -c '
        printf "nvidia-smi-Pfad: "; command -v nvidia-smi 2>/dev/null || printf "fehlt\n"
        printf "nvidia-smi-Paket:\n"
        dpkg-query -W -f="\${binary:Package}\t\${Version}\t\${db:Status-Abbrev}\n" nvidia-smi libnvidia-ml1 2>/dev/null || true
        printf "NVML-Linker-Cache:\n"
        ldconfig -p 2>/dev/null | grep -E "libnvidia-ml\.so" || true
        printf "Geräte:\n"
        find /dev -maxdepth 2 -type c -name "nvidia*" -exec stat -Lc "%n %a %u:%g %t:%T" {} \; 2>/dev/null | sort -V || true
        if command -v nvidia-smi >/dev/null 2>&1; then
            printf "Binärdatei:\n"
            ls -l "$(command -v nvidia-smi)" 2>/dev/null || true
            ldd "$(command -v nvidia-smi)" 2>/dev/null || true
        fi
    ' >"$detail_file" 2>&1 || true
    {
        printf 'LXC: %s (%s)\n' "$TARGET_LXC_ID" "$TARGET_LXC_NAME"
        printf 'Zielversion: %s\n' "$TARGET_VERSION"
        printf 'Ursachenklasse: %s\n' "$classification"
        printf 'Originalmeldung: %s\n' "${raw:-keine Ausgabe}"
        printf 'Laufzeitdetails: %s\n' "$detail_file"
        printf 'Automatische Massnahmen: ldconfig, Host-Geraeteknoten und verwaltete LXC-Zuweisung werden einmal neu synchronisiert; ein Neustart erfolgt nur nach vorheriger Freigabe.\n'
    } >"$analysis_file"
    warn "Automatische NVML-Analyse: $classification"
    log "Analysebericht: $analysis_file"
}

attempt_lxc_nvml_auto_repair_from_host() {
    local helper="/usr/local/sbin/nvidia-lxc-device-sync-${TARGET_LXC_ID}.sh"
    local retry_log="$BACKUP_DIR/lxc-${TARGET_LXC_ID}-nvidia-smi-after-auto-repair.txt"

    ((AUTOMATIC_REPAIR)) || return 1
    log "Versuche die LXC-NVIDIA-Laufzeit einmalig und kontrolliert automatisch zu reparieren ..."
    if command -v modprobe >/dev/null 2>&1; then
        modprobe nvidia >"$BACKUP_DIR/lxc-${TARGET_LXC_ID}-host-modprobe-nvidia.txt" 2>&1 || true
        modprobe nvidia_uvm >"$BACKUP_DIR/lxc-${TARGET_LXC_ID}-host-modprobe-uvm.txt" 2>&1 || true
    fi
    if command -v nvidia-modprobe >/dev/null 2>&1; then
        nvidia-modprobe -u -c=0 >"$BACKUP_DIR/lxc-${TARGET_LXC_ID}-host-device-repair.txt" 2>&1 || true
    fi
    if [[ -x "$helper" ]]; then
        "$helper" >"$BACKUP_DIR/lxc-${TARGET_LXC_ID}-device-resync-after-nvml-error.txt" 2>&1 || true
    fi
    pct exec "$TARGET_LXC_ID" -- ldconfig \
        >"$BACKUP_DIR/lxc-${TARGET_LXC_ID}-ldconfig-after-nvml-error.txt" 2>&1 || true
    if pct exec "$TARGET_LXC_ID" -- nvidia-smi >"$retry_log" 2>&1; then
        record_repair_action "LXC-NVML nach ldconfig- und Geraetesynchronisation wiederhergestellt"
        ok "nvidia-smi im LXC funktioniert nach der automatischen Laufzeitreparatur."
        return 0
    fi

    if ((CONFIGURE_LXC_GPU && LXC_RESTART_RUNNING_ALLOWED)); then
        warn "Die sichere Synchronisation reichte nicht aus; starte den bereits freigegebenen laufenden LXC einmal kontrolliert neu."
        shutdown_lxc_controlled \
            >"$BACKUP_DIR/lxc-${TARGET_LXC_ID}-restart-after-nvml-error.txt" 2>&1 || return 1
        pct start "$TARGET_LXC_ID" \
            >>"$BACKUP_DIR/lxc-${TARGET_LXC_ID}-restart-after-nvml-error.txt" 2>&1 || return 1
        wait_for_lxc_exec \
            >>"$BACKUP_DIR/lxc-${TARGET_LXC_ID}-restart-after-nvml-error.txt" 2>&1 || return 1
        pct exec "$TARGET_LXC_ID" -- ldconfig >/dev/null 2>&1 || true
        if pct exec "$TARGET_LXC_ID" -- nvidia-smi >"$retry_log" 2>&1; then
            record_repair_action "LXC-NVML nach freigegebenem kontrolliertem Neustart wiederhergestellt"
            ok "nvidia-smi im LXC funktioniert nach der automatischen Synchronisation und dem kontrollierten Neustart."
            return 0
        fi
    fi
    return 1
}

finalize_remote_lxc_pending_after_host_repair() {
    local directory="$1"
    local log_file="$BACKUP_DIR/lxc-${TARGET_LXC_ID}-finalize-after-auto-repair.log"

    is_safe_remote_backup_path "$directory" || return 1
    log "Lasse die vollständige LXC-interne Abschlussprüfung nach der Host-Reparatur erneut laufen ..."
    if pct exec "$TARGET_LXC_ID" -- env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
            "$LXC_REMOTE_SCRIPT_PATH" --finalize-pending "$directory" \
            >"$log_file" 2>&1; then
        record_repair_action "LXC-interne Abschlussprüfung nach Host-NVML-Reparatur erfolgreich wiederholt"
        LXC_REMOTE_RESULT="success"
        write_resume_state
        refresh_backup_checksums
        ok "Die erneute LXC-interne Paket-, NVML-, Geräte- und Codec-Prüfung war erfolgreich."
        return 0
    fi
    warn "Die automatische Laufzeitreparatur half, aber die vollständige LXC-interne Abschlussprüfung ist weiterhin offen. Details: $log_file"
    return 1
}

install_lxc_userspace_from_host() {
    local installed remote_backup="" remote_nvml="" remote_result=""
    local pin_option="--no-pin-packages" repair_option="--auto-repair"
    local final_autoremove_option="--final-autoremove" smoke_rc=0
    local -a update_options=()
    local runtime_verified=1
    local log_file="$BACKUP_DIR/lxc-${TARGET_LXC_ID}-userspace-install.log"

    ((INSTALL_LXC_USERSPACE_FROM_HOST)) || return 0
    resolve_host_lxc_target_version
    if [[ -n "${DETECTED_HOST_MODULE_VERSION:-}" \
          && "$DETECTED_HOST_MODULE_VERSION" != "$TARGET_VERSION" ]]; then
        LXC_USERSPACE_DEFERRED=1
        block_success_backup_cleanup "geladenes Host-Modul stimmt noch nicht mit der LXC-Zielversion überein"
        warn "LXC-Userspace wird noch nicht geändert: geladenes Host-Modul $DETECTED_HOST_MODULE_VERSION, Ziel $TARGET_VERSION. Starte zuerst den Host neu und wähle danach im Host-Menü 'LXC vollständig einrichten'."
        return 0
    fi

    prepare_lxc_runtime_from_host
    [[ -f "$0" ]] || die "Das laufende Skript kann nicht in den LXC übertragen werden: $0"
    log "Übertrage das geprüfte Skript in LXC $TARGET_LXC_ID ..."
    pct push "$TARGET_LXC_ID" "$0" "$LXC_REMOTE_SCRIPT_PATH" --perms 0700
    LXC_REMOTE_SCRIPT_PENDING=1
    write_resume_state
    refresh_backup_checksums

    if recover_remote_lxc_result_from_install_log; then
        remote_backup="$LXC_REMOTE_SUCCESS_BACKUP"
        remote_result="$LXC_REMOTE_RESULT"
        ok "Bereits abgeschlossene LXC-Teiltransaktion wurde sicher wieder mit dem Host-Zustand verknüpft."
    elif run_remote_lxc_recovery_if_needed; then
        remote_backup="$LXC_REMOTE_SUCCESS_BACKUP"
        remote_result="$LXC_REMOTE_RESULT"
        ok "Unterbrochene LXC-Installation wurde vom Host fortgesetzt und entspricht $TARGET_VERSION."
    else
        ((PIN_NVIDIA_PACKAGES)) && pin_option="--pin-packages"
        ((AUTOMATIC_REPAIR)) || repair_option="--no-auto-repair"
        ((FINAL_APT_AUTOREMOVE)) || final_autoremove_option="--no-final-autoremove"
        ((UPDATE_ONLY == 0)) || update_options=(--update)
        if ((UPDATE_ONLY)); then log "Aktualisiere NVIDIA-Userspace auf $TARGET_VERSION in LXC $TARGET_LXC_ID vom Host aus ...";
        else log "Installiere NVIDIA-Userspace $TARGET_VERSION in LXC $TARGET_LXC_ID vom Host aus ..."; fi
        if ! pct exec "$TARGET_LXC_ID" -- env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
            "$LXC_REMOTE_SCRIPT_PATH" --mode lxc --version "$TARGET_VERSION" \
            "${update_options[@]}" \
            --host-version "$TARGET_VERSION" "$pin_option" "$repair_option" \
            "$final_autoremove_option" \
            --nvtop "$NVTOP_MANAGEMENT" \
            --clean-scope "$CLEAN_INSTALL_SCOPE" --machine-readable-result \
            --keep-success-backup -y 2>&1 | tee "$log_file"; then
            die "Die LXC-Userspace-Installation ist fehlgeschlagen. Abbruchursache und Status eines gegebenenfalls nötigen LXC-Rollbacks stehen im Protokoll: $log_file"
        fi
        parse_single_machine_result_log "$log_file" \
            || die "Der LXC-Lauf lieferte keinen eindeutigen maschinenlesbaren Abschlussstatus. Protokoll: $log_file"
        remote_result="$PARSED_MACHINE_RESULT"
        remote_backup="$PARSED_MACHINE_BACKUP"
    fi

    # Die Remote-Rollbackbasis muss unmittelbar nach dem erfolgreichen Kindlauf
    # im Host-Zustand verankert sein. Jede spätere Prüfung kann noch abbrechen.
    [[ -n "$remote_backup" ]] || remote_backup="${LXC_REMOTE_SUCCESS_BACKUP:-}"
    if [[ -n "$remote_backup" ]]; then
        verify_remote_lxc_transaction_result "$remote_result" "$remote_backup" \
            || die "Der LXC-Ergebnismarker stimmt nicht mit Rollbackbasis, Prüfsummen, Transaktionsphase oder Pending-Zustand überein: $remote_backup"
        printf '%s\n' "$remote_backup" >"$BACKUP_DIR/lxc-${TARGET_LXC_ID}-remote-backup.txt"
        persist_remote_lxc_transaction_result "$remote_result" "$remote_backup" \
            || die "Die verifizierte LXC-Rollbackbasis konnte nicht dauerhaft im Host-Backup gespeichert werden."
    else
        die "Der erfolgreiche LXC-Lauf lieferte keine verifizierbare Rollback-Sicherung. Protokoll: $log_file"
    fi

    installed="$(pct exec "$TARGET_LXC_ID" -- dpkg-query -W -f='${Version}' \
        libnvidia-compute 2>/dev/null \
        || pct exec "$TARGET_LXC_ID" -- dpkg-query -W -f='${Version}' libnvidia-ml1 2>/dev/null \
        || true)"
    [[ "$(normalize_driver_version "$installed")" == "$TARGET_VERSION" ]] \
        || die "LXC $TARGET_LXC_ID meldet nach der Installation '${installed:-keine NVIDIA-Bibliothek}', erwartet wurde $TARGET_VERSION."
    if pct exec "$TARGET_LXC_ID" -- dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null \
        | awk -F'\t' '$2 !~ /^un/ {print $1}' \
        | grep -Eq "$LXC_FORBIDDEN_PACKAGE_REGEX"; then
        die "Im LXC $TARGET_LXC_ID wurden unerlaubte NVIDIA-Kernel-/DKMS-/Host-Hilfspakete gefunden."
    fi

    if pct exec "$TARGET_LXC_ID" -- test -e /dev/nvidiactl >/dev/null 2>&1; then
        if ! pct exec "$TARGET_LXC_ID" -- nvidia-smi \
            >"$BACKUP_DIR/lxc-${TARGET_LXC_ID}-nvidia-smi.txt" 2>&1; then
            write_lxc_nvml_failure_analysis "$BACKUP_DIR/lxc-${TARGET_LXC_ID}-nvidia-smi.txt"
            if attempt_lxc_nvml_auto_repair_from_host; then
                cp "$BACKUP_DIR/lxc-${TARGET_LXC_ID}-nvidia-smi-after-auto-repair.txt" \
                    "$BACKUP_DIR/lxc-${TARGET_LXC_ID}-nvidia-smi.txt"
                if [[ "$remote_result" == "pending" ]] \
                   && finalize_remote_lxc_pending_after_host_repair "$remote_backup"; then
                    remote_result="success"
                fi
            else
                runtime_verified=0
                LXC_USERSPACE_DEFERRED=1
                if ((AUTOMATIC_REPAIR)); then
                    record_repair_unresolved "nvidia-smi im LXC funktioniert nach der automatischen Host-Reparatur weiterhin nicht"
                else
                    block_success_backup_cleanup "nvidia-smi im LXC fehlgeschlagen"
                fi
                warn "Bibliotheken sind korrekt installiert, aber nvidia-smi im LXC schlägt weiterhin fehl. Siehe $BACKUP_DIR/lxc-${TARGET_LXC_ID}-nvml-analysis.txt"
            fi
        fi
        if ((runtime_verified)); then
            remote_nvml="$(pct exec "$TARGET_LXC_ID" -- nvidia-smi \
                --query-gpu=driver_version --format=csv,noheader 2>/dev/null \
                | head -n1 || true)"
            if [[ "$(normalize_driver_version "$remote_nvml")" != "$TARGET_VERSION" ]]; then
                runtime_verified=0
                LXC_USERSPACE_DEFERRED=1
                block_success_backup_cleanup "NVML-Version im LXC stimmt nicht exakt mit dem Host überein"
                warn "nvidia-smi im LXC meldet '${remote_nvml:-keine Version}', erwartet wurde exakt $TARGET_VERSION."
            fi
        fi
    else
        runtime_verified=0
        LXC_USERSPACE_DEFERRED=1
        block_success_backup_cleanup "NVIDIA-Geräte sind im LXC noch nicht sichtbar"
        warn "Bibliotheken sind installiert; die GPU-Geräte werden im LXC erst nach dem nächsten passenden Host-/LXC-Neustart sichtbar."
    fi
    LXC_USERSPACE_CONFIGURED=1
    if run_remote_lxc_transcode_smoke_test; then
        :
    else
        smoke_rc=$?
        if ((smoke_rc != 2)); then
            runtime_verified=0
            LXC_USERSPACE_DEFERRED=1
            block_success_backup_cleanup "echter NVENC-/NVDEC-Test im LXC fehlgeschlagen"
        fi
    fi
    if [[ "$remote_result" == "pending" ]]; then
        runtime_verified=0
        LXC_USERSPACE_DEFERRED=1
        if ((AUTOMATIC_REPAIR)); then
            record_repair_unresolved "LXC-interne Abschlussdiagnose meldet weiterhin eine ausstehende Laufzeitprüfung"
        else
            block_success_backup_cleanup "LXC-interne Abschlussdiagnose meldet eine ausstehende Laufzeitprüfung"
        fi
    fi
    if [[ -n "$remote_backup" ]]; then
        LXC_REMOTE_SUCCESS_BACKUP="$remote_backup"
        LXC_REMOTE_BACKUP_CLEANUP_PENDING=1
    elif ((KEEP_SUCCESS_BACKUP == 0)); then
        block_success_backup_cleanup "erfolgreiche LXC-Transaktion meldete keinen sicheren Sicherungspfad"
        warn "Die erfolgreiche LXC-Transaktion meldete kein sicher prüfbares Sicherungsverzeichnis; die Host-Sicherung bleibt erhalten."
    fi
    cleanup_remote_lxc_script
    refresh_backup_checksums
    if ((runtime_verified)); then
        ok "LXC $TARGET_LXC_ID wurde vollständig vom Host aus mit NVIDIA-Userspace $TARGET_VERSION eingerichtet und geprüft."
    else
        warn "LXC $TARGET_LXC_ID ist paketseitig auf NVIDIA-Userspace $TARGET_VERSION eingerichtet; die Laufzeitprüfung ist noch ausstehend."
    fi
}

stage_package_for_uninstall_backup() {
    stage_exact_installed_package_deb "$1" "$2" "$BACKUP_DIR/rollback-debs"
}

prepare_uninstall_backup() {
    local path rel package version ctid
    local -a paths=(
        /etc/apt/sources.list
        /etc/apt/sources.list.d
        /etc/apt/preferences.d
        /var/lib/extrepo/keys/nvidia-cuda.asc
        /etc/apt/keyrings/nvidia-cuda.asc
        /etc/apt/keyrings/cuda-archive-keyring.gpg
        /usr/share/keyrings/nvidia-cuda-keyring.gpg
        /usr/share/keyrings/cuda-archive-keyring.gpg
        /etc/modules-load.d/nvidia-lxc.conf
        /etc/modprobe.d/blacklist-nouveau.conf
        /etc/nvidia-container-runtime
        /etc/cdi/nvidia.yaml
        /usr/bin/nvidia-smi
        /var/lib/nvidia-driver-setup/lxc-nvidia-smi-payload.env
    )
    local -a existing=()

    create_backup_dir uninstall
    TMP_DIR="$(mktemp -d)"
    chmod 0700 "$TMP_DIR"
    mkdir -p "$BACKUP_DIR/rollback-debs"
    if [[ -f "$0" ]]; then
        cp -a -- "$0" "$BACKUP_DIR/script-used.sh"
    fi
    assert_no_unrelated_broken_dpkg_states full
    apt-mark showhold >"$BACKUP_DIR/apt-holds-before.txt" 2>/dev/null || true
    query_managed_nvidia_package_states full \
        | sort -u >"$BACKUP_DIR/nvidia-package-states-before.tsv"
    awk -F'\t' 'substr($3, 2, 1) == "i" && substr($3, 3, 1) != "R" {print $1 "\t" $2}' \
        "$BACKUP_DIR/nvidia-package-states-before.tsv" \
        | sort -u >"$BACKUP_DIR/nvidia-package-versions.tsv"
    awk -F'\t' 'substr($3, 2, 1) != "i" || substr($3, 3, 1) == "R" {print}' \
        "$BACKUP_DIR/nvidia-package-states-before.tsv" \
        | sort -u >"$BACKUP_DIR/nvidia-non-ii-states-before.tsv"
    cut -f1 "$BACKUP_DIR/nvidia-package-states-before.tsv" \
        | sed '/^$/d' | sort -u >"$BACKUP_DIR/nvidia-purge-candidates.txt"
    if [[ -s "$BACKUP_DIR/nvidia-non-ii-states-before.tsv" ]]; then
        ROLLBACK_COVERAGE="normalized"
        warn "Vorbestehende unvollständige oder residuale NVIDIA-/CUDA-Paketzustände werden vollständig entfernt, aber bei einem Rollback nicht künstlich rekonstruiert."
    else
        ROLLBACK_COVERAGE="exact"
    fi

    while IFS=$'\t' read -r package version; do
        [[ -n "$package" && -n "$version" ]] || continue
        log "Sichere für Deinstallations-Rollback: $package=$version"
        stage_package_for_uninstall_backup "$package" "$version" \
            || die "Vollständiger Rollback nicht möglich: $package=$version konnte nicht gesichert werden."
    done <"$BACKUP_DIR/nvidia-package-versions.tsv"

    if [[ "$MODE" == "host" ]]; then
        while IFS= read -r -d '' path; do paths+=("$path"); done \
            < <(find /etc/pve/lxc -maxdepth 1 -type f -name '*.conf' -print0 2>/dev/null || true)
        while IFS= read -r -d '' path; do paths+=("$path"); done \
            < <(find /usr/local/sbin -maxdepth 1 -type f -name 'nvidia-lxc-device-sync-*.sh' -print0 2>/dev/null || true)
        while IFS= read -r -d '' path; do paths+=("$path"); done \
            < <(find /etc/systemd/system -maxdepth 1 -type f -name 'nvidia-lxc-device-sync-*.service' -print0 2>/dev/null || true)
        while IFS= read -r -d '' path; do append_unique paths "$path"; done \
            < <(find /etc/systemd/system /run/systemd/system -type l \
                -name 'nvidia-lxc-device-sync-*.service' -print0 2>/dev/null || true)
        while IFS= read -r -d '' path; do paths+=("$path"); done \
            < <(find /var/lib/nvidia-lxc-device-sync -maxdepth 1 -type f -name '*.devices' -print0 2>/dev/null || true)
        : >"$BACKUP_DIR/lxc-states-before.tsv"
        if command -v pct >/dev/null 2>&1; then
            while IFS= read -r ctid; do
                [[ "$ctid" =~ ^[0-9]+$ ]] || continue
                printf '%s\t%s\n' "$ctid" \
                    "$(pct status "$ctid" 2>/dev/null | awk '{print $2}' || printf unknown)" \
                    >>"$BACKUP_DIR/lxc-states-before.tsv"
            done < <(pct list 2>/dev/null | awk 'NR > 1 {print $1}')
        fi
    fi

    : >"$BACKUP_DIR/config-paths.tsv"
    for path in "${paths[@]}"; do
        if [[ -e "$path" || -L "$path" ]]; then
            printf '1\t%s\n' "$path" >>"$BACKUP_DIR/config-paths.tsv"
            rel="${path#/}"
            existing+=("$rel")
        else
            printf '0\t%s\n' "$path" >>"$BACKUP_DIR/config-paths.tsv"
        fi
    done
    if ((${#existing[@]})); then
        tar -C / -cpf "$BACKUP_DIR/config-snapshot.tar" "${existing[@]}"
    else
        tar -C / -cpf "$BACKUP_DIR/config-snapshot.tar" --files-from /dev/null
    fi

    {
        printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' "IFS=\$'\\n\\t'"
        printf 'BACKUP_ROOT=%q\n' "$BACKUP_DIR"
        printf 'ROLLBACK_COVERAGE=%q\n' "$ROLLBACK_COVERAGE"
        printf 'NVIDIA_REGEX=%q\n' "$NVIDIA_DRIVER_REGEX"
        printf 'NVIDIA_AUX_REGEX=%q\n' "$NVIDIA_AUXILIARY_REGEX"
        printf 'NVIDIA_REPO_REGEX=%q\n' "$NVIDIA_REPOSITORY_PACKAGE_REGEX"
        cat <<'EOF_UNINSTALL_ROLLBACK'
[[ $EUID -eq 0 ]] || { printf '[rollback] root erforderlich.\n' >&2; exit 1; }
[[ -s "$BACKUP_ROOT/backup-checksums.sha256" ]] || { printf '[rollback] Prüfsummen fehlen.\n' >&2; exit 2; }
(cd "$BACKUP_ROOT" && sha256sum -c --quiet backup-checksums.sha256) \
    || { printf '[rollback] Sicherung beschädigt oder unvollständig.\n' >&2; exit 2; }
shopt -s nullglob
for deb in "$BACKUP_ROOT"/rollback-debs/*.deb; do
    relative=".${deb#"$BACKUP_ROOT"}"
    awk -v expected="$relative" '$2 == expected { found = 1 } END { exit !found }' \
        "$BACKUP_ROOT/backup-checksums.sha256" \
        || { printf '[rollback] Nicht manifestierte Paketdatei: %s\n' "$deb" >&2; exit 2; }
done
shopt -u nullglob
while IFS=$'\t' read -r existed path; do
    [[ -n "$path" ]] || continue
    case "$path" in
        /etc/apt/sources.list.d|/etc/apt/preferences.d|/etc/nvidia-container-runtime)
            rm -rf -- "$path"
            ;;
        /etc/apt/sources.list|/var/lib/extrepo/keys/nvidia-cuda.asc|\
        /etc/apt/keyrings/nvidia-cuda.asc|/etc/apt/keyrings/cuda-archive-keyring.gpg|\
        /usr/share/keyrings/nvidia-cuda-keyring.gpg|/usr/share/keyrings/cuda-archive-keyring.gpg|\
        /etc/modules-load.d/nvidia-lxc.conf|/etc/modprobe.d/blacklist-nouveau.conf|\
        /etc/cdi/nvidia.yaml|\
        /etc/pve/lxc/[0-9]*.conf|/usr/local/sbin/nvidia-lxc-device-sync-[0-9]*.sh|\
        /etc/systemd/system/nvidia-lxc-device-sync-[0-9]*.service|\
        /etc/systemd/system/*.wants/nvidia-lxc-device-sync-[0-9]*.service|\
        /etc/systemd/system/*.requires/nvidia-lxc-device-sync-[0-9]*.service|\
        /run/systemd/system/*.wants/nvidia-lxc-device-sync-[0-9]*.service|\
        /run/systemd/system/*.requires/nvidia-lxc-device-sync-[0-9]*.service|\
        /var/lib/nvidia-lxc-device-sync/[0-9]*.devices|\
        /usr/bin/nvidia-smi|/var/lib/nvidia-driver-setup/lxc-nvidia-smi-payload.env)
            rm -f -- "$path"
            ;;
        *) printf '[rollback] Unsicherer Pfad: %s\n' "$path" >&2; exit 3 ;;
    esac
done <"$BACKUP_ROOT/config-paths.tsv"
tar -C / -xpf "$BACKUP_ROOT/config-snapshot.tar"
if [[ -s "$BACKUP_ROOT/legacy-residuals.list0" \
      && -f "$BACKUP_ROOT/legacy-residuals.tar" ]]; then
    legacy_paths_safe=1
    while IFS= read -r -d '' path; do
        case "$path" in
            /etc/nvidia|/etc/nvidia/*|/var/lib/nvidia|/var/lib/nvidia/*|\
            /var/cache/nvidia|/var/cache/nvidia/*|\
            /run/nvidia|/run/nvidia/*|/run/nvidia-persistenced|/run/nvidia-persistenced/*|\
            /usr/local/nvidia|/usr/local/nvidia/*|/usr/lib/nvidia|/usr/lib/nvidia/*|\
            /usr/lib/x86_64-linux-gnu/nvidia|/usr/lib/x86_64-linux-gnu/nvidia/*|\
            /usr/share/nvidia|/usr/share/nvidia/*|/var/lib/dkms/nvidia*|/usr/src/nvidia-*|\
            /etc/modprobe.d/*nvidia*|/etc/modprobe.d/blacklist-nouveau.conf|\
            /etc/ld.so.conf.d/*nvidia*|/etc/OpenCL/vendors/*nvidia*|\
            /etc/vulkan/icd.d/*nvidia*|/etc/vulkan/implicit_layer.d/*nvidia*|\
            /usr/share/vulkan/icd.d/*nvidia*|/usr/share/vulkan/implicit_layer.d/*nvidia*|\
            /usr/share/glvnd/egl_vendor.d/*nvidia*|/etc/X11/xorg.conf|\
            /etc/X11/xorg.conf.d/*nvidia*|/etc/udev/rules.d/*nvidia*|\
            /etc/systemd/system/nvidia*.service|/etc/systemd/system/*/nvidia*.service|\
            /usr/lib/systemd/system/nvidia*.service|/lib/systemd/system/nvidia*.service|\
            /usr/local/lib/libnvidia*|/usr/local/lib/libcuda*|/usr/local/lib/libnvcuvid*|\
            /usr/local/lib64/libnvidia*|/usr/local/lib64/libcuda*|/usr/local/lib64/libnvcuvid*|\
            /usr/lib/x86_64-linux-gnu/libnvidia*|/usr/lib/x86_64-linux-gnu/libcuda*|\
            /usr/lib/x86_64-linux-gnu/libnvcuvid*|/lib/x86_64-linux-gnu/libnvidia*|\
            /lib/x86_64-linux-gnu/libcuda*|/lib/x86_64-linux-gnu/libnvcuvid*|\
            /usr/local/bin/nvidia-smi|/usr/local/bin/nvidia-modprobe|\
            /usr/local/bin/nvidia-settings|/usr/local/bin/nvidia-xconfig|\
            /usr/local/bin/nvidia-persistenced|/usr/local/bin/nvidia-uninstall|\
            /usr/bin/nvidia-smi|/usr/bin/nvidia-uninstall|\
            /var/lib/nvidia-driver-setup/lxc-nvidia-smi-payload.env|/var/log/nvidia-installer.log|\
            /var/log/nvidia-uninstall.log) ;;
            *)
                printf '[rollback] Unsicherer NVIDIA-Restpfad im Archiv: %s\n' "$path" >&2
                legacy_paths_safe=0
                ;;
        esac
    done <"$BACKUP_ROOT/legacy-residuals.list0"
    ((legacy_paths_safe)) \
        || { printf '[rollback] Altdateiarchiv enthält unsichere Pfade.\n' >&2; exit 3; }
    tar -C / -xpf "$BACKUP_ROOT/legacy-residuals.tar"
fi
if command -v apt-mark >/dev/null 2>&1; then
    mapfile -t current_holds < <(apt-mark showhold 2>/dev/null \
        | grep -E "$NVIDIA_REGEX|$NVIDIA_AUX_REGEX|$NVIDIA_REPO_REGEX" || true)
    ((${#current_holds[@]})) && apt-mark unhold "${current_holds[@]}" >/dev/null 2>&1 || true
fi
shopt -s nullglob
debs=("$BACKUP_ROOT"/rollback-debs/*.deb)
shopt -u nullglob
if ((${#debs[@]})); then
    DEBIAN_FRONTEND=noninteractive apt-get -s install --allow-downgrades "${debs[@]}" \
        >"$BACKUP_ROOT/rollback-apt-simulation.log"
    if awk '$1 == "Remv" || $1 == "Purg" {package=$2; sub(/:.*/, "", package); print package}' \
        "$BACKUP_ROOT/rollback-apt-simulation.log" \
        | grep -Eq '^(proxmox-ve|pve-manager|pve-container|proxmox-default-kernel|proxmox-kernel-helper|proxmox-kernel-|pve-kernel-|proxmox-headers-|pve-headers-|linux-image-|linux-headers-|systemd|systemd-sysv|init|openssh-server|apt|dpkg|fileflows)'; then
        printf '[rollback] Kritische Paketentfernung im Installationsplan erkannt; Abbruch.\n' >&2
        exit 3
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades \
        --allow-change-held-packages "${debs[@]}"
fi
while IFS=$'\t' read -r package expected; do
    actual="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
    status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null || true)"
    dpkg --compare-versions "${actual:-0}" eq "$expected" \
        && [[ ${#status} -ge 2 && "${status:1:1}" == "i" && "${status:2:1}" != "R" ]] \
        || { printf '[rollback] Paket %s nicht exakt wiederhergestellt.\n' "$package" >&2; exit 4; }
done <"$BACKUP_ROOT/nvidia-package-versions.tsv"
if command -v apt-mark >/dev/null 2>&1; then
    mapfile -t holds <"$BACKUP_ROOT/apt-holds-before.txt"
    ((${#holds[@]})) && apt-mark hold "${holds[@]}" >/dev/null
fi
command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true
command -v update-initramfs >/dev/null 2>&1 && update-initramfs -u || true
if [[ "$ROLLBACK_COVERAGE" == "exact" ]]; then
    printf '[rollback] Deinstallation exakt zurückgerollt.\n'
else
    printf '[rollback] Gesunde Pakete und Konfigurationen wiederhergestellt; vorbestehende nicht-ii-dpkg-Zustände wurden sicher normalisiert.\n'
fi
EOF_UNINSTALL_ROLLBACK
    } >"$BACKUP_DIR/rollback.sh"
    chmod 0700 "$BACKUP_DIR/rollback.sh"
    {
        printf 'Skriptversion: %s\n' "$SCRIPT_VERSION"
        printf 'Erstellt: %s\n' "$(date --iso-8601=seconds)"
        printf 'Aktion: vollständige NVIDIA-Deinstallation\n'
        printf 'Distribution: %s (%s)\n' "$OS_LABEL" "$DISTRO"
        printf 'Rolle: %s\n' "$MODE"
        printf 'Installierter Treiber: %s\n' "${DETECTED_PACKAGE_DEBIAN_VERSION:-nicht erkannt}"
        printf 'Geladenes Kernelmodul: %s\n' "${DETECTED_HOST_MODULE_VERSION:-nicht geladen}"
        printf 'Rollback-Abdeckung: %s\n' "$ROLLBACK_COVERAGE"
        printf 'Pakete: %s\n' "$(wc -l <"$BACKUP_DIR/nvidia-package-versions.tsv")"
        printf 'Betroffene Dateien:\n'
        printf '  %s\n' "${paths[@]}"
    } >"$BACKUP_DIR/rollback-manifest.txt"
    ROLLBACK_READY=1
    mark_transaction_active
    MUTATION_STARTED=1
}

remove_all_managed_lxc_entries() {
    local config ctid slot helper service state tmp
    command -v pct >/dev/null 2>&1 || return 0
    while IFS= read -r ctid; do
        [[ "$ctid" =~ ^[0-9]+$ ]] || continue
        config="/etc/pve/lxc/${ctid}.conf"
        [[ -f "$config" ]] || continue
        while IFS= read -r slot; do
            [[ "$slot" =~ ^dev[0-9]+$ ]] || continue
            pct set "$ctid" --delete "$slot"
        done < <(pct config "$ctid" 2>/dev/null | awk -F': ' '$1 ~ /^dev[0-9]+$/ && $2 ~ /(^|,)(path=)?\/dev\/nvidia/ {print $1}')
        tmp="$(mktemp "${config}.nvidia-remove.XXXXXX")"
        awk '
            /^# BEGIN NVIDIA-DRIVER-SETUP MANAGED DEVICES$/ { managed = 1; next }
            /^# END NVIDIA-DRIVER-SETUP MANAGED DEVICES$/ { managed = 0; next }
            managed { next }
            /^lxc\.mount\.entry:[[:space:]]+\/dev\/nvidia/ { next }
            { print }
        ' "$config" >"$tmp"
        chmod --reference="$config" "$tmp" 2>/dev/null || true
        chown --reference="$config" "$tmp" 2>/dev/null || true
        mv -f "$tmp" "$config"
        helper="/usr/local/sbin/nvidia-lxc-device-sync-${ctid}.sh"
        service="nvidia-lxc-device-sync-${ctid}.service"
        state="/var/lib/nvidia-lxc-device-sync/${ctid}.devices"
        systemctl disable "$service" >/dev/null 2>&1 || true
        rm -f -- "$helper" "/etc/systemd/system/$service" "$state"
    done < <(pct list 2>/dev/null | awk 'NR > 1 {print $1}')
    rm -f -- /etc/modules-load.d/nvidia-lxc.conf
    systemctl daemon-reload
}

verify_complete_uninstall_state() {
    local leftovers="" holds="" config="" residual_probe
    local -a helper_files=()

    leftovers="$(
        dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null \
            | awk '$2 !~ /^un/ {print $1}' \
            | grep -E "$NVIDIA_DRIVER_REGEX|$NVIDIA_AUXILIARY_REGEX|$NVIDIA_REPOSITORY_PACKAGE_REGEX" || true
    )"
    [[ -z "$leftovers" ]] || {
        warn "Installierte NVIDIA-Treiber-/Bibliothekspakete verblieben: $(tr '\n' ' ' <<<"$leftovers")"
        return 1
    }
    holds="$(apt-mark showhold 2>/dev/null | grep -E "$NVIDIA_DRIVER_REGEX|$NVIDIA_AUXILIARY_REGEX|$NVIDIA_REPOSITORY_PACKAGE_REGEX" || true)"
    [[ -z "$holds" ]] || {
        warn "NVIDIA-Paketholds verblieben: $(tr '\n' ' ' <<<"$holds")"
        return 1
    }
    [[ ! -e /etc/nvidia-container-runtime && ! -e /etc/cdi/nvidia.yaml ]] || {
        warn "NVIDIA-Container-Runtime-/CDI-Konfiguration ist noch vorhanden."
        return 1
    }
    if grep -RqsE 'developer\.download\.nvidia\.com/compute/cuda/repos|file:/var/(cuda-repo|nvidia-driver-local-repo)|/var/(cuda-repo|nvidia-driver-local-repo)' \
        /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
        warn "NVIDIA-spezifische APT-Paketquellen sind noch vorhanden."
        return 1
    fi

    residual_probe="$(mktemp "$TMP_DIR/uninstall-residuals.XXXXXX")"
    BACKUP_DIR="" collect_unowned_legacy_nvidia_residuals >"$residual_probe"
    if [[ -s "$residual_probe" ]]; then
        tr '\0' '\n' <"$residual_probe" >"$BACKUP_DIR/uninstall-residuals-after-verification.txt"
        rm -f -- "$residual_probe"
        warn "Unverwaltete NVIDIA-Dateireste sind nach der Deinstallation noch vorhanden."
        return 1
    fi
    rm -f -- "$residual_probe"

    if [[ "$MODE" == "host" ]]; then
        [[ ! -e /etc/modules-load.d/nvidia-lxc.conf \
           && ! -e /etc/modprobe.d/blacklist-nouveau.conf ]] || {
            warn "Vom Skript verwaltete NVIDIA-Modulkonfiguration ist noch vorhanden."
            return 1
        }
        while IFS= read -r -d '' config; do helper_files+=("$config"); done < <(
            find /usr/local/sbin /etc/systemd/system /var/lib/nvidia-lxc-device-sync \
                -maxdepth 1 -type f \
                \( -name 'nvidia-lxc-device-sync-*.sh' \
                   -o -name 'nvidia-lxc-device-sync-*.service' -o -name '*.devices' \) \
                -print0 2>/dev/null || true
        )
        ((${#helper_files[@]} == 0)) || {
            warn "Verwaltete NVIDIA-LXC-Helfer sind noch vorhanden: ${helper_files[*]}"
            return 1
        }
        while IFS= read -r -d '' config; do
            if grep -qE '(^dev[0-9]+:[[:space:]]+((path=)?/dev/nvidia)|^# (BEGIN|END) NVIDIA-DRIVER-SETUP MANAGED DEVICES$|^lxc\.mount\.entry:[[:space:]]+/dev/nvidia)' "$config"; then
                warn "NVIDIA-Geräteeinträge verblieben in $config"
                return 1
            fi
        done < <(find /etc/pve/lxc -maxdepth 1 -type f -name '*.conf' -print0 2>/dev/null || true)
    fi
    return 0
}

run_complete_uninstall() {
    local package
    local -a packages=() held=()
    PACKAGE_MUTATION_ALLOWED=1
    CONFIG_MUTATION_ALLOWED=1
    TRANSACTION_ACTION="uninstall"

    if ((ASSUME_YES == 0)); then
        if [[ "$MODE" == "lxc" ]]; then
            printf '\nAlle paketverwalteten NVIDIA-Userspace-Bibliotheken, CUDA-Toolkits, NVIDIA Container Toolkits und LXC-internen NVIDIA-Konfigurationen werden entfernt. Kernel/DKMS und die Gerätezuweisung auf dem Proxmox-Host bleiben unverändert.\n'
        else
            printf '\nAlle paketverwalteten NVIDIA-Treiber, NVIDIA-/CUDA-Bibliotheken, CUDA-Toolkits, NVIDIA Container Toolkits und verwalteten LXC-Geräteeinträge werden entfernt.\n'
        fi
        printf 'Persönliche Projekte, Medien, Docker-Volumes und FileFlows-Nutzdaten bleiben erhalten.\n'
        read -r -p 'Vollständige Entfernung starten? [j/N]: ' ANSWER
        [[ "$ANSWER" =~ ^([jJ]|[jJ][aA])$ ]] || die "Vom Benutzer abgebrochen."
    fi

    # Ein fremder Runfile-Uninstaller besitzt kein verlässliches Debian-
    # Dateimanifest und kann daher nicht transaktional zurückgerollt werden.
    # Fail-closed vor jeder Änderung statt einen falschen Vollerfolg zu melden.
    remove_runfile_installation

    if ((RESUME_REQUEST)); then
        verify_backup_checksums "$BACKUP_DIR" || die "Fortsetzen verweigert: Sicherung beschädigt."
        ROLLBACK_READY=1
        MUTATION_STARTED=1
        write_transaction_phase deinstallation-fortgesetzt
    else
        prepare_uninstall_backup
    fi
    if [[ -r "$BACKUP_DIR/nvidia-purge-candidates.txt" ]]; then
        mapfile -t packages < <(sed '/^$/d' "$BACKUP_DIR/nvidia-purge-candidates.txt")
    else
        # Kompatibilität mit bereits vorhandenen, älteren Sicherungen.
        mapfile -t packages < <(cut -f1 "$BACKUP_DIR/nvidia-package-versions.tsv" | sed '/^$/d')
    fi
    mapfile -t held < <(apt-mark showhold 2>/dev/null \
        | grep -E "$NVIDIA_DRIVER_REGEX|$NVIDIA_AUXILIARY_REGEX|$NVIDIA_REPOSITORY_PACKAGE_REGEX" || true)
    ((${#held[@]})) && apt_mark_mutate unhold "${held[@]}"
    if ((${#packages[@]})); then
        DEBIAN_FRONTEND=noninteractive apt_mutate purge -y "${packages[@]}"
    fi
    begin_config_mutation
    clean_apt_entries 'developer\.download\.nvidia\.com/compute/cuda/repos|file:/var/(cuda-repo|nvidia-driver-local-repo)|/var/(cuda-repo|nvidia-driver-local-repo)'
    rm -f -- /var/lib/extrepo/keys/nvidia-cuda.asc \
        /etc/apt/keyrings/nvidia-cuda.asc \
        /etc/apt/keyrings/cuda-archive-keyring.gpg \
        /usr/share/keyrings/nvidia-cuda-keyring.gpg \
        /usr/share/keyrings/cuda-archive-keyring.gpg
    find /etc/apt/preferences.d -maxdepth 1 -type f \
        \( -iname 'cuda-repository-pin-*' -o -iname 'nvidia-driver-pinning*' -o -iname '*nvidia*pin*' \) \
        -delete 2>/dev/null || true
    if [[ "$MODE" == "host" ]]; then
        begin_config_mutation
        remove_all_managed_lxc_entries
        rm -f -- /etc/modprobe.d/blacklist-nouveau.conf
        command -v update-initramfs >/dev/null 2>&1 && update-initramfs -u || true
    fi
    begin_config_mutation
    rm -rf -- /etc/nvidia-container-runtime
    rm -f -- /etc/cdi/nvidia.yaml
    quarantine_legacy_nvidia_residuals
    printf 'Archivierte unverwaltete NVIDIA-Altdateien: %s\n' \
        "$(wc -l <"$BACKUP_DIR/legacy-residuals.txt" 2>/dev/null || printf 0)" \
        >>"$BACKUP_DIR/rollback-manifest.txt"
    refresh_backup_checksums
    verify_complete_uninstall_state \
        || die "Die vollständige Deinstallationsprüfung ist fehlgeschlagen."
    if [[ "$MODE" == "host" ]] \
       && { [[ -d /sys/module/nvidia ]] || lsmod 2>/dev/null | grep -q '^nvidia'; }; then
        REBOOT_REQUIRED=1
        append_unique REBOOT_REASONS "NVIDIA-Kernelmodule sind nach der Paketentfernung noch geladen"
        block_success_backup_cleanup "NVIDIA-Kernelmodule müssen durch einen Host-Neustart entladen werden"
    fi
    write_transaction_phase abgeschlossen
    TRANSACTION_FINISHED=1
    clear_transaction_marker
    cleanup_old_backups "$BACKUP_RETENTION_DAYS"
    if ((SUCCESS_BACKUP_CLEANUP_BLOCKED)); then
        printf '\n\033[1;33mNVIDIA-Pakete vollständig entfernt; Neustartprüfung ausstehend.\033[0m\n'
    else
        printf '\n\033[1;32mNVIDIA vollständig entfernt und geprüft.\033[0m\n'
    fi
    printf 'Sicherung: %s\n' "$BACKUP_DIR"
    [[ "$MODE" == "host" ]] \
        && printf 'Kein LXC wurde gestartet, gestoppt oder neu gestartet; die erfassten Zustände dienten nur dem möglichen Rollback.\n'
    ((REBOOT_REQUIRED == 0)) \
        || printf 'Host-Neustart erforderlich: Danach Menüpunkt 8 zur Abschlussprüfung verwenden.\n'
    cleanup_successful_transaction_backup
    emit_machine_result
    write_success_completion_report \
        || warn "Die Deinstallation war erfolgreich, aber der Abschlussbericht konnte nicht gespeichert werden."
}

restore_pending_lxc_start() {
    ((PENDING_LXC_STARTED_BY_FINALIZER)) || return 0
    log "Stelle den ursprünglich gestoppten LXC $TARGET_LXC_ID wieder auf gestoppt."
    if shutdown_lxc_controlled >/dev/null 2>&1; then
        PENDING_LXC_STARTED_BY_FINALIZER=0
        return 0
    fi
    warn "LXC $TARGET_LXC_ID konnte nach der Abschlussprüfung nicht wieder gestoppt werden."
    return 1
}

prepare_pending_lxc_runtime() {
    local state choice
    PENDING_LXC_STARTED_BY_FINALIZER=0
    state="$(lxc_current_state 2>/dev/null || true)"
    case "$state" in
        running)
            [[ "${PENDING_LXC_ORIGINAL_STATE:-}" != "stopped" ]] \
                || PENDING_LXC_STARTED_BY_FINALIZER=1
            return 0
            ;;
        stopped)
            if ((LXC_TEMPORARY_START_ALLOWED == 0)) && ((ORIGINAL_ARGC == 0)); then
                menu_section "LXC-LAUFZEITPRÜFUNG"
                menu_note "LXC $TARGET_LXC_ID ist gestoppt. Für die Abschlussprüfung muss er kurz gestartet werden."
                menu_item 1 "Jetzt temporär starten und danach wieder stoppen"
                menu_item 2 "Prüfung verschieben  [Standard]"
                choice="$(menu_read 'Auswahl [2]: ')"
                choice="${choice:-2}"
                case "$choice" in
                    1) LXC_TEMPORARY_START_ALLOWED=1 ;;
                    2) ;;
                    *) warn "Ungültige Auswahl: $choice"; return 1 ;;
                esac
            fi
            ((LXC_TEMPORARY_START_ALLOWED)) || {
                warn "LXC $TARGET_LXC_ID bleibt gestoppt; die Sicherung bleibt erhalten."
                return 2
            }
            pct start "$TARGET_LXC_ID" || return 1
            PENDING_LXC_STARTED_BY_FINALIZER=1
            wait_for_lxc_exec || {
                restore_pending_lxc_start || true
                return 1
            }
            ;;
        *) warn "LXC-Zustand konnte nicht sicher ermittelt werden: ${state:-unbekannt}"; return 1 ;;
    esac
}

verify_pending_lxc_gpu_identity() {
    local output line uuid bus expected_uuid expected_bus
    local actual_count expected_count=0 max_expected=0 matched
    local i j
    local -a expected_uuids=() expected_buses=() actual_uuids=() actual_buses=() used=()

    if ! output="$(pct exec "$TARGET_LXC_ID" -- nvidia-smi \
            --query-gpu=uuid,pci.bus_id --format=csv,noheader 2>/dev/null)"; then
        warn "Die GPU-Identitäten können in LXC $TARGET_LXC_ID noch nicht über NVML gelesen werden."
        return 1
    fi
    printf '%s\n' "$output" >"$BACKUP_DIR/pending-lxc-gpu-identities-after.txt"
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS=',' read -r uuid bus <<<"$line"
        uuid="${uuid//[[:space:]]/}"
        bus="$(normalize_pci_bus_id "${bus//[[:space:]]/}")"
        [[ -n "$uuid" || -n "$bus" ]] || continue
        actual_uuids+=("${uuid^^}")
        actual_buses+=("${bus^^}")
    done <<<"$output"

    max_expected="${#TARGET_GPU_UUIDS[@]}"
    ((${#TARGET_GPU_BUS_IDS[@]} <= max_expected)) || max_expected="${#TARGET_GPU_BUS_IDS[@]}"
    for ((i = 0; i < max_expected; i++)); do
        expected_uuid="${TARGET_GPU_UUIDS[$i]:-}"
        expected_bus="$(normalize_pci_bus_id "${TARGET_GPU_BUS_IDS[$i]:-}")"
        [[ -n "$expected_uuid" || -n "$expected_bus" ]] || continue
        expected_uuids+=("${expected_uuid^^}")
        expected_buses+=("${expected_bus^^}")
        expected_count=$((expected_count + 1))
    done
    actual_count="${#actual_uuids[@]}"
    ((expected_count > 0)) || { warn "Keine stabile erwartete GPU-Identität ist gespeichert."; return 1; }
    [[ "$actual_count" -eq "$expected_count" ]] || {
        warn "LXC $TARGET_LXC_ID sieht $actual_count GPU(s), erwartet wird exakt die ausgewählte Menge von $expected_count GPU(s)."
        return 1
    }

    for ((i = 0; i < expected_count; i++)); do
        matched=0
        for ((j = 0; j < actual_count; j++)); do
            [[ "${used[$j]:-0}" == "0" ]] || continue
            [[ -z "${expected_uuids[$i]}" || "${actual_uuids[$j]}" == "${expected_uuids[$i]}" ]] || continue
            [[ -z "${expected_buses[$i]}" || "${actual_buses[$j]}" == "${expected_buses[$i]}" ]] || continue
            used[$j]=1
            matched=1
            break
        done
        ((matched)) || {
            warn "Die in LXC $TARGET_LXC_ID sichtbare GPU-Menge entspricht nicht den gespeicherten UUID-/PCI-Identitäten."
            return 1
        }
    done
    ok "Exakte GPU-UUID-/PCI-Menge im LXC bestätigt."
    return 0
}

verify_pending_lxc_runtime() {
    local installed nvml

    if ((PENDING_VERIFY_GPU)); then
        verify_pending_lxc_gpu_identity || return 1
        pct exec "$TARGET_LXC_ID" -- sh -c '
            test -c /dev/nvidiactl && test -c /dev/nvidia-uvm || exit 1
            found=0
            for device in /dev/nvidia[0-9]*; do
                test -c "$device" && found=1
            done
            test "$found" -eq 1
        ' || {
            warn "Die NVIDIA-Geräte sind in LXC $TARGET_LXC_ID noch nicht vollständig sichtbar."
            return 1
        }
    fi

    if ((PENDING_VERIFY_USERSPACE)); then
        installed="$(pct exec "$TARGET_LXC_ID" -- dpkg-query -W -f='${Version}' \
            libnvidia-compute 2>/dev/null \
            || pct exec "$TARGET_LXC_ID" -- dpkg-query -W -f='${Version}' libnvidia-ml1 2>/dev/null \
            || true)"
        [[ "$(normalize_driver_version "$installed")" == "$TARGET_VERSION" ]] || {
            warn "LXC-Userspace '${installed:-fehlt}' entspricht nicht $TARGET_VERSION."
            return 1
        }
        if pct exec "$TARGET_LXC_ID" -- dpkg-query -W \
            -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null \
            | awk -F'\t' '$2 !~ /^un/ {print $1}' \
            | grep -Eq "$LXC_FORBIDDEN_PACKAGE_REGEX"; then
            warn "Im LXC sind weiterhin NVIDIA-Kernel-/DKMS-/Host-Hilfspakete installiert."
            return 1
        fi
        nvml="$(pct exec "$TARGET_LXC_ID" -- nvidia-smi \
            --query-gpu=driver_version --format=csv,noheader 2>/dev/null \
            | head -n1 || true)"
        [[ "$(normalize_driver_version "$nvml")" == "$TARGET_VERSION" ]] || {
            warn "NVML im LXC meldet '${nvml:-fehlt}', erwartet wurde $TARGET_VERSION."
            return 1
        }
        if run_remote_lxc_transcode_smoke_test; then
            :
        else
            [[ $? -eq 2 ]] || return 1
        fi
    fi
    return 0
}

verify_pending_local_runtime() {
    local effective_mode="$1" smoke_rc=0

    detect_driver_versions "$effective_mode"
    if [[ "$PENDING_ACTION" == "uninstall" ]]; then
        verify_complete_uninstall_state || return 1
        if [[ "$effective_mode" == "host" ]] \
           && { [[ -d /sys/module/nvidia ]] || lsmod 2>/dev/null | grep -q '^nvidia'; }; then
            warn "NVIDIA-Kernelmodule sind noch geladen; zuerst den Host neu starten."
            return 1
        fi
        if compgen -G '/dev/nvidia*' >/dev/null; then
            warn "NVIDIA-Gerätedateien sind nach der Deinstallation noch vorhanden."
            return 1
        fi
        return 0
    fi
    if [[ "$PENDING_ACTION" == "attach" ]]; then
        return 0
    fi
    if [[ "$PENDING_ACTION" == update ]]; then
        if ! (load_nvidia_update_plan; verify_nvidia_update_packages; verify_nvidia_update_binding); then
            warn "Die gespeicherten exakten Updateversionen oder ihre Versionsbindung stimmen nicht mehr. Sicherung bleibt erhalten."
            return 1
        fi
    fi

    is_valid_driver_version "$TARGET_VERSION" || {
        warn "Die gespeicherte Zielversion ist ungültig: ${TARGET_VERSION:-leer}"
        return 1
    }
    if [[ "$effective_mode" == "host" ]]; then
        [[ "$DETECTED_HOST_MODULE_VERSION" == "$TARGET_VERSION" \
           && "$DETECTED_INSTALLED_MODULE_VERSION" == "$TARGET_VERSION" \
           && "$DETECTED_PACKAGE_VERSION" == "$TARGET_VERSION" ]] || {
            warn "Host-Versionen sind noch nicht konsistent: $DETECTED_VERSION_STATE"
            return 1
        }
        detect_reboot_requirement
        ((REBOOT_REQUIRED == 0)) || return 1
    else
        [[ "$DETECTED_HOST_MODULE_VERSION" == "$TARGET_VERSION" \
           && "$DETECTED_PACKAGE_VERSION" == "$TARGET_VERSION" ]] || {
            warn "LXC-Userspace und Host-Modul stimmen noch nicht exakt überein: $DETECTED_VERSION_STATE"
            return 1
        }
        nvidia_runtime_devices_ready /dev || {
            warn "Die NVIDIA-Gerätefreigabe im LXC ist unvollständig: $(nvidia_runtime_device_missing_summary /dev)"
            return 1
        }
    fi

    DIAGNOSTIC_ERROR_COUNT=0
    run_local_diagnostics "$effective_mode"
    ((DIAGNOSTIC_ERROR_COUNT == 0)) || return 1
    if run_local_transcode_smoke_test; then
        :
    else
        smoke_rc=$?
        ((smoke_rc == 2)) || return 1
    fi
    return 0
}

finalize_remote_backup_during_pending_check() {
    local directory="${LXC_REMOTE_SUCCESS_BACKUP:-}" finalize_log
    [[ -n "$directory" ]] || return 0
    is_safe_remote_backup_path "$directory" || return 1
    [[ "$(lxc_current_state 2>/dev/null || true)" == "running" ]] || {
        warn "Die zugehörige LXC-Sicherung kann nur bei laufendem LXC finalisiert werden."
        return 2
    }
    pct exec "$TARGET_LXC_ID" -- test -d "$directory" >/dev/null 2>&1 || {
        warn "Die gespeicherte LXC-Sicherung ist nicht mehr vorhanden: $directory"
        return 1
    }

    if pct exec "$TARGET_LXC_ID" -- test -f \
            "$directory/pending-verification.env" >/dev/null 2>&1; then
        [[ -f "$0" ]] || return 1
        finalize_log="$BACKUP_DIR/lxc-${TARGET_LXC_ID}-remote-finalize.log"
        pct push "$TARGET_LXC_ID" "$0" "$LXC_REMOTE_SCRIPT_PATH" --perms 0700 \
            || return 2
        LXC_REMOTE_SCRIPT_PENDING=1
        write_resume_state && refresh_backup_checksums || return 1
        if ! pct exec "$TARGET_LXC_ID" -- env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
                "$LXC_REMOTE_SCRIPT_PATH" --finalize-pending "$directory" \
                >"$finalize_log" 2>&1; then
            cleanup_remote_lxc_script || true
            warn "Die LXC-interne Abschlussprüfung ist weiterhin offen. Details: $finalize_log"
            return 2
        fi
        cleanup_remote_lxc_script || {
            warn "Das temporäre Prüfsystem konnte im LXC nicht vollständig entfernt werden."
            return 2
        }
    fi

    LXC_REMOTE_RESULT="success"
    verify_remote_lxc_transaction_result success "$directory" || {
        warn "Die finalisierte LXC-Sicherung besteht die Remote-Prüfsummen-/Statusprüfung nicht."
        return 1
    }
    if ((KEEP_SUCCESS_BACKUP)); then
        LXC_REMOTE_BACKUP_CLEANUP_PENDING=0
        LXC_REMOTE_SUCCESS_BACKUP="$directory"
        write_resume_state && refresh_backup_checksums || return 1
        log "Zugehörige LXC-Sicherung ist finalisiert und wird auf Wunsch behalten: $directory"
        return 0
    fi
    remove_completed_remote_lxc_backup "$directory" || {
        warn "Die finalisierte LXC-Sicherung konnte nicht sicher entfernt werden."
        return 2
    }
    ok "LXC-Erfolgssicherung entfernt: $directory"
    LXC_REMOTE_SUCCESS_BACKUP=""
    LXC_REMOTE_RESULT=""
    LXC_REMOTE_BACKUP_CLEANUP_PENDING=0
    write_resume_state && refresh_backup_checksums
}

run_pending_finalization() {
    local directory="$FINALIZE_PENDING_REQUEST" phase current_mode
    local pending_file started_restore_rc=0 pending_target legacy_identity_file legacy_bus_line legacy_uuid_line value
    local -a migrated_bus_ids=() migrated_uuids=()
    PENDING_SCHEMA_VERSION=""
    PENDING_SCRIPT_VERSION=""
    PENDING_MODE=""
    PENDING_ACTION=""
    PENDING_TARGET_VERSION=""
    # Schema 1 kann diese neueren Felder noch nicht enthalten haben. Der
    # konservative Migrationsstandard erweitert einen alten Lauf nicht.
    PENDING_CLEAN_INSTALL_SCOPE="driver"
    PENDING_KEEP_SUCCESS_BACKUP=1
    PENDING_DELETE_SUCCESS_LOGS=1
    PENDING_TARGET_LXC_ID=""
    PENDING_TARGET_LXC_NAME=""
    PENDING_TARGET_GPU_SELECTION_SUMMARY=""
    PENDING_TARGET_GPU_SELECTORS=()
    PENDING_TARGET_GPU_UUIDS=()
    PENDING_TARGET_GPU_BUS_IDS=()
    PENDING_LXC_DEVICE_BACKEND="auto"
    PENDING_LXC_DEVICE_MODE="0666"
    PENDING_LXC_DEVICE_UID=""
    PENDING_LXC_DEVICE_GID=""
    PENDING_VERIFY_GPU=0
    PENDING_VERIFY_USERSPACE=0
    PENDING_REMOTE_BACKUP=""
    PENDING_LXC_ORIGINAL_STATE=""
    PENDING_TRANSCODE_SMOKE_TEST="auto"
    PENDING_NVTOP_MANAGEMENT="auto"
    PENDING_STOPPED_GPU_CONSUMERS=()
    PENDING_NVIDIA_PERSISTENCED_WAS_ACTIVE=0
    PENDING_REASONS=()

    is_safe_backup_dir "$directory" || { warn "Unsichere ausstehende Sicherung: $directory"; return 1; }
    pending_file="$directory/pending-verification.env"
    [[ -r "$pending_file" ]] || { warn "Die Sicherung enthält keine ausstehende Abschlussprüfung."; return 1; }
    verify_backup_checksums "$directory" || { warn "Prüfsummen der ausstehenden Sicherung sind fehlerhaft."; return 1; }
    backup_manifest_contains_relative_file "$directory" './pending-verification.env' \
        || { warn "Die ausstehende Abschlussprüfung ist nicht im Prüfsummenmanifest erfasst."; return 1; }
    phase="$(backup_transaction_phase "$directory" 2>/dev/null || true)"
    [[ "$phase" == "abgeschlossen" ]] || { warn "Transaktion ist nicht abgeschlossen: ${phase:-unbekannt}"; return 1; }
    # Nur von diesem Skript mit printf %q erzeugte und zuvor per Prüfsumme geprüfte Werte laden.
    # shellcheck disable=SC1090
    source "$pending_file"

    case "$PENDING_SCHEMA_VERSION" in
        1|2)
            # Ältere Schemata speicherten Umfang, Gerätezugriff, GPU-Identität
            # und Löschrichtlinie nicht vollständig. Die Sicherung wird niemals
            # aufgrund erfundener Defaults gelöscht.
            PENDING_CLEAN_INSTALL_SCOPE="driver"
            PENDING_KEEP_SUCCESS_BACKUP=1
            PENDING_LXC_DEVICE_BACKEND="auto"
            PENDING_LXC_DEVICE_MODE="0666"
            PENDING_LXC_DEVICE_UID=""
            PENDING_LXC_DEVICE_GID=""
            warn "Legacy-Abschlussprüfung (Schema $PENDING_SCHEMA_VERSION): nicht sicher gespeicherte Einstellungen werden als unbekannt ausgewiesen; die Erfolgssicherung bleibt erhalten."
            ;;
        "$PENDING_SCHEMA_CURRENT")
            for pending_target in \
                PENDING_SCRIPT_VERSION PENDING_MODE PENDING_ACTION \
                PENDING_TARGET_VERSION PENDING_CLEAN_INSTALL_SCOPE \
                PENDING_KEEP_SUCCESS_BACKUP PENDING_TARGET_LXC_ID \
                PENDING_TARGET_LXC_NAME PENDING_TARGET_GPU_SELECTION_SUMMARY \
                PENDING_TARGET_GPU_SELECTORS PENDING_TARGET_GPU_UUIDS \
                PENDING_TARGET_GPU_BUS_IDS PENDING_LXC_DEVICE_BACKEND \
                PENDING_LXC_DEVICE_MODE PENDING_LXC_DEVICE_UID \
                PENDING_LXC_DEVICE_GID PENDING_VERIFY_GPU \
                PENDING_VERIFY_USERSPACE PENDING_REMOTE_BACKUP \
                PENDING_LXC_ORIGINAL_STATE PENDING_TRANSCODE_SMOKE_TEST \
                PENDING_STOPPED_GPU_CONSUMERS PENDING_NVIDIA_PERSISTENCED_WAS_ACTIVE \
                PENDING_REASONS; do
                grep -q "^${pending_target}=" "$pending_file" || {
                    warn "Ausstehende Abschlussprüfung ist unvollständig: $pending_target fehlt."
                    return 1
                }
            done
            ;;
        *) warn "Nicht unterstütztes Format der ausstehenden Abschlussprüfung."; return 1 ;;
    esac
    [[ -n "$PENDING_SCRIPT_VERSION" ]] \
        || { warn "Die ausstehende Abschlussprüfung enthält keine Skriptversion."; return 1; }
    case "$PENDING_MODE" in host|lxc) ;; *) warn "Ungültige gespeicherte Rolle: $PENDING_MODE"; return 1 ;; esac
    case "$PENDING_ACTION" in install|update|uninstall|attach|lxc-complete|lxc-userspace|lxc-update|repair) ;;
        *) warn "Ungültige gespeicherte Aktion: $PENDING_ACTION"; return 1 ;;
    esac
    [[ "$PENDING_VERIFY_GPU" =~ ^[01]$ && "$PENDING_VERIFY_USERSPACE" =~ ^[01]$ ]] \
        || { warn "Ungültige gespeicherte LXC-Prüfkennzeichen."; return 1; }
    case "$PENDING_TRANSCODE_SMOKE_TEST" in auto|yes|no) ;;
        *) warn "Ungültiger gespeicherter Transcoding-Testmodus."; return 1 ;;
    esac
    case "$PENDING_NVTOP_MANAGEMENT" in auto|install|skip) ;;
        *) warn "Ungültiger gespeicherter nvtop-Modus."; return 1 ;;
    esac
    case "$PENDING_CLEAN_INSTALL_SCOPE" in full|driver) ;;
        *) warn "Ungültiger gespeicherter Neuinstallationsumfang."; return 1 ;;
    esac
    [[ "$PENDING_KEEP_SUCCESS_BACKUP" =~ ^[01]$ ]] \
        || { warn "Ungültige gespeicherte Erfolgssicherungsrichtlinie."; return 1; }
    [[ "$PENDING_DELETE_SUCCESS_LOGS" =~ ^[01]$ ]] \
        || { warn "Ungültige gespeicherte Erfolgslog-Richtlinie."; return 1; }
    case "$PENDING_LXC_DEVICE_BACKEND" in auto|native|manual) ;;
        *) warn "Ungültiges gespeichertes LXC-Gerätebackend."; return 1 ;;
    esac
    [[ "$PENDING_LXC_DEVICE_MODE" == "inherit" || "$PENDING_LXC_DEVICE_MODE" =~ ^0[0-7]{3}$ ]] \
        || { warn "Ungültiger gespeicherter LXC-Gerätemodus."; return 1; }
    [[ -z "$PENDING_LXC_DEVICE_UID" || "$PENDING_LXC_DEVICE_UID" =~ ^[0-9]+$ ]] \
        || { warn "Ungültige gespeicherte LXC-Geräte-UID."; return 1; }
    [[ -z "$PENDING_LXC_DEVICE_GID" || "$PENDING_LXC_DEVICE_GID" =~ ^[0-9]+$ ]] \
        || { warn "Ungültige gespeicherte LXC-Geräte-GID."; return 1; }
    [[ "$PENDING_NVIDIA_PERSISTENCED_WAS_ACTIVE" =~ ^[01]$ ]] \
        || { warn "Ungültiger gespeicherter Status von nvidia-persistenced."; return 1; }
    for pending_target in "${PENDING_STOPPED_GPU_CONSUMERS[@]}"; do
        [[ -z "$pending_target" ]] && continue
        gpu_consumer_target_is_valid "$pending_target" \
            || { warn "Ungültiges gespeichertes GPU-Dienstziel: $pending_target"; return 1; }
    done
    [[ -z "$PENDING_TARGET_LXC_ID" || "$PENDING_TARGET_LXC_ID" =~ ^[0-9]+$ ]] \
        || { warn "Ungültige gespeicherte LXC-ID."; return 1; }
    case "$PENDING_LXC_ORIGINAL_STATE" in ""|running|stopped) ;;
        *) warn "Ungültiger gespeicherter LXC-Ursprungszustand."; return 1 ;;
    esac
    [[ -z "$PENDING_REMOTE_BACKUP" ]] || is_safe_remote_backup_path "$PENDING_REMOTE_BACKUP" \
        || { warn "Unsicherer gespeicherter LXC-Sicherungspfad."; return 1; }
    if ((PENDING_VERIFY_GPU || PENDING_VERIFY_USERSPACE)); then
        [[ "$PENDING_TARGET_LXC_ID" =~ ^[0-9]+$ ]] \
            || { warn "Für die gespeicherte LXC-Prüfung fehlt eine gültige LXC-ID."; return 1; }
        case "$PENDING_LXC_ORIGINAL_STATE" in running|stopped) ;;
            *) warn "Für die gespeicherte LXC-Prüfung fehlt der ursprüngliche LXC-Zustand."; return 1 ;;
        esac
    fi
    if [[ "$PENDING_ACTION" == "attach" && "$PENDING_VERIFY_GPU" != "1" ]]; then
        warn "Eine ausstehende reine GPU-Zuweisung muss die GPU-Laufzeitprüfung enthalten."
        return 1
    fi
    if ((PENDING_VERIFY_USERSPACE)) && [[ "$PENDING_MODE" == "host" ]]; then
        [[ -n "$PENDING_REMOTE_BACKUP" ]] \
            || { warn "Zur Host-gesteuerten LXC-Userspace-Prüfung fehlt die Remote-Rollbackbasis."; return 1; }
    fi

    # Schema 1/2 kann die stabile Identität aus dem bereits geprüften
    # Passthrough-Bericht migrieren. Ohne UUID/PCI-ID bleibt die Prüfung offen.
    if ((PENDING_VERIFY_GPU && ${#PENDING_TARGET_GPU_UUIDS[@]} == 0 \
          && ${#PENDING_TARGET_GPU_BUS_IDS[@]} == 0)); then
        legacy_identity_file="$directory/lxc-${PENDING_TARGET_LXC_ID}-gpu-passthrough.txt"
        if [[ -r "$legacy_identity_file" ]] \
           && backup_manifest_contains_relative_file "$directory" ".${legacy_identity_file#"$directory"}"; then
            legacy_bus_line="$(sed -n 's/^GPU-PCI-Bus-IDs: //p' "$legacy_identity_file" | head -n1)"
            legacy_uuid_line="$(sed -n 's/^GPU-UUIDs: //p' "$legacy_identity_file" | head -n1)"
            if [[ -n "$legacy_bus_line" ]]; then
                IFS=',' read -r -a PENDING_TARGET_GPU_BUS_IDS <<<"$legacy_bus_line"
            elif [[ -n "$legacy_uuid_line" ]]; then
                IFS=',' read -r -a PENDING_TARGET_GPU_UUIDS <<<"$legacy_uuid_line"
            fi
            for value in "${PENDING_TARGET_GPU_BUS_IDS[@]}"; do
                value="${value#${value%%[![:space:]]*}}"
                value="${value%${value##*[![:space:]]}}"
                [[ -z "$value" ]] || migrated_bus_ids+=("$(normalize_pci_bus_id "$value")")
            done
            if ((${#migrated_bus_ids[@]})); then
                PENDING_TARGET_GPU_BUS_IDS=("${migrated_bus_ids[@]}")
            fi
            for value in "${PENDING_TARGET_GPU_UUIDS[@]}"; do
                value="${value#${value%%[![:space:]]*}}"
                value="${value%${value##*[![:space:]]}}"
                [[ -z "$value" ]] || migrated_uuids+=("$value")
            done
            if ((${#migrated_uuids[@]})); then
                PENDING_TARGET_GPU_UUIDS=("${migrated_uuids[@]}")
            fi
            if [[ -z "$PENDING_TARGET_GPU_SELECTION_SUMMARY" ]] \
               && ((${#PENDING_TARGET_GPU_UUIDS[@]} || ${#PENDING_TARGET_GPU_BUS_IDS[@]})); then
                PENDING_TARGET_GPU_SELECTION_SUMMARY="Legacy; über UUID/PCI verifiziert: $(join_by ', ' \
                    "${PENDING_TARGET_GPU_UUIDS[@]}" "${PENDING_TARGET_GPU_BUS_IDS[@]}")"
            fi
        fi
        if ((${#PENDING_TARGET_GPU_UUIDS[@]} == 0 && ${#PENDING_TARGET_GPU_BUS_IDS[@]} == 0)); then
            warn "Die alte Sicherung enthält keine prüfbare GPU-UUID/PCI-ID. Richte die GPU-Zuweisung mit der aktuellen Skriptversion erneut ein; diese Sicherung wird nicht gelöscht."
            return 2
        fi
    fi
    for value in "${PENDING_TARGET_GPU_UUIDS[@]}"; do
        [[ -z "$value" || "$value" =~ ^GPU-[A-Za-z0-9-]+$ ]] \
            || { warn "Ungültige gespeicherte GPU-UUID: $value"; return 1; }
    done
    for value in "${PENDING_TARGET_GPU_BUS_IDS[@]}"; do
        [[ -z "$value" || "$(normalize_pci_bus_id "$value")" =~ ^[0-9A-F]{4}:[0-9A-F]{2}:[0-9A-F]{2}\.[0-7]$ ]] \
            || { warn "Ungültige gespeicherte GPU-PCI-ID: $value"; return 1; }
    done
    current_mode="$MODE"
    [[ "$current_mode" == "$PENDING_MODE" ]] || {
        warn "Diese Sicherung gehört zur Rolle $PENDING_MODE, aktuell erkannt wurde $current_mode."
        return 1
    }
    BACKUP_DIR="$directory"
    TARGET_VERSION="$PENDING_TARGET_VERSION"
    TARGET_LXC_ID="$PENDING_TARGET_LXC_ID"
    TARGET_LXC_NAME="$PENDING_TARGET_LXC_NAME"
    TARGET_GPU_SELECTION_SUMMARY="$PENDING_TARGET_GPU_SELECTION_SUMMARY"
    TARGET_GPU_SELECTORS=("${PENDING_TARGET_GPU_SELECTORS[@]}")
    TARGET_GPU_UUIDS=("${PENDING_TARGET_GPU_UUIDS[@]}")
    TARGET_GPU_BUS_IDS=("${PENDING_TARGET_GPU_BUS_IDS[@]}")
    TRANSACTION_ACTION="$PENDING_ACTION"
    CLEAN_INSTALL_SCOPE="$PENDING_CLEAN_INSTALL_SCOPE"
    TRANSCODE_SMOKE_TEST="$PENDING_TRANSCODE_SMOKE_TEST"
    NVTOP_MANAGEMENT="$PENDING_NVTOP_MANAGEMENT"
    LXC_DEVICE_BACKEND="$PENDING_LXC_DEVICE_BACKEND"
    LXC_DEVICE_MODE="$PENDING_LXC_DEVICE_MODE"
    LXC_DEVICE_UID="$PENDING_LXC_DEVICE_UID"
    LXC_DEVICE_GID="$PENDING_LXC_DEVICE_GID"
    CONFIGURE_LXC_GPU="$PENDING_VERIFY_GPU"
    INSTALL_LXC_USERSPACE_FROM_HOST="$PENDING_VERIFY_USERSPACE"
    LXC_REMOTE_SUCCESS_BACKUP="$PENDING_REMOTE_BACKUP"
    LXC_ORIGINAL_STATE="$PENDING_LXC_ORIGINAL_STATE"
    STOPPED_GPU_CONSUMERS=()
    for pending_target in "${PENDING_STOPPED_GPU_CONSUMERS[@]}"; do
        [[ -z "$pending_target" ]] || STOPPED_GPU_CONSUMERS+=("$pending_target")
    done
    NVIDIA_PERSISTENCED_WAS_ACTIVE="$PENDING_NVIDIA_PERSISTENCED_WAS_ACTIVE"
    TRANSACTION_FINISHED=1
    KEEP_SUCCESS_BACKUP="$PENDING_KEEP_SUCCESS_BACKUP"
    DELETE_SUCCESS_LOGS="$PENDING_DELETE_SUCCESS_LOGS"

    printf '\nAusstehende NVIDIA-Abschlussprüfung:\n'
    printf '  Sicherung:  %s\n' "$BACKUP_DIR"
    printf '  Aktion:     %s\n' "$TRANSACTION_ACTION"
    printf '  Zielversion: %s\n' "${TARGET_VERSION:-nicht zutreffend}"
    ((${#PENDING_REASONS[@]} == 0)) || printf '  Gründe:     %s\n' "$(join_by '; ' "${PENDING_REASONS[@]}")"

    verify_pending_local_runtime "$PENDING_MODE" || {
        warn "Die lokale Abschlussprüfung ist noch nicht erfolgreich; die Sicherung bleibt erhalten."
        return 2
    }

    if [[ -n "$TARGET_LXC_ID" ]] && ((PENDING_VERIFY_GPU || PENDING_VERIFY_USERSPACE)); then
        command -v pct >/dev/null 2>&1 || { warn "pct fehlt für die gespeicherte LXC-Prüfung."; return 1; }
        validate_lxc_container_target
        prepare_pending_lxc_runtime || {
            started_restore_rc=$?
            ((started_restore_rc == 2)) && return 2
            return 1
        }
        if ! verify_pending_lxc_runtime; then
            restore_pending_lxc_start || true
            warn "Die LXC-Abschlussprüfung ist noch nicht erfolgreich; die Sicherung bleibt erhalten."
            return 2
        fi
    fi

    if ! restore_stopped_gpu_consumers; then
        restore_pending_lxc_start || true
        warn "Mindestens ein zuvor aktiver GPU-Dienst konnte nicht wieder gestartet werden; die Sicherung bleibt erhalten."
        return 2
    fi
    if ! restore_nvidia_persistenced; then
        restore_pending_lxc_start || true
        warn "nvidia-persistenced konnte nicht wieder gestartet werden; die Sicherung bleibt erhalten."
        return 2
    fi

    if [[ -n "$LXC_REMOTE_SUCCESS_BACKUP" ]]; then
        finalize_remote_backup_during_pending_check || {
            started_restore_rc=$?
            restore_pending_lxc_start || true
            return "$started_restore_rc"
        }
    fi

    restore_pending_lxc_start || started_restore_rc=$?
    if ((started_restore_rc != 0)); then
        PENDING_VERIFICATION_REASONS=("${PENDING_REASONS[@]}")
        block_success_backup_cleanup "ursprünglicher LXC-Zustand konnte nicht wiederhergestellt werden"
        write_pending_verification_state || true
        return 2
    fi

    if ((KEEP_SUCCESS_BACKUP)); then
        rm -f -- "$BACKUP_DIR/pending-verification.env"
        refresh_backup_checksums || {
            warn "Die abgeschlossene Prüfung konnte nicht sicher im behaltenen Backup vermerkt werden."
            return 1
        }
        ok "Nachgelagerte Abschlussprüfung erfolgreich; Sicherung wird auf Wunsch behalten: $BACKUP_DIR"
        write_success_completion_report \
            || warn "Die Abschlussprüfung war erfolgreich, aber der Abschlussbericht konnte nicht gespeichert werden."
        return 0
    fi
    if remove_success_backup_directory "$BACKUP_DIR"; then
        ok "Nachgelagerte Abschlussprüfung erfolgreich; Erfolgssicherung entfernt: $BACKUP_DIR"
        write_success_completion_report \
            || warn "Die Abschlussprüfung war erfolgreich, aber der Abschlussbericht konnte nicht gespeichert werden."
        return 0
    fi
    return 1
}

if [[ -n "$FINALIZE_PENDING_REQUEST" ]]; then
    if run_pending_finalization; then
        exit 0
    else
        PENDING_FINALIZE_RC=$?
        exit "$PENDING_FINALIZE_RC"
    fi
elif ((UNINSTALL_REQUEST)); then
    run_complete_uninstall
    exit "$(completion_exit_code)"
elif ((DRY_RUN)); then
    if ((UPDATE_ONLY)); then run_nvidia_update_dry_run; else run_dry_run; fi
    exit 0
elif ((ATTACH_ONLY || HOST_LXC_OPERATION)); then
    CONFIG_MUTATION_ALLOWED=1
    prepare_attach_only_backup
else
    run_driver_installation
    ensure_nvtop_monitoring_ready
fi

if [[ "$MODE" == "host" ]] && ((CONFIGURE_LXC_GPU)); then
    configure_nvidia_lxc_passthrough
fi
if [[ "$MODE" == "host" ]] && ((INSTALL_LXC_USERSPACE_FROM_HOST)); then
    install_lxc_userspace_from_host
fi
if ((ATTACH_ONLY == 0 && HOST_LXC_OPERATION == 0 && REPAIR_ONLY_REQUEST == 0)) \
   && [[ "$MODE" == "host" ]]; then
    resync_all_nvidia_lxc_devices
fi

if ((ATTACH_ONLY || HOST_LXC_OPERATION)); then
    if ((LXC_GPU_DEFERRED || LXC_USERSPACE_DEFERRED)); then
        block_success_backup_cleanup "LXC-Geräte oder Userspace sind noch nicht vollständig zur Laufzeit geprüft"
    fi
    if ((ATTACH_ONLY)); then
        block_success_backup_cleanup "reine GPU-Zuweisung muss nach einem LXC-Start oder -Neustart geprüft werden"
    fi
    write_transaction_phase abgeschlossen
    TRANSACTION_FINISHED=1
    clear_transaction_marker
    restore_lxc_runtime_state \
        || block_success_backup_cleanup "ursprünglicher LXC-Zustand konnte nicht wiederhergestellt werden"
    cleanup_deferred_remote_backup_after_host_success
    cleanup_old_backups "$BACKUP_RETENTION_DAYS"
    if ((SUCCESS_BACKUP_CLEANUP_BLOCKED)); then
        if ((ATTACH_ONLY)); then
            printf '\n\033[1;33mLXC-GPU-Zuweisung gespeichert; Laufzeitprüfung ausstehend.\033[0m\n'
        else
            printf '\n\033[1;33mLXC-Paketinstallation abgeschlossen; Laufzeitprüfung ausstehend.\033[0m\n'
        fi
    elif ((HOST_LXC_OPERATION)); then
        printf '\n\033[1;32mLXC-Verwaltung vom Host vollständig abgeschlossen.\033[0m\n'
    else
        printf '\n\033[1;32mGPU-Freigabe abgeschlossen.\033[0m\n'
    fi
    printf 'LXC:       %s (%s)\n' "$TARGET_LXC_ID" "$TARGET_LXC_NAME"
    if ((CONFIGURE_LXC_GPU)); then
        printf 'GPU(s):    %s\n' "$TARGET_GPU_SELECTION_SUMMARY"
        printf 'Zugriff:   mode=%s%s%s\n' "$LXC_DEVICE_MODE" \
            "${LXC_DEVICE_UID:+,uid=$LXC_DEVICE_UID}" "${LXC_DEVICE_GID:+,gid=$LXC_DEVICE_GID}"
    fi
    if ((INSTALL_LXC_USERSPACE_FROM_HOST)); then
        if ((LXC_USERSPACE_CONFIGURED && LXC_USERSPACE_DEFERRED == 0)); then
            printf 'Userspace: %s installiert und laufzeitgeprüft\n' "$TARGET_VERSION"
        elif ((LXC_USERSPACE_CONFIGURED)); then
            printf 'Userspace: %s installiert; Laufzeitprüfung offen\n' "$TARGET_VERSION"
        else
            printf 'Userspace: bis zum Host-Neustart zurückgestellt\n'
        fi
        printf 'LXC-Status: ursprünglicher Zustand %s wiederhergestellt\n' "${LXC_ORIGINAL_STATE:-unverändert}"
    fi
    printf 'Sicherung: %s\n' "$BACKUP_DIR"
    if ((LXC_GPU_DEFERRED)); then
        printf '\nDie Gerätedateien fehlen noch. Der aktivierte Dienst versucht die Zuordnung beim nächsten Host-Start erneut.\n'
    elif ((ATTACH_ONLY)); then
        printf '\nStarte LXC %s neu und prüfe darin: nvidia-smi\n' "$TARGET_LXC_ID"
    elif ((LXC_USERSPACE_DEFERRED)); then
        if ((REBOOT_REQUIRED)); then
            printf '\nNach dem erforderlichen Host-Neustart erneut „LXC vollständig einrichten“ wählen. Im LXC selbst ist kein Befehl nötig.\n'
        else
            printf '\nDie Pakete stimmen bereits. Prüfe den genannten NVML-Analysebericht und wähle danach Menüpunkt 8 „Ausstehende Prüfung abschließen“; im LXC selbst ist kein Installationsbefehl nötig.\n'
        fi
    elif ((SUCCESS_BACKUP_CLEANUP_BLOCKED)); then
        printf '\nDie Paketänderung ist abgeschlossen, aber nicht als vollständig funktionsfähig bestätigt. Die Sicherung bleibt bis zur Abschlussprüfung erhalten.\n'
    else
        printf '\nDie Einrichtung und Prüfung wurden vollständig vom Host ausgeführt.\n'
    fi
    cleanup_successful_transaction_backup
    emit_machine_result
    write_success_completion_report \
        || warn "Die LXC-Verwaltung war erfolgreich, aber der Abschlussbericht konnte nicht gespeichert werden."
    exit "$(completion_exit_code)"
fi

# Letzte Paketbereinigung erst nach abgeschlossener Installation, aber noch
# innerhalb der rollbackfähigen Transaktion und vor der Abschlussdiagnose.
run_final_safe_autoremove

# Liste nach der Installation sichern.
dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' \
    | grep -Ei '(^|\t)(nvidia|libnvidia|libcuda|libnvcuvid|cuda-(drivers|compat|mps))' \
    >"$BACKUP_DIR/nvidia-packages-after.txt" 2>/dev/null || true

if [[ "$MODE" == "lxc" ]]; then
    detect_driver_versions "lxc"
    HOST_MODULE_VERSION="$DETECTED_HOST_MODULE_VERSION"

    if [[ -n "$HOST_MODULE_VERSION" && "$HOST_MODULE_VERSION" != "$TARGET_VERSION" ]]; then
        die "Abschlussprüfung fehlgeschlagen: Host-Kernelmodul $HOST_MODULE_VERSION, LXC-Userspace $TARGET_VERSION."
    fi

    if ! nvidia_runtime_devices_ready /dev; then
        LXC_MISSING_RUNTIME_DEVICES="$(nvidia_runtime_device_missing_summary /dev)"
        block_success_backup_cleanup "LXC-Gerätefreigabe ist unvollständig: $LXC_MISSING_RUNTIME_DEVICES"
        warn "NVIDIA-Gerätefreigabe unvollständig: $LXC_MISSING_RUNTIME_DEVICES. Korrigiere sie auf dem Proxmox-Host über „LXC vollständig vom Host einrichten“."
    fi
fi

printf '\n'
if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi; then
        LOADED_VERSION="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 || true)"
        if [[ -n "$LOADED_VERSION" && "$LOADED_VERSION" == "$TARGET_VERSION" ]]; then
            ok "nvidia-smi verwendet bereits $LOADED_VERSION."
        elif [[ "$MODE" == "host" ]]; then
            block_success_backup_cleanup "geladenes NVIDIA-Modul entspricht noch nicht der installierten Zielversion"
            warn "Geladen ist noch ${LOADED_VERSION:-eine alte Version}; installiert wurde $TARGET_VERSION. Der Neustart lädt den neuen Treiber."
        else
            block_success_backup_cleanup "nvidia-smi meldet im LXC nicht die erwartete Version"
            warn "nvidia-smi meldet ${LOADED_VERSION:-eine unbekannte Version}; erwartet wird $TARGET_VERSION. Prüfe den Host-Neustart."
        fi
    else
        block_success_backup_cleanup "nvidia-smi/NVML ist noch nicht funktionsfähig"
        if [[ "$MODE" == "host" ]]; then
            warn "nvidia-smi funktioniert vor dem notwendigen Host-Neustart möglicherweise noch nicht."
        else
            warn "nvidia-smi fehlgeschlagen. Meist stimmen Host-Treiber und LXC-Bibliotheken noch nicht überein oder /dev/nvidia* fehlt."
        fi
    fi
fi

detect_driver_versions "$MODE"
detect_reboot_requirement
DIAGNOSTIC_ERROR_COUNT=0
run_diagnostic_summary "$MODE"
SMOKE_TEST_RC=0
if ((REBOOT_REQUIRED == 0)); then
    if run_local_transcode_smoke_test; then
        :
    else
        SMOKE_TEST_RC=$?
        ((SMOKE_TEST_RC == 2)) \
            || block_success_backup_cleanup "echter lokaler NVENC-/NVDEC-Test fehlgeschlagen"
    fi
elif [[ "$TRANSCODE_SMOKE_TEST" != "no" ]]; then
    block_success_backup_cleanup "Transcoding-Smoke-Test ist erst nach dem Host-Neustart möglich"
fi
if ((DIAGNOSTIC_ERROR_COUNT)); then
    block_success_backup_cleanup "$DIAGNOSTIC_ERROR_COUNT Fehler in der lokalen Abschlussdiagnose"
    warn "$DIAGNOSTIC_ERROR_COUNT Abschlussdiagnose-Fehler erkannt; die Sicherung wird nicht automatisch entfernt."
fi
if ((REBOOT_REQUIRED)); then
    block_success_backup_cleanup "Host-Neustart und erneute Laufzeitprüfung erforderlich"
    warn "Die Sicherung bleibt erhalten, bis der erforderliche Neustart und die Laufzeitprüfung abgeschlossen sind."
fi
if [[ "$MODE" == "host" ]] && ((CONFIGURE_LXC_GPU)) \
   && ((INSTALL_LXC_USERSPACE_FROM_HOST == 0)); then
    block_success_backup_cleanup "LXC-GPU-Zuweisung muss nach einem LXC-Start oder -Neustart geprüft werden"
fi
((AUTOMATIC_REPAIR == 0)) || write_automatic_repair_report
capture_nvidia_diagnostic_bundle abschluss
{
    printf 'GPU(s): %s\n' "$DETECTED_GPU_SUMMARY"
    printf 'Kernelmodul nach Installation: %s\n' "${DETECTED_HOST_MODULE_VERSION:-nicht geladen/erkannt}"
    printf 'Kernelmodulquelle: %s\n' "${DETECTED_HOST_MODULE_SOURCE:-nicht erkannt}"
    printf 'Paketversion nach Installation: %s\n' "${DETECTED_PACKAGE_VERSION:-nicht installiert}"
    printf 'nvidia-smi nach Installation: %s\n' "${DETECTED_SMI_VERSION:-nicht verfügbar}"
    printf 'Versionsstatus: %s\n' "$DETECTED_VERSION_STATE"
    printf 'Neustart erforderlich: %s\n' "$REBOOT_REQUIRED"
    printf 'Neustartgründe: %s\n' "$(join_by '; ' "${REBOOT_REASONS[@]}")"
} >"$BACKUP_DIR/hardware-and-version-detection-after.txt"

remove_temporary_version_pin
restore_nvidia_holds
apply_nvidia_version_binding
if ((UPDATE_ONLY)); then
    verify_nvidia_update_packages
    verify_nvidia_update_binding
fi
restore_stopped_gpu_consumers \
    || block_success_backup_cleanup "zuvor aktive GPU-Dienste konnten nicht vollständig wiederhergestellt werden"
restore_nvidia_persistenced \
    || block_success_backup_cleanup "nvidia-persistenced konnte nicht wiederhergestellt werden"
((AUTOMATIC_REPAIR == 0)) || write_automatic_repair_report
write_transaction_phase abgeschlossen
TRANSACTION_FINISHED=1
clear_transaction_marker
restore_lxc_runtime_state \
    || block_success_backup_cleanup "ursprünglicher LXC-Zustand konnte nicht wiederhergestellt werden"
cleanup_deferred_remote_backup_after_host_success
cleanup_old_backups "$BACKUP_RETENTION_DAYS"

if ((SUCCESS_BACKUP_CLEANUP_BLOCKED)); then
    printf '\n\033[1;33mVorgang abgeschlossen; Abschlussprüfung noch nicht erfolgreich.\033[0m\n'
elif ((REPAIR_ONLY_REQUEST)); then
    printf '\n\033[1;32mAutomatische Fehleranalyse und sichere Reparatur vollständig abgeschlossen.\033[0m\n'
elif ((UPDATE_ONLY)); then
    printf '\n\033[1;32mNVIDIA-Paketupdate abgeschlossen und Versionen gebunden.\033[0m\n'
else
    printf '\n\033[1;32mInstallation abgeschlossen.\033[0m\n'
fi
printf 'Distribution:   %s (%s)\n' "$OS_LABEL" "$DISTRO"
printf 'Rolle:          %s\n' "$MODE"
printf 'GPU(s):         %s\n' "$DETECTED_GPU_SUMMARY"
printf 'Versionsstatus: %s\n' "$DETECTED_VERSION_STATE"
printf 'Zielversion:    %s\n' "$TARGET_VERSION"
printf 'Empfehlung:     %s\n' "$RECOMMENDED_VERSION"
printf 'Sicherung:      %s\n' "$BACKUP_DIR"
if ((LXC_GPU_CONFIGURED || LXC_GPU_DEFERRED)); then
    printf 'LXC-Freigabe:   CT %s (%s) ← %s\n' "$TARGET_LXC_ID" "$TARGET_LXC_NAME" "$TARGET_GPU_SELECTION_SUMMARY"
fi

if [[ "$MODE" == "host" ]]; then
    printf '\nNächste Schritte:\n'
    if ((REBOOT_REQUIRED)); then
        printf '  1. %s neu starten: reboot\n' "$OS_LABEL"
        printf '  2. Danach prüfen: nvidia-smi\n'
    else
        printf '  1. Kein NVIDIA-bedingter Host-Neustart erkannt.\n'
        printf '  2. Treiber prüfen: nvidia-smi\n'
    fi
    if ((LXC_GPU_CONFIGURED || LXC_GPU_DEFERRED)); then
        if ((INSTALL_LXC_USERSPACE_FROM_HOST && LXC_USERSPACE_DEFERRED)); then
            if ((REBOOT_REQUIRED)); then
                printf '  3. Nach dem Host-Neustart im Host-Menü „LXC vollständig einrichten“ wählen.\n'
            else
                printf '  3. NVML-/Geräteursache anhand des Analyseberichts beheben und Menüpunkt 8 zur Abschlussprüfung wählen.\n'
            fi
            printf '  4. Im LXC selbst muss kein Installationsbefehl ausgeführt werden.\n'
        elif ((INSTALL_LXC_USERSPACE_FROM_HOST && LXC_GPU_DEFERRED)); then
            printf '  3. Der Host-Dienst richtet die LXC-Gerätefreigabe beim Neustart ein.\n'
            printf '  4. Danach LXC %s über den Proxmox-Host neu starten; die Bibliotheken sind bereits installiert.\n' "$TARGET_LXC_ID"
            printf '  5. Diagnose kann vollständig über Menüpunkt 5 auf dem Host erfolgen.\n'
        elif ((INSTALL_LXC_USERSPACE_FROM_HOST)); then
            printf '  3. LXC %s wurde einschließlich NVIDIA-Bibliotheken vom Host eingerichtet.\n' "$TARGET_LXC_ID"
            printf '  4. Weitere Prüfung ist über Menüpunkt 5 auf dem Host möglich.\n'
        elif ((LXC_GPU_DEFERRED)); then
            printf '  3. Der Host-Dienst richtet die LXC-Gerätefreigabe beim Neustart ein.\n'
            printf '  4. Für die Bibliotheken danach Menüpunkt 2 auf dem Host verwenden.\n'
        else
            printf '  3. Für GPU-Bibliotheken und Prüfung Menüpunkt 2 auf dem Host verwenden.\n'
        fi
    elif ((SUCCESS_BACKUP_CLEANUP_BLOCKED)); then
        printf '  3. Der Vorgang ist noch nicht vollständig geprüft; nach Behebung des genannten Grundes Menüpunkt 8 ausführen.\n'
        if ((UPDATE_ONLY && IS_PROXMOX_HOST)); then
            printf '  4. Nach erfolgreichem Host-Neustart/Abschluss die NVIDIA-LXC jeweils über Menüpunkt 13 aktualisieren.\n'
        fi
    elif ((IS_PROXMOX_HOST)); then
        if ((UPDATE_ONLY)); then printf '  3. NVIDIA-Pakete der LXC jeweils über Menüpunkt 13 auf diesem Host aktualisieren.\n';
        else printf '  3. LXC vollständig über Menüpunkt 2 auf diesem Host einrichten.\n'; fi
    else
        printf '  3. Host-Installation auf %s ist damit abgeschlossen.\n' "$OS_LABEL"
    fi
else
    printf '\nPrüfen:\n'
    printf '  nvidia-smi\n'
    printf '  ls -la /dev/nvidia*\n'
    printf "  ffmpeg -hide_banner -encoders | grep nvenc\n"
fi

cleanup_successful_transaction_backup
emit_machine_result
write_success_completion_report \
    || warn "Die NVIDIA-Transaktion war erfolgreich, aber der Abschlussbericht konnte nicht gespeichert werden."
exit "$(completion_exit_code)"
