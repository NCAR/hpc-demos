#ifndef MY_SIG_HANDLER_H
#define MY_SIG_HANDLER_H

#ifdef HAVE_MPI
#  include <mpi.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

int  checkpoint_requested ();
void done_checkpoint ();
void register_sig_handler ();
void my_sig_handler (int signum);

#ifdef HAVE_MPI
  int mpi_checkpoint_requested (MPI_Comm comm);
#endif


#ifdef __cplusplus
}
#endif


#endif /* #define MY_SIG_HANDLER_H */
