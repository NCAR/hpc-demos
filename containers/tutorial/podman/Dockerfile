FROM docker.io/rockylinux/rockylinux:9

RUN yum -y install dnf-plugins-core \
    && dnf -y update \
    && dnf config-manager --set-enabled crb \
    && dnf -y install epel-release \
    && dnf clean all --verbose
