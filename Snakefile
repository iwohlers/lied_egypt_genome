#kate:syntax python;

#######################################
### Analyzing an Egyptian genome
#######################################

from Bio import SeqIO
import os


################################################################################
############### Writing some general statistics to file ########################
################################################################################

# Chromosome and scaffold names for later use
CHR_GRCh38 = ["chromosome."+str(x) for x in range(1,23)] \
           + ["chromosome."+str(x) for x in ["MT","X","Y"]]
EGYPT_SCAFFOLDS = ["fragScaff_scaffold_"+str(x)+"_pilon" for x in range(0,41)] \
                + ["original_scaffold_"+str(x)+"_pilon" for x in range(41,145)]

# Just getting the header lines of the individual sequences in the fasta
rule scaffold_names:
    input: "seq_{assembly}/{fname}.fa"
    output: "results/{assembly}/scaffold_names_{fname}.txt"
    shell: "cat {input} | grep '>' > {output}"
    
# Quantifying the sequence content individually for all scaffolds
rule sequence_content:
    input: "seq_{assembly}/{fname}.fa"
    output: "results/{assembly}/num_bases_{fname}.txt"
    script: "scripts/sequence_content.py"

# Quantifying the sequence content over all scaffolds
rule sequence_content_overall:
    input: "seq_{assembly}/{fname}.fa"
    output: "results/{assembly}/num_all_{fname}.txt"
    script: "scripts/sequence_content_overall.py"
            
# Compute N50 and other related values as statistic for the assembly
rule compute_assembly_stats:
    input: "results/{assembly}/num_bases_{fname}.txt"
    output: "results/{assembly}/assembly_stats_{fname}.txt"
    script: "scripts/compute_assembly_stats.py"

# Computing all info numbers:
rule compute_content_and_assembly_numbers:
    input: expand( \
           "results/GRCh38/{task}_Homo_sapiens.GRCh38.dna.primary_assembly.txt", \
           task = ["scaffold_names","num_bases","num_all","assembly_stats"]),
           expand( \
           "results/EGYPTREF/{task}_Homo_sapiens.EGYPTREF.dna.primary_assembly.txt", \
           task = ["scaffold_names","num_bases","num_all","assembly_stats"])
                       
# Downloading the Busco lineage information
rule download_linage:
    output: temp("busco_lineage/mammalia_odb9.tar.gz")
    shell: "wget -P busco_lineage https://busco.ezlab.org/datasets/mammalia_odb9.tar.gz"
    
# ... and extracting it; the output files are just two of the many files in this
# archive
rule extract_lineage:
    input: "busco_lineage/mammalia_odb9.tar.gz"
    output: "busco_lineage/mammalia_odb9/lengths_cutoff",
            "busco_lineage/mammalia_odb9/scores_cutoff"
    shell: "tar --directory busco_lineage -xvzf {input}"


################################################################################
############### Finding mammalian core genes as QC using busco #################
################################################################################
                    
# Running Busco on a genome file
# --force: Deleting results folder; start new run
# --tmp: Likely /tmp is too small, so make a new tmp folder on scratch (also 
#  this can be accessed much quicker)
# --blast_single_core: There is a (known!) bug, that blast sometimes fails in
# multi-cpu mode. I also observe this for GRCh38, with exactly the corresponding
# error message; therefore, this is run with a single core.
# Note: According to Busco documentation, 3.1Gbp genome assessment with 12 CPUs 
# takes 6 days and 15 hours
# I use a separate environment for busco, because, as of now, its newest version
# cannot be used together with the repeatmasker and installing it together 
# would result in downgrading of augustus, blast, boost and busco to older 
# versions.
rule run_busco:
    input: "busco_lineage/mammalia_odb9/lengths_cutoff",
           "seq_{assembly}/Homo_sapiens.{assembly}.dna.{chr_or_type}.fa"
    output: "busco_{assembly}/run_busco_{assembly}_{chr_or_type}/short_summary_busco_{assembly}_{chr_or_type}.txt",
            "busco_{assembly}/run_busco_{assembly}_{chr_or_type}/full_table_busco_{assembly}_{chr_or_type}.tsv",
    threads: 12
    conda: "envs/busco.yaml"
    shell:  "workdir=$PWD; cd /scratch; " + \
            "rm -rf /scratch/run_busco_{wildcards.assembly}_{wildcards.chr_or_type}; " + \
            "rm -rf /scratch/tmp_busco_{wildcards.assembly}_{wildcards.chr_or_type}; " + \
            "mkdir /scratch/tmp_busco_{wildcards.assembly}_{wildcards.chr_or_type}; " + \
            "cd /scratch; " + \
            "run_busco --in $workdir/{input[1]} " + \
            "--out busco_{wildcards.assembly}_{wildcards.chr_or_type} " + \
            "--lineage_path $workdir/busco_lineage/mammalia_odb9 " + \
            "--mode genome " + \
            "--force " + \
            "--cpu 12 " + \
#           "--blast_single_core " + \
            "--tmp /scratch/tmp_busco_{wildcards.assembly}_{wildcards.chr_or_type}; " + \
            "rm -rf /scratch/tmp_busco_{wildcards.assembly}_{wildcards.chr_or_type}; " + \
            "mkdir -p busco_{wildcards.assembly}; " + \
            "cd $workdir; "
            "rm -rf busco_{wildcards.assembly}/run_busco_{wildcards.assembly}_{wildcards.chr_or_type}; " + \
            "rsync -avz /scratch/run_busco_{wildcards.assembly}_{wildcards.chr_or_type} busco_{wildcards.assembly}/; " + \
            "rm -rf /scratch/run_busco_{wildcards.assembly}_{wildcards.chr_or_type}; "

# Running busco on the entire primary assembly...
rule run_busco_primary_assembly:
    input: "busco_EGYPTREF/run_busco_EGYPTREF_primary_assembly/short_summary_busco_EGYPTREF_primary_assembly.txt",
           "busco_GRCh38/run_busco_GRCh38_primary_assembly/short_summary_busco_GRCh38_primary_assembly.txt"

# ... and running busco chromosome or scaffold-wise
rule run_busco_chromosomewise:
    input: expand("busco_EGYPTREF/run_busco_EGYPTREF_{scaffolds}/short_summary_busco_EGYPTREF_{scaffolds}.txt", \
                  scaffolds=EGYPT_SCAFFOLDS),
           expand("busco_GRCh38/run_busco_GRCh38_{chrom}/short_summary_busco_GRCh38_{chrom}.txt", \
                  chrom=CHR_GRCh38)

