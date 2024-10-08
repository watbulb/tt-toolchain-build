## TinyTapeout Local Linux Toolchain Builder

![docker-build](https://github.com/watbulb/tt-toolchain-build/actions/workflows/docker-image.yml/badge.svg)

**Current Version: TT09**

**Disk Requirement: ~13-15GB**

**Linux Flavor: Debian 12**

### Current Versions (TT09)

Default **VOLUME_ROOT**: `/mnt/output` 

| Repository Link                                              | Tag                                        | Notes                                                                                               |
---------------------------------------------------------------|--------------------------------------------|-----------------------------------------------------------------------------------------------------|
[tt-support-tools](https://github.com/TinyTapeout/tt-support-tools) | `tt09`                                | TinyTapeout Project Tools                                                                           |
[Verilator](https://github.com/verilator/verilator)            | Latest as of tag date                      | (System)Verilog Elaboration and Simulation (+VPI)                                                   |
[icarus](https://github.com/verilator/verilator)               | Latest as of tag date                      | (System)Verilog Elaboration and Simulation (+VPI)                                                   |
[synlig](https://github.com/chipsalliance/synlig)              | Latest as of tag date                      | ChipsAlliance SystemVerilog Support and YoSys                                                       |
[Surelog](https://github.com/chipsalliance/Surelog)            | Latest as of tag date                      | Dependency of Synlig                                                                                |
[Yosys](https://github.com/YosysHQ/yosys)                      | Latest as of tag date                      | Dependency of Synlig                                                                                |
[eqy](https://github.com/YosysHQ/eqy)                          | Latest as of tag date                      | Dependency of Yosys                                                                                 |
[OR-Tools](https://github.com/google/or-tools)                 | 9.11 (for Debian 12)                       | Dependency of OpenROAD                                                                              |
[CUDD](https://github.com/The-OpenROAD-Project/cudd)           | `3.0.0`                                    | Dependency of OpenROAD/OpenSTA                                                                      |
[OpenSTA](https://github.com/The-OpenROAD-Project/OpenSTA)     | `cc9eb1f12a0d5030aebc1f1428e4300480e30b40` | Workaround for OpenLane 2.1.8 ([OpenLane PR #544](https://github.com/efabless/openlane2/pull/544))  |
[OpenROAD](https://github.com/The-OpenROAD-Project/OpenROAD)   | `b16bda7e82721d10566ff7e2b68f1ff0be9f9e38` | Dependency of Openlane2                                                                             |
[OpenLane](https://github.com/efabless/openlane2)              | `2.1.8`                                    | 2.1.8 Requires OpenSTA WAR                                                                          |
[Xschem](https://github.com/StefanSchippers/xschem)            | `adb855db0b32870886c26ed346e4c2f12ccecc56` | Design Schematic Layout                                                                             |
[Magic](https://github.com/RTimothyEdwards/magic)              | Latest as of tag date                      | Physical Layout (Option 1)                                                                          |
[KLayout](https://github.com/RTimothyEdwards/magic)            | ~`29.1`                                    | Physical Layout (Option 2)                                                                          |
[Netgen](https://github.com/smunaut/netgen)                    | `fix-assign-implicit-lhs`                  | LVS                                                                                                 |
[NGSpice](https://sourceforge.net/projects/ngspice/)           | `ngspice-43`                               | Analog Simulation. Uses KLU                                                                         |
[GTKWave](https://salsa.debian.org/electronics-team/gtkwave)   | `3.3.120-1`                                | VCD / XSCHEM RAW Wave Browser                                                                       |
[SkyWater PDK](https://github.com/RTimothyEdwards/open_pdks)   | `bdc9412b3e468c102d01b7cf6337be06ec6e9c9a` | `PDK=sky130A` (waiting for skywater DRC update)                                                     |

>[!NOTE]
>Please note the following projects come from the following non-official sources specifically for TT09:
>- **Netgen**: https://github.com/smunaut/netgen
>- **OpenLane2**: UPDATE: We no longer apply TT08 OpenLane2 patch, as all changes have been merged since: [`openlane2.patch`](https://github.com/TinyTapeout/tinytapeout-08/blob/main/patches/openlane2.patch)

### Build Docker

_Note:_ This step will build the full toolchain environment and workspace to the volume path. This only needs to be done once.

```bash
docker build -t ol2-base -f docker/base.dockerfile .
docker build -t ol2:tt09 -f docker/ol2.dockerfile  .
mkdir -p vol
docker run  -it ol2:tt09 --volume $PWD/vol:/mnt/output
# Once build has completed, check:
ls -la $PWD/vol/.built
```

### Run Docker Environment

```bash
docker run -it ol2:tt09 --volume $PWD/vol:/mnt/output
```

### XPRA (Optional)

Included in the build is a copy of [XPRA](https://xpra.org/index.html).
XPRA allows us to create a simple managed X server daemon which we can run our applications on. Through this we can connect to them remotely
or locally through the docker network. (Be sure to create a docker network you can access if you choose this)

**Usage:**

```
# Start XPRA on localhost:3000
# This creates DISPLAY=:0 on localhost:3000 with `xterm` running (install it)
xpra start --start="xterm" --bind-tcp=localhost:3000

# Run a program on existing display (by display index)
xpra control 0 start "xterm"
xpra control 0 start "magic -rcfile <...>" 

# View your server (Ctrl+P for simple browser)
http://localhost:3000

# Manage connection options (clipboard audio, keyboard, auth, etc)
http://localhost:3000/connect.html

# Shutdown the index 0 daemon
xpra stop 0
```

You should be able to now navigate to `http://localhost:3000` in a web-browser, and access any app you run on the server.

![image](https://github.com/user-attachments/assets/4cd045bf-2bd2-433b-8e58-5f8ccf3c1508)

---

### Alternative: Run on fly.io

_Note:_ You need an account on https://fly.io, then follow: https://fly.io/docs/flyctl/install/


**Creating the machine:**

```bash
# Place your pubkey
cp ~/.ssh/id_ed25519.pub pubkey/id_ed25519.pub 
# Create the machine
$ export INSTANCE_DEFAULT_CORES=8
$ ./fly-machine.sh -h
$ ./fly-machine.sh create

# List machines
$ ./fly-machine.sh list
ol2-tt09:deployed

# Start machine
$ ./fly-machine.sh start ol2-tt09

# Access machine
$ ./fly-machine.sh ssh ol2-tt09

# If you want X11 and SCP abilities ($2+ per month):
$ fly ip allocate-v4 -a ol2-tt09
$ ssh -Snone -X -p 1122 root@ol2-tt09.fly.dev
```

**Updating the machine performance:**

```bash
$ fly machine update -a ol2-tt09 --vm-size="shared-cpu-8x" --vm-memory=8192
```

**Rebuilding/updating the toolchain:**

Simply update any part of the docker files, and run:

```bash
$ ./fly-machine.sh update ol2-tt09
```

### TODO:

- [ ] Extract docker build to standard bash scripts
