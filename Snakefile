# kate: syntax Python;
import itertools

# Parameters
index_nucleotides = 3
indexes = ["".join(tuple) for tuple in itertools.product("ATCG", repeat=index_nucleotides)]

rule trim_r1_handle:
    "Trim away E handle on R1 5'. Also removes reads shorter than 85 bp."
    output:
        r1_fastq="{dir}/trimmed-a.1.fastq.gz",
        r2_fastq="{dir}/trimmed-a.2.fastq.gz"
    input:
        r1_fastq="{dir}/reads.1.fastq.gz",
        r2_fastq="{dir}/reads.2.fastq.gz"
    log: "{dir}/trimmed-a.log"
    threads: 20
    shell:
        "cutadapt"
        " -g ^CAGTTGATCATCAGCAGGTAATCTGG"
        " -e 0.2"
        " --discard-untrimmed"
        " -j {threads}"
        " -m 65"
        " -o {output.r1_fastq}"
        " -p {output.r2_fastq}"
        " {input.r1_fastq}"
        " {input.r2_fastq}"
        " > {log}"


rule extract_barcodes:
    output:
        r1_fastq=temp("{dir}/unbarcoded.1.fastq"),
        r2_fastq=temp("{dir}/unbarcoded.2.fastq")
    input:
        r1_fastq="{dir}/trimmed-a.1.fastq.gz",
        r2_fastq="{dir}/trimmed-a.2.fastq.gz"
    log: "{dir}/extractbarcode.log"
    shell:
        # BDHVBDVHBDVHBDVH
        "blr extractbarcode"
        " {input.r1_fastq} {input.r2_fastq}"
        " -o1 {output.r1_fastq} -o2 {output.r2_fastq}"
        " 2> {log}"


rule compress:
    output: "{dir}/unbarcoded.{nr}.fastq.gz"
    input: "{dir}/unbarcoded.{nr}.fastq"
    shell:
        "pigz < {input} > {output}"

rule final_trim:
    """
    Cut H1691' + TES sequence from 5' of R1. H1691'=CATGACCTCTTGGAACTGTC, TES=AGATGTGTATAAGAGACAG.
    Cut 3' TES' sequence from R1 and R2. TES'=CTGTCTCTTATACACATCT
    Discard untrimmed.
    """
    output:
        r1_fastq="{dir}/trimmed-c.1.fastq.gz",
        r2_fastq="{dir}/trimmed-c.2.fastq.gz"
    input:
        r1_fastq="{dir}/unbarcoded.1.fastq.gz",
        r2_fastq="{dir}/unbarcoded.2.fastq.gz"
    log: "{dir}/trimmed-b.log"
    threads: 20
    shell:
        "cutadapt"
        " -a ^CATGACCTCTTGGAACTGTCAGATGTGTATAAGAGACAG...CTGTCTCTTATACACATCT "
        " -A CTGTCTCTTATACACATCT "
        " -e 0.2"
        " --discard-untrimmed"
        " --pair-filter 'first'"
        " -j {threads}"
        " -m 25"
        " -o {output.r1_fastq}"
        " -p {output.r2_fastq}"
        " {input.r1_fastq}"
        " {input.r2_fastq}"
        " > {log}"

# TODO Currently this cannot handle 0 index nucleotides.
rule cdhitprep:
    output:
        expand("{{dir}}/unique_bc/{sample}.fa", sample=indexes)
    input:
        r1_fastq = "{dir}/reads.1.fastq.trimmed.fastq.gz"
    params:
        dir = "{dir}/unique_bc/"
    log:
        stdout = "{dir}/cdhit_prep.stdout",
        stderr = "{dir}/cdhit_prep.stderr"
    shell:
        "blr cdhitprep "
        " {input.r1_fastq}"
        " {params.dir}"
        " -i {index_nucleotides}"
        " -f 0 > {log.stdout} 2> {log.stderr}"

rule barcode_clustering:
    input:
       "{dir}/unique_bc/{sample}.fa"
    output:
        "{dir}/unique_bc/{sample}.clustered",
        "{dir}/unique_bc/{sample}.clustered.clstr"
    threads: 20
    log: "{dir}/unique_bc/{sample}.clustering.log"
    params:
        prefix= lambda wc,output: os.path.splitext(output[1])[0]
    shell:
        " (cd-hit-454 "
        " -i {input} "
        " -o {params.prefix} "
        " -T {threads} "
        " -c 0.9 -gap 100 -g 1 -n 3 -M 0) >> {log}"

rule concat_files:
    output:
        "{dir}/barcodes.clstr"
    input:
        expand("{{dir}}/unique_bc/{sample}.clustered.clstr", sample=indexes)
    shell:
        "cat {input} >> {output}"