# Make a comparison table for the busco analysis for EGYPTREF
rule summary_busco_egyptref:
    input: expand("busco_EGYPTREF/run_busco_EGYPTREF_{scaffolds}/full_table_busco_EGYPTREF_{scaffolds}.tsv", \
                  scaffolds=EGYPT_SCAFFOLDS)
    output: "busco_EGYPTREF/busco_summary.txt"
    script: "scripts/busco_summary.py"

# Make a comparison table for the busco analysis for GRCh38
rule summary_busco_grch38:
    input: expand("busco_GRCh38/run_busco_GRCh38_{chrom}/full_table_busco_GRCh38_{chrom}.tsv", \
                  chrom=CHR_GRCh38)
    output: "busco_GRCh38/busco_summary.txt"
    script: "scripts/busco_summary.py"


################################################################################
###################### Getting reference sequences #############################
################################################################################

# Downloading all GRCh38 sequence data available from Ensembl (release 93,
# but note, that on sequence level, the release shouldn't make a difference)
rule download_GRCh38:
    output: "seq_GRCh38/Homo_sapiens.GRCh38.{dna_type}.{chr_or_type}.fa.gz"
    run: 
        # Remove target dir to obtain file name for download
        base = output[0].split("/")[1]
        shell("wget -P seq_GRCh38 " + \
        "ftp://ftp.ensembl.org/pub/release-93/fasta/homo_sapiens/dna/{base}")
              
# Download README
rule download_GRCh38_readme:
    output: "seq_GRCh38/README"
    shell: "wget -P seq_GRCh38 " + \
           "ftp://ftp.ensembl.org/pub/release-93/fasta/homo_sapiens/dna/README"

# Downloading all GRCh38 sequence files available under the ENSEMBLE release 93
# FTP address 
CHR_OR_TYPE = ["chromosome."+str(x) for x in range(1,23)] \
       + ["chromosome."+str(x) for x in ["MT","X","Y"]] \
       + ["nonchromosomal","primary_assembly","toplevel","alt"]
rule download_GRCh38_all:
    input: expand("seq_GRCh38/"+ \
                  "Homo_sapiens.GRCh38.{dna_type}.{chr_or_type}.fa.gz", \
            dna_type=["dna","dna_rm","dna_sm"],chr_or_type=CHR_OR_TYPE),
           "seq_GRCh38/README"

# Uncompressing fasta files, needed e.g. for Busco analysis
# -d decompress; -k keep archive; -c to stdout
rule uncompress_fasta:
    input: "seq_GRCh38/{fname}.fa.gz"
    output: "seq_GRCh38/{fname}.fa"
    resources: io=1
    shell: "gzip -cdk {input} > {output}"

# Copy the assembled sequence
rule cp_and_rename_assembly:
    input: "data/pilon.fasta"
    output: "seq_EGYPTREF/Homo_sapiens.EGYPTREF.dna.primary_assembly.fa"
    shell: "cp {input} {output}"


################################################################################
######################### Repeat masking with repeatmasker #####################
################################################################################

# Running repeatmasker on the Egyptian genome assembly
# I use a separate environment for repeatmasker, because, as of now, it cannot 
# be used together with the newest busco version and installing it together 
# would result in downgrading of augustus, blast, boost and busco to older 
# versions.
# -s  Slow search; 0-5% more sensitive, 2-3 times slower than default
# -q  Quick search; 5-10% less sensitive, 2-5 times faster than default
# -qq Rush job; about 10% less sensitive, 4->10 times faster than default
# -html Creates an additional output file in xhtml format
# -gff Creates an additional Gene Feature Finding format output
# Note: Result file 
# "repeatmasked_{assembly}/Homo_sapiens.{assembly}.dna.{chr_or_type}.fa.cat.gz"
# is not in the output file list, because depending on the size, either this
# file or the uncompressed file
# "repeatmasked_{assembly}/Homo_sapiens.{assembly}.dna.{chr_or_type}.fa.cat"
# will be generated.
# Temporarily outcommented output files (in case they will also be zipped):
# "repeatmasked_{assembly}/Homo_sapiens.{assembly}.dna.{chr_or_type}.fa.out",
# "repeatmasked_{assembly}/Homo_sapiens.{assembly}.dna.{chr_or_type}.fa.out.gff",
# "repeatmasked_{assembly}/Homo_sapiens.{assembly}.dna.{chr_or_type}.fa.out.html",
rule run_repeatmasker:
    input: "seq_{assembly}/Homo_sapiens.{assembly}.dna.{chr_or_type}.fa"
    output: "repeatmasked_{assembly}/Homo_sapiens.{assembly}.dna.{chr_or_type}.fa.masked",
            "repeatmasked_{assembly}/Homo_sapiens.{assembly}.dna.{chr_or_type}.fa.tbl"
    threads: 12
    conda: "envs/repeatmasker.yaml"
    shell: "workdir=$PWD; cd /scratch; " + \
           "rm -rf /scratch/repeatmasked_{wildcards.assembly}_{wildcards.chr_or_type}; " + \
           "mkdir -p /scratch/repeatmasked_{wildcards.assembly}_{wildcards.chr_or_type}; " + \
           "RepeatMasker -species human " + \
           "             -dir /scratch/repeatmasked_{wildcards.assembly}_{wildcards.chr_or_type} " + \
           "             -pa 12 " + \
           "             -xsmall " + \
           "             -q " + \
           "             -html " + \
           "             -gff $workdir/{input}; " + \
           "cd $workdir; "
           "rsync -avz /scratch/repeatmasked_{wildcards.assembly}_{wildcards.chr_or_type}/ repeatmasked_{wildcards.assembly}/; " + \
           "rm -rf /scratch/repeatmasked_{wildcards.assembly}_{wildcards.chr_or_type}; "

# Running repeatmasker on the primary assembly ...
rule run_repeatmasker_primary_assembly:
    input: "repeatmasked_GRCh38/Homo_sapiens.GRCh38.dna.primary_assembly.fa.tbl",
           "repeatmasked_EGYPTREF/Homo_sapiens.EGYPTREF.dna.primary_assembly.fa.tbl"

# ... and on the individual scaffolds
rule run_repeatmasker_chromosomewise:
    input: expand("repeatmasked_GRCh38/Homo_sapiens.GRCh38.dna.{x}.fa.tbl", \
                  x=CHR_GRCh38),
           expand("repeatmasked_EGYPTREF/Homo_sapiens.EGYPTREF.dna.{x}.fa.tbl", \
                  x=EGYPT_SCAFFOLDS)

