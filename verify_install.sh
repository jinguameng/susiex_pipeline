#!/bin/bash
# =============================================================================
# verify_install.sh -- post-install sanity check
# -----------------------------------------------------------------------------
# Run this after install.sh to verify everything is wired up correctly before
# announcing the pipeline to your team. It does NOT run any actual analysis;
# it just checks that all the pieces can find each other.
#
# Usage:
#     ./verify_install.sh
# =============================================================================
set -uo pipefail   # not -e: we want to continue on failures and report them

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
WARN=0

ok()   { echo "  [PASS] $*";  PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $*" >&2;  FAIL=$((FAIL+1)); }
warn() { echo "  [WARN] $*" >&2;  WARN=$((WARN+1)); }

echo "============================================================"
echo " SuSiEx pipeline -- install verification"
echo " Install dir: $INSTALL_DIR"
echo "============================================================"

# ---- 1. File layout ---------------------------------------------------------
echo ""
echo "[1] File layout"
for f in \
    Snakefile \
    install.sh \
    bin/susiex-pipeline \
    scripts/prepare_susiex_input.sh \
    scripts/run_susiex_one_locus.sh \
    scripts/lib/parse_yaml.py \
    scripts/lib/common.sh \
    snakemake_slurm_profile/config.yaml \
    templates/pipeline.yaml.template \
    templates/cohorts.yaml.template \
    templates/loci.tsv.template \
    templates/submit.sh.template \
    config/pipeline.yaml \
    plot_susiex_pip.R \
    VERSION
do
    if [[ -f "$INSTALL_DIR/$f" ]]; then
        ok "$f exists"
    else
        fail "$f MISSING"
    fi
done

# ---- 2. Executable bits -----------------------------------------------------
echo ""
echo "[2] Executable bits"
for f in \
    install.sh \
    bin/susiex-pipeline \
    scripts/prepare_susiex_input.sh \
    scripts/run_susiex_one_locus.sh \
    scripts/lib/parse_yaml.py \
    plot_susiex_pip.R
do
    if [[ -x "$INSTALL_DIR/$f" ]]; then
        ok "$f is executable"
    else
        fail "$f is NOT executable -- run install.sh"
    fi
done

# ---- 3. Group-readable for shared use ---------------------------------------
echo ""
echo "[3] Group permissions"
group_ok=1
for f in bin/susiex-pipeline scripts/prepare_susiex_input.sh; do
    perms=$(stat -c '%A' "$INSTALL_DIR/$f" 2>/dev/null)
    if [[ "${perms:4:1}" == "r" ]]; then
        ok "$f group-readable ($perms)"
    else
        warn "$f NOT group-readable ($perms) -- group users won't be able to run it"
        group_ok=0
    fi
done

# ---- 4. Venv ----------------------------------------------------------------
echo ""
echo "[4] Python venv"
VENV="$INSTALL_DIR/venv"
if [[ -d "$VENV" ]]; then
    ok "venv directory exists"
    if [[ -x "$VENV/bin/python" ]]; then
        pyver=$("$VENV/bin/python" --version 2>&1)
        ok "venv Python: $pyver"
    else
        fail "venv Python not executable"
    fi
    if [[ -x "$VENV/bin/snakemake" ]]; then
        smver=$("$VENV/bin/snakemake" --version 2>&1)
        ok "venv snakemake: $smver"
    else
        fail "snakemake not in venv -- re-run install.sh"
    fi

    # SLURM executor plugin
    if "$VENV/bin/python" -c 'import snakemake_executor_plugin_slurm' 2>/dev/null; then
        ok "snakemake-executor-plugin-slurm is importable"
    else
        fail "snakemake-executor-plugin-slurm NOT installed -- re-run install.sh"
    fi

    # PyYAML
    if "$VENV/bin/python" -c 'import yaml' 2>/dev/null; then
        ok "PyYAML is importable"
    else
        fail "PyYAML NOT installed -- re-run install.sh"
    fi
else
    fail "venv missing -- run install.sh"
fi

# ---- 5. External tools ------------------------------------------------------
echo ""
echo "[5] External tools (must be on PATH)"
for cmd in awk sbatch; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd ($(command -v "$cmd"))"
    else
        fail "$cmd NOT FOUND on PATH"
    fi
done

# Rscript may only be available after `module load r/4.5.0`, so check it
# both with and without the module.
if command -v module >/dev/null 2>&1 || type module 2>/dev/null | grep -q function; then
    ok "module command available"
    # Try loading the R module the Snakefile expects
    if module load r/4.5.0 2>/dev/null && command -v Rscript >/dev/null 2>&1; then
        ok "module load r/4.5.0 -> Rscript ($(command -v Rscript))"
        module unload r/4.5.0 2>/dev/null || true
    else
        fail "module load r/4.5.0 failed -- check 'module avail R' on this cluster"
    fi
else
    warn "module command not found; checking Rscript on bare PATH"
    if command -v Rscript >/dev/null 2>&1; then
        ok "Rscript ($(command -v Rscript))"
    else
        fail "Rscript NOT FOUND and no module command available"
    fi
fi

# ---- 6. Admin pipeline.yaml has real paths ----------------------------------
echo ""
echo "[6] Admin defaults (config/pipeline.yaml)"
ADMIN_CFG="$INSTALL_DIR/config/pipeline.yaml"
if [[ -f "$ADMIN_CFG" ]]; then
    susiex_path=$("$VENV/bin/python" "$INSTALL_DIR/scripts/lib/parse_yaml.py" \
        get "$ADMIN_CFG" susiex_bin 2>/dev/null || echo "")
    plink_path=$("$VENV/bin/python" "$INSTALL_DIR/scripts/lib/parse_yaml.py" \
        get "$ADMIN_CFG" plink_bin 2>/dev/null || echo "")

    if [[ "$susiex_path" == /shared/path/* ]] || [[ -z "$susiex_path" ]]; then
        warn "susiex_bin still points to placeholder ($susiex_path) -- edit $ADMIN_CFG"
    elif [[ -x "$susiex_path" ]]; then
        ok "susiex_bin: $susiex_path (executable)"
    else
        fail "susiex_bin: $susiex_path NOT executable or not found"
    fi

    if [[ "$plink_path" == /shared/path/* ]] || [[ -z "$plink_path" ]]; then
        warn "plink_bin still points to placeholder ($plink_path) -- edit $ADMIN_CFG"
    elif [[ -x "$plink_path" ]]; then
        ok "plink_bin: $plink_path (executable)"
    else
        fail "plink_bin: $plink_path NOT executable or not found"
    fi
fi

# ---- 7. SLURM profile partition sanity --------------------------------------
echo ""
echo "[7] SLURM profile"
PROFILE="$INSTALL_DIR/snakemake_slurm_profile/config.yaml"
if [[ -f "$PROFILE" ]]; then
    partition=$(grep -E '^\s*-\s*slurm_partition' "$PROFILE" | sed 's/.*=//' | tr -d ' ')
    if [[ "$partition" == "production" ]]; then
        warn "Partition still set to default 'production' -- confirm this is correct for your cluster"
    else
        ok "Partition: $partition"
    fi
fi

# ---- 8. Launcher dispatch ---------------------------------------------------
echo ""
echo "[8] Launcher"
if "$INSTALL_DIR/bin/susiex-pipeline" version >/dev/null 2>&1; then
    ver=$("$INSTALL_DIR/bin/susiex-pipeline" version)
    ok "susiex-pipeline version: $ver"
else
    fail "susiex-pipeline launcher does not run"
fi

# ---- 9. R libPaths sanity ---------------------------------------------------
echo ""
echo "[9] R packages (loaded via module + .libPaths in plot_susiex_pip.R)"
# Load the module first so Rscript is available, then verify packages load
if command -v module >/dev/null 2>&1 || type module 2>/dev/null | grep -q function; then
    module load r/4.5.0 2>/dev/null || true
fi
if command -v Rscript >/dev/null 2>&1; then
    libpath=$(grep -oE '"\K[^"]*rlib[^"]*' "$INSTALL_DIR/plot_susiex_pip.R" | head -1)
    if [[ -n "$libpath" ]] && [[ -d "$libpath" ]]; then
        ok "R library path exists: $libpath"
        if Rscript -e ".libPaths(c('$libpath', .libPaths()));
                       suppressMessages(library(optparse));
                       suppressMessages(library(dplyr));
                       suppressMessages(library(readr));
                       suppressMessages(library(ggplot2));
                       suppressMessages(library(ggrepel));
                       cat('OK\n')" 2>/dev/null | grep -q OK; then
            ok "All required R packages load successfully"
        else
            fail "One or more R packages failed to load"
        fi
    else
        warn "R library path in plot_susiex_pip.R not found: $libpath"
    fi
else
    warn "Rscript not available -- cannot verify R packages"
fi

# ---- Summary ----------------------------------------------------------------
echo ""
echo "============================================================"
echo " Summary: $PASS passed, $FAIL failed, $WARN warnings"
echo "============================================================"
if [[ $FAIL -gt 0 ]]; then
    echo " Result: FAILED -- fix the issues above before announcing to team"
    exit 1
elif [[ $WARN -gt 0 ]]; then
    echo " Result: PASSED with warnings -- review and decide if action needed"
    exit 0
else
    echo " Result: PASSED -- you're ready to smoke-test with real data"
    exit 0
fi
