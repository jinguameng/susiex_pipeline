#!/bin/bash
# =============================================================================
# prepare_susiex_input.sh
# -----------------------------------------------------------------------------
# Convert a PLINK association file (linear or logistic) into the SuSiEx input
# format:  chr  snp  bp  a1  a2  beta  se  stat  p
#
# The script auto-detects whether the assoc file is linear (BETA column) or
# logistic (OR column). For logistic files, OR is converted to log(OR) so the
# output `beta` column is always on the additive log-odds / linear-effect scale.
#
# A2 (the non-effect allele) is resolved by looking up each SNP in the BIM file.
# Variants whose A1 matches neither BIM allele are skipped, as are variants
# absent from the BIM file or with NA effects/p-values.
#
# Usage:
#     prepare_susiex_input.sh <cohort.bim> <cohort_assoc_file> <output_file>
#
# Example:
#     prepare_susiex_input.sh ADNI_EUR.bim ADNI_EUR.assoc.linear.gz \
#         ADNI_EUR_susiex_input.txt
# =============================================================================
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
    echo "Usage: $0 <cohort.bim> <cohort_assoc_file> <output_file>" >&2
    echo "Example: $0 ADNI_EUR.bim ADNI_EUR_assoc.linear.gz ADNI_EUR_susiex_input.txt" >&2
    exit 1
fi

BIM_FILE="$1"
ASSOC_FILE="$2"
OUT_FILE="$3"

[[ -f "$BIM_FILE"   ]] || { echo "[ERROR] BIM file not found: $BIM_FILE"     >&2; exit 1; }
[[ -f "$ASSOC_FILE" ]] || { echo "[ERROR] Assoc file not found: $ASSOC_FILE" >&2; exit 1; }

mkdir -p "$(dirname "$OUT_FILE")"

echo "[prepare_susiex_input] Processing $ASSOC_FILE with reference $BIM_FILE..."

# zcat -f handles both .gz and plain text seamlessly
zcat -f "$ASSOC_FILE" | awk -v bim="$BIM_FILE" '
BEGIN {
    OFS="\t"
    # 1. Print the SuSiEx header
    print "chr", "snp", "bp", "a1", "a2", "beta", "se", "stat", "p"

    # 2. Load the BIM file (SNP -> A1/A2 mapping)
    # PLINK bim format: CHR SNP CM BP A1 A2 (cols 1, 2, 3, 4, 5, 6)
    while ((getline < bim) > 0) {
        bim_a1[$2] = $5
        bim_a2[$2] = $6
    }
    close(bim)
}
NR==1 {
    # 3. Map column indices from the assoc header
    for (i=1; i<=NF; i++) col[$i] = i

    # 4. Detect linear vs. logistic
    is_logistic = 0
    if ("OR" in col) {
        is_logistic = 1
        eff_col = col["OR"]
    } else if ("BETA" in col) {
        eff_col = col["BETA"]
    } else {
        print "ERROR: Neither OR nor BETA column found in assoc header." > "/dev/stderr"
        exit 1
    }

    chr_c = col["CHR"]; snp_c = col["SNP"]; bp_c = col["BP"]
    a1_c  = col["A1"];  se_c  = col["SE"];  stat_c = col["STAT"]
    p_c   = col["P"]
    next
}
{
    # Skip invalid rows from PLINK
    if ($eff_col == "NA" || $p_c == "NA") next

    snp = $snp_c
    assoc_a1 = $a1_c

    # 5. Resolve A2 from the BIM file
    a2 = "NA"
    if (snp in bim_a1) {
        if (assoc_a1 == bim_a1[snp]) {
            a2 = bim_a2[snp]
        } else if (assoc_a1 == bim_a2[snp]) {
            a2 = bim_a1[snp]
        } else {
            next  # A1 matches neither BIM allele
        }
    } else {
        next      # SNP not in BIM
    }

    # 6. Convert OR to log(OR) for logistic results
    if (is_logistic == 1) {
        if ($eff_col + 0 > 0) {
            beta = log($eff_col)
        } else {
            next  # invalid OR
        }
    } else {
        beta = $eff_col
    }

    # 7. Output
    print $chr_c, snp, $bp_c, assoc_a1, a2, beta, $se_c, $stat_c, $p_c
}
' > "$OUT_FILE"

echo "[prepare_susiex_input] Saved: $OUT_FILE"
