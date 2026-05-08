#!/bin/bash
# =============================================================================
# common.sh -- shared functions for the SuSiEx pipeline
#
# Source this from other scripts:
#     source "$(dirname "$0")/lib/common.sh"
# =============================================================================

# ---- locate pipeline root and helper -----------------------------------------
# Resolve PIPELINE_ROOT to the parent of scripts/, regardless of where the
# caller cd'd to.
PIPELINE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_SCRIPTS_DIR="$(dirname "$PIPELINE_LIB_DIR")"
PIPELINE_ROOT="$(dirname "$PIPELINE_SCRIPTS_DIR")"
PARSE_YAML="$PIPELINE_LIB_DIR/parse_yaml.py"

export PIPELINE_ROOT PIPELINE_SCRIPTS_DIR PIPELINE_LIB_DIR PARSE_YAML

# ---- logging -----------------------------------------------------------------
log_info()  { echo "[INFO  $(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log_warn()  { echo "[WARN  $(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }
log_error() { echo "[ERROR $(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }
log_step()  { echo ""; echo "============================================================"; echo " $*"; echo "============================================================"; }

# ---- yaml convenience wrappers -----------------------------------------------
yaml_get()   { python3 "$PARSE_YAML" get   "$1" "$2"; }
yaml_list()  { python3 "$PARSE_YAML" list  "$1" "$2" "$3"; }
yaml_row()   { python3 "$PARSE_YAML" row   "$@"; }
yaml_count() { python3 "$PARSE_YAML" count "$1" "$2"; }

# ---- guards ------------------------------------------------------------------
require_file() {
    local f="$1"; local label="${2:-file}"
    if [[ ! -f "$f" ]]; then
        log_error "Required $label not found: $f"
        exit 1
    fi
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command not found in PATH: $cmd"
        exit 1
    fi
}

require_executable() {
    local f="$1"; local label="${2:-binary}"
    if [[ ! -x "$f" ]]; then
        log_error "Required $label not found or not executable: $f"
        exit 1
    fi
}

# ---- path helpers ------------------------------------------------------------
# Read core paths from pipeline.yaml and export them.
load_pipeline_config() {
    local cfg="$1"
    require_file "$cfg" "pipeline config"

    PHENO=$(yaml_get "$cfg" phenotype)
    OUTPUT_ROOT=$(yaml_get "$cfg" output_root)
    SUSIEX_BIN=$(yaml_get "$cfg" susiex_bin)
    PLINK_BIN=$(yaml_get "$cfg" plink_bin)
    COHORTS_CFG=$(yaml_get "$cfg" cohorts_config)
    LOCI_FILE=$(yaml_get "$cfg" loci_file)

    # Resolve relative paths against the pipeline root for portability.
    [[ "$COHORTS_CFG" != /* ]] && COHORTS_CFG="$PWD/$COHORTS_CFG"
    [[ "$LOCI_FILE"   != /* ]] && LOCI_FILE="$PWD/$LOCI_FILE"

    PHENO_OUT="$OUTPUT_ROOT/$PHENO"
    INPUTS_DIR="$PHENO_OUT/inputs"
    LOCI_DIR="$PHENO_OUT/loci"
    LOGS_DIR="$PHENO_OUT/logs"

    export PHENO OUTPUT_ROOT SUSIEX_BIN PLINK_BIN COHORTS_CFG LOCI_FILE
    export PHENO_OUT INPUTS_DIR LOCI_DIR LOGS_DIR
}

ensure_dirs() {
    mkdir -p "$INPUTS_DIR" "$LOCI_DIR" "$LOGS_DIR"
}
