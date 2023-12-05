my_alpine.stamp: Dockerfile.my_alpine extras/ Makefile
	rm -f $@
	module load podman ; \
	podman build --tag my_alpine:latest --file $< . ; \
	date > $@

extras/: ../apptainer/extras/
	rm -rf $@
	cp -r $< $@
