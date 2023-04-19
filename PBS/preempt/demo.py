#!/usr/bin/env python3

import signal
import sys
import time
import os
from datetime import datetime

checkpoint_requested = False



def my_signal_handler(sig, frame):

    global checkpoint_requested

    if signal.SIGINT == sig:
        print("...caught SIGINT at "+ datetime.now().strftime("%H:%M:%S %B %d, %Y"))
        checkpoint_requested = True

    elif signal.SIGTERM == sig:
        print("...caught SIGTERM at " + datetime.now().strftime("%H:%M:%S %B %d, %Y"))
        checkpoint_requested = True

    elif signal.SIGUSR1 == sig:
        print("...caught SIGUSR1, ignoring...")

    else:
        print("...caught unknown signal: " + sig)
        sys.exit(1)

    print(" --> Restoring default handler for signal {}".format(sig))
    signal.signal(sig, signal.SIG_DFL)
    return



def register_signal_handler ():
    print("Registering user-specified signal handlers for PID {}".format(os.getpid()))
    signal.signal(signal.SIGINT,  my_signal_handler)
    signal.signal(signal.SIGTERM, my_signal_handler)
    signal.signal(signal.SIGUSR1, my_signal_handler)
    return




def do_checkpoint ():

    global checkpoint_requested

    for i in range(1, 11):
        print("\t{:2d} : Inside checkpoint function".format(i))
        sys.stdout.flush()
        time.sleep(5)

    checkpoint_requested = False;
    return



if __name__ == "__main__":

    register_signal_handler();

    for i in range(1, 51):
        print("{:2d} : Inside main function".format(i))
        sys.stdout.flush()
        time.sleep(5)

        if checkpoint_requested:
            do_checkpoint()