# Summarising the chromosome-wise repeatmasker summary files for Egyptref
rule repeatmasker_summary_table_egyptref:
    input: expand("repeatmasked_EGYPTREF/Homo_sapiens.EGYPTREF.dna.{x}.fa.tbl", \
                  x=EGYPT_SCAFFOLDS)
    output: "repeatmasked_EGYPTREF/summary.txt"
    script: "scripts/repeatmasker_summary.py"

# Summarising the chromosome-wise repeatmasker summary files for GRCh38
rule repeatmasker_summary_table_grch38:
    input: expand("repeatmasked_GRCh38/Homo_sapiens.GRCh38.dna.{x}.fa.tbl", \
                  x=CHR_GRCh38)
    output: "repeatmasked_GRCh38/summary.txt"
    script: "scripts/repeatmasker_summary.py"

# Making a repeatmasker stat table over all chromosomes, one line for EGYPTREF,
# one line for GRCh38
rule comparison_repeatmasker:
    input: expand("repeatmasked_{assembly}/summary.txt", \
                  assembly=["EGYPTREF","GRCh38"])
    output: "results/repeatmasker_comparison.txt"
    script: "scripts/repeatmasker_comparison.py"

# Writing the scaffolds of the Egyptian genome to separate fasta files because
# processing the whole assembly often takes too much time
rule write_scaffold_fastas:
    input: "data/pilon.fasta"
    output: expand("seq_EGYPTREF/Homo_sapiens.EGYPTREF.dna.{scaffold}.fa", \
                   scaffold=EGYPT_SCAFFOLDS)
    run:
        with open(input[0], "r") as f_in:
            i = 0
            for record in SeqIO.parse(f_in,"fasta"):            
                with open(output[i], "w") as f_out:
                    SeqIO.write(record, f_out, "fasta")
                    i += 1


################################################################################
########### Reference to assembly genome alignment with lastz ##################
################################################################################

# Computing genome alignments using lastz
# [unmask] Attaching this to the chromosome filename instructs lastz to ignore 
# masking information and treat repeats the same as any other part of the 
# chromosome -> We do NOT want this, alignments will be crappy with it!!
# Parameters used for quick and dirty, alignment (lastz manual), taking minutes
# --notransition Don't allow any match positions in seeds to be satisified by 
#                transitions (lowers seeding sensitivity and reduces runtime)
# --nogapped Eliminates the computation of gapped alignments
# --step 20 Lowers seeding senitivity reducing runtime and memory (factor 3.3)
# Parameters from the Korean reference genome AK1 (Seo et al. 2016)
# --gapped Perform gapped extension of HSPs after first reducing them to anchor 
#          points
# --gap=600,150 Gap open and gap extension penalty
# --hspthresh=4500 Set the score threshold for the x-drop extension method; HSPs
#                  scoring lower are discarded.
# --seed 12of19 Seeds require a 19bp word with matches in 12 specific positions
# --notransition Don't allow any match positions in seeds to be satisified by 
#                transitions
# --ydrop=15000 Set the threshold for terminating gapped extension; this
#               restricts the endpoints of each local alignment by 
#               limiting the local region around each anchor in which 
#               extension is performed
# --chain Perform chaining of HSPs with no penalties
# Parameters from another Korean reference genome, KOREF (Cho et al. 2016)
# --step 19 Offset between the starting positins of successive target words 
#           considered for potential seeds
# --hspthresh 3000 Set the score threshold for the x-drop extension method; HSPs
#                  scoring lower are discared.
# --gappedthresh 3000 Set the threshold for gapped extension; alignments scoring
#                     lower than score are discarded.
# --seed 12of19 Seeds require a 19bp word with matches in 12 specific positions
# --minScore 3000 ? kenttools?
# --linearGap medium ? kenttools?
rule align_with_lastz:
    input: "repeatmasked_GRCh38/Homo_sapiens.GRCh38.dna.{chr}.fa.masked",
           "repeatmasked_EGYPTREF/Homo_sapiens.EGYPTREF.dna.{scaffold}.fa.masked"
    output: "align_lastz_GRCh38_vs_EGYPTREF/{chr}_vs_{scaffold}.maf",
            "align_lastz_GRCh38_vs_EGYPTREF/dotplots/{chr}_vs_{scaffold}.rdotplot"
    conda: "envs/lastz.yaml"
    shell: "lastz {input[0]} {input[1]} " + \
                                  "--gapped " + \
                                  "--gap=600,150 " + \
                                  "--hspthresh=4500 " + \
                                  "--seed=12of19 " + \
                                  "--notransition " + \
                                  "--ydrop=15000 " + \
                                  "--chain " + \
                                  "--format=maf " + \
                                  "--rdotplot={output[1]} " + \
                                  ">{output[0]}"

# Plot the dotplot output of lastz
rule individual_lastz_dotplot:
    input: "align_lastz_GRCh38_vs_EGYPTREF/dotplots/{chr}_vs_{scaffold}.rdotplot"
    output: "align_lastz_GRCh38_vs_EGYPTREF/dotplots/{chr}_vs_{scaffold}.pdf"
    script: "scripts/dotplot.R"

# Plotting for one scaffold the dotplot versus all chromosomes
rule dotplots_scaffold_vs_chromosomes:
    input: expand("align_lastz_GRCh38_vs_EGYPTREF/dotplots/{chr}_vs_{{scaffold}}.rdotplot", \
                  chr=CHR_GRCh38)
    output: "align_lastz_GRCh38_vs_EGYPTREF/dotplots/{scaffold}.pdf"
    script: "scripts/scaffold_vs_grch38.R"            

# Plotting the dotplots for all scaffolds
rule dotplots_scaffold_vs_chromosomes_all:
    input: expand("align_lastz_GRCh38_vs_EGYPTREF/dotplots/{scaffold}.pdf", \
                  scaffold=EGYPT_SCAFFOLDS)

# All versus all comparisons of reference and Egyptian genome
rule align_all_vs_all:
    input: expand("align_lastz_GRCh38_vs_EGYPTREF/{chr}_vs_{scaffold}.maf", \
                  chr=CHR_GRCh38, scaffold=EGYPT_SCAFFOLDS)

