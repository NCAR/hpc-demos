my_alpine.sqfs: Dockerfile.my_alpine extras/
	module load charliecloud ; \
	ch-image build --force fakeroot --tag my_alpine:latest -f $< . ; \
	ch-convert my_alpine:latest $@

extras/: ../apptainer/extras/
	rm -rf $@
	cp -r $< $@
