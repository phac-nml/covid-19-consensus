# covid-19-consensus
Generate Sars-CoV2 sequence metrics from fasta file inputs using [ncov-tools](https://github.com/jts/ncov-tools) and some small combitorial steps

## Installation

It is easiest to install and run this pipeline through [conda](https://conda.io/projects/conda/en/latest/index.html). If you aleady have conda installed you can skip to step 2.

1. Install Miniconda3
    1. Download the latest release of [Miniconda3](https://conda.io/en/latest/miniconda.html) with `wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh`
    2. Run `bash Miniconda-latest-Linux-x86_64.sh`
    3. Follow the prompts on the installer
    4. Close and re-open the terminal to allow the changes to take effect

2. Clone the covid-19-consensus repo
    ```
    git clone https://github.com/phac-nml/covid-19-consensus.git
    cd covid-19-consensus
    ```

3. Set up the two conda environments found in the conda_envs folder
    1. Covid-Consensus-Pipeline environment
        ```
        conda env create -f conda_envs/covid-consensus-pipeline.yaml 
        ```

    2. NCOV-QC environment with mamba (too large to do quickly with `conda env create`)
        ```
        # Install mamba into base if it isn't there
        conda install -c conda-forge mamba
        # Create environment
        mamba env create -f conda_envs/ncov-qc.yaml
        ```

And then you are good to go

## Running

Running the pipeline is done through a singular bash script that at minimum requires a directory of fasta consensus sequences:
```
bash covid-19-consensus/run_covid_consensus.sh -d <Path/to/Consensus/directory>
```

With the output directory being located where you ran the command as `consensus_results_<Directory_ran>_<time>`.

### Optional Inputs

Running the bash script with no arguments will print out the usage statement which is also found below:
```
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
```

#### Metadata
- Added with `-m or --metadata`
- Will add any metadata in the file to the final output csv file
- Must contain columns called 'sample', 'ct', and 'date' to work within ncov-tools

Example command: `bash run_covid_consensus.sh -d fasta_files/ -m metadata_table.tsv`

Example metadata table:

| sample | ct | date | location | primer_scheme |
|-|-|-|-|-|
| Sample_name1 | 23.33 | 2020-08-22 | Canada | Freed |
| Sample_name2 | 22.53 | NA | Canada | Resende |
| Sample_name3 | NA | NA | NA | Unknown |
| Sample_name6 | NA | 2020-08-22 | Unknown | Freed

#### Run Name
- By default the run name is "nml" but it can be changed with `-n or --run-name` to whatever you want
- This will effect some of the output names including the final output csv file

Example command: `bash run_covid_consensus.sh -d fasta_files/ -n canada_VOCs`

Output files will be:
```
canada_VOCs.qc.csv
ncov-tools/plots/canada_VOCs_tree_snps.pdf
etc.
```

#### PDF
- The pdf output of ncov-tools is available with the argument `--pdf` due to having to manually install pdflatex

Example command: `bash run_covid_consensus.sh -d fasta_files/ --pdf`

