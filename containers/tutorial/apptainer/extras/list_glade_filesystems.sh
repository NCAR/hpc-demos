#!/bin/sh

echo "------------------------------"
for dir in /glade/u/home /glade/work /glade/derecho/scratch /glade/campaign /random/path ; do
    echo -n "${dir} :"
    [ -d ${dir} ] && echo " mounted" || echo " NOT mounted"
done
echo "------------------------------"
