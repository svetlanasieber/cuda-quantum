#!/bin/bash

# ============================================================================ #
# Copyright (c) 2022 - 2023 NVIDIA Corporation & Affiliates.                   #
# All rights reserved.                                                         #
#                                                                              #
# This source code and the accompanying materials are made available under     #
# the terms of the Apache License 2.0 which accompanies this distribution.     #
# ============================================================================ #

trap '(return 0 2>/dev/null) && return 1 || exit 1' ERR

# [>InstallLocations]
export CUDAQ_INSTALL_PREFIX=/usr/local/cudaq
export CUQUANTUM_INSTALL_PREFIX=/usr/local/cuquantum
export CUTENSOR_INSTALL_PREFIX=/usr/local/cutensor
export LLVM_INSTALL_PREFIX=/usr/local/llvm
export BLAS_INSTALL_PREFIX=/usr/local/blas
export ZLIB_INSTALL_PREFIX=/usr/local/zlib
export OPENSSL_INSTALL_PREFIX=/usr/local/openssl
export CURL_INSTALL_PREFIX=/usr/local/curl
# [<InstallLocations]

if [ "$1" == "install-cuda" ]; then
    DISTRIBUTION=${DISTRIBUTION:-rhel8}
    CUDA_ARCH_FOLDER=$([ "$(uname -m)" == "aarch64" ] && echo sbsa || echo x86_64)

# [>CUDAInstall]
    CUDA_VERSION=11.8
    CUDA_DOWNLOAD_URL=https://developer.download.nvidia.com/compute/cuda/repos
    # Go to the url above, set the variables below to a suitable distribution
    # and subfolder for your platform, and uncomment the line below.
    # DISTRIBUTION=rhel8 CUDA_ARCH_FOLDER=x86_64

    dnf config-manager --add-repo "${CUDA_DOWNLOAD_URL}/${DISTRIBUTION}/${CUDA_ARCH_FOLDER}/cuda-${DISTRIBUTION}.repo"
    dnf install -y --nobest --setopt=install_weak_deps=False \
        cuda-toolkit-$(echo ${CUDA_VERSION} | tr . -)
# [<CUDAInstall]
fi

if [ "$1" == "install-cudart" ]; then
    DISTRIBUTION=${DISTRIBUTION:-rhel8}
    CUDA_ARCH_FOLDER=$([ "$(uname -m)" == "aarch64" ] && echo sbsa || echo x86_64)

# [>CUDARTInstall]
    CUDA_VERSION=11.8
    CUDA_DOWNLOAD_URL=https://developer.download.nvidia.com/compute/cuda/repos
    # Go to the url above, set the variables below to a suitable distribution
    # and subfolder for your platform, and uncomment the line below.
    # DISTRIBUTION=rhel8 CUDA_ARCH_FOLDER=x86_64

    version_suffix=$(echo ${CUDA_VERSION} | tr . -)
    dnf config-manager --add-repo "${CUDA_DOWNLOAD_URL}/${DISTRIBUTION}/${CUDA_ARCH_FOLDER}/cuda-${DISTRIBUTION}.repo"
    dnf install -y --nobest --setopt=install_weak_deps=False \
        cuda-nvtx-${version_suffix} cuda-cudart-${version_suffix} \
        libcusolver-${version_suffix} libcublas-${version_suffix}
# [<CUDARTInstall]
fi

if [ "$1" == "install-cuquantum" ]; then
    CUDA_VERSION=11.8
    CUDA_ARCH_FOLDER=$([ "$(uname -m)" == "aarch64" ] && echo sbsa || echo x86_64)

# [>cuQuantumInstall]
    CUQUANTUM_VERSION=23.10.0.6
    CUQUANTUM_DOWNLOAD_URL=https://developer.download.nvidia.com/compute/cuquantum/redist/cuquantum

    cuquantum_archive=cuquantum-linux-${CUDA_ARCH_FOLDER}-${CUQUANTUM_VERSION}_cuda$(echo ${CUDA_VERSION} | cut -d . -f1)-archive.tar.xz
    wget "${CUQUANTUM_DOWNLOAD_URL}/linux-${CUDA_ARCH_FOLDER}/${cuquantum_archive}"
    mkdir -p "${CUQUANTUM_INSTALL_PREFIX}" 
    tar xf "${cuquantum_archive}" --strip-components 1 -C "${CUQUANTUM_INSTALL_PREFIX}" 
    rm -rf "${cuquantum_archive}"