# Computing the GRCh38 recovery rate using the mafTools package 
# (as in Cho et al.). Using mafTools program mafPairCoverage, it is necessary
# to first combine all scaffold maf files for a chromosome, and then run 
# mafTransitiveClosure
rule combine_maf_files_for_recovery:
    input: expand("align_lastz_GRCh38_vs_EGYPTREF/{{chr}}_vs_{scaffold}.maf", \
                   scaffold=EGYPT_SCAFFOLDS)
    output: "align_lastz_GRCh38_vs_EGYPTREF/recovery/{chr}_alignments.maf"
    run: 
        shell("cat {input[0]} > {output}")
        for filename in input[1:]:
            # Append to large file; some file only have comments, no alignments
            # therefore we need to add & true because other wise the exit code
            # would indicate an error
            shell("cat {filename} | grep -v '#' >> {output} & true")

rule transitive_closure:
    input: "align_lastz_GRCh38_vs_EGYPTREF/recovery/{chr}_alignments.maf"
    output: "align_lastz_GRCh38_vs_EGYPTREF/recovery/{chr}.transclos"
    params: chr_number=lambda wildcards: wildcards.chr.split(".")[1]
    shell: "./ext_tools/mafTools/bin/mafTransitiveClosure " + \
           "--maf {input} > {output}"

rule maftools_coverage:
    input: "align_lastz_GRCh38_vs_EGYPTREF/recovery/{chr}.transclos"
    output: "align_lastz_GRCh38_vs_EGYPTREF/recovery/{chr}.coverage"
    params: chr_number=lambda wildcards: wildcards.chr.split(".")[1]
    shell: "./ext_tools/mafTools/bin/mafPairCoverage " + \
           "--maf {input} --seq1 {params.chr_number} --seq2 \* > {output}"

rule recovery:
    input: expand("align_lastz_GRCh38_vs_EGYPTREF/recovery/{chr}.coverage", \
                   chr=CHR_GRCh38)
    output: "align_lastz_GRCh38_vs_EGYPTREF/recovery/recovery.txt"
    run:
        pass


################################################################################
########### Reference to assembly genome alignment with mummer #################
################################################################################

# Genome alignments using mummer4
rule align_with_mummer:
    input: "repeatmasked_GRCh38/Homo_sapiens.GRCh38.dna.{chr}.fa.masked",
           "repeatmasked_EGYPTREF/Homo_sapiens.EGYPTREF.dna.{scaffold}.fa.masked"
    output: "align_mummer_GRCh38_vs_EGYPTREF/{chr}_vs_{scaffold}.delta"
    conda: "envs/mummer.yaml"
    shell: "nucmer " + \
           "-p align_mummer_GRCh38_vs_EGYPTREF/{wildcards.chr}_vs_{wildcards.scaffold} " + \
           "{input[0]} {input[1]}"

rule plot_mummer:
    input: "align_mummer_GRCh38_vs_EGYPTREF/{chr}_vs_{scaffold}.filter"
    output: "align_mummer_GRCh38_vs_EGYPTREF/dotplots/{chr}_vs_{scaffold}.gp",
            "align_mummer_GRCh38_vs_EGYPTREF/dotplots/{chr}_vs_{scaffold}.rplot",
            "align_mummer_GRCh38_vs_EGYPTREF/dotplots/{chr}_vs_{scaffold}.fplot",
            "align_mummer_GRCh38_vs_EGYPTREF/dotplots/{chr}_vs_{scaffold}.ps"
    conda: "envs/mummer.yaml"
    shell: "mummerplot " + \
           "--postscript " + \
           "-p align_mummer_GRCh38_vs_EGYPTREF/dotplots/{wildcards.chr}_vs_{wildcards.scaffold} " + \
           "{input[0]}; " + \
           "gnuplot {output[0]}"

# All versus all comparisons of reference and Egyptian genome
rule align_all_vs_all_mummer:
    input: expand("align_mummer_GRCh38_vs_EGYPTREF/{chr}_vs_{scaffold}.delta", \
                  chr=CHR_GRCh38, scaffold=EGYPT_SCAFFOLDS)

# All versus all dotplots of reference and Egyptian genome
rule all_vs_all_dotplots_mummer:
    input: expand("align_mummer_GRCh38_vs_EGYPTREF/dotplots/{chr}_vs_{scaffold}.gp", \
                  chr=CHR_GRCh38, scaffold=EGYPT_SCAFFOLDS)

# Plotting the dotplots for all scaffolds
rule mummer_dotplots_scaffold_vs_chromosomes_all:
    input: expand("align_lastz_GRCh38_vs_EGYPTREF/dotplots/{scaffold}.pdf", \
                  scaffold=EGYPT_SCAFFOLDS)

# Filtering the mummer alignments: Query sequences can be mapped to reference 
# sequences with -q, this allows the user to exclude chance and repeat 
# alignments, leaving only the best alignments between the two data sets (i.e.
# use the -q option for mapping query contigs to their best reference location)
# -u: float; Set the minimum alignment uniqueness, i.e. percent of the alignment 
#     matching to unique reference AND query sequence [0, 100], default 0
# -l: int; Set the minimum alignment length, default 0
rule delta_filter_mummer:
    input: "align_mummer_GRCh38_vs_EGYPTREF/{chr}_vs_{scaffold}.delta"
    output: "align_mummer_GRCh38_vs_EGYPTREF/{chr}_vs_{scaffold}.filter"
    conda: "envs/mummer.yaml"
    shell: "delta-filter -l 10000 -u 0 -q {input} > {output}"

# Running the tool nucdiff to compare two assemblies based on alignment with 
# mummer, which is also performed by the nucdiff tool
rule run_nucdiff:
    input: ref="seq_{a1}/Homo_sapiens.{a1}.dna.primary_assembly.fa", \
           query="seq_{a2}/Homo_sapiens.{a2}.dna.primary_assembly.fa"
    output: "nucdiff_{a1}_vs_{a2}/results/{a1}_vs_{a2}_ref_snps.gff", \
            "nucdiff_{a1}_vs_{a2}/results/{a1}_vs_{a2}_ref_struct.gff", \
            "nucdiff_{a1}_vs_{a2}/results/{a1}_vs_{a2}_ref_blocks.gff", \
            "nucdiff_{a1}_vs_{a2}/results/{a1}_vs_{a2}_ref_snps.vcf", \
            "nucdiff_{a1}_vs_{a2}/results/{a1}_vs_{a2}_query_snps.gff", \
            "nucdiff_{a1}_vs_{a2}/results/{a1}_vs_{a2}_query_struct.gff", \
            "nucdiff_{a1}_vs_{a2}/results/{a1}_vs_{a2}_query_blocks.gff", \
            "nucdiff_{a1}_vs_{a2}/results/{a1}_vs_{a2}_query_snps.vcf", \
            "nucdiff_{a1}_vs_{a2}/results/{a1}_vs_{a2}_stat.out"
    params: outdir=lambda wildcards: "nucdiff_"+wildcards.a1+"_vs_"+wildcards.a2
    conda: "envs/nucdiff.yaml"
    shell: "nucdiff {input.ref} {input.query} {params.outdir} " + \
           "{wildcards.a1}_vs_{wildcards.a2} " + \
           "--proc 24"


