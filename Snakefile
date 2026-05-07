# =============================================================================
# Snakefile -- SuSiEx fine-mapping pipeline
# -----------------------------------------------------------------------------
# This Snakefile is the single source of truth for the workflow. It lives in
# the shared pipeline install and is invoked from each user's analysis
# directory via:
#
#     snakemake -s <install>/Snakefile --configfile config/pipeline.yaml ...
#
# Path conventions:
#   - PIPELINE_ROOT = directory containing this Snakefile (the shared install).
#   - Working dir   = the user's analysis directory (where they ran sbatch).
#                     Snakemake's `workflow.basedir` is the Snakefile dir; we
#                     use os.getcwd() for user-relative paths in configs.
# =============================================================================
import os
import sys
import yaml
import csv

# -----------------------------------------------------------------------------
# Resolve install root and helpers
# -----------------------------------------------------------------------------
PIPELINE_ROOT = workflow.basedir
SCRIPTS       = os.path.join(PIPELINE_ROOT, "scripts")
PLOT_R        = os.path.join(PIPELINE_ROOT, "plot_susiex_pip.R")
USER_DIR      = os.getcwd()

def resolve_user_path(p):
    """Resolve a path that may be relative to the user's analysis dir."""
    full = p if os.path.isabs(p) else os.path.join(USER_DIR, p)
    return os.path.normpath(full)

# -----------------------------------------------------------------------------
# Load cohort manifest and loci list
# -----------------------------------------------------------------------------
cohorts_cfg_path = resolve_user_path(config["cohorts_config"])
loci_file_path   = resolve_user_path(config["loci_file"])

with open(cohorts_cfg_path) as fh:
    COHORTS = yaml.safe_load(fh)["cohorts"]
COHORT_NAMES = [c["name"] for c in COHORTS]

LOCI = []
with open(loci_file_path) as fh:
    reader = csv.DictReader(fh, delimiter="\t")
    for row in reader:
        if row["locus_name"].startswith("#") or not row["locus_name"].strip():
            continue
        LOCI.append(row)
LOCUS_NAMES   = [l["locus_name"] for l in LOCI]
LOCUS_INDEX   = {l["locus_name"]: i + 1 for i, l in enumerate(LOCI)}  # 1-based

# Convenience paths (output_root may be absolute or user-relative)
PHENO       = config["phenotype"]
OUTPUT_ROOT = resolve_user_path(config["output_root"])
PHENO_OUT   = os.path.join(OUTPUT_ROOT, PHENO)
INPUTS_DIR  = os.path.join(PHENO_OUT, "inputs")
LOCI_DIR    = os.path.join(PHENO_OUT, "loci")
LOGS_DIR    = os.path.join(PHENO_OUT, "logs")

# Need the original config path for scripts that re-read it (they expect a path
# argument, not the parsed dict). Snakemake stores configfile paths here:
CONFIG_PATH = resolve_user_path(workflow.configfiles[0]) if workflow.configfiles else None
if CONFIG_PATH is None:
    sys.stderr.write("ERROR: --configfile must be supplied\n")
    sys.exit(1)

# -----------------------------------------------------------------------------
# Default target
# -----------------------------------------------------------------------------
rule all:
    input:
        expand(
            os.path.join(LOCI_DIR, "{locus}", f"{PHENO}.{{locus}}_PIP.pdf"),
            locus=LOCUS_NAMES
        )

# -----------------------------------------------------------------------------
# Rule: prepare per-cohort SuSiEx input files
# -----------------------------------------------------------------------------
def cohort_meta(name, field):
    return next(c[field] for c in COHORTS if c["name"] == name)

rule prepare_input:
    input:
        bim  = lambda wc: cohort_meta(wc.cohort, "bim_prefix") + ".bim",
        gwas = lambda wc: cohort_meta(wc.cohort, "gwas_file"),
    output:
        os.path.join(INPUTS_DIR, "{cohort}_susiex_input.txt")
    log:
        os.path.join(LOGS_DIR, "prepare_input.{cohort}.log")
    resources:
        mem_mb=8000,
        runtime=60,
        cpus_per_task=2,
    shell:
        "{SCRIPTS}/prepare_susiex_input.sh {input.bim} {input.gwas} {output} > {log} 2>&1"

# -----------------------------------------------------------------------------
# Rule: run SuSiEx for one locus
# -----------------------------------------------------------------------------
rule susiex_locus:
    input:
        inputs = expand(
            os.path.join(INPUTS_DIR, "{cohort}_susiex_input.txt"),
            cohort=COHORT_NAMES
        )
    output:
        cs  = os.path.join(LOCI_DIR, "{locus}", f"SuSiEx.{PHENO}.{{locus}}.cs"),
        snp = os.path.join(LOCI_DIR, "{locus}", f"SuSiEx.{PHENO}.{{locus}}.snp"),
    log:
        os.path.join(LOGS_DIR, "susiex.{locus}.log")
    threads: config["susiex"]["threads"]
    resources:
        mem_mb=32000,
        runtime=360,
        cpus_per_task=lambda wc: config["susiex"]["threads"],
    params:
        idx = lambda wc: LOCUS_INDEX[wc.locus],
        cfg = CONFIG_PATH,
    shell:
        "{SCRIPTS}/run_susiex_one_locus.sh {params.cfg} {params.idx} > {log} 2>&1"

# -----------------------------------------------------------------------------
# Rule: plot one locus
# -----------------------------------------------------------------------------
rule plot_locus:
    input:
        cs  = os.path.join(LOCI_DIR, "{locus}", f"SuSiEx.{PHENO}.{{locus}}.cs"),
        snp = os.path.join(LOCI_DIR, "{locus}", f"SuSiEx.{PHENO}.{{locus}}.snp"),
    output:
        pdf = os.path.join(LOCI_DIR, "{locus}", f"{PHENO}.{{locus}}_PIP.pdf"),
        png = os.path.join(LOCI_DIR, "{locus}", f"{PHENO}.{{locus}}_PIP.png"),
    log:
        os.path.join(LOGS_DIR, "plot.{locus}.log")
    envmodules:
        "r/4.5.0"
    resources:
        mem_mb=8000,
        runtime=60,
        cpus_per_task=2,
    params:
        outdir    = lambda wc: os.path.join(LOCI_DIR, wc.locus),
        outprefix = lambda wc: f"{PHENO}.{wc.locus}",
        plotR     = PLOT_R,
    shell:
        "Rscript {params.plotR} "
        "--snp {input.snp} --cs {input.cs} "
        "--outdir {params.outdir} --outprefix {params.outprefix} > {log} 2>&1"
