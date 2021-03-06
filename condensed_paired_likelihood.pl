use List::Util qw(shuffle);
use Getopt::Long;

my($cond_graph) = "";
my($comp_sets) = "";
my($paths_file) = "";
my($truefile) = "";
my($iter) = 100000; 
my($mode) = '';  
my($back) = ''; #backward elimination mode
my($kmer_size) = 60; 
GetOptions( "condgraph=s" => \$cond_graph,
	    "compset=s" => \$comp_sets,
	    "pathsfile:s" => \$paths_file,
	    "trueset:s" => \$truefile,
	     "iter:i" => \$iter,
	     "kmer:i" => \$kmer_size,
	    "random" => \$mode, "back" => \$back)  
	or die("Error in input data \n");

load_condensed_graph($cond_graph);
$count = load_paired_compatibles($comp_sets);

pair_complement_nodes();
retain_paired_paths() if $paths_file ne "";
#
load_all_paths() if $paths_file ne "";  # modified to load only forwad and reverse pairs 

$wrfile = $truefile;

likelihood_trueset() if $truefile ne "";
%set_paths = ();
print_compatible_set();
#print "$count loaded ".scalar(keys %cond_graphout)." nodes loaded ".scalar(keys %compatible_set)." compatible set loaded \n";
if($mode)
{	
	$wrfile =~ s/trueset/like_rand.txt/;
	open(wr,">$wrfile"); 
	likelihood_subset_random(14,$iter); 
}elsif($back)
{
	print "Estimating backward elimination \n";
#	print "number of possible haplotypes is ".scalar(keys %allpaths)."\n";
#	my(@start_set) = keys %allpaths;
#	print "Likelihood all ".likelihood_current_set(@start_set)."\n";
	likelihood_subset_backward_elimination();
}else
{
	$wrfile =~ s/trueset/like_replace.txt/;
	open(wr,">$wrfile"); 
	likelihood_subset(14,$iter)
}

print  "True likelihood $trueset_like\n";
sub likelihood_subset_backward_elimination
{
	# Start with the set of all possible haplotypes and subsequently remove a haplotype and compute the likelihood in two cases.. , remove the one that has the highest possible change in likelihood
	my(@start_set) = keys %allpaths ;
	$remove_haps = backward_elimination_fixed_size(@start_set);
	$old_like = $temp_like;
	while($temp_like != -9**9**9) 
	{
		$old_like = $temp_like;
		#$temp = splice(@start_set,$remove_haps,1);
		@start_set = grep { $_ != $remove_haps} @start_set;
		@start_set = grep { $_ != $path_pair{$remove_haps} } @start_set;  # Remove haplotypes in pairs of forward and reverse 
		print scalar(@start_set)." $temp_like $remove_haps $path_pair{$remove_haps}\n";
		$remove_haps = backward_elimination_fixed_size(@start_set);
	}
#	print "printing start set \n";
	foreach (sort @start_set) { print "$_ "; } print "\n";
	#print_haplotypes_final(@start_set);
	foreach (sort @trueset) { print "$_ "; } print "\n";
#	print "$current_like with ".$#current_haps_." haplotypes and $temp_like with best minus one. Removed one is $current_haps_[$imp_var] \n";
}
sub backward_elimination_fixed_size
{
	my(@current_haps_) = @_;
	my($current_like ) = likelihood_current_set(@current_haps_);
	#print "$#current_haps_\n";
	print $current_like."\n";
	my($new_like) = 0; my(@set_reduced) = @current_haps_; $temp_like  = -9**9**9;
	my($imp_var) = -10;
	my($num_haps_temp) = scalar(@current_haps_);
	my(%temp_set_reduced) = map{ $_ => 0} @current_haps_;
	for $k(keys %temp_set_reduced) 
	{
		# Remove an haplotype from the current set and compute likelihood of the remaining set 
		if($temp_set_reduced{$k} == 0) 
		{
			@set_reduced = grep {$_ != $k} @current_haps_;
			@set_reduced = grep {$_ != $path_pair{$k} } @set_reduced; 
			$temp_set_reduced{$k} = 1;
			$temp_set_reduced{$path_pair{$k}} = 1;
			$new_like = likelihood_current_set(@set_reduced);
#			if ($new_like !=0 && scalar(@set_reduced) <=26) {
#				foreach (@set_reduced) { print "$_ "; }
#				print "$new_like\n"; 
#			}	
			if($new_like != 0 && $new_like > $temp_like ) { 
				$temp_like = $new_like; $imp_var = $k; 
			}
		}
	}
	#print scalar(@set_reduced)." $temp_like $imp_var\n";
	undef(%temp_set_reduced);
	return $imp_var;
}

