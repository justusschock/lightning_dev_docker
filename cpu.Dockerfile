
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
# Adapted from Lightning-AI/lightning/docker/base-cuda/Dockerfile

ARG UBUNTU_VERSION=20.04

FROM ubuntu:${UBUNTU_VERSION}

ARG PYTHON_VERSION=3.9
ARG PYTORCH_VERSION=1.12

SHELL ["/bin/bash", "-c"]
# https://techoverflow.net/2019/05/18/how-to-fix-configuring-tzdata-interactive-input-when-building-docker-images/
ENV \
    DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/Berlin \
    PATH="$PATH:/root/.local/bin" \
    MKL_THREADING_LAYER=GNU \
    # MAKEFLAGS="-j$(nproc)"
    MAKEFLAGS="-j2"

RUN \
    apt-get update -qq --fix-missing && \
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
        ssh && \
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
    pip config set global.cache-dir false && \
    # set particular PyTorch version
    python lightning/requirements/pytorch/adjust-versions.py lightning/requirements/pytorch/base.txt ${PYTORCH_VERSION} && \
    python lightning/requirements/pytorch/adjust-versions.py lightning/requirements/pytorch/extra.txt ${PYTORCH_VERSION} && \
    python lightning/requirements/pytorch/adjust-versions.py lightning/requirements/pytorch/examples.txt ${PYTORCH_VERSION} && \
    # Install all requirements \
    pip install 'jsonargparse[signatures]' && \
    pip install -r lightning/requirements/pytorch/devel.txt --no-cache-dir --find-links https://download.pytorch.org/whl/cpu/torch_stable.html && \
    pip install -r lightning/requirements/lite/devel.txt && \
    pip install -r lightning/requirements/app/devel.txt && \
    pip install -r lightning/requirements.txt

ENV \
    HOROVOD_WITH_PYTORCH=1 \
    HOROVOD_WITHOUT_TENSORFLOW=1 \
    HOROVOD_WITHOUT_MXNET=1 \
    HOROVOD_WITH_GLOO=1 \
    HOROVOD_WITH_MPI=1

RUN \
    cmake --version && \
    pip install --no-cache-dir -r lightning/requirements/pytorch/strategies.txt --find-links https://release.colossalai.org && \
    horovodrun --check-build

RUN \
    # Show what we have
    pip --version && \
    pip list && \
    python -c "import sys; ver = sys.version_info ; assert f'{ver.major}.{ver.minor}' == '$PYTHON_VERSION', ver" && \
    python -c "import torch; assert torch.__version__.startswith('$PYTORCH_VERSION'), torch.__version__" && \
    python lightning/requirements/pytorch/check-avail-extras.py && \
    python -c "import horovod.torch; import deepspeed; import fairscale" && \
    rm -rf lightning/
