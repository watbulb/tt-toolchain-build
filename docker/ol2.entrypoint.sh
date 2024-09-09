#!/bin/bash
set -e -u

PREFIX=ol2-main
STALL=${STALL:-99999}

# SSH
echo "[$PREFIX] entrypoint"
echo "[$PREFIX] service ssh start"
service ssh start

# Ensure a non-temporal storage is attached
if [[ ! -d $VOLUME_ROOT ]]; then
  echo "[$PREFIX] FATAL: NO VOLUME ATTACHED!"
  exit 255
fi

# Build toolchain
if [[ ! -f $VOLUME_ROOT/.built ]]; then
  #
  # Environment
  echo "[$PREFIX] Environment"
  apt-get update -y
  mkdir -p $VOLUME_ROOT/toolchain
  cp -f /syn.env $VOLUME_ROOT/syn.env
  source $VOLUME_ROOT/syn.env
  python3 -m venv $VENV_ROOT

  #
  # SVLS (for vscode remote)
  wget -O /tmp/svls.zip https://github.com/dalance/svls/releases/download/v0.2.12/svls-v0.2.12-x86_64-lnx.zip
  unzip /tmp/svls.zip && mv svls $VENV_ROOT/bin/svls


  #
  # TinyTapeout Support Tools
  echo "[$PREFIX] TT Support Tools: [$TT_SUPPORT_ROOT]"
  git clone -b $TT_SUPPORT_TAG https://github.com/TinyTapeout/tt-support-tools $TT_SUPPORT_ROOT
  /bin/bash -c "source $VENV_ROOT/bin/activate && pip3 install -r $TT_SUPPORT_ROOT/requirements.txt"
  # BUG: TT incorrectly uses yowasp-yosys (installed from pip) for systemverilog projects, breaking the tool
  # because vanilla yosys with the -sv flag is abysmally supported in favor of synlig,
  # we should just use our own synlig yosys ... i have zero idea why they would install this ...
  /bin/bash -c "source $VENV_ROOT/bin/activate && pip3 uninstall -y yowasp-yosys"
  cat <<EOF > $VENV_ROOT/bin/yowasp-yosys
#!/bin/bash
if [[ "\$USE_SYNLIG" = "1" ]]; then
  yosys -p "plugin -i systemverilog" -f systemverilog "\${@}"
else
  yosys \$@
