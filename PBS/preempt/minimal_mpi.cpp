#include <iostream>
#include <iomanip>
#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <mpi.h>



namespace {
  int numranks, rank;
  char hn[256];
  int checkpoint_req = 0;

  void done_checkpoint () { checkpoint_req = 0; }

}


int checkpoint_requested (MPI_Comm comm)
{
  int local_checkpoint_req = checkpoint_req;
  MPI_Allreduce(&local_checkpoint_req, &checkpoint_req,
                1, MPI_INT, MPI_MAX, comm);
  return checkpoint_req;
}



void my_sig_handler (int signum)
{
  time_t now;
  time(&now);

  if (0 == rank) printf("...inside handler function\n");

  switch (signum)
    {
    case SIGSTOP:
    case SIGINT:
    case SIGTERM:
    case SIGUSR1:
      checkpoint_req = 1;
      if (0 == rank) printf("...caught signal %d at %s", signum, ctime(&now));
      break;

    default:
      if (0 == rank)
        {
          printf("...caught other unknown signal: %d at %s", signum, ctime(&now));
          printf("   see \"man 7 signal\" for a list of known signals\n");
        }
      break;
    }

  // re-register default signal handler for action
  //if (0 == rank) printf(" --> Restoring default handler for signal %d\n", signum);
  //signal(signum, SIG_DFL);

  return;
}




void register_sig_handler ()
{
  if (0 == rank) printf("Registering user-specified signal handlers for PID %d\n", getpid());

  signal(SIGSTOP, my_sig_handler);
  signal(SIGINT,  my_sig_handler);
  signal(SIGTERM, my_sig_handler);
  signal(SIGUSR1, my_sig_handler);
  signal(SIGUSR2, my_sig_handler);
}



void do_checkpoint (MPI_Comm comm)
{
  for (int i=1; i<=10; i++)
    {
      if (0 == rank)
        {
          time_t now;
          time(&now);
          printf("\t%2d : Inside checkpoint function : %s",i, ctime(&now));
          fflush(stdout);
          sleep(5);
        }
      MPI_Barrier(comm);
    }

  done_checkpoint();

  if (0 == rank)
    {
      time_t now;
      time(&now);
      printf(" --> Gracefully exiting after checkpoint : %s", ctime(&now));
      fflush(stdout);
    }

  MPI_Finalize();
  exit(EXIT_SUCCESS);

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

  for (int i=1; i<=5000 ;i++)
    {
      if (0 == rank)
        {
          time_t now;
          time(&now);
          printf("%2d : Main function loop : %s",i,ctime(&now));
          fflush(stdout);
          sleep(5);
        }
      MPI_Barrier(MPI_COMM_WORLD);

      // this function needs to perform a reduction to see if any rank received
      // a signal, hence it is blocking.
      if (checkpoint_requested(MPI_COMM_WORLD))
        do_checkpoint(MPI_COMM_WORLD);
    }

  MPI_Finalize();
  return 0;
}
