#!/bin/bash
# =============================================================================
# 02_run_susiex_one_locus.sh
# -----------------------------------------------------------------------------
# Run SuSiEx for ONE locus, identified by its 1-based index in loci.tsv.
#
# Used by:
#   - SLURM array tasks:    $SLURM_ARRAY_TASK_ID is the locus index
#   - Snakemake rules:      one locus per rule invocation
#   - Manual single runs:   debug a specific locus without re-running others
#
# Usage:
#     ./02_run_susiex_one_locus.sh <pipeline.yaml> <locus_index_1based> [--force]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

if [[ "$#" -lt 2 ]]; then
    echo "Usage: $0 <pipeline.yaml> <locus_index_1based> [--force]" >&2
    exit 1
fi

CONFIG="$1"
LOCUS_IDX="$2"
FORCE="false"
[[ "${3:-}" == "--force" ]] && FORCE="true"

load_pipeline_config "$CONFIG"
ensure_dirs

require_file       "$COHORTS_CFG" "cohorts config"
require_file       "$LOCI_FILE"   "loci file"
require_executable "$SUSIEX_BIN"  "SuSiEx binary"
require_executable "$PLINK_BIN"   "PLINK binary"

# ---- SuSiEx parameters -------------------------------------------------------
LEVEL=$(yaml_get      "$CONFIG" susiex.level)
PVAL_THRESH=$(yaml_get "$CONFIG" susiex.pval_thresh)
MAF=$(yaml_get        "$CONFIG" susiex.maf)
MULT_STEP=$(yaml_get  "$CONFIG" susiex.mult_step)
KEEP_AMBIG=$(yaml_get "$CONFIG" susiex.keep_ambig)
THREADS=$(yaml_get    "$CONFIG" susiex.threads)
to_pyflag() { case "$1" in true) echo True;; false) echo False;; *) echo "$1";; esac; }
MULT_STEP=$(to_pyflag "$MULT_STEP")
KEEP_AMBIG=$(to_pyflag "$KEEP_AMBIG")

# ---- Build comma-separated cohort args --------------------------------------
N_COHORTS=$(yaml_count "$COHORTS_CFG" cohorts)
sst_files=(); n_gwas_list=(); ref_files=()
for ((i=0; i<N_COHORTS; i++)); do
    IFS=$'\t' read -r name n_gwas bim_prefix < <(
        yaml_row "$COHORTS_CFG" cohorts "$i" name n_gwas bim_prefix
    )
    sst="$INPUTS_DIR/${name}_susiex_input.txt"
    require_file "$sst" "input for cohort $name (run 01_prepare_inputs.sh first)"
    sst_files+=("$sst")
    n_gwas_list+=("$n_gwas")
    ref_files+=("$bim_prefix")
done
join_csv() { local IFS=','; echo "$*"; }
SST_ARG=$(join_csv "${sst_files[@]}")
NGWAS_ARG=$(join_csv "${n_gwas_list[@]}")
REF_ARG=$(join_csv "${ref_files[@]}")
build_col_arg() { local val="$1" n="$2"; local arr=(); for ((j=0;j<n;j++)); do arr+=("$val"); done; join_csv "${arr[@]}"; }
SNP_COL=$(build_col_arg 2 "$N_COHORTS")
CHR_COL=$(build_col_arg 1 "$N_COHORTS")
BP_COL=$(build_col_arg  3 "$N_COHORTS")
A1_COL=$(build_col_arg  4 "$N_COHORTS")
A2_COL=$(build_col_arg  5 "$N_COHORTS")
EFF_COL=$(build_col_arg 6 "$N_COHORTS")
SE_COL=$(build_col_arg  7 "$N_COHORTS")
PVAL_COL=$(build_col_arg 9 "$N_COHORTS")

# ---- Pluck the requested locus from loci.tsv --------------------------------
read -r header < "$LOCI_FILE"
declare -A col_idx
i=1
for col in $header; do col_idx[$col]=$i; i=$((i+1)); done
for required in locus_name chr start end; do
    [[ -z "${col_idx[$required]:-}" ]] && { log_error "loci.tsv missing column: $required"; exit 1; }
done

# Read 1-based row from body (skip header)
LOCUS_LINE=$(tail -n +2 "$LOCI_FILE" | sed -n "${LOCUS_IDX}p")
if [[ -z "$LOCUS_LINE" ]]; then
    log_error "Locus index $LOCUS_IDX out of range in $LOCI_FILE"
    exit 1
fi

IFS=$'\t' read -r -a row <<< "$LOCUS_LINE"
locus_name=${row[$((col_idx[locus_name]-1))]}
chr=${row[$((col_idx[chr]-1))]}
start=${row[$((col_idx[start]-1))]}
end=${row[$((col_idx[end]-1))]}

log_step "Locus #$LOCUS_IDX: $locus_name (chr$chr:$start-$end)"

LOCUS_DIR="$LOCI_DIR/$locus_name"
mkdir -p "$LOCUS_DIR"
OUT_NAME="SuSiEx.${PHENO}.${locus_name}"
CS_OUT="$LOCUS_DIR/${OUT_NAME}.cs"

if [[ -s "$CS_OUT" && "$FORCE" != "true" ]]; then
    log_info "Output exists, skipping (use --force to regenerate): $CS_OUT"
    exit 0
fi

"$SUSIEX_BIN" \
    --sst_file="$SST_ARG" \
    --n_gwas="$NGWAS_ARG" \
    --ref_file="$REF_ARG" \
    --out_dir="$LOCUS_DIR" \
    --out_name="$OUT_NAME" \
    --level="$LEVEL" \
    --pval_thresh="$PVAL_THRESH" \
    --maf="$MAF" \
    --chr="$chr" \
    --bp="${start},${end}" \
    --snp_col="$SNP_COL" \
    --chr_col="$CHR_COL" \
    --bp_col="$BP_COL" \
    --a1_col="$A1_COL" \
    --a2_col="$A2_COL" \
    --eff_col="$EFF_COL" \
    --se_col="$SE_COL" \
    --pval_col="$PVAL_COL" \
    --plink="$PLINK_BIN" \
    --mult-step="$MULT_STEP" \
    --keep-ambig="$KEEP_AMBIG" \
    --threads="$THREADS"

if [[ ! -s "$CS_OUT" ]]; then
    log_warn "SuSiEx finished but produced no .cs output for $locus_name"
    exit 2
fi

log_info "Done: $CS_OUT"
