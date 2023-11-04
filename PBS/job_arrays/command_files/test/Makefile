

gs_openmp: gs_openmp.c
	gfortran -O2 -o $@ $< -fopenmp

gs_openmp.c: Makefile
	rm -f $@
	wget https://raw.githubusercontent.com/benkirk/paradigms_playground/master/gs_openmp.c

omp_cmdfile: Makefile
	echo "# sample cmdfile for an OpenMP application" > $@.tmp
	for i in $$(seq 1 512); do \
	  echo "./gs_openmp $$((1024*8*2)) # step $${i}" >> $@.tmp ; \
	done
	mv $@.tmp $@
