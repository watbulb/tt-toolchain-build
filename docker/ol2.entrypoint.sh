#!/bin/bash
set -e -u

STALL=${STALL:-99999}

echo "[ol2] entrypoint"

# SSH
echo "[ol2] service ssh start"
service ssh start

# Ensure a non-temporal storage is attached
if [[ ! -d $VOLUME_ROOT ]]; then
  echo "[ol2] FATAL: NO VOLUME ATTACHED!"
  exit 255
fi

# Update some files regardless
cp -f /syn.env $VOLUME_ROOT/syn.env

# Build toolchain
if [[ ! -f $VOLUME_ROOT/.built ]]; then
  #
  # Environment
  echo "[ol2] Environment"
  apt-get update -y
  mkdir -p $VOLUME_ROOT/toolchain
  source $VOLUME_ROOT/syn.env
  python3 -m venv $VENV_ROOT

  #
  # SVLS (for vscode remote)
  if [[ ! -f $VENV_ROOT/bin/svls ]]; then
    wget -O /tmp/svls.zip https://github.com/dalance/svls/releases/download/v0.2.12/svls-v0.2.12-x86_64-lnx.zip
    unzip /tmp/svls.zip && mv svls $VENV_ROOT/bin/svls
  fi

  #
  # TinyTapeout Support Tools
  echo "[ol2:$VSE_VERSION] TT Support Tools: [$TT_SUPPORT_ROOT]"
  if [[ ! -d $TT_SUPPORT_ROOT ]]; then
    git clone -b $TT_SUPPORT_TAG https://github.com/TinyTapeout/tt-support-tools $TT_SUPPORT_ROOT
  fi
  if [[ ! -f $TT_SUPPORT_ROOT/.built ]]; then
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
    touch $TT_SUPPORT_ROOT/.built
  fi


  #
  # NGSpice
  echo "[ol2:$VSE_VERSION] NGSpice: [$NGSPICE_ROOT:$NGSPICE_TAG]"
  if [[ ! -d $NGSPICE_ROOT ]]; then
    git clone -b $NGSPICE_TAG https://git.code.sf.net/p/ngspice/ngspice $NGSPICE_ROOT
  fi
  if [[ ! -f $NGSPICE_ROOT/.built ]]; then
    pushd $NGSPICE_ROOT
    {
      mkdir -p release
      ./autogen.sh
      ./configure \
        --prefix=$NGSPICE_ROOT/release \
        --disable-debug \
        --with-readline=yes \
        --enable-openmp=yes \
        --enable-klu \
        --enable-cider \
        --with-x
      make -j $(nproc)
      make install
      touch .built
    }
    popd
  fi


  #
  # XSCHEM
  echo "[ol2:$VSE_VERSION] XSCHEM: [$XSCHEM_ROOT:$XSCHEM_TAG]"
  if [[ ! -d $XSCHEM_ROOT ]]; then
    git clone https://github.com/StefanSchippers/xschem $XSCHEM_ROOT
  fi
  if [[ ! -f $XSCHEM_ROOT/.built ]]; then
    pushd $XSCHEM_ROOT
    {
      git checkout $XSCHEM_TAG
      mkdir -p release
      ./configure --prefix=$XSCHEM_ROOT/release --user-conf-dir=$VOLUME_ROOT/.xschem
      make -j $(nproc)
      make install
      touch .built
    }
    popd
  fi


  #
  # Magic
  echo "[ol2:$VSE_VERSION] Magic VLSI: [$MAGIC_ROOT]"
  if [[ ! -d $MAGIC_ROOT ]]; then
    git clone https://github.com/RTimothyEdwards/magic $MAGIC_ROOT
  fi
  if [[ ! -f $MAGIC_ROOT/.built ]]; then
    pushd $MAGIC_ROOT
    {
      mkdir -p release
      ./configure --prefix=$MAGIC_ROOT/release --with-tcl=/usr/lib --with-tk=/usr/lib
      make -j $(nproc)
      make install
      touch .built
    }
    popd
  fi


  # Netgen
  # NOTE: TT specific netgen
  echo "[ol2:$VSE_VERSION] Netgen: [$NETGEN_ROOT:$NETGEN_TAG]"
  if [[ ! -d $NETGEN_ROOT ]]; then
    git clone -b $NETGEN_TAG https://github.com/smunaut/netgen $NETGEN_ROOT
  fi
  if [[ ! -f $NETGEN_ROOT/.built ]]; then
    pushd $NETGEN_ROOT
    {
      mkdir -p release
      ./configure --prefix=$NETGEN_ROOT/release
      make -j $(nproc)
      make install
      touch .built
    }
    popd
  fi


  #
  # Synlig
  echo "[ol2:$VSE_VERSION] Synlig & YoSys: [$SYNLIG_ROOT]"
  if [[ ! -d $SYNLIG_ROOT ]]; then
    git clone --depth=1 https://github.com/chipsalliance/synlig $SYNLIG_ROOT
  fi
  if [[ ! -f $SYNLIG_ROOT/.built ]]; then
    pushd $SYNLIG_ROOT
    {
      git submodule sync
      git submodule update --checkout --init --recursive third_party/{surelog,yosys,eqy}
      python3 -m pip install orderedmultidict --break-system-packages
      make -j$(nproc) CFG_OUT_DIR=$SYNLIG_ROOT/release/ PREFIX=$SYNLIG_ROOT/release/ install@yosys
      make -j$(nproc) CFG_OUT_DIR=$SYNLIG_ROOT/release/ PREFIX=$SYNLIG_ROOT/release/ install@synlig
      make -j$(nproc) CFG_OUT_DIR=$SYNLIG_ROOT/release/ PREFIX=$SYNLIG_ROOT/release/ install@surelog
      make -j$(nproc) CFG_OUT_DIR=$SYNLIG_ROOT/release/ PREFIX=$SYNLIG_ROOT/release/ install@systemverilog-plugin
      make -j$(nproc) CFG_OUT_DIR=$SYNLIG_ROOT/release/ PREFIX=$SYNLIG_ROOT/release/ install@eqy
      touch .built
    }
    popd
  fi

  #
  # CUDD
  # built because the version of OpenROAD's (etc/DependencyInstaller) OpenLane <= 2.1.8 targets
  # does not yet include the patch to install CUDD
  echo "[ol2:$VSE_VERSION] CUDD: [$CUDD_ROOT:$CUDD_TAG]"
  if [[ ! -d $CUDD_ROOT ]]; then
    git clone --depth=1 -b $CUDD_TAG https://github.com/The-OpenROAD-Project/cudd.git $CUDD_ROOT
  fi
  if [[ ! -f $CUDD_ROOT/.built ]]; then
    pushd $CUDD_ROOT
    {
      mkdir -p release
      ln -sf $(which aclocal)  "/usr/local/bin/aclocal-1.14"
      ln -sf $(which automake) "/usr/local/bin/automake-1.14"
      autoconf
      ./configure --prefix=$CUDD_ROOT/release
      make -j $(nproc) install
      touch .built
    }
    popd
  fi

  #
  # OpenSTA
  # Only required in unique circumstances, tt09 (& <= OpenLane 2.1.7) needs to use a specific version due to recent OpenSTA bug.
  echo "[ol2:$VSE_VERSION] OpenROAD[OpenSTA]: [$OPENSTA_ROOT:$OPENSTA_TAG]"
  if [[ ! -d $OPENSTA_ROOT ]]; then
    git clone https://github.com/parallaxsw/OpenSTA $OPENSTA_ROOT
  fi
  if [[ ! -f $OPENSTA_ROOT/.built ]]; then
    pushd $OPENSTA_ROOT
    {
      git checkout $OPENSTA_TAG
      mkdir -p $OPENSTA_ROOT/build/release
      cmake -S $OPENSTA_ROOT -B $OPENSTA_ROOT/build -DCMAKE_INSTALL_PREFIX=$OPENSTA_ROOT/build/release
      cmake --build   $OPENSTA_ROOT/build -j $(nproc)
      cmake --install $OPENSTA_ROOT/build
      touch .built
    }
    popd
  fi


  #
  # OpenROAD (includes or-tools, eigen, etc ..)
  echo "[ol2:$VSE_VERSION] OpenROAD: [$OPENROAD_ROOT:$OPENROAD_TAG]"
  if [[ ! -d $OPENROAD_ROOT ]]; then
    git clone --recursive https://github.com/The-OpenROAD-Project/OpenROAD.git $OPENROAD_ROOT
  fi
  if [[ ! -f $OPENROAD_ROOT/.built ]]; then
    pushd $OPENROAD_ROOT
    {
      git checkout $OPENROAD_TAG
      git submodule update --init --recursive

      ## uncomment to force or-tools scratch build
      # sed -i 's/"$(uname -m)" == "aarch64"/"$(uname -m)" == "x86_64"/g' ./etc/DependencyInstaller.sh
      # sed -i 's/_installOrTools "debian" "${version}"/_installOrTools "debian" "11"/g' ./etc/DependencyInstaller.sh || :

      ## TT09: Force or-tools 9.11.4210 for debian 12 support
      if [[ "$VSE_VERSION" = "TT09" ]]; then
        sed -i 's/9[.]5/9.11/g' ./etc/DependencyInstaller.sh
        sed -i 's/2237/4210/g' ./etc/DependencyInstaller.sh
        sed -i 's/md5sum/# md5sum/g' ./etc/DependencyInstaller.sh
      fi

      # Use the built-in dependency installer:
      /bin/bash -c "source $VENV_ROOT/bin/activate && ./etc/DependencyInstaller.sh"

      ## Build OpenROAD
      # Note: we don't use system STA since OpenROAD depends on a different version
      # and currently OpenLane == 2.1.8 builds it seperately and puts it ahead in the PATH
      mkdir -p build/release
      cmake -S $OPENROAD_ROOT -B $OPENROAD_ROOT/build \
        -DCMAKE_INSTALL_PREFIX=$OPENROAD_ROOT/build/release \
        -DTCL_HEADER=/usr/include/tcl8.6/tcl.h \
        -DTCL_LIBRARY=/usr/lib/x86_64-linux-gnu/libtcl.so \
        -DUSE_SYSTEM_OPENSTA:BOOL=OFF \
        -DCUDD_LIB=$CUDD_ROOT/release/lib/libcudd.a \
        -DCMAKE_CXX_FLAGS="-L$OPENSTA_ROOT/build/release/lib" \
        -DENABLE_TESTS:BOOL=OFF
      cmake --build   $OPENROAD_ROOT/build -j $(nproc)
      cmake --install $OPENROAD_ROOT/build
      # grab a copy of or-tools placed in /opt
      cp -r /opt/or-tools $ORTOOL_ROOT
      touch .built
    }
    popd # OPENROAD_ROOT
  fi


  #
  # OpenLane2
  echo "[ol2:$VSE_VERSION] OpenLane2: [$OPENLANE_ROOT:$OPENLANE2_TAG]"
  if [[ ! -d $OPENLANE_ROOT ]]; then
    git clone -b $OPENLANE2_TAG https://github.com/efabless/openlane2 $OPENLANE_ROOT
    /bin/bash -c "source $VENV_ROOT/bin/activate && python3 -m pip install poetry"
  fi
  if [[ "$VSE_VERSION" = "TT08" ]]; then
    ## Patching not required post tt08, changes merged (for now)
    wget -O $VOLUME_ROOT/toolchain/openlane2.patch \
      'https://github.com/TinyTapeout/tinytapeout-09/raw/main/patches/openlane2.patch'
    git -C $OPENLANE_ROOT apply $VOLUME_ROOT/toolchain/openlane2.patch
  fi
  pushd $OPENLANE_ROOT
  {
    /bin/bash -c "source $VENV_ROOT/bin/activate && python3 -m poetry install"
  }
  popd


  #
  # PDK (Via Volare)
  echo "[ol2:$VSE_VERSION] PDK: [$PDK:$PDK_VERSION:$PDK_ROOT]"
  if [[ ! -x $(which volare) ]]; then
    /bin/bash -c "source $VENV_ROOT/bin/activate && pip3 install volare"
  fi
  /bin/bash -c "source $VENV_ROOT/bin/activate && python3 -m volare fetch  $PDK_VERSION"
  /bin/bash -c "source $VENV_ROOT/bin/activate && python3 -m volare enable $PDK_VERSION"


  #
  # Verilator
  echo "[ol2:$VSE_VERSION] Verilator [$VERILATOR_ROOT]"
  if [[ ! -d $VERILATOR_ROOT ]]; then
    git clone https://github.com/verilator/verilator $VERILATOR_ROOT
  fi
  if [[ ! -f $VERILATOR_ROOT/.built ]]; then
    pushd $VERILATOR_ROOT
    {
      autoconf
      ./configure
      make -j $(nproc)
      touch .built
    }
    popd
  fi

  # Done
  echo "[ol2:$VSE_VERSION] Done"
  touch $VOLUME_ROOT/.built
fi

echo "[ol2] stalling ($STALL) seconds"
sleep $STALL
