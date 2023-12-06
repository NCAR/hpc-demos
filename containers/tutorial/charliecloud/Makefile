my_alpine.sqfs: Dockerfile.my_alpine extras/
	module load charliecloud ; \
	ch-image build --force fakeroot --tag my_alpine:latest -f $< . ; \
	ch-convert my_alpine:latest $@

extras/: ../apptainer/extras/
	rm -rf $@
	cp -r $< $@

results/%.out: % my_alpine.sqfs Makefile
	mkdir -p results
	rm -f $@
	./$< 2>&1 | grep -v "\+ set " > $@.tmp
	sed -i 's/+ /host\$$ /g' $@.tmp
	mv $@{.tmp,}
	cat $@
