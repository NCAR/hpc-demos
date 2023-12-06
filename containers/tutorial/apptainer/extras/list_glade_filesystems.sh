#!/bin/sh

echo "------------------------------"
echo "HOME=${HOME}"
echo "PWD=$(pwd)"
df -h | egrep -v "dev/random|dev/urandom" | egrep "glade|random"
echo "------------------------------"
