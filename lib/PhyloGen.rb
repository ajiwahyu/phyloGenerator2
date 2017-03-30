#Building very large phylogenies from already outputted sequences
# - PhyloGen smashes, he doesn't think (yet)
require "bio"
require "set"

class PhyloGen
  @@n_phylogen = 0
  @@n_runs = 0
  def initialize(method="raxml", partition=false, model_params="", logger)
    @this_phylogen = @@n_phylogen
    @@n_phylogen = @@n_phylogen + 1
    @model_params = model_params
    @phy_string = ""; @parse_string = ""
    @partition = partition
    @partition_file = []
    @method = method
    @logger = logger
  end

  def build(species, genes, constraint=false)
    @spp_lookup = Hash[species.zip(('a'..'z').to_a.repeated_combination(5).map(&:join)[0..species.length]).map{|x,y| [x,y]}]
    File.open("phylo_species_lookup_#{@this_phylogen}.txt", "w") do |handle|
      handle << "code_name\torig_name\n"
      @spp_lookup.each {|orig_name, code_name| handle << "#{code_name}\t#{orig_name}\n"}
    end
    align(species, genes)
    conc_align(genes)
    if constraint then constraint.leaves.each {|x| x.name = @spp_lookup[x]} end
    result = phylo_generate(constraint)
  end
  
  #Internal methods
  private
  def align(species, genes)
    @logger.info("PhyloGen_#{@this_phylogen}") {"Beginning alignment"}
    cr_len = 0
    ids = Set.new
    genes.each do |gene|
      File.open("phylo_#{@this_phylogen}_#{gene}.fasta", "w") do |file|
        species.each do |sp|
          if File.exists? "#{sp}_#{gene}.fasta"
            seq = Bio::FastaFormat.open("#{sp}_#{gene}.fasta", "r").first
            if ids.include? seq.definition
              puts "Warning: duplicated sequences - #{sp}_#{gene}.fasta"
              @logger.warn("PhyloGen_#{@this_phylogen}") {"Warning: duplicated sequences - #{sp}_#{gene}.fasta"}
            end
            ids.add seq.definition
            file << seq.to_biosequence.output_fasta("#{sp}_#{gene}")
          else
            file << ">#{sp}_#{gene}\n"
          end
        end
      end
      `mafft --quiet phylo_#{@this_phylogen}_#{gene}.fasta > phylo_#{@this_phylogen}_#{gene}_mafft.fasta`
      if @partition
        align = Bio::Alignment.new(Bio::FastaFormat.open("phylo_#{@this_phylogen}_#{gene}_mafft.fasta")).alignment_length
        @partition_file << "DNA, #{gene}=#{cr_len+1}-#{cr_len+align}\\3,#{cr_len+2}-#{cr_len+align}\\3,#{cr_len+3}-#{cr_len+align}\\3"
        cr_len += align
      end
    end
    @logger.info("PhyloGen_#{@this_phylogen}") {"Alignment complete"}
  end
  
  private
  def conc_align(genes)
    @logger.info("PhyloGen_#{@this_phylogen}") {"Beginning concatenation"}
    seqs = {}
    genes.each do |gene|
      Bio::FastaFormat.open("phylo_#{@this_phylogen}_#{gene}_mafft.fasta").each_entry do |seq|
        seq = seq.to_biosequence
        sp = @spp_lookup[seq.definition.split("_")[0...-1].join("_")]
        if seqs.include? sp
          seqs[sp] = Bio::Sequence.new(seqs[sp] + seq)
        else
          seqs[sp] = seq
        end
      end
    end
    align = Bio::Alignment.new(seqs)
    File.open("phylo_#{@this_phylogen}.phylip", "w") {|file| file << align.output_phylip}
    @logger.info("PhyloGen_#{@this_phylogen}") {"Concatenation complete"}
  end

  private
  def phylo_generate(constraint=false)
    @logger.info("PhyloGen_#{@this_phylogen}") {"Beginning phylogeny search"}
    @@n_runs += 1
    if @partition
      File.open("phylo_#{@this_phylogen}_#{@@n_runs}.partition", "w") {|file| file << @partition_file.join("\n")}
      @parse_string << " -q phylo_#{@this_phylogen}_#{@@n_runs}.partition"
    end
    if constraint
      File.open("phylo_#{@this_phylogen}_#{@@n_runs}.constraint", "w"){|file| file << constraint.output_newick}
      @phy_string << " -g phylo_#{@this_phylogen}_#{@@n_runs}.constraint"
    end
    case @method
    when "examl"
      `Rscript -e "require(ape);t<-read.dna('phylo_#{@this_phylogen}.phylip');t<-rtree(nrow(t),tip.label=rownames(t),br=NULL);write.tree(t,'phylo_#{@this_phylogen}_#{@@n_runs}.tre')"`
      `parse-examl -s phylo_#{@this_phylogen}.phylip -n phylo_#{@this_phylogen}_#{@@n_runs}_parse -m DNA#{@parse_string}`
      `examl -s phylo_#{@this_phylogen}_#{@@n_runs}_parse.binary -p #{Random.rand(100000)} -m PSR -n phylo_#{@this_phylogen}_#{@@n_runs} -t phylo_#{@this_phylogen}_#{@@n_runs}.tre#{@phy_string} #{@model_params}`
      output_phylo = ["ExaML_result.phylo_#{@this_phylogen}_#{@@n_runs}"]
    when "exabayes"
      `yggdrasil -f phylo_#{@this_phylogen}.phylip -s #{Random.rand(100000)} -m DNA -n phylo_#{@this_phylogen}_#{@@n_runs}#{@phy_string} #{@model_params}`
    when "raxml"
      `raxml -s phylo_#{@this_phylogen}.phylip -p #{Random.rand(100000)} -m GTRGAMMA -n phylo_#{@@n_phylogen}_#{@@n_runs}#{@phy_string} #{@model_params}`
      output_phylo = ["RAxML_bestTree.phylo_#{@@n_phylogen}_#{@@n_runs}#{@phy_string}", "RAxML_parsimonyTree.phylo_#{@@n_phylogen}_#{@@n_runs}#{@phy_string}", "RAxML_result.phylo_#{@@n_phylogen}_#{@@n_runs}#{@phy_string}"]
    else
      raise RuntimeError, "PhyloGen called with unsupported method #{@method}"
    end
    @logger.info("PhyloGen_#{@this_phylogen}") {"Phylogeny search complete"}
    #Cleanup and re-name
    unless @method == "exabayes"
      begin
        output_phylo.each do |file_name|
          raw = File.read(file_name)
          @spp_lookup.each {|orig_name, code_name| raw.sub!(code_name, orig_name)}
          File.open(file_name, "w") {|x| x << raw}
        end
      rescue
        puts "Error correcting output names; check 'phylo' folder for errors"
      end    
    end
  end
end
