#!/bin/bash
# =============================================================================
# install.sh -- one-time setup for the shared pipeline install
# -----------------------------------------------------------------------------
# Run this once after dropping the pipeline directory on a shared filesystem.
# It will:
#   1. Create a Python venv at <install>/venv/ and install Snakemake + deps.
#   2. Make scripts executable for the group (chmod g+rx).
#   3. Verify required external tools (Rscript, awk, etc.).
#   4. Optionally symlink the launcher into a directory on PATH.
#
# Usage:
#     ./install.sh                                  # default install
#     ./install.sh --link-to /shared/bin            # also symlink launcher
#     ./install.sh --python /path/to/python3.11     # use a specific Python
#     ./install.sh --skip-venv                      # don't (re)create venv
# =============================================================================
set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK_DIR=""
PYTHON_BIN="python3"
SKIP_VENV=0

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --link-to)   LINK_DIR="$2"; shift 2 ;;
        --python)    PYTHON_BIN="$2"; shift 2 ;;
        --skip-venv) SKIP_VENV=1; shift ;;
        -h|--help)
            sed -n '/^# ====/,/^# ====/p' "$0" | sed 's/^# \{0,1\}//' | head -25
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

echo "============================================================"
echo " SuSiEx pipeline install"
echo "============================================================"
echo " Install dir : $INSTALL_DIR"
echo " Python      : $PYTHON_BIN ($(command -v $PYTHON_BIN || echo 'NOT FOUND'))"
echo "============================================================"

# ---- Step 1: create shared venv ---------------------------------------------
VENV="$INSTALL_DIR/venv"
if [[ "$SKIP_VENV" -eq 1 ]]; then
    echo "[1/4] Skipping venv creation (--skip-venv)."
elif [[ -d "$VENV" ]]; then
    echo "[1/4] Venv already exists at $VENV (use --skip-venv to skip, or remove to rebuild)"
else
    echo "[1/4] Creating venv at $VENV ..."
    "$PYTHON_BIN" -m venv "$VENV"
    # shellcheck source=/dev/null
    source "$VENV/bin/activate"
    pip install --quiet --upgrade pip
    echo "      Installing snakemake, snakemake-executor-plugin-slurm, pyyaml ..."
    pip install --quiet \
        "snakemake>=8.0" \
        "snakemake-executor-plugin-slurm" \
        "pyyaml"
    deactivate
    echo "      Done."
fi

# ---- Step 2: chmod ----------------------------------------------------------
echo "[2/4] Setting executable bits ..."
chmod +x "$INSTALL_DIR/install.sh"
chmod +x "$INSTALL_DIR/bin/"*
chmod +x "$INSTALL_DIR/scripts/"*.sh
chmod +x "$INSTALL_DIR/scripts/lib/parse_yaml.py"
chmod +x "$INSTALL_DIR/plot_susiex_pip.R"

# Group-readable / group-executable for shared use.
# Files: g+r ; directories and scripts: g+rx
chmod -R g+rX "$INSTALL_DIR"
chmod g+rx "$INSTALL_DIR/install.sh" \
           "$INSTALL_DIR/bin/"* \
           "$INSTALL_DIR/scripts/"*.sh \
           "$INSTALL_DIR/scripts/lib/parse_yaml.py" \
           "$INSTALL_DIR/plot_susiex_pip.R"
echo "      Done. (You may also want to chgrp -R <group> $INSTALL_DIR)"

# ---- Step 3: dependency check ------------------------------------------------
echo "[3/4] Checking external dependencies ..."
check_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        echo "      OK : $1 ($(command -v "$1"))"
    else
        echo "      MISSING : $1"
        return 1
    fi
}

missing=0
check_cmd "$PYTHON_BIN" || missing=$((missing+1))
check_cmd awk           || missing=$((missing+1))
check_cmd sbatch        || missing=$((missing+1))

# Rscript is loaded via `module load r/4.5.0` at job runtime (see Snakefile
# envmodules: directive), so we don't require it on the install-time PATH.
if command -v module >/dev/null 2>&1 || type module 2>/dev/null | grep -q function; then
    if (module load r/4.5.0 && command -v Rscript) >/dev/null 2>&1; then
        echo "      OK : module load r/4.5.0 -> Rscript available"
        module unload r/4.5.0 2>/dev/null || true
    else
        echo "      WARN : 'module load r/4.5.0' did not yield Rscript -- check 'module avail R'"
    fi
elif command -v Rscript >/dev/null 2>&1; then
    echo "      OK : Rscript ($(command -v Rscript))"
else
    echo "      WARN : neither 'module' nor 'Rscript' found -- plotting step will fail"
fi

if [[ "$SKIP_VENV" -eq 0 ]] && [[ -f "$VENV/bin/snakemake" ]]; then
    echo "      OK : snakemake ($VENV/bin/snakemake)"
else
    if [[ "$SKIP_VENV" -eq 0 ]]; then
        echo "      MISSING : snakemake (venv setup may have failed)"
        missing=$((missing+1))
    fi
fi

if [[ $missing -gt 0 ]]; then
    echo ""
    echo "WARNING: $missing dependency check(s) failed. Install before running pipeline."
fi

# Note about R packages -- can't easily verify without running Rscript, but
# remind the admin.
cat <<'EOF'

      Note: R packages required (install once per shared R install):
            install.packages(c("optparse","dplyr","readr","ggplot2","ggrepel"))
EOF

# ---- Step 4: optional launcher symlink --------------------------------------
if [[ -n "$LINK_DIR" ]]; then
    if [[ ! -d "$LINK_DIR" ]]; then
        echo "[4/4] ERROR: --link-to target $LINK_DIR is not a directory" >&2
        exit 1
    fi
    LINK_PATH="$LINK_DIR/susiex-pipeline"
    ln -sf "$INSTALL_DIR/bin/susiex-pipeline" "$LINK_PATH"
    echo "[4/4] Symlinked launcher: $LINK_PATH -> $INSTALL_DIR/bin/susiex-pipeline"
else
    echo "[4/4] Skipped symlinking (use --link-to <dir-on-PATH> to enable)"
    echo ""
    echo "      To make the launcher available on PATH for your group, either:"
    echo "        a) Symlink (recommended):"
    echo "             ./install.sh --link-to /shared/bin"
    echo "        b) Tell users to add to their shell rc:"
    echo "             export PATH=\"$INSTALL_DIR/bin:\$PATH\""
fi

echo ""
echo "============================================================"
echo " Install complete."
echo "============================================================"
echo " Test with:"
echo "   $INSTALL_DIR/bin/susiex-pipeline version"
echo ""
echo " Users can now run:"
echo "   cd ~/my_analysis"
echo "   susiex-pipeline init ."
echo "   # edit configs"
echo "   sbatch submit.sh"
echo "============================================================"
