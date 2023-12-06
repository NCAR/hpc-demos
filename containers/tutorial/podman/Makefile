my_alpine.stamp: Dockerfile.my_alpine extras/ Makefile
	rm -f $@
	module load podman ; \
	podman build --tag my_alpine:latest --file $< . ; \
	date > $@

extras/: ../apptainer/extras/
	rm -rf $@
	cp -r $< $@

results/%.out: % my_alpine.stamp Makefile
	mkdir -p results
	rm -f $@
	./$< 2>&1 | grep -v "\+ set " > $@.tmp
	sed -i 's/+ /host\$$ /g' $@.tmp
	sed -i 's/--log-level error //g' $@.tmp
	mv $@{.tmp,}
	cat $@