################################################################################
######## Processing Illumina PE data for the assembled individual ##############
################################################################################

# The Illumina library sample names
ILLUMINA_SAMPLES = ["NDES00177","NDES00178","NDES00179","NDES00180","NDES00181"]
ILLUMINA_SAMPLES_TO_LANES = {
    "NDES00177": [4,5,6,7],
    "NDES00178": [1,4,5,6,7],
    "NDES00179": [4,5,6,7],
    "NDES00180": [1,4,5,6,7],
    "NDES00181": [4,5,6,7]
}
ILLUMINA_LIBS = []
for sample in ILLUMINA_SAMPLES:
    ILLUMINA_LIBS += [sample+"_L"+str(x) for x in \
                      ILLUMINA_SAMPLES_TO_LANES[sample]]

# Mapping the Illumina PE data to the scaffolds
# -a STR: Algorithm for constructing BWT index. Chosen option: 
#         bwtsw: Algorithm implemented in BWT-SW. This method works with the 
#         whole human genome.
# -p STR: Prefix of the output database [same as db filename] 
rule bwa_index:
    input: "seq_{assembly}/Homo_sapiens.{assembly}.dna.primary_assembly.fa"
    output: "bwa_index/Homo_sapiens.{assembly}.dna.primary_assembly.amb",
            "bwa_index/Homo_sapiens.{assembly}.dna.primary_assembly.ann",
            "bwa_index/Homo_sapiens.{assembly}.dna.primary_assembly.bwt",
            "bwa_index/Homo_sapiens.{assembly}.dna.primary_assembly.pac",
            "bwa_index/Homo_sapiens.{assembly}.dna.primary_assembly.sa"
    conda: "envs/bwa.yaml"
    shell: "bwa index -a bwtsw " + \
                     "-p bwa_index/Homo_sapiens." + \
                     "{wildcards.assembly}.dna.primary_assembly " + \
                     "{input}"

rule bwa_index_all:
    input: expand("bwa_index/Homo_sapiens.{assembly}.dna.primary_assembly.sa", \
                  assembly=["EGYPTREF","GRCh38"])

rule bwa_mem:
    input: index = "bwa_index/Homo_sapiens.{assembly}.dna.primary_assembly.sa",
           fastq_r1 = "data/02.DES/{lib}_1.fq.gz",
           fastq_r2 = "data/02.DES/{lib}_2.fq.gz"
    output: "map_bwa_{assembly}/{lib}.bam"
    shell: "bwa mem -t 48 " + \
           "bwa_index/Homo_sapiens.{wildcards.assembly}.dna.primary_assembly "+\
           "{input.fastq_r1} {input.fastq_r2} " + \
           " | samtools sort -@48 -o {output} -"

rule bwa_mem_all:
    input: expand("map_bwa_{assembly}/{lib}.bam", \
                  assembly=["EGYPTREF","GRCh38"], lib=ILLUMINA_LIBS)

# For SNP calling and other things that are done for the Illumnin PE data
rule symlink_illumina_wgs_dir:
    output: directory("data/02.DES")
    shell: "ln -s /data/lied_egypt_genome/raw/02.DES {output}"

# Some QC: Here, fastqc for all Illumina PE WGS files
rule run_fastqc:
    input: "data/02.DES/{lib}_{read}.fq.gz"
    output: html="illumina_qc/fastqc/{lib}_{read}_fastqc.html",
            zip="illumina_qc/fastqc/{lib}_{read}_fastqc.zip"
    conda: "envs/fastqc.yaml"
    shell: "fastqc --outdir illumina_qc/fastqc/ {input[0]}"

rule run_fastqc_all:
    input: expand("illumina_qc/fastqc/{lib}_{read}_fastqc.html", lib=ILLUMINA_LIBS, \
                                                          read=["1","2"])


################################################################################
################### SNP Calling for 9 Egyptian individuals #####################
################################################################################

# If possible, the variant calling (vc) tasks are performed with 8 threads and
# with 35Gb of memory, such that 5 tasks can be run on a node in parallel

# These are the sample IDs
EGYPT_SAMPLES = ["LU18","LU19","LU2","LU22","LU23","LU9","PD114","PD115","PD82","TEST"]

# These are additional IDs after the sample IDs, given by Novogene, e.g 
# H75TCDMXX is the ID of the sequencer, L1 is the first lane
EGYPT_SAMPLES_TO_PREPLANES = {
    "LU18":  ["NDHG02363_H75HVDMXX_L1", "NDHG02363_H75TCDMXX_L1", \
              "NDHG02363_H75HVDMXX_L2", "NDHG02363_H75TCDMXX_L2", \
              "NDHG02363_H75FVDMXX_L1", "NDHG02363_H75FVDMXX_L2"],
    "LU19":  ["NDHG02358_H7777DMXX_L1", "NDHG02358_H7777DMXX_L2"],
    "LU2":   ["NDHG02365_H75FVDMXX_L1", "NDHG02365_H75FVDMXX_L1"],
    "LU22":  ["NDHG02364_H75LLDMXX_L1", "NDHG02364_H75LLDMXX_L2"],
    "LU23":  ["NDHG02366_H75FVDMXX_L1", "NDHG02366_H75FVDMXX_L2"],
    "LU9":   ["NDHG02362_H772LDMXX_L1", "NDHG02362_H772LDMXX_L2"],
    "PD114": ["NDHG02360_H772LDMXX_L1", "NDHG02360_H772LDMXX_L2"],
    "PD115": ["NDHG02361_H772LDMXX_L1", "NDHG02361_H772LDMXX_L2"],
    "PD82":  ["NDHG02359_H772LDMXX_L1", "NDHG02359_H772LDMXX_L2"],
    "TEST":  ["PROTOCOL_SEQUENCER_L1", "PROTOCOL_SEQUENCER_L2"] # the last is for testing purposes
}