sub likelihood_current_set
{
	my(@temp_haps) = @_;
	undef %set_paths;
	foreach (@temp_haps) { push @{$set_paths{$_}}, @{$allpaths{$_}}; }
#	print scalar(keys %set_paths)." total paths in current set\n";
	return compute_paired_likelihood();
}
sub likelihood_subset_random
{
	#compute likelihood of a subset of all the paths
	#which contains all the compatible sets , but is not exactly the same as true set 
	my($haps_total) = $_[0];
	my($iter) = $_[1];
	my(@all_haps_) = keys %allpaths;
	#create $iter subsets of all_haps_ which contain $haps_total haplotypes and compute its likelihood
	%ground_truth = map{ $_ =>1} @trueset ; 
	$start = time;
	for( my($i) = 0 ; $i < $iter;  $i++)
	{
		undef %set_paths;
		#print "Added $hap1 $hap2 Removed $rem1 $rem2\n";
		@shuffled_indices = shuffle(0..$#all_haps_);
		@pick_indices = @shuffled_indices[1 ..$haps_total];
		@current_set = @all_haps_[@pick_indices];
		for(my($j)=0;$j<scalar(@current_set); $j++)
		{
			push @{$set_paths{$j}}, @{$allpaths{$current_set[$j]}};
		}
		my($like) =compute_paired_likelihood(); 
		if ($like != 0 ) {  
			print wr "Iter $i $like ";
			foreach (@current_set) { print wr "$_ "; }
			if($like > $trueset_like ) { print wr  "greator "; }
			print wr "\n";	
		}
		if($i % 10000 ==0 ) { $dur = time-$start ; print "$i done in $dur seconds \n"; } 
	} 	
}
sub likelihood_subset
{
	#compute likelihood of a subset of all the paths
	#which contains all the compatible sets , but is not exactly the same as true set 
	my($haps_total) = $_[0];
	my($iter) = $_[1];
	my(@all_haps_) = keys %allpaths;
	#create $iter subsets of all_haps_ which contain $haps_total haplotypes and compute its likelihood
	%ground_truth = map{ $_ =>1} @trueset ; 
	$start = time;
	for( my($i) = 0 ; $i < $iter;  $i++)
	{
		undef %set_paths;
		my($hap1 ) = $all_haps_[rand @all_haps_]; my($hap1c) = $path_pair{$hap1};
		my($hap2 ) = $all_haps_[rand @all_haps_]; my($hap2c) = $path_pair{$hap2};
		while(	exists($ground_truth{$hap1}) || exists($ground_truth{$hap2}) || $hap1 ==$hap2)
		{
			$hap1  = $all_haps_[rand @all_haps_]; $hap1c = $path_pair{$hap1}; 
			$hap2  = $all_haps_[rand @all_haps_]; $hap2c = $path_pair{$hap2}; 
		}
			
		my($rem1) = $trueset[rand @trueset]; my($rem1c) = $path_pair{$rem1};
		my($rem2) = $trueset[rand @trueset]; my($rem2c) = $path_pair{$rem2};
		while($rem2 == $rem1) 
		{
			$rem2 = $trueset[rand @trueset]; $rem2c = $path_pair{$rem2};
		}
		#print "Added $hap1 $hap2 Removed $rem1 $rem2\n";
		for(my($j)=0;$j<scalar(@trueset); $j++)
		{
			if($trueset[$j]==$rem1 )
			{
				push @{$set_paths{$j}}, @{$allpaths{$hap1}};
			}elsif($trueset[$j]==$rem2 )
			{
				push @{$set_paths{$j}}, @{$allpaths{$hap2}};
			}elsif($trueset[$j]==$rem1c )
			{
				push @{$set_paths{$j}}, @{$allpaths{$hap1c}};
			}elsif($trueset[$j]==$rem2c )
			{
				push @{$set_paths{$j}}, @{$allpaths{$hap2c}};
			}else
			{
				push @{$set_paths{$j}}, @{$allpaths{$trueset[$j]}};
			}
		}
		my($like) =compute_paired_likelihood(); 
		if ($like != 0 ) {
			foreach (keys %set_paths) { print "$_ "; } 
			print "$like \n";
		}
		if($i % 10000 ==0 ) { $dur = time-$start ; print "$i done in $dur seconds \n"; } 
	} 	
}
sub likelihood_trueset 
{
	open(tmp,$truefile);
	$l=<tmp>; chomp($l);
	@trueset = split(/,/,$l);   #Dataset 50

	for (my($i)=0; $i<scalar(@trueset) ; $i++ ) 
	{	
		push @{$set_paths{$i}}, @{$allpaths{$trueset[$i]}};
	}
	
	$trueset_like = compute_paired_likelihood();
	
}

sub load_all_paths
{
	%allpaths = ();
	open(file,$paths_file);
	while($l=<file>)
	{
		chomp($l);
		@arr = split(/ /,$l);
		$l = <file>;
		chomp($l);
		($pathno,$t,$length) = split(/_/,substr($l,1));
		if(exists($path_pair{$pathno})) {
			for(my($i)=0;$i<scalar(@arr);$i=$i+2){ 
				my($n,$node) = split(/:/,$arr[$i]);
				push @{$allpaths{$pathno}}, $node;
			}
		}
	}
	close file;
	print "Number of paired paths is ".scalar(keys %allpaths)."\n";
#	for $k1 (keys %allpaths)
#	{
#		print "Path $k1: ";
#		foreach $v(@{$allpaths{$k1 }}) {
#			print "$v ";
#		}
#		print "\n";
#	}
}

sub load_paired_feature_select
{
	# Load only those paired k-mers that span across two bubbles, as the rest of them are uuninformative in regards to resolving the bubbles 
	# Use the depth of the paired k-mers to inform which sets of paired k-mers will be informative 
	# Traverse the nodes that form a bubble, and fill up their compatible sets by traversing other nodes that are within
	# insert size distance 
	#
	# FIRST: obtain a list of nodes that form bubbles
	# Assuming the following variables are already defined: %depth, %cond_graphout %cond_graphin, %cond_ver_suffix
	# %cond_ver_prefix, %cond_ver
	my(%nodes_bubbles) = ();
	for $k1( sort {$depth{$a}<=>$depth{$b}} keys %cond_ver_suffix )
	{
		if( scalar(keys %{$cond_graphout{ $cond_ver_suffix{$k1} } } ) > 1) 
		{
			foreach $k2 ( keys %{$cond_graphout{ $cond_ver_suffix{$k1} } } ) 
			{
				$nodes_bubbles{$k2} = 1;
			}
		}
	}
	# SECOND: Add sink and source nodes also to the bubble set
	foreach (@cond_source_nodes) { $nodes_bubbles{$_} = 1; }
	foreach (@cond_sink_nodes)   { $nodes_bubbles{$_} = 1; }
	# THIRD: Find pairs in the paired-kmers set, where both of the k-mers are present in one of the bubbles
	%selective_pairs = ();
	my ($sel_no) = 0;
	for $n1( keys %paired_kmers ) 
	{	
		for $n2( keys %{$paired_kmers{$n1}} ) 
		{
			if (exists($nodes_bubbles{$vertex{$n1}}) && exists($nodes_bubbles{$vertex{$n2}} ) ) 
			{
				$selective_pairs{$n1}{$n2} = $paired_kmers{$n1}{$n2};	
				$sel_no ++;
			}
		}
	}
	return $sel_no++;
}

sub load_condensed_graph
{
	my($cond_graph) = $_[0]; # Condensed graph file
	open(file,$cond_graph);
	%cond_ver = ();
	%cond_graphout = ();
	while($l=<file>)
	{
		chomp($l);
		($v1, $v2) = split(/ /,$l);
		if( $v2 =~ /^[A,G,C,T]+$/) 
		{
			$cond_ver{$v1} = $v2;
			$length_ver{$v1} = length($v2);
		}else
		{
			$cond_graphout{$v1}{$v2}=1;
		}
	}
	close file;
}

sub load_paired_compatibles
{
	# Load the node pairs that are mapped in the compatiblle sets ... 
	# The file contains the following information.
	# x1:Depth of x1 compatiblevertex:Depth:SupportCount
	my($pairedfile) = $_[0];
	open(paired_compatible_file,"$pairedfile");
	%compatible_set = ();
	%length_diff = ();
	$total_count = 0;
	while($l=<paired_compatible_file>)
	{
		chomp($l);
		@arr = split(/ /,$l);
		($v1,$v1_depth) = split(/:/,$arr[0]);
		for(my($i)=1;$i<scalar(@arr); $i++) 
		{
			($v2,$v2_depth,$count) = split(/:/,$arr[$i]);
			
			if ($v2 ne $v1) 
			{
				$total_count +=$count;
				$compatible_set{$v1}{$v2} = $count;
				$length_diff{$v1}{$v2} = $v2_depth - $v1_depth + $length_ver{$v2} ;
			}
		}
	}
	close paired_compatible_file;
	return $total_count;
}
sub print_condensed_graph
{	
	for $n1(keys %cond_graphout) 
	{
		for $n2(keys %{$cond_graphout{$n1}}) 
		{
			print "$n1 $n2 $length_ver{$n1} $length{$n2}\n";
		}		
	}
}
sub print_compatible_set
{	
	my(%visit_fwd_rev) = ();
	for $k1 ( keys %compatible_set) 
	{
		for $k2( keys %{$compatible_set{$k1}} ) 
		{
			$visit_fwd_rev{$k1}{$k2} = 0;
		}
	}
	for $n1(keys %compatible_set) 
	{
		for $n2(keys %{$compatible_set{$n1}}) 
		{
			if($visit_fwd_rev{$n1}{$n2} ==0) {
				print "$n1 $n2 $compatible_set{$n1}{$n2} $length_diff{$n1}{$n2} $paired_nodes{$n2} $paired_nodes{$n1} $compatible_set{$paired_nodes{$n2}}{$paired_nodes{$n1}} $length_diff{$paired_nodes{$n2}}{$paired_nodes{$n1}}\n";
				$visit_fwd_rev{$n1}{$n2} = 1;
				$visit_fwd_rev{$paired_nodes{$n2}}{$paired_nodes{$n1}} = 1;
			}
		}
	}
	undef %visit_fwd_rev;
}
sub compute_paired_likelihood
{
	# Compute the likelihood of a set of paths based on the paired k-mers that support it 
	# Need to know d_ijk, 
	# Break the node paths into compatible sets 
	# See if some compatible sets are shared across two or more haplotypes 
	# %set_paths contains the set of haplotypes for which likelihood is to be computed... 
	%d_hashtable = ();
	$num_haps = scalar(keys %set_paths);
	$genome_length = 1200;
#	print "Number of haplotypes is $num_haps \n";
#	print "Computing d-hasttable \n";
	compute_d_hashtable();
#	print "D hash table done,Starting on likelihood \n";
	$like = compute_set_likelihood_using_d();
#	print "Likelihood of set $like \n";
	return $like;
}

sub compute_set_likelihood_using_d
{
	#print "In compute set \n";
	my($llik) = 0; my($min) = 0; my($max) = -9**9**9; 
	$Scale = $num_haps*$genome_length;
	# Make sure that one -forward and reverse node pair is only visited once. 
	my(%visit_fwd_rev) = ();
	for $k1 ( keys %compatible_set) 
	{
		for $k2( keys %{$compatible_set{$k1}} ) 
		{
			$visit_fwd_rev{$k1}{$k2} = 0;
		}
	}
	for $k1( keys %compatible_set ) 
	{
		for $k2(keys %{$compatible_set{$k1}}) 
		{
			if(exists($d_hashtable{$k1}{$k2}) )
			{
				if($visit_fwd_rev{$k1}{$k2}==0) {
					#print "Processing $k1 $k2  \n";
					$temp0 = $d_hashtable{$k1}{$k2}/($Scale-$length_diff{$k1}{$k2});
					#if($temp0 == 0 ) { print "$k1 $k2 $d_hashtable{$k1}{$k2} \n"; }
					$temp1 = $total_count - $compatible_set{$k1}{$k2};
					$temp2 = 1 - ($d_hashtable{$k1}{$k2}/($Scale-$length_diff{$k1}{$k2}));
					#if($temp2 == 0 ) { print "$k1 $k2 $d_hashtable{$k1}{$k2} \n"; }
					$val = $temp1*log($temp2) + $compatible_set{$k1}{$k2} * log($temp0);
		#			if($val > $max ) { $max = $val; } 
		#			if($val < $min ) { $min = $val; $t1 = $k1; $t2 = $k2;}
					$llik += $val;
					$visit_fwd_rev{$k1}{$k2} = 1;
					$visit_fwd_rev{$paired_nodes{$k2}}{$paired_nodes{$k1}} = 1;
				}
			}else 
			{
				#compatible set contains a haplotype which is not supported by the set of haplotypes given, reject the set of haplotypes 	
				#print "Set of haplotypes not compatible based on data $k1 $k2 $compatible_set{$k1}{$k2} \n";
				return $min;
			}
		}
	}
	#print "Max $max and Min $min $t1 $t2 $compatible_set{$t1}{$t2}\n";
	#print "Likelihood is $llik \n";
	return $llik;
}
sub compute_d_hashtable
{
	for $n1( keys %set_paths ) 
	{
		#pick a path in the haplotype set
		my(@one_path) = @{$set_paths{$n1}};
		#print "Operating on $n1 ".scalar(@one_path)." nodes in it \n";
		my(%temp_set) = ();
		for $k(@one_path) 
		{	
			$temp_set{$k} = 1;
		}
		for (my($i)=0;$i<scalar(@one_path);$i++)
		{
			for $k(keys %{$compatible_set{$one_path[$i]}})
			{
				if(exists($temp_set{$k})) 
				{
					$d_hashtable{$one_path[$i]}{$k}++;
				}
			}
		}
	}
}

sub pair_complement_nodes
{
	# take all the nodes and compute their reverse complements, and a paired hash table be created. 
	my(%temp_hash) = ();
	my(%inverse_hash) = ();
	for $k( keys %cond_ver) {
		$temp_hash{$k} = 0;
		$inverse_hash{$cond_ver{$k}} = $k;
	} 
	#Link nodes which are reverse complements of each other. 
	for $k(keys %cond_ver)
	{
		if($temp_hash{$k}==0) {
			my($temp) = revcomplement($cond_ver{$k});
			$paired_nodes{$k} = $inverse_hash{$temp};
			$paired_nodes{$inverse_hash{$temp}} = $k ; 
			$temp_hash{$k} = 1; 
			$temp_hash{$inverse_hash{$temp}} = 1;
		}
	}
	undef %inverse_hash;
	undef %temp_hash;
}

sub retain_paired_paths
{
	%allpaths = ();
	open(file,$paths_file);
	while($l=<file>)
	{
		chomp($l);
		@arr = split(/ /,$l);
		$l = <file>;
		chomp($l);
		($pathno,$t,$length) = split(/_/,substr($l,1));
		my($str) = ""; my($rev_str) = "";
		for(my($i)=0;$i<scalar(@arr);$i=$i+2){ 
			my($n,$node) = split(/:/,$arr[$i]);
	#		push @{$allpaths{$pathno}}, $node;
			$str = $str."_".$node;
			$rev_str = $paired_nodes{$node}."_".$rev_str;
		}
		$str = substr($str,1);
		$rev_str = substr($rev_str,0,-1);
#		print "$str $rev_str\n";
		if(exists($allpaths{$rev_str})) { 
			$path_pair{$pathno} = $allpaths{$rev_str}; 
			$path_pair{$allpaths{$rev_str}} = $pathno;
			delete $allpaths{$rev_str};
		}else{
			$allpaths{$str} = $pathno;
		}
	}
	close file;
#	for $k1 (sort {$a<=>$b} keys %path_pair)
#	{
#		print "$k1 $path_pair{$k1}\n";
#	}
	undef %allpaths;
}
sub revcomplement
{
	my($str) = $_[0];
	$str = scalar reverse $str;
	$rev_str="";
	for (my($i)=0;$i<length($str);$i++) {
		if(substr($str,$i,1) eq "A") {$rev_str = $rev_str."T";} 
		elsif(substr($str,$i,1) eq "T") {$rev_str = $rev_str."A";}
		elsif(substr($str,$i,1) eq "C") {$rev_str = $rev_str."G";}
		else {$rev_str = $rev_str."C";}
	}
	return $rev_str;
}

sub print_haplotypes_final
{
	#print the haplotypes present in the subset finally chosen or at any point 
	my(@hap_set) = @_;
	my($K) = $kmer_size;
	foreach $k (@hap_set) {
		my(@nodes) = @{$allpaths{$k}};
		my($str) = $cond_ver{$nodes[0]};
		foreach (my($i)=1;$i<=$#nodes;$i++) 
		{
			$str = $str.substr($cond_ver{$nodes[$i]},$K-1);
		}
		print ">$k\n$str\n";
	}
}
