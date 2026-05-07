# SuSiEx Fine-mapping Pipeline

A shared bash + Snakemake pipeline for cross-cohort statistical fine-mapping
with [SuSiEx](https://github.com/getian107/SuSiEx). One install on the cluster,
many users; each user keeps their analysis directory wherever they like.

## How it runs

```
       ┌──────────────────────────────────────────┐
User → │ sbatch submit.sh  (in their analysis dir)│
       └────────────┬─────────────────────────────┘
                    ↓
       ┌──────────────────────────────────────────┐
       │ Outer SLURM job: activates shared venv,  │  ← tiny, just runs
       │ runs Snakemake against shared Snakefile  │     Snakemake
       └────────────┬─────────────────────────────┘
                    ↓
                 Snakemake
                    ↓ submits one SLURM job per locus
       ┌──────────────────────────────────────────┐
       │ Per-locus SuSiEx jobs, run in parallel   │
       │ via the SLURM executor plugin            │
       └──────────────────────────────────────────┘
```

The user submits one tiny controller job. Snakemake handles the parallelism,
dependency tracking, resume-on-failure, and per-locus SLURM submission.

## Admin install (one-time)

Drop the pipeline directory anywhere on a shared filesystem your group can
read, then run the installer:

```bash
cd /data/h_vmac/zhanm32/software/
git clone <repo-url> susiex_pipeline    # or rsync/cp
cd susiex_pipeline

# Edit the admin-default binary paths
vim config/pipeline.yaml                 # set susiex_bin and plink_bin

# Edit the SLURM profile for your cluster's partition / account
vim snakemake_slurm_profile/config.yaml

# Install: creates venv, installs Snakemake, sets group permissions
./install.sh

# Verify everything is wired up correctly
./verify_install.sh
```

`install.sh` will:

1. Create a Python venv at `<install>/venv/` and install `snakemake`,
   `snakemake-executor-plugin-slurm`, and `pyyaml`.
2. Make all scripts group-readable and group-executable.
3. Verify external tools (`Rscript`, `awk`, `sbatch`) are in PATH.

`verify_install.sh` runs after install and checks that the venv works,
Snakemake imports the SLURM plugin, R packages load via the configured
`.libPaths()`, and admin defaults point at real binaries.

R packages are loaded from a shared library path baked into
`plot_susiex_pip.R` via `.libPaths()`. R itself is loaded via the cluster's
module system (the `plot_locus` rule in the Snakefile uses an `envmodules:`
directive to `module load r/4.5.0` at runtime, and `submit.sh` runs
Snakemake with `--use-envmodules`). To use a different R version or a
different shared library location, edit those two lines.

### Customizing the SLURM profile

Edit `snakemake_slurm_profile/config.yaml` to set your cluster's partition
name, default account, and any flags Snakemake's SLURM executor needs for
your site. The default partition is `production` — change as appropriate
for your cluster.

## User workflow

The launcher lives at `<install>/bin/susiex-pipeline`. Two ways to invoke it:

**Option A: Add the install's bin/ to your PATH** (recommended for frequent users)

Add this line to your `~/.bashrc` (one time):

```bash
export PATH="/data/h_vmac/zhanm32/software/susiex_pipeline/bin:$PATH"
```

Then `source ~/.bashrc` (or open a new shell). After this, `susiex-pipeline`
works from anywhere.

**Option B: Use the full path** (no setup required)

Just type out the full path each time:

```bash
/data/h_vmac/zhanm32/software/susiex_pipeline/bin/susiex-pipeline init .
```

A common pattern is to alias it in your shell:

```bash
alias susiex='/data/h_vmac/zhanm32/software/susiex_pipeline/bin/susiex-pipeline'
```

### End-to-end example

```bash
# 1. Create an analysis directory anywhere you like
mkdir ~/projects/my_finemap_analysis
cd    ~/projects/my_finemap_analysis

# 2. Scaffold configs and submit script
susiex-pipeline init .
# (or use the full path if PATH not set up:
#  /data/h_vmac/zhanm32/software/susiex_pipeline/bin/susiex-pipeline init . )

# 3. Edit the configs
vim config/pipeline.yaml    # phenotype, output dir, SuSiEx params
vim config/cohorts.yaml     # cohort list with paths to BIM and GWAS files
vim config/loci.tsv         # loci to fine-map (chr, start, end)

# 4. Optional: dry-run to verify the workflow without submitting
susiex-pipeline dry-run .

# 5. Submit
sbatch submit.sh

# 6. Monitor
squeue -u $USER
tail -f output/<phenotype>/logs/snakemake.log
```

After submission, `squeue` will first show one controller job (`susiex_ctrl`).
Once that starts running, additional per-rule jobs will appear as Snakemake
submits them.

## What the user's analysis directory looks like

```
my_finemap_analysis/
├── config/
│   ├── pipeline.yaml          # phenotype, paths, SuSiEx params
│   ├── cohorts.yaml           # cohort manifest
│   └── loci.tsv               # loci to fine-map
├── submit.sh                  # generated SLURM controller job
├── slurm_controller_<JID>.log # outer job log
└── output/
    └── <phenotype>/
        ├── inputs/            # per-cohort SuSiEx input files
        ├── loci/<locus>/      # per-locus results + plots
        └── logs/
            ├── snakemake.log              # Snakemake's master log
            ├── prepare_input.<cohort>.log
            ├── susiex.<locus>.log
            └── plot.<locus>.log
```

## Re-running and resuming

Snakemake checks output files and only runs missing or stale ones.

- **Add a locus to `loci.tsv` and re-run:** `sbatch submit.sh` — only the new
  locus runs.
- **A locus failed:** fix the issue, `sbatch submit.sh` again — only the
  failed locus is retried.
- **Force a full rebuild:** `sbatch submit.sh --forceall`.
- **Dry-run after edits:** `susiex-pipeline dry-run .` — shows what *would*
  run without submitting.

## Configuration reference

### `config/pipeline.yaml`

| Key | Description |
|---|---|
| `phenotype` | Short label; used in output filenames and folder names |
| `output_root` | Output base directory (absolute or relative to analysis dir) |
| `susiex_bin` | Path to SuSiEx binary (admin default pre-filled by `init`) |
| `plink_bin` | Path to PLINK binary (admin default pre-filled by `init`) |
| `cohorts_config` | Path to cohorts YAML (default `config/cohorts.yaml`) |
| `loci_file` | Path to loci TSV (default `config/loci.tsv`) |
| `susiex.level` | Credible set coverage (e.g., 0.95) |
| `susiex.pval_thresh` | P-value threshold for variant filtering |
| `susiex.maf` | Minor allele frequency threshold |
| `susiex.mult_step` | Use multi-step L selection (recommended) |
| `susiex.keep_ambig` | Keep strand-ambiguous SNPs |
| `susiex.threads` | CPUs per SuSiEx job |

### `config/cohorts.yaml`

```yaml
cohorts:
  - name: ADNI
    ancestry: EUR
    n_gwas: 1411
    bim_prefix: /path/to/ADNI_imputed_unrelated_final
    gwas_file:  /path/to/ADNI_baseline.assoc.linear   # or .logistic[.gz]
```

The pipeline auto-detects linear (`BETA`) vs. logistic (`OR`) assoc files
and converts OR to log(OR) automatically.

### `config/loci.tsv`

Tab-separated, header required, column order flexible:

```
locus_name	chr	start	end
APOE_region	19	44658684	45158684
chr9_27Mb_locus	9	27015328	27515328
```

## Repository layout (the install)

```
susiex_pipeline/
├── VERSION
├── README.md
├── install.sh                          # admin install
├── Snakefile                           # the workflow (single source of truth)
├── snakemake_slurm_profile/config.yaml # tells Snakemake to use SLURM
├── plot_susiex_pip.R
├── venv/                               # created by install.sh
├── config/
│   └── pipeline.yaml                   # admin-edited binary defaults
├── bin/
│   └── susiex-pipeline                 # user launcher (init / dry-run / version)
├── scripts/
│   ├── prepare_susiex_input.sh         # PLINK assoc -> SuSiEx input (one cohort)
│   ├── run_susiex_one_locus.sh      # SuSiEx for one locus (called by Snakemake)
│   └── lib/
│       ├── common.sh
│       └── parse_yaml.py
└── templates/                          # rendered into user analysis dirs
    ├── pipeline.yaml.template
    ├── cohorts.yaml.template
    ├── loci.tsv.template
    └── submit.sh.template
```

## Common issues

- **Controller job runs but no per-locus jobs ever appear in `squeue`** —
  Check the controller's log (`slurm_controller_*.log`); usually a
  `--profile` problem or the SLURM executor plugin isn't installed in the
  venv. Re-run `install.sh`.
- **`snakemake: command not found` in submit.sh** — venv didn't install
  correctly. Re-run `install.sh` and check for pip errors.
- **`sbatch: command not found` from inside the controller job** — the
  cluster doesn't allow nested SLURM submission. Talk to your cluster admin
  or fall back to running everything in the outer job by replacing
  `--profile ...` with `--cores N` in `submit.sh`.
- **PyYAML not found at init time** — the launcher uses the system Python to
  read admin defaults. Either install PyYAML system-wide, or have the
  launcher use the venv's Python (small change to `bin/susiex-pipeline`).
- **Variants dropped at prep** — usually means the cohort's GWAS used a
  different SNP set than its BIM file. Confirm BIM matches the GWAS sample.

## Citation

> Yuan K, Longchamps RJ, Pardiñas AF, et al. Fine-mapping across diverse
> ancestries drives the discovery of putative causal variants underlying
> human complex traits and diseases. *Nat Genet* 56, 1841–1850 (2024).
> doi:10.1038/s41588-024-01870-z
