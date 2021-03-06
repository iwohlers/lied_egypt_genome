# Making a comparison table of the repeatmasker results for several assemblies
# Watch out: Scaffolds that have no repeats are not listed in the inout file 
# and thus neglected in the overall computation; these should be only small
# scaffolds though (but this should be checked!)

# Getting input and output filenames
fnames_in = snakemake.input
fname_out = snakemake.output[0]

# Some columns (with plain numbers) just need to be summed up; columns with
# percentages need to be recomputed based on the scaffold/chromosome length
# These are the column indices (starting with 0) with percentages
perc_col = [3,5,7,10,13,16,19,22,25,28,31,34,37,40,43,46,49,52,55,58,61,64,67]

# Write the header
with open(fnames_in[0],"r") as f_in, open(fname_out,"w") as f_out:
    for line in f_in:
        if line[:8] == "filename":
            f_out.write(line)

# Go over the different assembly files
for filename in fnames_in:
    # Initialize
    assembly_len = 0
    sums = [0 for x in range(67)]
    nums = [0 for x in range(67)]
    # Get the overall length of the assembly (all chromosomes/scaffolds)
    with open(filename,"r") as f_in:
        for line in f_in:
            if line[:8] == "filename":
                continue
            s = line.strip("\n").split("\t")
            assembly_len += int(s[1])
    # Summarize all scoffolds / chromosomes for this assembly
    with open(filename,"r") as f_in, open(fname_out,"a") as f_out:
        for line in f_in:
            if line[:8] == "filename":
                header = line
                continue
            s = line.strip("\n").split("\t")
            nums = [float(x) for x in s[1:]]
            scaff_len = nums[0]
            # Sum the numbers of this line to the previous ones; in case of 
            # percentages, sum the previous (number) referring to the percentage 
            # We have to use i+1, because the perc_col include the filename col
            for i in range(len(sums)):
                if i+1 in perc_col:
                    # Make sure this is a percentage column
                    # 100.01 because of rounding issues (occurs once for yoruba)
                    assert(0<=float(nums[i])<=100.01)
                    sums[i] += nums[i-1]
                else:
                        sums[i] += int(nums[i])
            # Round the percentage columns
            for i in range(len(sums)):
                if i+1 in perc_col:
                    sums[i] = round(sums[i],2)
        # Compute overall percentages based on overall numbers/counts
        # Start with column 4 because 3 is the GC content which we don't want to
        # recompute
        for i in range(4,len(sums)):
            if i+1 in perc_col:
                sums[i] = round(100*sums[i]/assembly_len,2)    
        f_out.write(filename+"\t"+"\t".join([str(x) for x in sums])+"\n")