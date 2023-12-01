FROM rockylinux/rockylinux:9

RUN yum -y install dnf-plugins-core \
    && dnf -y update \
    && dnf config-manager --set-enabled crb \
    && dnf -y install epel-release \
    && dnf -y groupinstall "Development Tools" \
    && dnf -y install \
           chrpath \
           bzip2 autoconf automake libtool \
           gcc gcc-c++ gcc-gfortran emacs make procps-ng openmpi-devel \
    && dnf clean all --verbose
