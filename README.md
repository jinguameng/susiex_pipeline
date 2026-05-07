# SuSiEx Fine-Mapping Pipeline

A shared bash + Snakemake pipeline for cross-cohort statistical fine-mapping with [SuSiEx](https://github.com/getian107/SuSiEx). 

Designed for high-performance computing (HPC) environments using SLURM, this pipeline allows for a single cluster installation that multiple users can leverage. Each user can scaffold and run their own isolated analyses without interfering with the core codebase.

## 🧠 Architecture & Workflow

```mermaid
flowchart TD
    %% =========================================================
    %% SuSiEx pipeline -- execution flow
    %% =========================================================

    User([User in analysis dir]) -->|Runs| Submit[/"sbatch submit.sh"/]

    %% ---------- Controller layer ----------
    subgraph Controller["SLURM Controller Job (4GB / 2 CPUs / 24h)"]
        direction TB
        ActVenv["source venv/bin/activate"] --> Snake["Snakemake Orchestrator<br/>--snakefile Snakefile<br/>--profile snakemake_slurm_profile<br/>--use-envmodules"]
    end

    Submit --> ActVenv

    %% ---------- Data Preparation (Per Cohort) ----------
    Snake ==>|Submits N Jobs| PrepGroup

    subgraph PrepGroup["Rule: prepare_input (Parallel per Cohort)"]
        direction TB
        Prep1["Cohort: A4"] --> PrepScript
        Prep2["Cohort: ADNI"] --> PrepScript
        PrepN["Cohort: NACC..."] --> PrepScript
        PrepScript["scripts/prepare_susiex_input.sh<br/>(BIM + assoc -> SuSiEx input)"]
    end

    PrepScript --> InputFiles[("inputs/&lt;cohort&gt;_susiex_input.txt")]

    %% ---------- SuSiEx Execution (Per Locus) ----------
    InputFiles ==>|All cohort inputs ready| SusiexGroup

    subgraph SusiexGroup["Rule: susiex_locus (Parallel per Locus)"]
        direction TB
        Sus1["Locus: APOE"] --> SusiexScript
        Sus2["Locus: chr9_27Mb"] --> SusiexScript
        SusN["Locus: ..."] --> SusiexScript
        SusiexScript["scripts/run_susiex_one_locus.sh<br/>(Builds args -> Runs SuSiEx)"]
    end

    SusiexScript --> SusiexOut[("loci/&lt;locus&gt;/<br/>SuSiEx.&lt;phenotype&gt;.&lt;locus&gt;.cs & .snp")]

    %% ---------- Plotting (Per Locus) ----------
    SusiexOut ==>|Per locus complete| PlotGroup

    subgraph PlotGroup["Rule: plot_locus (Parallel per Locus)"]
        direction TB
        Plot1["Locus: APOE"] --> PlotScript
        Plot2["Locus: chr9_27Mb"] --> PlotScript
        PlotN["Locus: ..."] --> PlotScript
        PlotScript["plot_susiex_pip.R<br/>(module load r/4.5.0)"]
    end

    PlotScript --> PlotOut[("loci/&lt;locus&gt;/<br/>&lt;phenotype&gt;.&lt;locus&gt;_PIP.pdf & .png")]

    %% ---------- Final ----------
    PlotOut ==> Done([All loci complete])

    %% ---------- Styling ----------
    classDef controller fill:#e1f5ff,stroke:#0288d1,stroke-width:2px,color:#000
    classDef rule       fill:#fff4e1,stroke:#f57c00,stroke-width:2px,color:#000
    classDef script     fill:#f3e5f5,stroke:#7b1fa2,stroke-width:1px,color:#000
    classDef output     fill:#e8f5e9,stroke:#388e3c,stroke-width:1px,color:#000
    classDef user       fill:#fff,stroke:#000,stroke-width:2px,color:#000

    class User,Submit,Done user
    class Controller,ActVenv,Snake controller
    class Prep1,Prep2,PrepN,Sus1,Sus2,SusN,Plot1,Plot2,PlotN rule
    class PrepScript,SusiexScript,PlotScript script
    class InputFiles,SusiexOut,PlotOut output
```

## 🛠️ Admin Installation (One-Time Setup)

Clone this repository onto a shared filesystem where your group has read and execute permissions.

```bash
git clone <your-github-repo-url> susiex_pipeline
cd susiex_pipeline

# 1. Edit the admin-default binary paths
vim config/pipeline.yaml                 # Set global susiex_bin and plink_bin paths

# 2. Edit the SLURM profile for your cluster's partition / account
vim snakemake_slurm_profile/config.yaml

# 3. Install dependencies and set permissions
./install.sh

# 4. Verify everything is wired up correctly
./verify_install.sh
```

## 🚀 User Workflow

Users do not need to copy the entire repository. They simply use the pipeline launcher to scaffold an analysis in their own workspace.

**1. Initialize an Analysis Directory**
```bash
mkdir ~/my_finemap_analysis
cd ~/my_finemap_analysis

# Scaffold configs and submit script
/path/to/susiex_pipeline/bin/susiex-pipeline init .
```

**2. Configure Your Analysis**
Edit the generated files to match your dataset:
* `config/pipeline.yaml`: Set your phenotype name and SuSiEx parameters.
* `config/cohorts.yaml`: List your cohorts and provide paths to `.bim` and GWAS `.assoc` files.
* `config/loci.tsv`: Define the target loci (chr, start, end).

**3. Dry-Run & Submit**
```bash
# Verify configs without executing
/path/to/susiex_pipeline/bin/susiex-pipeline dry-run .

# Submit to SLURM cluster
sbatch submit.sh
```

## 📊 Outputs

Results are organized cleanly in your analysis directory:

```text
output/
└── <phenotype>/
    ├── inputs/            # Formatted per-cohort SuSiEx inputs
    ├── loci/<locus>/      # .cs, .snp files, and PIP scatter plots (.pdf, .png)
    └── logs/              # Snakemake and per-rule execution logs
```

## 📚 Citation

If you use this pipeline, please cite the original SuSiEx methodology:
> Yuan K, Longchamps RJ, Pardiñas AF, et al. Fine-mapping across diverse ancestries drives the discovery of putative causal variants underlying human complex traits and diseases. *Nat Genet* 56, 1841–1850 (2024). doi:10.1038/s41588-024-01870-z