# Symlinking the raw data directory
rule symlink_data_for_variant_detection:
    output: directory("data/raw_data")
    shell: "ln -s /data/lied_egypt_genome/raw_data {output}"

# Getting the latest dbsnp version for GRCh38, this is version 151; I am 
# getting the VCF file deposited under GATK, which is very slightly larger than
# the file under VCF, but I didn't check the precise difference and there is 
# no note in the READMEs.
rule get_known_snps_from_dbsnp:
    output: "dbsnp_GRCh38/All_20180418.vcf.gz"
    shell: "wget -P dbsnp_GRCh38 " + \
           "ftp://ftp.ncbi.nlm.nih.gov/snp/organisms/human_9606/VCF/GATK/All_20180418.vcf.gz"

# ... and getting its index
rule get_index_of_known_snps_from_dbsnp:
    output: "dbsnp_GRCh38/All_20180418.vcf.gz.tbi"
    shell: "wget -P dbsnp_GRCh38 " + \
           "ftp://ftp.ncbi.nlm.nih.gov/snp/organisms/human_9606/VCF/GATK/All_20180418.vcf.gz.tbi"

### 1. map reads to genome
# Mapping to reference/assembly using bwa
rule vc_bwa_mem:
    input: index = "bwa_index/Homo_sapiens.{assembly}.dna.primary_assembly.sa",
           fastq_r1 = "data/raw_data/{sample}/{sample}_{infolane}_1.fq.gz",
           fastq_r2 = "data/raw_data/{sample}/{sample}_{infolane}_2.fq.gz"
    output: "variants_{assembly}/{sample}_{infolane}.sam"
    wildcard_constraints: sample="[A-Z,0-9]+", infolane="[A-Z,0-9,_]+"
    conda: "envs/variant_calling.yaml"
    shell: "bwa mem -t 24 " + \
           "bwa_index/Homo_sapiens.{wildcards.assembly}.dna.primary_assembly " + \
           "{input.fastq_r1} {input.fastq_r2} > {output}"

### 2. CleanSam
# Cleans the provided SAM/BAM, soft-clipping beyond-end-of-reference alignments 
# and setting MAPQ to 0 for unmapped reads
# java -Xmx35g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar share/picard-2.18.9-0/picard.jar
rule vc_clean_sam:
    input: "variants_{assembly}/{sample}_{infolane}.sam"
    output: "variants_{assembly}/{sample}_{infolane}.cleaned.sam"
    conda: "envs/variant_calling.yaml"
    shell: "java -Xmx80g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar .snakemake/conda/d590255f/share/picard-2.18.9-0/picard.jar " + \ 
           "CleanSam " + \
           "I={input} " + \
           "O={output}"

### 3. Sort Sam -> output: bam + idx
# Sorting by coordinates, making an index and outputting as bam
rule vc_sort_and_index_sam:
    input: "variants_{assembly}/{sample}_{infolane}.cleaned.sam"
    output: "variants_{assembly}/{sample}_{infolane}.cleaned.bam"
    conda: "envs/variant_calling.yaml"
    shell: "java -Xmx80g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar .snakemake/conda/d590255f/share/picard-2.18.9-0/picard.jar " + \
           "SortSam " + \
           "I={input} " + 
           "O={output} " + \
           "SORT_ORDER=coordinate " + \
           "CREATE_INDEX=true"

### 4. Fix Mate Pair Information
# verify mate-pair information between mates and fix if needed
rule vc_fix_mates:
    input: "variants_{assembly}/{sample}_{infolane}.cleaned.bam"
    output: "variants_{assembly}/{sample}_{infolane}.fixed.bam"
    conda: "envs/variant_calling.yaml"
    shell: "java -Xmx80g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar .snakemake/conda/d590255f/share/picard-2.18.9-0/picard.jar " + \
           "FixMateInformation " + \
           "I={input} " + \
           "O={output} " + \
           "SORT_ORDER=coordinate " + \
           "CREATE_INDEX=true"

### 5. Mark Duplicates
rule vc_mark_duplicates:
    input: "variants_{assembly}/{sample}_{infolane}.fixed.bam"
    output: "variants_{assembly}/{sample}_{infolane}.rmdup.bam",
            "variants_{assembly}/{sample}_{infolane}.rmdup.txt"
    conda: "envs/variant_calling.yaml"
    shell: "java -Xmx80g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar .snakemake/conda/d590255f/share/picard-2.18.9-0/picard.jar " + \
           "MarkDuplicates " + \
           "I={input} " + \
           "O={output[0]} " + \
           "M={output[1]} " + \
           "REMOVE_DUPLICATES=true "+ \
           "ASSUME_SORTED=coordinate " + \
           "CREATE_INDEX=true"

### 6. merge *.bam files
# Merging all bam Files for a sample
rule vc_merge_bams_per_sample:
    input: lambda wildcards: \
           expand("variants_{assembly}/{sample}_{infolane}.rmdup.bam", \
           assembly = wildcards.assembly, \
           sample=wildcards.sample, \
           infolane = EGYPT_SAMPLES_TO_PREPLANES[wildcards.sample])
    output: "variants_{assembly}/{sample}.merged.bam"
    params:
        picard_in=lambda wildcards, input: "I="+" I=".join(input)
    conda: "envs/variant_calling.yaml"
    shell: "java -Xmx80g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar .snakemake/conda/d590255f/share/picard-2.18.9-0/picard.jar " + \
           "MergeSamFiles " + \
           "{params.picard_in} " + \
           "O={output} " + \
           "SORT_ORDER=coordinate " + \
           "CREATE_INDEX=true " + \
           "USE_THREADING=24"

### 7. Collect Alignment Summary Metrics
rule vc_alignment_metrics:
    input: "variants_{assembly}/{sample}.merged.bam"
    output: "variants_{assembly}/{sample}.stats.txt"
    conda: "envs/variant_calling.yaml"
    shell: "java -Xmx80g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar .snakemake/conda/d590255f/share/picard-2.18.9-0/picard.jar " + \
           "CollectAlignmentSummaryMetrics " + \
           "I={input} " + \
           "O={output}"

