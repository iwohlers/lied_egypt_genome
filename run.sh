#!/bin/bash

## If environment.yaml has been changed, the existing environment needs to be removed
## in order to re-generate the environment using:
#source ~/.bashrc; conda env remove -n workflow_lied_egypt_genome

mkdir -p log

echo "GENERATING AND ACTIVATING BIOCONDA WORKFLOW ENVIRONMENT..."
export PATH="$HOME/miniconda3/bin:$PATH"
if [ ! -d $HOME/miniconda3/envs/workflow_lied_egypt_genome ]; then
    conda env create -n workflow_lied_egypt_genome --file environment.yaml
fi
source activate workflow_lied_egypt_genome

echo "RUNNING SNAKEMAKE WORKFLOW..."
snakemake --rerun-incomplete -k -j 12 --resources io=4 --use-conda --jobname "{jobid}.{rulename}.sh" --cluster "sbatch --mem 80G --partition=longterm --time 4-00:00:00 -c 24 -o log/%j.{rule}.log" --printshellcmds variants_GRCh38/TEST.vcf  variants_GRCh38/egyptians.vcf variants_GRCh38/EGYPTREF.final.MT.bam #align_assemblies_with_mummer_all vc_snp_calling_with_gatk_hc_all 

source deactivate
conda list -n workflow_lied_egypt_genome --export > environment_versions.yaml
