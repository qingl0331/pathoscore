wget -nc -r --accept "*illumina.vcf.gz*"  https://genomics.scripps.edu/browser/files/wellderly/vcf/ --no-check-certificate

if [[ ! -e gnomad.exomes.r2.0.1.sites.no-VEP.nohist.tidy.vcf.gz ]]; then
wget https://s3.amazonaws.com/gemini-annotations/gnomad.exomes.r2.0.1.sites.no-VEP.nohist.tidy.vcf.gz
fi
if [[ ! -e gnomad.exomes.r2.0.1.sites.no-VEP.nohist.tidy.vcf.gz.tbi ]]; then
wget https://s3.amazonaws.com/gemini-annotations/gnomad.exomes.r2.0.1.sites.no-VEP.nohist.tidy.vcf.gz.tbi
fi

if [[ ! -e ./vcfanno ]]; then
wget -O vcfanno https://github.com/brentp/vcfanno/releases/download/v0.2.8/vcfanno_linux64
chmod +x vcfanno
fi

wget -O gargs https://github.com/brentp/gargs/releases/download/v0.3.8/gargs_linux
chmod +x gargs

cat > conf.toml << EOL
[[annotation]]
file="gnomad.exomes.r2.0.1.sites.no-VEP.nohist.tidy.vcf.gz"
fields = ["AC"]
ops=["flag"]
names=["gnomad_ac"]
EOL

ls chr*.illumina.vcf.gz \
    | cut -d"." -f1 \
    | ./gargs -p 24 'vcfanno conf.toml <(zcat {}.illumina.vcf.gz | grep -v "^####INFO" | cut -f1-7 | bcftools view) | bcftools view -Oz -i "gnomad_ac=0" > {}.vcf.gz'

ls chr*.vcf.gz \
    | grep -v illumina \
    | ./gargs -p 24 "tabix {}"

wget -O gsort https://github.com/brentp/gsort/releases/download/v0.0.6/gsort_linux_amd64
chmod +x gsort

bcftools view -h gnomad.exomes.r2.0.1.sites.no-VEP.nohist.tidy.vcf.gz \
    | grep contig \
    | sed -e "s/##contig=<ID=//" \
    | sed -e "s/>//" \
    | sed -e "s/,length=/\t/" \
    > genome.txt

bcftools concat $( ls chr*.vcf.gz | grep -v illumina ) \
    | ./gsort /dev/stdin genome.txt \
    | bcftools view -Oz > wellderly.vcf.gz

wget ftp://ftp.ensembl.org/pub/grch37/release-84/gff3/homo_sapiens/Homo_sapiens.GRCh37.82.gff3.gz
zcat Homo_sapiens.GRCh37.82.gff3.gz | awk '$3=="CDS"' | cut -f 1,4,5 | ./gsort /dev/stdin genome.txt > exons.bed

bedtools intersect -sorted -header -a wellderly.vcf.gz -b exons.bed -g genome.txt | bcftools view -Oz > tmp.vcf.gz

fasta=/uufs/chpc.utah.edu/common/home/u6000771/bcbio/genomes/Hsapiens/GRCh37/seq/GRCh37.fa
if [[ ! -e ../Homo_sapiens.GRCh37.82.gff3.gz ]]; then
    wget ftp://ftp.ensembl.org/pub/grch37/release-84/gff3/homo_sapiens/Homo_sapiens.GRCh37.82.gff3.gz
    mv Homo_sapiens.GRCh37.82.gff3.gz ..
fi

gff=../Homo_sapiens.GRCh37.82.gff3.gz

bash ../../../scripts/bcsq.sh $gff tmp.vcf.gz $fasta \
    | python ../../score.py - \
    | bgzip -c >  wellderly.coding.benign.vcf.gz
rm tmp.vcf.gz
tabix -f wellderly.coding.benign.vcf.gz
