## TinyTapeout Local Linux Toolchain Builder

**Current Version: TT08**

**Disk Requirement: ~13-15GB**

**Linux Flavor: Debian 12**

### Current Versions (TT08):


| Tool / Component    | Value                                        |
|---------------------|----------------------------------------------|
| `NETGEN_TAG`        | `fix-assign-implicit-lhs`                    |
| `OPENSTA_TAG`       | `tt`                                         |
| `TT_SUPPORT_TAG`    | `tt08`                                       |
| `MAGIC_SUPPORT_TAG` | `HEAD`                                       |
| `SYNLIG_TAG`        | `HEAD`                                       |
| `VERILATOR_TAG`     | `HEAD`                                       |
| `OPENROAD_TAG`      | `a515fc6cc97a7092efd51a28c1414e2fb4e53413`   |
| `OPENLANE2_TAG`     | `2.0.7`                                      |
| `PDK_VERSION`       | `bdc9412b3e468c102d01b7cf6337be06ec6e9c9a`   |
| `PDK`               | `sky130A`                                    |


Please note the following projects come from the following sources specifically for TT08:
- **Netgen**:  https://github.com/smunaut/netgen
- **OpenSTA**: https://github.com/smunaut/OpenSTA
- **OpenLane2**: We apply TT08 [`openlane2.patch`](https://github.com/TinyTapeout/tinytapeout-08/blob/main/patches/openlane2.patch)

### Build Docker

_Note:_ This step will build the full toolchain environment and workspace to the volume path. This only needs to be done once.

```bash
docker build -t ol2-base -f docker/base.dockerfile .
docker build -t ol2-main -f docker/ol2.dockerfile  .
mkdir -p vol
docker run  -it ol2-main --volume $PWD/vol:/mnt/output
# Once build has completed, check:
ls -la $PWD/vol/.built
```

### Run Docker Environment

```bash
docker run -it ol2-main --volume $PWD/vol:/mnt/output
```

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
$ ./fly-machine.sh create ol2

# List machines
$ ./fly-machine.sh list
ol2-main:deployed

# Start machine
$ ./fly-machine.sh start ol2-main

# Access machine
$ ./fly-machine.sh ssh ol2-main

# If you want X11 and SCP abilities ($2+ per month):
$ fly ip allocate-v4 -a ol2-main
$ ssh -Snone -X -p 1122 root@ol2-main.fly.dev
```

**Updating the machine performance:**

```bash
$ fly machine update -a ol2-main --vm-size="shared-cpu-8x" --vm-memory=8192
```

**Rebuilding/updating the toolchain:**

Simply update any part of the docker files, and run:

```bash
$ ./fly-machine.sh update ol2-main
```

### TODO:

- [ ] Extract docker build to standard bash scripts