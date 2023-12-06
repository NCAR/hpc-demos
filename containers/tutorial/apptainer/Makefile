my_alpine.sif: my_alpine.def extras/
	module load apptainer ; \
	TMPDIR=/var/tmp singularity build $@ $<

results/%.out: % my_alpine.sif Makefile
	mkdir -p results
	rm -f $@
	./$< 2>&1 | grep -v "\+ set " > $@.tmp
	sed -i 's/+ /host\$$ /g' $@.tmp
	sed -i 's/--quiet //g' $@.tmp
	mv $@{.tmp,}
	cat $@
