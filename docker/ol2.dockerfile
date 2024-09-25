# Base layer
ARG REGISTRY
FROM $REGISTRY/ol2-base:latest

# Output Volume
ENV VOLUME_ROOT=/mnt/output
VOLUME $VOLUME_ROOT

# Environment forwarded build ARGS
ARG USE_XPRA=1
ENV USE_XPRA=$USE_XPRA

# Dependencies ...
RUN apt-get update && \
    apt-get install -y \
      time \
      curl \
      jq \
      tar \
      unzip \
      wget \
      pkg-config \
      libcairo2-dev \
      libffi-dev \
      libxaw7-dev \
      libreadline-dev \
      cgroup-tools \
      procps \
      openssh-server \
      librsvg2-bin \
      pngquant \
      help2man \
      perl \
      perl-doc \
      cmake \
      tk \
      tk-dev \
      tclsh \
      tcl-dev \
      tcl-tclreadline \
      python3-tk \
      python3-pip \
      python3.11-venv \
      python3-click \
      python3-rich \
      ant \
      default-jre \
      swig \
      libtool \
      autoconf \
      flex \
      bison \
      google-perftools \
      libgoogle-perftools-dev \
      numactl \
      libfl-dev \
      libfl2 \
      zlib1g \
      uuid \
      uuid-dev \
      libqt5widgets5 \
      qt5dxcb-plugin \
      xcb

# OpenLane2 needs this globally for some reason when placing custom ports
RUN python3 -m pip install --break-system-packages ioplace_parser

# Grab some projects which don't need to be built
# KLayout should be > 29.1 on debian
RUN apt install -y \
  iverilog \
  klayout  \
  gtkwave

# Add XPRA
RUN test $USE_XPRA -eq 1 && apt install -y xpra xterm || :

# Default to volume workpath
WORKDIR $VOLUME_ROOT

# Container Scripts
COPY syn.env                   /syn.env
COPY docker/ol2.entrypoint.sh  /ol2.entrypoint.sh
RUN  chmod +x /*.sh

# Public Keys
COPY pubkey/* /root/.ssh/
RUN  cat /root/.ssh/*.pub >> /root/.ssh/authorized_keys && \
     rm   -f /root/.ssh/*.pub

# Profile
RUN echo "source $VOLUME_ROOT/syn.env && cd $VOLUME_ROOT" >> ~/.profile

# Cleanup
RUN apt clean -y
RUN rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/ol2.entrypoint.sh"]