### 8. Replace Read Groups
rule vc_replace_read_groups:
    input: "variants_{assembly}/{sample}.merged.bam"
    output: "variants_{assembly}/{sample}.merged.rg.bam"
    conda: "envs/variant_calling.yaml"
    shell: "java -Xmx80g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar .snakemake/conda/d590255f/share/picard-2.18.9-0/picard.jar " + \
           "AddOrReplaceReadGroups " + \
           "I={input} " + \
           "O={output} " + \
           "RGID={wildcards.sample} " + \
           "RGPL=illumina " + \
           "RGLB={wildcards.sample} " + \
           "RGPU=unit1 " + \
           "RGSM={wildcards.sample} " + \
           "CREATE_INDEX=true"

### 9. Realign

# Therefore, generate a sequence dictionary for use with picard tools first
rule vc_seq_dict:
    input: "seq_{assembly}/Homo_sapiens.{assembly}.dna.primary_assembly.fa"
    output: "seq_{assembly}/Homo_sapiens.{assembly}.dna.primary_assembly.dict"
    conda: "envs/variant_calling.yaml"
    shell: "java -Xmx80g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar .snakemake/conda/d590255f/share/picard-2.18.9-0/picard.jar " + \
           "CreateSequenceDictionary " + \
           "R={input} " + \
           "O={output}"

rule vc_realign:
    input: "variants_{assembly}/{sample}.merged.rg.bam",
           "seq_{assembly}/Homo_sapiens.{assembly}.dna.primary_assembly.fa",
           "seq_{assembly}/Homo_sapiens.{assembly}.dna.primary_assembly.dict"
    output: "variants_{assembly}/{sample}.merged.rg.ordered.bam"
    conda: "envs/variant_calling.yaml"
    shell: "java -Xmx80g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar .snakemake/conda/d590255f/share/picard-2.18.9-0/picard.jar " + \
           "ReorderSam " + \
           "I={input[0]} " + \
           "O={output} " + \
           "R={input[1]} " + \
           "CREATE_INDEX=true"

### 10. RealignerTargetCreator

# Therefore, the fasta file needs to be indexed
rule vc_inex_fasta:
    input: "seq_GRCh38/Homo_sapiens.GRCh38.dna.primary_assembly.fa"
    output: "seq_GRCh38/Homo_sapiens.GRCh38.dna.primary_assembly.fa.fai"
    shell: "samtools faidx {input}"

# java -Xmx35g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar
rule vc_realigner_target_creator:
    input: "variants_{assembly}/{sample}.merged.rg.ordered.bam",
           "seq_{assembly}/Homo_sapiens.{assembly}.dna.primary_assembly.fa",
           "seq_GRCh38/Homo_sapiens.GRCh38.dna.primary_assembly.fa.fai"
    output: "variants_{assembly}/{sample}.merged.rg.ordered.bam.intervals"
    conda: "envs/variant_calling.yaml"
    shell: "java -Xmx80g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar .snakemake/conda/d590255f/opt/gatk-3.8/GenomeAnalysisTK.jar " + \
           "-T RealignerTargetCreator " + \
           "-R {input[1]} " + \
           "-I {input[0]} " + \
           "-o {output} " + \
           "-nt 24"

### 11. IndelRealigner
rule vc_indel_realigner:
    input: "variants_{assembly}/{sample}.merged.rg.ordered.bam",
           "seq_{assembly}/Homo_sapiens.{assembly}.dna.primary_assembly.fa",
           "variants_{assembly}/{sample}.merged.rg.ordered.bam.intervals"
    output: "variants_{assembly}/{sample}.indels.bam"
    conda: "envs/variant_calling.yaml"
    shell: "java -Xmx80g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar .snakemake/conda/d590255f/opt/gatk-3.8/GenomeAnalysisTK.jar " + \
           "-T IndelRealigner " + \
           "-R \"{input[1]}\" " + \
           "-I {input[0]} " + \
           "-targetIntervals {input[2]} " + \
           "-o {output}"

### 12. Base Quality Recalibration
rule vc_base_recalibrator:
    input: "variants_{assembly}/{sample}.indels.bam",
           "seq_{assembly}/Homo_sapiens.{assembly}.dna.primary_assembly.fa",
           "dbsnp_{assembly}/All_20180418.vcf.gz",
           "dbsnp_{assembly}/All_20180418.vcf.gz.tbi"
    output: "variants_{assembly}/{sample}.indels.recal.csv"
    conda: "envs/variant_calling.yaml"
    shell: "java -Xmx80g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar .snakemake/conda/d590255f/opt/gatk-3.8/GenomeAnalysisTK.jar " + \
           "-T BaseRecalibrator " + \
           "-R {input[1]} " + \
           "-I {input[0]} " + \
           "-cov ReadGroupCovariate " + \
           "-cov QualityScoreCovariate " + \
           "-cov CycleCovariate " + \
           "-cov ContextCovariate " + \
           "-o {output} " + \
           "-knownSites {input[2]} " + \
           "-nct 24"

### 13. Print Reads
rule vc_print_reads:
    input: "variants_{assembly}/{sample}.indels.bam",
           "seq_{assembly}/Homo_sapiens.{assembly}.dna.primary_assembly.fa",
           "variants_{assembly}/{sample}.indels.recal.csv"
    output: "variants_{assembly}/{sample}.final.bam"
    conda: "envs/variant_calling.yaml"
    shell: "java -Xmx80g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar .snakemake/conda/d590255f/opt/gatk-3.8/GenomeAnalysisTK.jar " + \
           "-T PrintReads " + \
           "-R {input[1]} " + \
           "-I {input[0]} " + \
           "-o {output[0]} " + \
           "-BQSR {input[2]} " + \
           "-nct 24"

### 14. variant calling with GATK-HC
# use GATK Haplotypecaller with runtime-optimized settings
# -variant_index_type LINEAR -variant_index_parameter 128000 IW added because
# the GATK program told me so and otherwise would exit with error.
# java -XX:+UseConcMarkSweepGC -XX:ParallelGCThreads=4 -Xmx35g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar gatk 
rule vc_snp_calling_with_gatk_hc:
    input: "variants_{assembly}/{sample}.final.bam",
           "seq_{assembly}/Homo_sapiens.{assembly}.dna.primary_assembly.fa",
    output: "variants_{assembly}/{sample}.vcf"
    conda: "envs/variant_calling.yaml"
    shell: "java -XX:+UseConcMarkSweepGC -XX:ParallelGCThreads=4 -Xmx80g -Djava.io.tmpdir=/data/lied_egypt_genome/tmp -jar .snakemake/conda/d590255f/opt/gatk-3.8/GenomeAnalysisTK.jar " + \
           "-T HaplotypeCaller " + \
           "-R {input[1]} " + \
           "-I {input[0]} " + \
           "--genotyping_mode DISCOVERY " + \
           "-o {output} " + \
           "-ERC GVCF " + \
           "-variant_index_type LINEAR " + \
           "-variant_index_parameter 128000 " + \
           "-nct 24"

