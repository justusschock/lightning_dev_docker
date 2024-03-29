# Copyright The PyTorch Lightning team.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# Adapted from Lightning-AI/lightning/docker/base-cuda/cuda.Dockerfile


ARG UBUNTU_VERSION=22.04
ARG CUDA_VERSION=11.3.1

FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION}

ARG PYTHON_VERSION=3.10
ARG PYTORCH_VERSION=1.13.1

SHELL ["/bin/bash", "-c"]
# https://techoverflow.net/2019/05/18/how-to-fix-configuring-tzdata-interactive-input-when-building-docker-images/
ENV \
    DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/Berlin \
    PATH="$PATH:/root/.local/bin" \
    CUDA_TOOLKIT_ROOT_DIR="/usr/local/cuda" \
    TORCH_CUDA_ARCH_LIST="3.7;5.0;6.0;7.0;7.5;8.0" \
    MKL_THREADING_LAYER=GNU \
    # MAKEFLAGS="-j$(nproc)"
    MAKEFLAGS="-j2"

RUN \
    # TODO: Remove the manual key installation once the base image is updated.
    # https://github.com/NVIDIA/nvidia-docker/issues/1631
    apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/3bf863cc.pub && \
    apt-get update -qq --fix-missing && \
    NCCL_VER=$(dpkg -s libnccl2 | grep '^Version:' | awk -F ' ' '{print $2}' | awk -F '-' '{print $1}' | grep -ve '^\s*$') && \
    CUDA_VERSION_MM="${CUDA_VERSION%.*}" && \
    MAX_ALLOWED_NCCL=2.11.4 && \
    TO_INSTALL_NCCL=$(echo -e "$MAX_ALLOWED_NCCL\n$NCCL_VER" | sort -V  | head -n1)-1+cuda${CUDA_VERSION_MM} && \
    apt-get install -y --no-install-recommends --allow-downgrades --allow-change-held-packages \
        build-essential \
        pkg-config \
        cmake \
        git \
        wget \
        curl \
        unzip \
        ca-certificates \
        software-properties-common \
        libopenmpi-dev \
        openmpi-bin \
        mpich \
        ssh \
        libnccl2=$TO_INSTALL_NCCL \
        libnccl-dev=$TO_INSTALL_NCCL && \
# Install python
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get install -y \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-distutils \
        python${PYTHON_VERSION}-dev \
    && \
    update-alternatives --install /usr/bin/python${PYTHON_VERSION%%.*} python${PYTHON_VERSION%%.*} /usr/bin/python${PYTHON_VERSION} 1 && \
    update-alternatives --install /usr/bin/python python /usr/bin/python${PYTHON_VERSION} 1 && \
# Cleaning
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /root/.cache && \
    rm -rf /var/lib/apt/lists/*
    
RUN git clone https://github.com/Lightning-AI/lightning

ENV PYTHONPATH=/usr/lib/python${PYTHON_VERSION}/site-packages

RUN \
    wget https://bootstrap.pypa.io/get-pip.py --progress=bar:force:noscroll --no-check-certificate && \
    python${PYTHON_VERSION} get-pip.py && \
    rm get-pip.py && \
    pip install -q fire && \
    # Disable cache \
    CUDA_VERSION_MM=$(python -c "print(''.join('$CUDA_VERSION'.split('.')[:2]))") && \
    pip config set global.cache-dir false && \
    # set particular PyTorch version
    python lightning/requirements/pytorch/adjust-versions.py lightning/requirements/pytorch/base.txt ${PYTORCH_VERSION} && \
    python lightning/requirements/pytorch/adjust-versions.py lightning/requirements/pytorch/extra.txt ${PYTORCH_VERSION} && \
    python lightning/requirements/pytorch/adjust-versions.py lightning/requirements/pytorch/examples.txt ${PYTORCH_VERSION} && \
    # Install all requirements \
    pip install -r lightning/requirements/pytorch/devel.txt --no-cache-dir --find-links https://download.pytorch.org/whl/cu${CUDA_VERSION_MM}/torch_stable.html && \
    pip install -r lightning/requirements/lite/devel.txt && \
    pip install -r lightning/requirements/app/devel.txt && \
    pip install mpi4py && \
    pip install -r lightning/requirements.txt

ENV \
    HOROVOD_CUDA_HOME=$CUDA_TOOLKIT_ROOT_DIR \
    HOROVOD_GPU_OPERATIONS=NCCL \
    HOROVOD_WITH_PYTORCH=1 \
    HOROVOD_WITHOUT_TENSORFLOW=1 \
    HOROVOD_WITHOUT_MXNET=1 \
    HOROVOD_WITH_GLOO=1 \
    HOROVOD_WITH_MPI=1

RUN \
    python -c "import torch; torch_version = '.'.join(torch.__version__.split('+')[0].split('.')[:2]) ; cuda_version_mm = float(''.join(map(str, torch.version.cuda))) ; cuda_version = [ver for ver in [11.3, 11.1] if cuda_version_mm >= ver][0] ; fname = 'lightning/requirements/pytorch/strategies.txt' ; import os ; lines_old = open(fname).readlines() ; lines = [line if 'colossalai' not in line else line.strip().replace('\n', '') + f'+torch{torch_version}cu{cuda_version}\n' for line in lines_old]; print(lines); open(fname, 'w').writelines(lines)" && cat lightning/requirements/pytorch/strategies.txt

RUN \
    # CUDA 10.2 doesn't support ampere architecture (8.0).
    if [[ "$CUDA_VERSION" < "11.0" ]]; then export TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST//";8.0"/}; echo $TORCH_CUDA_ARCH_LIST; fi && \
    HOROVOD_BUILD_CUDA_CC_LIST=${TORCH_CUDA_ARCH_LIST//";"/","} && \
    export HOROVOD_BUILD_CUDA_CC_LIST=${HOROVOD_BUILD_CUDA_CC_LIST//"."/""} && \
    echo $HOROVOD_BUILD_CUDA_CC_LIST && \
    cmake --version && \
    pip install --no-cache-dir -r lightning/requirements/pytorch/strategies.txt --find-links https://release.colossalai.org && \
    horovodrun --check-build

RUN \
    # install Bagua
    CUDA_VERSION_MM=$(python -c "print(''.join('$CUDA_VERSION'.split('.')[:2]))") && \
    CUDA_VERSION_BAGUA=$(python -c "print([ver for ver in [116,115,113,111,102] if int($CUDA_VERSION_MM) >= ver][0])") && \
    pip install "bagua-cuda$CUDA_VERSION_BAGUA" && \
    if [[ "$CUDA_VERSION_MM" = "$CUDA_VERSION_BAGUA" ]]; then python -c "import bagua_core; bagua_core.install_deps()"; fi && \
    python -c "import bagua; print(bagua.__version__)"

RUN \
    # Show what we have
    pip --version && \
    pip list && \
    python -c "import sys; ver = sys.version_info ; assert f'{ver.major}.{ver.minor}' == '$PYTHON_VERSION', ver" && \
    python -c "import torch; assert torch.__version__.startswith('$PYTORCH_VERSION'), torch.__version__" && \
    python lightning/requirements/pytorch/check-avail-extras.py && \
    python lightning/requirements/pytorch/check-avail-strategies.py && \
    rm -rf lightning/
