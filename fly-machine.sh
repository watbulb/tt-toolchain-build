#!/bin/bash
# fly.io constrained instance helper wrapper
# Dayton Pidhirney
set -e -o pipefail

# Default app target config
INSTANCE_DEFAULT_CONFIG="ol2"
# Default prefix for all apps
INSTANCE_PREFIX=${INSTANCE_PREFIX:-"main"}
# Default instance cores
INSTANCE_DEFAULT_CORES=${INSTANCE_DEFAULT_CORES:-"8"}
# Default instance type
INSTANCE_DEFAULT_TYPE="performance-${INSTANCE_DEFAULT_CORES}x"

# Better interrupt handling
CMDLINE_OPTIONS="${CMDLINE_OPTIONS} tsc=noirqtime skew_tick=1 nohz=on no-steal-acc"

# Create a base app image which all other
# app instances are based off of. Only runs once.
check_build_base() {
    if ! fly image show -a "$INSTANCE_DEFAULT_CONFIG-base" >/dev/null 2>&1; then
        fly app create "$INSTANCE_DEFAULT_CONFIG-base"
        fly deploy \
            --verbose \
            --config /dev/null \
            --app "$INSTANCE_DEFAULT_CONFIG-base" \
            --build-only \
            --dockerfile ./docker/base.dockerfile \
            --image-label "latest" \
            --push || fly app destroy "$INSTANCE_DEFAULT_CONFIG-base" -y
    fi
}

# $1: app_name
# $2: state
wait_machine_state() {
  while true; do
      if [[ "$(fly machine list -j -a $1 | jq -r '.[0].state')" != $2 ]]; then
          sleep 1
          echo -n '.'
      else
          echo
          break
      fi
  done
}

if [[ $# -gt 1 || "$1" = "list" ]]; then
  declare -a CURRENT_APPS=$(
    fly app list | grep $INSTANCE_PREFIX | grep -v base | tr -d ' ' | tr '\t' ','
  )
fi

# Parse options:
case $1 in
    -h|help)
        echo "$0 [command] [options]"
        echo "Commands:"
        echo "* create  [type]"
        echo "* scale   <name> <count>"
        echo "* update  <name>"
        echo "* destroy <name>"
        echo "* start   <name>"
        echo "* stop    <name>"
        echo "* ssh     <name>"
        echo "* list"
        ;;
    create)
        # ensure the base is built
        check_build_base

        shift
        app_config=$1
        if [[ "$app_config" = "" ]]; then
            app_config=$INSTANCE_DEFAULT_CONFIG
        elif [[ ! -f ./docker/$app_config.dockerfile ]]; then
            echo "unknown app config: $app_config"
            echo "please choose from:"
            for config in $(ls -p docker/*.dockerfile | grep -v base | cut -d/ -f2 | cut -d. -f1); do
                echo " - $config"
            done
            exit 1
        fi

        app_name="$app_config-$INSTANCE_PREFIX"
        app_volname="$(echo $app_name | tr '-' '_')"

        # Create app config from base
        fly apps create $app_name

        # Build app config image
        fly deploy \
            --verbose \
            --config /dev/null \
            --app $app_name \
            --build-only \
            --regions iad \
            --vm-size $INSTANCE_DEFAULT_TYPE \
            --dockerfile "./docker/$app_config.dockerfile" \
            --image-label "latest" \
            --push || fly app destroy $app_name -y

        # Create volume for app instance
        fly volume create -y \
            --app $app_name \
            --size 30 \
            $app_volname

        # Create machine app instance
        fly machine create "registry.fly.io/$app_name:latest" \
            --verbose \
            --name "$app_name-${#CURRENT_APPS[@]}-machine" \
            --app $app_name \
            --region iad \
            --port 1122:22 \
            --vm-size $INSTANCE_DEFAULT_TYPE \
            --kernel-arg "$CMDLINE_OPTIONS" \
            --volume $app_volname:/mnt/output:rw

        # Wait for machine to be created
        wait_machine_state $app_name stopped

        # Start app instance
        fly machine start -a $app_name

        # Wait for machine to be deployed
        wait_machine_state $app_name started
        ;;
    scale)
        shift
        app_name=$1
        if [[ "$app_name" = "" ]]; then
            echo "scale what? (run list command)"
            exit 1
        fi
        shift
        app_scale=$1
        if [[ $app_scale -le 0 ]]; then
            echo "invalid app scale value"
            exit 1
        fi
        fly scale count -a $app_name $app_scale
        ;;
    update)
        shift
        app_name=$1
        if [[ "$app_name" = "" ]]; then
            echo "update what? (run list command)"
            exit 1
        fi
        app_config=$(echo $app_name | cut -d- -f1)

        # Re-build app config image
        fly deploy \
            --verbose \
            --config /dev/null \
            --app $app_name \
            --dockerfile "./docker/$app_config.dockerfile" \
            --image-label "latest" \
            --build-only \
            --push

        # Update machines in app
        fly machine update -y \
            --verbose \
            --app $app_name \
            --image "registry.fly.io/$app_name:latest" \
            --metadata "DEPLOY_ID=$RANDOM"
        wait_machine_state $app_name started
        ;;
    destroy)
        shift
        app_name=$1
        if [[ "$app_name" = "" ]]; then
            echo "destroy what? (run list command)"
            exit 1
        fi
        fly app destroy $app_name ${@:2}
        ;;
    start)
        shift
        app_name=$1
        if [[ "$app_name" = "" ]]; then
            echo "start what? (run list command)"
            exit 1
        fi
        fly machine start -a $app_name
        wait_machine_state $app_name started
        ;;
    stop)
        shift
        app_name=$1
        if [[ "$app_name" = "" ]]; then
            echo "stop what? (run list command)"
            exit 1
        fi
        fly machine stop -a $app_name
        wait_machine_state $app_name stopped
        ;;
    ssh)
        shift
        app_name=$1
        if [[ "$app_name" = "" ]]; then
            echo "ssh what? (run list command)"
            exit 1
        fi
        fly ssh console -a $app_name
        ;;
    list)
        if [[ "${CURRENT_APPS[@]}" = "" ]]; then
            echo "no machines currently"
            exit 0
        fi
        for app in ${CURRENT_APPS[@]}; do
             app_name=$(echo $app | cut -d, -f1)
            app_state=$(echo $app | cut -d, -f3)
            echo "$app_name:$app_state"
        done
        ;;
    *)
        echo 'Unknown option: (See help using `-h` or simply `help`)'
        exit 1
        ;;
esac
exit 0
