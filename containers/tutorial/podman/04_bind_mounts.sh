#!/bin/bash

module load podman >/dev/null 2>&1

make -s my_alpine.stamp || exit 1
. config_demo_env_vars.sh || exit 1

echo -e "# Step #1:"
set -x
podman \
    --log-level error \
    run \
    my_alpine:latest /opt/container/list_glade_filesystems.sh
set +x

echo -e "\n# Step #2:"
set -x
podman \
    --log-level error \
    run \
    --volume ${HOME} \
    --volume /glade/derecho/scratch \
    --volume /glade/work \
    --volume /glade/campaign \
    --volume "/glade/work:/random/path" \
    my_alpine:latest /opt/container/list_glade_filesystems.sh
set +x
