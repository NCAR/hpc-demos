#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include "my_sig_handler.h"



int checkpoint_req = 0;



int checkpoint_requested ()
{
  return checkpoint_req;
}



void done_checkpoint ()
{
  checkpoint_req = 0;
}



void register_sig_handler ()
{
  printf("Registering user-specified signal handlers for PID %d\n", getpid());

  signal(SIGINT,  my_sig_handler);
  signal(SIGTERM, my_sig_handler);
  signal(SIGUSR1, my_sig_handler);
  signal(SIGUSR2, my_sig_handler);
}



int checkpoint_requested_ ()
{
  return checkpoint_requested();
}



void done_checkpoint_ ()
{
  done_checkpoint();
}



void register_sig_handler_ ()
{
  register_sig_handler ();
}



void my_sig_handler (int signum)
{
  time_t now;
  time(&now);

  printf("\nInside handler function\n");

  switch (signum)
    {
    case SIGINT:
      printf("...caught SIGINT at %s", ctime(&now));
      checkpoint_req = 1;
      break;

    case SIGTERM:
      printf("...caught SIGTERM at %s", ctime(&now));
      checkpoint_req = 1;
      break;

    case SIGUSR1:
      printf("...caught SIGUSR1 at %s", ctime(&now));
      checkpoint_req = 1;
      break;

    case SIGUSR2:
      printf("...caught SIGUSR2 at %s, ignoring...\n",ctime(&now));
      return;

    default:
      printf("...caught other unknown signal: %d at %s", signum, ctime(&now));
      printf("   see \"man 7 signal\" for a list of known signals\n");
      break;
    }

  // re-register default signal handler for action
  printf(" --> Restoring default handler for signal %d\n", signum);
  signal(signum, SIG_DFL);

  return;
}



#ifdef HAVE_MPI
int mpi_checkpoint_requested (MPI_Comm comm)
{
  int local_checkpoint_req = checkpoint_req;
  MPI_Allreduce(&local_checkpoint_req,
                &checkpoint_req,
                1, MPI_INT, MPI_MAX, comm);
  return checkpoint_req;
}



int mpi_checkpoint_requested_ (MPI_Comm comm)
{
  return mpi_checkpoint_requested(comm);
}
#endif /* #ifdef HAVE_MPI */