# Doing the variant calling for all 9 samples
rule vc_snp_calling_with_gatk_hc_all:
    input: expand("variants_GRCh38/{sample}.vcf", sample=EGYPT_SAMPLES)

# Extracting variants within a certain genes (and near to it)

# Therefore, obtain a recent Ensemble annotation file first
rule get_ensembl_gene_annotation_gtf:
    output: temp("annotations/Homo_sapiens.GRCh38.94.gtf.gz")
    shell: "wget -P annotations " + \
           "ftp://ftp.ensembl.org/pub/release-94/gtf/homo_sapiens/Homo_sapiens.GRCh38.94.gtf.gz "

rule unzip_ensembl_gene_annotation_gtf:
    input: "annotations/Homo_sapiens.GRCh38.94.gtf.gz"
    output: "annotations/Homo_sapiens.GRCh38.94.gtf"
    shell: "gzip -d {input}"


################################################################################
##### Assembly assessment and correction (Things related to PacBio data) #######
################################################################################

# There are 5 PacBio libraries from the same individual, each sequences in 
# various sequencing runs  
PACBIO_SAMPLES = ["r54171","r54172","r54212","r54214","r54217"]

# The naming convention for folders is the sample name, _, then the seqrun ID, 
# The naming convention for files is the same, but for some reason the "r" of
# the samples has been replaced by "m"; also sum files are in subdirectories
# Since there seems no apparent system to the file naming, I here just map the
# samples to the corresponding Pacbio filenames (without ending, but the file
# basename is always the same)
PACBIO_SAMPLES_TO_SEQRUN_PATH = { \
    "r54171": ["r54171_180507_074037/m54171_180507_074037", \
               "r54171_180508_081816/m54171_180508_081816", \
               "r54171_180509_085337/m54171_180509_085337", \
               "r54171_180509_190202/m54171_180509_190202", \
               "r54171_180510_051157/m54171_180510_051157", \
               "r54171_180511_073925/m54171_180511_073925", \
               "r54171_180511_174954/m54171_180511_174954", \
               "r54171_180512_040316/m54171_180512_040316", \
               "r54171_180512_141733/m54171_180512_141733", \
               "r54171_180513_003153/m54171_180513_003153", \
               "r54171_180514_191117/m54171_180514_191117", \
               "r54171_180515_052445/m54171_180515_052445", \
               "r54171_180515_153940/m54171_180515_153940"],\
    "r54172": ["r54172_20180226_063627/1_A08/m54172_180226_064443", \
               "r54172_20180227_060945/1_A08/m54172_180227_061743", \
               "r54172_20180227_060945/2_B08/m54172_180227_162339", \
               "r54172_20180227_060945/3_C08/m54172_180228_023312", \
               "r54172_20180301_065149/2_B08/m54172_180301_170719"], \
    "r54212": ["r54212_20180207_084734/1_A05/m54212_180207_085743"], \
    "r54214": ["r54214_20180225_094705/1_A08/m54214_180225_095639", \
               "r54214_20180226_063218/1_A08/m54214_180226_064236", \
               "r54214_20180226_063218/2_B08/m54214_180226_164754", \
               "r54214_20180227_074241/1_A08/m54214_180227_075436", \
               "r54214_20180227_074241/2_B08/m54214_180227_180004", \
               "r54214_20180228_083736/1_A05/m54214_180228_084706", \
               "r54214_20180301_092943/1_A08/m54214_180301_094052", \
               "r54214_20180301_092943/2_B08/m54214_180301_194631", \
               "r54214_20180301_092943/3_C08/m54214_180302_055606", \
               "r54214_20180303_091311/1_A08/m54214_180303_092301", \
               "r54214_20180304_073054/1_A05/m54214_180304_074025", \
               "r54214_20180304_073054/2_B05/m54214_180304_174558", \
               "r54214_20180304_073054/3_C05/m54214_180305_035534", \
               "r54214_20180304_073054/4_D05/m54214_180305_140511", \
               "r54214_20180304_073054/5_E05/m54214_180306_001437", \
               "r54214_20180304_073054/6_F05/m54214_180306_102433", \
               "r54214_20180304_073054/7_G05/m54214_180306_203421", \
               "r54214_20180304_073054/8_H05/m54214_180307_064357", \
               "r54214_20180308_072240/1_A01/m54214_180308_073253", \
               "r54214_20180308_072240/2_B01/m54214_180308_173821", \
               "r54214_20180309_085608/1_A01/m54214_180309_090535", \
               "r54214_20180309_085608/2_B01/m54214_180309_191107", \
               "r54214_20180309_085608/3_C01/m54214_180310_052041", \
               "r54214_20180309_085608/4_D01/m54214_180310_153039", \
               "r54214_20180309_085608/5_E01/m54214_180311_014012", \
               "r54214_20180309_085608/6_F01/m54214_180311_114949", \
               "r54214_20180312_065341/1_A08/m54214_180312_071349", \
               "r54214_20180313_083026/1_A08/m54214_180313_083936", \
               "r54214_20180314_082924/1_A05/m54214_180314_083852"], \
    "r54217": ["r54217_20180205_093834/1_A01/m54217_180205_095019"]
}

rule symlink_pacbio:
    output: directory("data/01.pacbio")
    shell: "ln -s /data/lied_egypt_genome/raw/P101HW18010820-01_human_2018.08.29/00.data/01.pacbio {output}"

rule count_pacbio_reads:
    input: expand("data/01.pacbio/{pb_files}.subreads.bam", \
           pb_files = [item for subl in PACBIO_SAMPLES_TO_SEQRUN_PATH.values() \
                       for item in subl])
    output: "pacbio/num_reads.txt"
    run:
        shell("touch {output}")
        for filename in input[1:]:
            shell("samtools view {filename} | wc -l >> {output}.tmp")
        sum = 0
        with open("{output}.tmp","r") as f_in, open("{output}","r") as f_out:
            for line in f_in:
                s = line.strip().split(" ")
                num = s[0]
                sum += num
                filename = s[1].split("/")[-1]
                f_out.write(filename+"\t"+num+"\n")
            f_out.write("Sum"+ "\t"+sum+"\n")
                
    
