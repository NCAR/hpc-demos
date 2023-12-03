rocky8_openhpc_cuda_mpich-ofi.sqfs: Dockerfile.base
	ch-image build --force fakeroot --tag rocky8_openhpc_cuda_mpich-ofi -f Dockerfile.base .
	ch-image list
	ch-convert rocky8_openhpc_cuda_mpich-ofi ./tmp-$@
	rm -f $@ && mv {tmp-,}$@ && ls -ltrh $@

FastEddy.sqfs: Dockerfile.FE rocky8_openhpc_cuda_mpich-ofi.sqfs
	ch-image build --force fakeroot --tag fasteddy_rocky8_openhpc_cuda_mpich-ofi -f Dockerfile.FE .
	ch-image list
	ch-convert fasteddy_rocky8_openhpc_cuda_mpich-ofi ./tmp-$@
	rm -f $@ && mv {tmp-,}$@ && ls -ltrh $@
