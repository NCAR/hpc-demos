#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include "my_sig_handler.h"



void do_checkpoint ()
{
  for (int i=1; i<=10; i++)
    {
      printf("\t%2d : Inside checkpoint function\n",i);
      fflush(stdout);
      sleep(5);
    }
  done_checkpoint();
  return;
}



int main ()
{
  register_sig_handler();

  for (int i=1; i<=50 ;i++)
    {
      printf("%2d : Inside main function\n",i);
      fflush(stdout);
      sleep(5);

      if (checkpoint_requested())
        do_checkpoint();
    }

  return 0;
}
