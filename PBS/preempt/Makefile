CXX := mpicxx
CC  := mpicc
FC  := mpif90
F77 := mpif77

all: cdemo fdemo demo_mpi minimal_mpi

cdemo : main.o my_sig_handler.o
	$(CC) -o $@ $^ $(CFLAGS) $(LDFLAGS)

fdemo: fmain.o my_sig_handler.o
	$(FC) -o $@ $^ $(FFLAGS) $(LDFLAGS)

my_sig_handler_mpi.o: my_sig_handler.c my_sig_handler.h
	$(CC) -c -o $@ $< -DHAVE_MPI $(CFLAGS) $(LDFLAGS)

main_mpi.o: main_mpi.cpp my_sig_handler.h
	$(CXX) -c -o $@ $< -DHAVE_MPI $(CXXFLAGS) $(LDFLAGS)

demo_mpi: main_mpi.o my_sig_handler_mpi.o
	$(CXX) -o $@ $^ $(CXXFLAGS) $(LDFLAGS)

minimal_mpi.o: minimal_mpi.cpp
	$(CXX) -c -o $@ $< -DHAVE_MPI $(CXXFLAGS) $(LDFLAGS)

minimal_mpi: minimal_mpi.o
	$(CXX) -o $@ $^ $(CXXFLAGS) $(LDFLAGS)

clean:
	rm -f cdemo fdemo demo_mpi minimal_mpi *.o *~

clobber:
	$(MAKE) clean
	rm -f hello_preempt.o* TAGS

run: preempt_gust.sh
	qsub preempt_gust.sh

run_mpi: preempt_gust_mpi.sh
	qsub preempt_gust_mpi.sh
runmany:
	for cnt in $$(seq 1 20); do qsub preempt_gust_mpi.sh ; sleep 1s; done

qdelall:
	qdel $$(qstat -u $${USER} | grep gusched | cut -d'.' -f1)
