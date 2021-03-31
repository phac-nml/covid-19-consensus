#!/bin/bash

### Settings ###
################
SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

DIRECTORY=0
METADATA=0
CORES=2
RUNNAME="nml"
PDF=false
RUN_SNP_TREE=true

# Envs needed
envArray=(covid-consensus-pipeline ncov-qc)

HELP="""
Run ncov-tools on fasta files and combine the results into singular QC csv file

Usage
    bash $SCRIPTPATH/run_covid_consensus.sh -d <Path/to/Consensus_Dir/> <OPTIONAL FLAGS>

Flags:
    -d  --directory :  Path to directory containing fasta files
    -m  --metadata  :  (OPTIONAL) Path to TSV metadata file containing at minimum the columns 'sample', 'date', and 'ct'
    -c  --cores     :  (OPTIONAL) Number of Cores to use in Signal. Default is 2
    -n  --run-name  :  (OPTIONAL) Run name for final ncov-tools outputs. Default is 'nml'
    --pdf           :  (OPTIONAL) If you have pdflatex installed runs ncov-tools pdf output
    --no-snp-tree   :  (OPTIONAL) Turns off ncov-tools SNP tree (recommended for larger datasets if limited time available)
"""

# INPUTS #
##########

# Check for Args #
if [ $# -eq 0 ]; then
    echo "$HELP"
    exit 0
fi

# Set Arguments #
while [ "$1" = "--directory" -o "$1" = "-d" -o "$1" = "--metadata" -o "$1" = "-m" -o "$1" = "--cores" -o "$1" = "-c" -o "$1" = "--run-name" -o "$1" = "-n" -o "$1" = "--pdf" -o "$1" = "--no-snp-tree" ];
do
    if [ "$1" = "--directory" -o "$1" = "-d" ]; then
        shift
        DIRECTORY=$1
        shift
    elif [ "$1" = "--metadata" -o "$1" = "-m" ]; then
        shift
        METADATA=$1
        FULL_PATH_METADATA=$(realpath $METADATA)
        shift
    elif [ "$1" = "--cores" -o "$1" = "-c" ]; then
        shift
        CORES=$1
        shift
    elif [ "$1" = "--run-name" -o "$1" = "-n" ]; then
        shift
        RUNNAME=$1
        shift
    elif [ "$1" = "--pdf" ]; then
        PDF=true
        shift
    elif [ "$1" = "--no-snp-tree" ]; then
        RUN_SNP_TREE=false
        shift
    else
        shift
    fi
done

### Checking Inputs ###
#######################
if [ "$DIRECTORY" = 0 ]; then
    echo "ERROR: You must specify a valid directory with '-d DIRECTORY'"
    echo "$HELP"
    exit 1
elif [ ! -d "$DIRECTORY" ]; then
    echo "ERROR: $DIRECTORY is not a valid directory"
    echo "$HELP"
    exit 1
fi

if [[ $CORES == +([0-9]) ]]; then
    echo "Using $CORES cores for analysis"
else
    echo "ERROR: Cores input (-c) not an integer"
    exit 1
fi

### Check for Fasta Files ###
#############################
if [ $(find $DIRECTORY -maxdepth 1 -type "f" -name "*.fa*" | wc -l) == 0 ]; then
    echo "ERROR: No fasta files found in $DIRECTORY"
    ls $DIRECTORY
    exit 1
fi
### End Checking Inputs ###

### Conda ###
#############
eval "$(conda shell.bash hook)"

for ENV in ${envArray[@]}; do
    # Check if env exists in user envs. NOTE if it is a env not listed in `conda env list` it will error out
    if [[ $(conda env list | awk '{print $1}' | grep "^$ENV"'$') ]]; then
        :
    else
        echo "ERROR: Conda ENV '$ENV' was not found. Please follow the README instructions and install the environment"
        exit 1
    fi
done

conda activate covid-consensus-pipeline
### End Conda ###

### Root Output Setup ###
#########################
timestamp=`date +%b%d_%H%M`
dir_path=$(realpath $DIRECTORY)
run_name=${dir_path##*/}
root="consensus_results_${run_name}_${timestamp}"
mkdir -p $root

cd $root

# Get ncov-tools latest version for most up to date everything
git clone https://github.com/jts/ncov-tools.git
mkdir -p ./ncov-tools/files
ln -s $SCRIPTPATH/resources/nCoV-2019.reference.fasta* .
### Root Setup ###

### Run for each consensus in folder ###
#######################################

# Set up raw data and names to match a nanopore run (to make it easier to interface, can be changed if needed)
for FASTA in $dir_path/*.fa*
do
    # Set the name by stripping the path and all additional `.`
    filename="$(basename $FASTA)"
    name=$(echo "$filename" | cut -f 1 -d '.')
    echo $name

    ## Generate input files ##
    # Bam file and vcf files needed for ncov-tools based on nanopore input
    minimap2 -a -x asm5 ./nCoV-2019.reference.fasta $FASTA > aligned.sam
    htsbox samview -S -b aligned.sam > ./ncov-tools/files/${name}.sorted.bam

    # VCF file that is subsequently gzipped to match nanopore pipeline
    htsbox pileup -f ./nCoV-2019.reference.fasta -d -c ./ncov-tools/files/${name}.sorted.bam > ./ncov-tools/files/${name}.pass.vcf
    bgzip ./ncov-tools/files/${name}.pass.vcf
    tabix ./ncov-tools/files/${name}.pass.vcf.gz

    # Add in consensus using the found name to be consistent
    ln -s $FASTA ./ncov-tools/files/${name}.consensus.fasta
    rm aligned.sam
done
### Done Set Up of Inputs ###

### NCOV-TOOLS ###
##################
# Get config and needed files
cp $SCRIPTPATH/resources/ncov-tools-files/* ./ncov-tools/

# Metadata #
if [ "$METADATA" = 0 ]; then
    sed -i -e 's/^metadata/#metadata/' ./ncov-tools/config.yaml
    cleanup_metadata=""
else
    cp $FULL_PATH_METADATA ./ncov-tools/metadata.tsv
    cleanup_metadata="--sample_sheet $FULL_PATH_METADATA"
fi

# Build tree
if [ "$RUN_SNP_TREE" = false ]; then
    echo "build_snp_tree: false" >> ./ncov-tools/config.yaml
fi

# Set Run name
echo "run_name: $RUNNAME" >> ./ncov-tools/config.yaml

# Run ncov-tools #
conda activate ncov-qc

cd ncov-tools
snakemake -kp -s workflow/Snakefile --cores 1 build_snpeff_db
snakemake -kp -s workflow/Snakefile all --cores $CORES
snakemake -kp -s workflow/Snakefile --cores 2 all_qc_annotation

if [ "$PDF" = true ]; then
    snakemake -s workflow/Snakefile all_final_report --cores 1
fi

conda deactivate
cd -
### Done NCOV-TOOLS ###

### QC Summary ###
##################

# Make output summary location
mkdir -p summary_csvs

# Relative file locations needed for all samples
ncov_qc="./ncov-tools/qc_reports/${RUNNAME}_summary_qc.tsv"
pangolin="./ncov-tools/lineages/${RUNNAME}_lineage_report.csv"

for FASTA in $(ls ./ncov-tools/files/*.consensus.fasta)
do
    filename="$(basename $FASTA)"
    name=$(echo "$filename" | cut -f 1 -d '.')
    snpeff="./ncov-tools/qc_annotation/${name}_aa_table.tsv"

    # Summary
    python $SCRIPTPATH/sub_scripts/qc.py --nanopore \
        --outfile ./summary_csvs/${name}.qc.csv \
        --sample ${name} \
        --vcf ./ncov-tools/files/${name}.pass.vcf.gz \
        --pangolin ${pangolin} \
        --ncov_summary ${ncov_qc} \
        --revision v1.5 \
        --script_name consensus_only \
        --snpeff_tsv $snpeff \
        --pcr_bed $SCRIPTPATH/resources/pcr_primers.bed \
        $cleanup_metadata
done

csvtk concat ./summary_csvs/*.qc.csv > ${RUNNAME}.qc.csv

if [ -f "./ncov-tools/qc_analysis/${RUNNAME}_aligned.fasta" ];
then
    snp-dists ./ncov-tools/qc_analysis/${RUNNAME}_aligned.fasta > matrix.tsv
else
    echo "No ./ncov-tools/qc_analysis/${RUNNAME}_aligned.fasta file, skipping the snp-dist check"
fi

# Done