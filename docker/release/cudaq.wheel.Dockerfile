# ============================================================================ #
# Copyright (c) 2022 - 2023 NVIDIA Corporation & Affiliates.                   #
# All rights reserved.                                                         #
#                                                                              #
# This source code and the accompanying materials are made available under     #
# the terms of the Apache License 2.0 which accompanies this distribution.     #
# ============================================================================ #

# This file is used to build CUDA Quantum Python wheels.
# Build with buildkit to get the wheels as output instead of the image.
#
# Usage:
# Must be built from the repo root with:
#   DOCKER_BUILDKIT=1 docker build -f docker/release/cudaq.wheel.Dockerfile . --output out

ARG base_image=ghcr.io/nvidia/cuda-quantum-devdeps:manylinux-amd64-gcc11-main
FROM $base_image as wheelbuild

ARG release_version=
ENV CUDA_QUANTUM_VERSION=$release_version

ARG workspace=.
ARG destination=cuda-quantum
ADD "$workspace" "$destination"

ARG python_version=3.10
RUN echo "Building MLIR bindings for python${python_version}" \
    && python${python_version} -m pip install --no-cache-dir numpy \
    && rm -rf "$LLVM_INSTALL_PREFIX/src" "$LLVM_INSTALL_PREFIX/python_packages" \
    && export Python3_EXECUTABLE="$(which python${python_version})" \
    && LLVM_PROJECTS='clang;mlir;python-bindings' \
        bash /scripts/build_llvm.sh -s /llvm-project -c Release -v 

# Build the wheel
RUN echo "Building wheel for python${python_version}." \
    && cd cuda-quantum && python=python${python_version} \
    # Find any external NVQIR simulator assets to be pulled in during wheel packaging.
    && export CUDAQ_EXTERNAL_NVQIR_SIMS=$(bash scripts/find_wheel_assets.sh assets) \
    && export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$(pwd)/assets" \
    && $python -m pip install --no-cache-dir \
        auditwheel cuquantum-cu11==23.10.0 cutensor-cu11==1.7.0 \
    && cuquantum_location=`$python -m pip show cuquantum-cu11 | grep -e 'Location: .*$'` \
    && export CUQUANTUM_INSTALL_PREFIX="${cuquantum_location#Location: }/cuquantum" \
    && cutensor_location=`$python -m pip show cutensor-cu11 | grep -e 'Location: .*$'` \
    && export CUTENSOR_INSTALL_PREFIX="${cutensor_location#Location: }/cutensor" \
    && ln -s $CUQUANTUM_INSTALL_PREFIX/lib/libcustatevec.so.1 $CUQUANTUM_INSTALL_PREFIX/lib/libcustatevec.so \
    && ln -s $CUQUANTUM_INSTALL_PREFIX/lib/libcutensornet.so.2 $CUQUANTUM_INSTALL_PREFIX/lib/libcutensornet.so \
    && ln -s $CUTENSOR_INSTALL_PREFIX/lib/libcutensor.so.1 $CUTENSOR_INSTALL_PREFIX/lib/libcutensor.so \
    &&  SETUPTOOLS_SCM_PRETEND_VERSION=${CUDA_QUANTUM_VERSION:-0.0.0} \
        CUDAQ_ENABLE_STATIC_LINKING=ON \
        CUDACXX="$CUDA_INSTALL_PREFIX/bin/nvcc" CUDAHOSTCXX=$CXX \
        $python -m build --wheel \
    && LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$(pwd)/_skbuild/lib" \
        $python -m auditwheel -v repair dist/cuda_quantum-*linux_*.whl \
            --exclude libcustatevec.so.1 \
            --exclude libcutensornet.so.2 \
            --exclude libcublas.so.11 \
            --exclude libcublasLt.so.11 \
            --exclude libcusolver.so.11 \
            --exclude libcutensor.so.1 \
            --exclude libnvToolsExt.so.1 \ 
            --exclude libcudart.so.11.0 

FROM scratch
COPY --from=wheelbuild /cuda-quantum/wheelhouse/*manylinux*.whl . 
