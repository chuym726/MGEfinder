
import os
from os.path import basename, join

WD = config['wd']

GENOME_DIR= join(WD, config['genome_dir'])
BAM_DIR = join(WD, config['bam_dir'])
MUSTACHE_DIR = join(WD, config['mgefinder_dir'])
DATABASE_DIR = join(WD, config['database_dir'])
RESULTS_DIR = join(WD, config['results_dir'])

WC_genomes = glob_wildcards(join(GENOME_DIR, '{genome}.fna'))
WC_bam_samples = glob_wildcards(join(BAM_DIR, "{sample}.{genome}.bam"))


GENOMES = set(WC_genomes.genome)
SAMPLES = set(WC_bam_samples.sample)

rule all:
    input:
        expand(join(RESULTS_DIR, '{genome}/04.makefasta.{genome}.all_seqs.fna'), genome=GENOMES)
    run:
        pass


rule index_genome_bowtie2:
    log: join(GENOME_DIR, "log/{genome}.index_bowtie2.log")
    benchmark: join(GENOME_DIR, "log/{genome}.index_bowtie2.benchmark.txt")
    input:
        join(GENOME_DIR, "{genome}.fna")
    output:
        one=join(GENOME_DIR, "{genome}.fna.1.bt2"),
        two=join(GENOME_DIR, "{genome}.fna.2.bt2"),
        three=join(GENOME_DIR, "{genome}.fna.3.bt2"),
        four=join(GENOME_DIR, "{genome}.fna.4.bt2"),
        revone=join(GENOME_DIR, "{genome}.fna.rev.1.bt2"),
        revtwo=join(GENOME_DIR, "{genome}.fna.rev.2.bt2")
    shell:
        """
        bowtie2-build {input} {input} 1> {log} 2> {log}.err || \
        (cat {log}.err; exit 1)
        """

rule index_database_bowtie2:
    log: join(DATABASE_DIR, "log/database.index_bowtie2.log")
    benchmark: join(DATABASE_DIR, "log/database.index_bowtie2.benchmark.txt")
    input:
        join(DATABASE_DIR, "database.fna")
    output:
        one=join(DATABASE_DIR, "database.fna.1.bt2"),
        two=join(DATABASE_DIR, "database.fna.2.bt2"),
        three=join(DATABASE_DIR, "database.fna.3.bt2"),
        four=join(DATABASE_DIR, "database.fna.4.bt2"),
        revone=join(DATABASE_DIR, "database.fna.rev.1.bt2"),
        revtwo=join(DATABASE_DIR, "database.fna.rev.2.bt2")
    shell:
        """
        bowtie2-build {input} {input} 1> {log} 2> {log}.err || \
        (cat {log}.err; exit 1)
        """

rule find:
    log: join(MUSTACHE_DIR, "{genome}/{sample}/log/{sample}.{genome}.find.log")
    benchmark: join(MUSTACHE_DIR, "{genome}/{sample}/log/{sample}.{genome}.find.benchmark.txt")
    input:
        bam=join(BAM_DIR, "{sample}.{genome}.bam"),
    output:
        find=join(MUSTACHE_DIR, '{genome}/{sample}/01.find.{sample}.{genome}.tsv')
    params:
        sample='{sample}',
        minlen=config['find']['minlen'],
        mincount=config['find']['mincount'],
        minq=config['find']['minq'],
        minial=config['find']['minial'],
        mindist=config['find']['mindist'],
        minratio=config['find']['minratio'],
        maxir=config['find']['maxir'],
        lins=config['find']['lins'],
        mcc=config['find']['mcc'],
        check_bwa=config['find']['check_bwa_flag']
    shell:
        """
        mgefinder find -id {params.sample} -minlen {params.minlen} -mincount {params.mincount} -minq {params.minq} \
        -minial {params.minial} -mindist {params.mindist} -minratio {params.minratio} -maxir {params.maxir} -lins \
        {params.lins} -mcc {params.mcc} {params.check_bwa} {input.bam} -o {output.find} 1> {log} 2> {log}.err || \
        (cat {log}.err; exit 1)
        """

rule pair:
    log: join(MUSTACHE_DIR, "{genome}/{sample}/log/{sample}.{genome}.pair.log")
    benchmark: join(MUSTACHE_DIR, "{genome}/{sample}/log/{sample}.{genome}.pair.benchmark.txt")
    input:
        find=ancient(join(MUSTACHE_DIR, '{genome}/{sample}/01.find.{sample}.{genome}.tsv')),
        bam=join(BAM_DIR, "{sample}.{genome}.bam"),
        genome=join(GENOME_DIR, "{genome}.fna")
    output:
        pair=join(MUSTACHE_DIR, '{genome}/{sample}/02.pair.{sample}.{genome}.tsv')
    params:
        maxdr=config['pair']['maxdr'],
        minq=config['pair']['minq'],
        minial=config['pair']['minial'],
        maxjsp=config['pair']['maxjsp'],
        lins=config['pair']['lins']
    shell:
        """
        mgefinder pair -maxdr {params.maxdr} -minq {params.minq} -minial {params.minial} -maxjsp {params.maxjsp} \
        -lins {params.lins} {input.find} {input.bam} {input.genome} -o {output.pair} 1> {log} 2> {log}.err || \
        (cat {log}.err; exit 1)
        """

