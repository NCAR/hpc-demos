#!/bin/bash

module load charliecloud >/dev/null 2>&1

make -s my_alpine.sqfs || exit 1
. config_demo_env_vars.sh || exit 1

echo -e "# Step #1:"
set -x
ch-run \
    ./my_alpine.sqfs -- /opt/container/list_glade_filesystems.sh
set +x

echo -e "\n# Step #2:"
set -x
ch-run \
    --bind=/glade/derecho/scratch \
    --bind=/glade/work \
    --bind=/glade/campaign \
    --bind="/glade/work:/random/path" \
    ./my_alpine.sqfs -- /opt/container/list_glade_filesystems.sh
set +x

echo -e "\n# Step #3:"
set -x
ch-run \
    --bind=/glade/derecho/scratch \
    --bind=/glade/work \
    --bind=/glade/campaign \
    --bind="/glade/work:/random/other/path" \
    ./my_alpine.sqfs -- /opt/container/list_glade_filesystems.sh
set +x