# [<cuQuantumInstall]
fi

if [ "$1" == "install-cutensor" ]; then
    CUDA_VERSION=11.8
    CUDA_ARCH_FOLDER=$([ "$(uname -m)" == "aarch64" ] && echo sbsa || echo x86_64)

# [>cuTensorInstall]
    CUTENSOR_VERSION=1.7.0.1
    CUTENSOR_DOWNLOAD_URL=https://developer.download.nvidia.com/compute/cutensor/redist/libcutensor

    cutensor_archive=libcutensor-linux-${CUDA_ARCH_FOLDER}-${CUTENSOR_VERSION}-archive.tar.xz
    wget "${CUTENSOR_DOWNLOAD_URL}/linux-${CUDA_ARCH_FOLDER}/${cutensor_archive}"
    mkdir -p "${CUTENSOR_INSTALL_PREFIX}" && tar xf "${cutensor_archive}" --strip-components 1 -C "${CUTENSOR_INSTALL_PREFIX}"
    mv "${CUTENSOR_INSTALL_PREFIX}"/lib/$(echo ${CUDA_VERSION} | cut -d . -f1)/* ${CUTENSOR_INSTALL_PREFIX}/lib/
    ls -d ${CUTENSOR_INSTALL_PREFIX}/lib/*/ | xargs rm -rf && rm -rf "${cutensor_archive}"
# [<cuTensorInstall]
fi

if [ "$1" == "install-gcc" ]; then
# [>gccInstall]
    GCC_VERSION=11
    dnf install -y --nobest --setopt=install_weak_deps=False \
        gcc-toolset-${GCC_VERSION}
# [<gccInstall]
fi

# [>ToolchainConfiguration]
GCC_INSTALL_PREFIX=/opt/rh/gcc-toolset-11
export CXX="${GCC_INSTALL_PREFIX}/root/usr/bin/g++"
export CC="${GCC_INSTALL_PREFIX}/root/usr/bin/gcc"
export FC="${GCC_INSTALL_PREFIX}/root/usr/bin/gfortran"
export CUDACXX=/usr/local/cuda/bin/nvcc
# [<ToolchainConfiguration]

if [ "$1" == "install-prereqs" ]; then
    export LDFLAGS="-static-libgcc -static-libstdc++"
    export LLVM_PROJECTS='clang;lld;mlir'
    this_file_dir=`dirname "$(readlink -f "${BASH_SOURCE[0]}")"`
    bash "$this_file_dir/install_prerequisites.sh"
fi

if [ "$1" == "build-openmpi" ]; then
    source $GCC_INSTALL_PREFIX/enable

# [>OpenMPIBuild]
    OPENMPI_VERSION=4.1.4
    OPENMPI_DOWNLOAD_URL=https://github.com/open-mpi/ompi

    wget "${OPENMPI_DOWNLOAD_URL}/archive/v${OPENMPI_VERSION}.tar.gz" -O /tmp/openmpi.tar.gz
    mkdir -p ~/.openmpi-src && tar xf /tmp/openmpi.tar.gz --strip-components 1 -C ~/.openmpi-src
    rm -rf /tmp/openmpi.tar.gz && cd ~/.openmpi-src
    ./autogen.pl 
    LDFLAGS=-Wl,--as-needed ./configure \
        --prefix=/usr/local/openmpi \
        --disable-getpwuid --disable-static \
        --disable-debug --disable-mem-debug --disable-event-debug \
        --disable-mem-profile --disable-memchecker \
        --without-verbs \
        --with-cuda=/usr/local/cuda
    make -j$(nproc) 
    make -j$(nproc) install
    cd - && rm -rf ~/.openmpi-src
# [<OpenMPIBuild]
fi

trap - ERR
(return 0 2>/dev/null) && return 0 || exit 0