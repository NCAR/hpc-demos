#include <iostream>
#include <iomanip>
#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <mpi.h>
#include "my_sig_handler.h"



namespace {
  int numranks, rank;
  char hn[256];
}



void do_checkpoint (MPI_Comm comm)
{
  for (int i=1; i<=10; i++)
    {
      if (0 == rank)
        {
          printf("\t%2d : Inside checkpoint function\n",i);
          fflush(stdout);
          sleep(5);
        }
      MPI_Barrier(comm);
    }
  done_checkpoint();
  return;
}



int main (int argc, char **argv)
{
  gethostname(hn, sizeof(hn) / sizeof(char));

  MPI_Init(&argc, &argv);

  MPI_Comm_size (MPI_COMM_WORLD, &numranks);
  MPI_Comm_rank (MPI_COMM_WORLD, &rank);

  std::cout << "Hello from " << rank << " / " << std::string (hn)
	    << ", running " << argv[0] << " on " << numranks << " ranks" << std::endl;

  // register our user-defined signal handlers, on every rank
  register_sig_handler();

  for (int i=1; i<=50 ;i++)
    {
      if (0 == rank)
        {
          printf("%2d : Inside main function\n",i);
          fflush(stdout);
          sleep(5);
        }
      MPI_Barrier(MPI_COMM_WORLD);

      // this function needs to perform a reduction to see if any rank received
      // a signal, hence it is blocking.
      if (mpi_checkpoint_requested(MPI_COMM_WORLD))
        do_checkpoint(MPI_COMM_WORLD);
    }

  MPI_Finalize();
  return 0;
}
