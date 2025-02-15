FROM alpine/git:2.36.2 as download

COPY builder/clone.sh /clone.sh

RUN . /clone.sh taming-transformers https://github.com/CompVis/taming-transformers.git 24268930bf1dce879235a7fddd0b2355b84d7ea6 \
  && rm -rf data assets **/*.ipynb

RUN . /clone.sh stable-diffusion-stability-ai https://github.com/Stability-AI/stablediffusion.git 47b6b607fdd31875c9279cd2f4f16b92e4ea958e \
  && rm -rf assets data/**/*.png data/**/*.jpg data/**/*.gif

RUN . /clone.sh CodeFormer https://github.com/sczhou/CodeFormer.git c5b4593074ba6214284d6acd5f1719b6c5d739af \
  && rm -rf assets inputs

RUN . /clone.sh BLIP https://github.com/salesforce/BLIP.git 48211a1594f1321b00f14c9f7a5b4813144b2fb9
RUN . /clone.sh k-diffusion https://github.com/crowsonkb/k-diffusion.git c9fe758757e022f05ca5a53fa8fac28889e4f1cf
RUN . /clone.sh clip-interrogator https://github.com/pharmapsychotic/clip-interrogator 2486589f24165c8e3b303f84e9dbbea318df83e8
RUN . /clone.sh generative-models https://github.com/Stability-AI/generative-models 45c443b316737a4ab6e40413d7794a7f5657c19f


FROM alpine:3.17 as xformers
RUN apk add --no-cache aria2
RUN aria2c -x 5 --dir / --out wheel.whl 'https://github.com/AbdBarho/stable-diffusion-webui-docker/releases/download/5.0.0/xformers-0.0.17.dev449-cp310-cp310-manylinux2014_x86_64.whl'


FROM python:3.10.9-slim

ENV DEBIAN_FRONTEND=noninteractive PIP_PREFER_BINARY=1

RUN --mount=type=cache,target=/var/cache/apt \
  apt-get update --allow-releaseinfo-change && \
  # we need those
  apt-get install -y fonts-dejavu-core rsync git jq moreutils aria2 \
  # extensions needs those
  ffmpeg libglfw3-dev libgles2-mesa-dev pkg-config libcairo2 libcairo2-dev build-essential


RUN --mount=type=cache,target=/cache --mount=type=cache,target=/root/.cache/pip \
    aria2c -x 5 --dir /cache --out torch-1.13.0+cu117-cp310-cp310-linux_x86_64.whl -c \
    https://download.pytorch.org/whl/cu117/torch-1.13.0%2Bcu117-cp310-cp310-linux_x86_64.whl && \
    pip install /cache/torch-1.13.0+cu117-cp310-cp310-linux_x86_64.whl torchvision --index-url https://download.pytorch.org/whl/cu117

RUN --mount=type=cache,target=/root/.cache/pip \
  git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git && \
  cd stable-diffusion-webui && \
  git reset --hard 20ae71faa8ef035c31aa3a410b707d792c8203a3 && \
  pip install -r requirements_versions.txt

RUN --mount=type=cache,target=/root/.cache/pip  \
  --mount=type=bind,from=xformers,source=/wheel.whl,target=/xformers-0.0.15-cp310-cp310-linux_x86_64.whl \
  pip install triton /xformers-0.0.15-cp310-cp310-linux_x86_64.whl

ENV ROOT=/stable-diffusion-webui


COPY --from=download /repositories/ ${ROOT}/repositories/
RUN mkdir ${ROOT}/interrogate && cp ${ROOT}/repositories/clip-interrogator/data/* ${ROOT}/interrogate
RUN --mount=type=cache,target=/root/.cache/pip \
  pip install -r ${ROOT}/repositories/CodeFormer/requirements.txt

RUN --mount=type=cache,target=/root/.cache/pip \
  pip install pyngrok \
  git+https://github.com/TencentARC/GFPGAN.git@8d2447a2d918f8eba5a4a01463fd48e45126a379 \
  git+https://github.com/openai/CLIP.git@d50d76daa670286dd6cacf3bcd80b5e4823fc8e1 \
  git+https://github.com/mlfoundations/open_clip.git@bb6e834e9c70d9c27d0dc3ecedeebeaeb1ffad6b

# Note: don't update the sha of previous versions because the install will take forever
# instead, update the repo state in a later step

# TODO: either remove if fixed in A1111 (unlikely) or move to the top with other apt stuff
RUN apt-get -y install libgoogle-perftools-dev && apt-get clean
ENV LD_PRELOAD=libtcmalloc.so

## 1.5.1
# ARG SHA=68f336bd994bed5442ad95bad6b6ad5564a5409a
## 1.6.0
ARG SHA=5ef669de080814067961f28357256e8fe27544f4
RUN --mount=type=cache,target=/root/.cache/pip \
  cd stable-diffusion-webui && \
  git fetch && \
  git reset --hard ${SHA} && \
  pip install -r requirements_versions.txt


COPY builder/requirements.txt /requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade pip && \
    pip install --upgrade -r /requirements.txt --no-cache-dir && \
    rm /requirements.txt

ADD builder/* /docker/

RUN \
  python3 /docker/info.py ${ROOT}/modules/ui.py && \
  mv ${ROOT}/style.css ${ROOT}/user.css && \
  # one of the ugliest hacks I ever wrote \
  sed -i 's/in_app_dir = .*/in_app_dir = True/g' /usr/local/lib/python3.10/site-packages/gradio/routes.py && \
  git config --global --add safe.directory '*'

# Cleanup section (Worker Template)
RUN apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

WORKDIR ${ROOT}
# 重要，决定是否正确使用CUDA，踩坑
RUN chmod +x /docker/start.sh
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV NVIDIA_VISIBLE_DEVICES=all
ENV CLI_ARGS=""
EXPOSE 7860
ENTRYPOINT ["/docker/entrypoint.sh"]
CMD /docker/start.sh