rule inferseq_database:
    log: join(MUSTACHE_DIR, "{genome}/{sample}/log/{sample}.{genome}.inferseq_database.log")
    benchmark: join(MUSTACHE_DIR, "{genome}/{sample}/log/{sample}.{genome}.inferseq_database.benchmark.txt")
    input:
        pair=join(MUSTACHE_DIR, '{genome}/{sample}/02.pair.{sample}.{genome}.tsv'),
        database=join(DATABASE_DIR, 'database.fna'),
        one=join(DATABASE_DIR, 'database.fna.1.bt2')
    output:
        outfile=join(MUSTACHE_DIR, '{genome}/{sample}/03.inferseq_database.{sample}.{genome}.tsv')
    params:
        minident=config['inferseq_database']['minident'],
        maxclip=config['inferseq_database']['maxclip'],
        maxedgedist=config['inferseq_database']['maxedgedist']
    shell:
        """
        mgefinder inferseq-database -minident {params.minident} -maxclip {params.maxclip} -maxedgedist \
        {params.maxedgedist} {input.pair} {input.database} -o {output.outfile} 1> {log} 2> {log}.err
        """


rule make_inferseq_file_path_list:
    input:
        expand(join(MUSTACHE_DIR, '{{genome}}/{sample}/03.inferseq_database.{sample}.{{genome}}.tsv'), sample=SAMPLES)
    output:
        outfile=join(MUSTACHE_DIR, '{genome}/{genome}.all_inferseq.txt')
    run:
        with open(output.outfile, 'w') as outfile:
            for f in input:
                outfile.write(f+'\n')


rule clusterseq:
    input:
        join(MUSTACHE_DIR, '{genome}/{genome}.all_inferseq.txt')
    output:
        clusterseq=join(RESULTS_DIR, '{genome}/01.clusterseq.{genome}.tsv')
    threads:
        16
    params:
        memory=config['memory'],
        prefix='{genome}.database',
        minsize=config['clusterseq']['minsize'],
        maxsize=config['clusterseq']['maxsize'],
    shell:
        """
        mgefinder clusterseq -minsize {params.minsize} -maxsize {params.maxsize} --threads {threads} \
        --memory {params.memory} {input} -o {output}
        """


rule make_pair_file_path_list:
    input:
        expand(join(MUSTACHE_DIR, '{{genome}}/{sample}/02.pair.{sample}.{{genome}}.tsv'), sample=SAMPLES)
    output:
        outfile=join(MUSTACHE_DIR, '{genome}/{genome}.all_pair.txt')
    run:
        with open(output.outfile, 'w') as outfile:
            for f in input:
                outfile.write(f+'\n')


rule genotype:
    log: join(RESULTS_DIR, "{genome}/log/{genome}.genotype.log")
    benchmark: join(RESULTS_DIR, "{genome}/log/{genome}.genotype.benchmark.txt")
    input:
        join(RESULTS_DIR, '{genome}/01.clusterseq.{genome}.tsv'),
        outfile=join(MUSTACHE_DIR, '{genome}/{genome}.all_pair.txt')
    output:
        genotype=join(RESULTS_DIR, '{genome}/02.genotype.{genome}.tsv')
    params:
        filter_clusters=config['genotype']['filter_clusters']
    shell:
        """
        if [ "{params.filter_clusters}" == "True" ]; then
            mgefinder genotype --filter-clusters-inferred-assembly {input} -o {output} 1> {log} 2> {log}.err || \
            (cat {log}.err; exit 1)
        else
            mgefinder genotype --no-filter-clusters-inferred-assembly {input} -o {output} 1> {log} 2> {log}.err || \
            (cat {log}.err; exit 1)
        fi
        """

rule summarize:
    log: join(RESULTS_DIR, "{genome}/log/{genome}.summarize.log")
    benchmark: join(RESULTS_DIR, "{genome}/log/{genome}.summarize.benchmark.txt")
    input:
        join(RESULTS_DIR, '{genome}/01.clusterseq.{genome}.tsv'),
        join(RESULTS_DIR, '{genome}/02.genotype.{genome}.tsv')
    output:
        outfile1=join(RESULTS_DIR, '{genome}/03.summarize.{genome}.clusters.tsv'),
        outfile2=join(RESULTS_DIR, '{genome}/03.summarize.{genome}.groups.tsv')
    params:
        prefix=join(RESULTS_DIR, '{genome}/03.summarize.{genome}')
    shell:
        """
        mgefinder summarize {input} -o {params.prefix} 1> {log} 2> {log}.err || \
        (cat {log}.err; exit 1)
        """


rule makefasta:
    log: join(RESULTS_DIR, "{genome}/log/{genome}.makefasta.log")
    benchmark: join(RESULTS_DIR, "{genome}/log/{genome}.makefasta.benchmark.txt")
    input:
        join(RESULTS_DIR, '{genome}/01.clusterseq.{genome}.tsv'),
        join(RESULTS_DIR, '{genome}/03.summarize.{genome}.clusters.tsv')
    output:
        outfile1=join(RESULTS_DIR, '{genome}/04.makefasta.{genome}.all_seqs.fna'),
        outfile2=join(RESULTS_DIR, '{genome}/04.makefasta.{genome}.repr_seqs.fna')
    params:
        prefix=join(RESULTS_DIR, '{genome}/04.makefasta.{genome}')
    shell:
        """
        mgefinder makefasta {input} -o {params.prefix} 1> {log} 2> {log}.err || \
        (cat {log}.err; exit 1)
        """
