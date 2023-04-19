#!/usr/bin/env bash


checkpoint_requested=false


function my_signal_handler()
{

    case ${sig} in
        SIGINT)
            printf "...caught %s at %s\n" ${sig} "$(date)"
            checkpoint_requested=true
            ;;
        SIGTERM)
            printf "...caught %s at %s\n" ${sig} "$(date)"
            checkpoint_requested=true
            ;;
        SIGUSR1)
            printf "...caught %s1, ignoring...\n" ${sig}
            ;;
        *)
            printf "...caught unknown signal: %s\n" ${sig}
            exit 1
            ;;
    esac

    printf " --> Restoring default handler for signal %s\n" ${sig}
    trap - ${sig}
}


function register_signal_handler ()
{
    printf "Registering user-specified signal handlers for PID %d\n" $$

    trap "sig=SIGINT;  my_signal_handler" SIGINT
    trap "sig=SIGTERM; my_signal_handler" SIGTERM
    trap "sig=USR1;    my_signal_handler" USR1
}



function do_checkpoint ()
{

    for i in $(seq 1 10); do
        printf "\t%2d : Inside checkpoint function\n" $i
        sleep 5s
    done
    checkpoint_requested=false;
}



# main function follows
register_signal_handler

for i in $(seq 1 50); do

    printf "%2d : Inside main function\n" $i
    sleep 5s

    if $checkpoint_requested; then
        do_checkpoint
    fi

done