fi
EOF
  chmod +x $VENV_ROOT/bin/yowasp-yosys

  #
  # Magic
  echo "[$PREFIX] Magic VLSI: [$MAGIC_ROOT]"
  git clone https://github.com/RTimothyEdwards/magic $MAGIC_ROOT
  pushd $MAGIC_ROOT
  {
    mkdir -p release
    ./configure --prefix=$MAGIC_ROOT/release --with-tcl=/usr/lib --with-tk=/usr/lib
    make -j $(nproc)
    make install
  }
  popd # MAGIC_ROOT


  # Netgen
  # NOTE: TT specific netgen
  echo "[$PREFIX] Netgen: [$NETGEN_ROOT:$NETGEN_TAG]"
  git clone -b $NETGEN_TAG https://github.com/smunaut/netgen $NETGEN_ROOT
  pushd $NETGEN_ROOT
  {
    mkdir -p release
    ./configure --prefix=$NETGEN_ROOT/release
    make -j $(nproc)
    make install
  }
  popd


  #
  # Synlig
  echo "[$PREFIX] Synlig & YoSys: [$SYNLIG_ROOT]"
  git clone https://github.com/chipsalliance/synlig $SYNLIG_ROOT
  pushd $SYNLIG_ROOT
  {
    git submodule sync
    git submodule update --init --recursive third_party/{surelog,yosys}
    python3 -m pip install orderedmultidict --break-system-packages
    make -j$(nproc) install
  }
  popd


  #
  # OpenROAD (OpenSTA, CUDD, or-tools, ...)
  echo "[$PREFIX] OpenROAD: [$OPENROAD_ROOT:$OPENROAD_TAG]"
  git clone --recursive https://github.com/The-OpenROAD-Project/OpenROAD.git $OPENROAD_ROOT
  pushd $OPENROAD_ROOT
  {
    # Use the latest dependency installer
    sed -i 's/"$(uname -m)" == "aarch64"/"$(uname -m)" == "x86_64"/g' ./etc/DependencyInstaller.sh
    /bin/bash -c "source $VENV_ROOT/bin/activate && ./etc/DependencyInstaller.sh"

    # OpenSTA (uses OpenROAD base dependencies)
    echo "[$PREFIX] OpenROAD[OpenSTA]: [$OPENSTA_ROOT:$OPENSTA_TAG]"
    git clone -b $OPENSTA_TAG https://github.com/smunaut/OpenSTA $OPENSTA_ROOT
    mkdir -p $OPENSTA_ROOT/build/release
    cmake -S $OPENSTA_ROOT -B $OPENSTA_ROOT/build -DCMAKE_INSTALL_PREFIX=$OPENSTA_ROOT/build/release
    cmake --build   $OPENSTA_ROOT/build -j $(nproc)
    cmake --install $OPENSTA_ROOT/build

    # Checkout TT checkpointed OpenROAD
    git stash && git checkout $OPENROAD_TAG
    mkdir -p build/release
    cmake -S $OPENROAD_ROOT -B $OPENROAD_ROOT/build \
      -DCMAKE_INSTALL_PREFIX=$OPENROAD_ROOT/build/release \
      -DUSE_SYSTEM_OPENSTA:BOOL=ON \
      -DOPENSTA_HOME=$OPENSTA_ROOT \
      -DOPENSTA_LIBRARY=$OPENSTA_ROOT/build/release/lib \
      -DOPENSTA_INCLUDE_DIR=$OPENSTA_ROOT/build/release/include \
      -DTCL_HEADER=/usr/include/tcl8.6/tcl.h \
      -DTCL_LIBRARY=/usr/lib/x86_64-linux-gnu/libtcl.so \
      -DENABLE_TESTS:BOOL=OFF \
      -DCMAKE_CXX_FLAGS="-L$OPENSTA_ROOT/build/release/lib"
    cmake --build   $OPENROAD_ROOT/build -j $(nproc)
    cmake --install $OPENROAD_ROOT/build
    # grab a copy of or-tools placed in /opt
    cp -r /opt/or-tools $ORTOOL_ROOT
  }
  popd # OPENROAD_ROOT


  #
  # OpenLane2
  echo "[$PREFIX] OpenLane2: [$OPENLANE_ROOT:$OPENLANE2_TAG]"
  git clone -b $OPENLANE2_TAG https://github.com/efabless/openlane2 $OPENLANE_ROOT
  wget -O $VOLUME_ROOT/toolchain/openlane2.patch \
      'https://github.com/TinyTapeout/tinytapeout-08/raw/main/patches/openlane2.patch'
  git -C $OPENLANE_ROOT apply $VOLUME_ROOT/toolchain/openlane2.patch
  pushd $OPENLANE_ROOT
  /bin/bash -c "source $VENV_ROOT/bin/activate && python3 -m pip uninstall -y setuptools"
  /bin/bash -c "source $VENV_ROOT/bin/activate && python3 -m pip install setuptools==74.0.0"
  /bin/bash -c "source $VENV_ROOT/bin/activate && python3 ./setup.py install"
  popd


  #
  # PDK (Via Volare)
  echo "[$PREFIX] PDK: [$PDK:$PDK_VERSION:$PDK_ROOT]"
  /bin/bash -c "source $VENV_ROOT/bin/activate && pip3 install volare"
  /bin/bash -c "source $VENV_ROOT/bin/activate && python3 -m volare fetch  $PDK_VERSION"
  /bin/bash -c "source $VENV_ROOT/bin/activate && python3 -m volare enable $PDK_VERSION"


  #
  # Verilator
  echo "[$PREFIX] Verilator [$VERILATOR_ROOT]"
  git clone https://github.com/verilator/verilator $VERILATOR_ROOT
  pushd $VERILATOR_ROOT
  {
    autoconf
    ./configure
    make -j $(nproc)
  }
  popd

  # Done
  echo "[$PREFIX] Done"
  touch $VOLUME_ROOT/.built
  echo "source $VOLUME_ROOT/syn.env && cd $VOLUME_ROOT" >> ~/.profile
fi

echo "[$PREFIX] stalling ($STALL) seconds"
sleep $STALL
