#!/usr/bin/env bash

: "${EXPOSE_TCP:=false}"

cat <<-EOF > "$LIGHTNINGD_DATA/config"
${LIGHTNINGD_OPT}
EOF

: "${EXPOSE_TCP:=false}"

LIGHTNINGD_NETWORK_NAME=""
NBXPLORER_DATA_DIR_NAME=""

if [ "$LIGHTNINGD_NETWORK" == "mainnet" ]; then
    NBXPLORER_DATA_DIR_NAME="Main"
elif [ "$LIGHTNINGD_NETWORK" == "testnet" ]; then
    NBXPLORER_DATA_DIR_NAME="TestNet"
elif [ "$LIGHTNINGD_NETWORK" == "regtest" ]; then
    NBXPLORER_DATA_DIR_NAME="RegTest"
else
    echo "Invalid value for LIGHTNINGD_NETWORK (should be mainnet, testnet or regtest)"
    exit
fi

if [ "$LIGHTNINGD_CHAIN" == "btc" ] && [ "$LIGHTNINGD_NETWORK" == "mainnet" ]; then
    LIGHTNINGD_NETWORK_NAME="bitcoin"
elif [ "$LIGHTNINGD_CHAIN" == "btc" ] && [ "$LIGHTNINGD_NETWORK" == "testnet" ]; then
    LIGHTNINGD_NETWORK_NAME="testnet"
elif [ "$LIGHTNINGD_CHAIN" == "btc" ] && [ "$LIGHTNINGD_NETWORK" == "regtest" ]; then
    LIGHTNINGD_NETWORK_NAME="regtest"
elif [ "$LIGHTNINGD_CHAIN" == "ltc" ] && [ "$LIGHTNINGD_NETWORK" == "mainnet" ]; then
    LIGHTNINGD_NETWORK_NAME="litecoin"
elif [ "$LIGHTNINGD_CHAIN" == "ltc" ] && [ "$LIGHTNINGD_NETWORK" == "testnet" ]; then
    LIGHTNINGD_NETWORK_NAME="litecoin-testnet"
else
    echo "Invalid combinaion of LIGHTNINGD_NETWORK and LIGHTNINGD_CHAIN. LIGHTNINGD_CHAIN should be btc or ltc. LIGHTNINGD_NETWORK should be mainnet, testnet or regtest."
    echo "ltc regtest is not supported"
    exit
fi

echo "network=$LIGHTNINGD_NETWORK_NAME" >> "$LIGHTNINGD_DATA/config"
echo "network=$LIGHTNINGD_NETWORK_NAME added in $LIGHTNINGD_DATA/config"

if [[ $TRACE_TOOLS == "true" ]]; then
echo "Trace tools detected, installing sample.sh..."
echo 0 > /proc/sys/kernel/kptr_restrict
echo "
# This script will take one minute of stacktrace samples and plot it in a flamegraph
LIGHTNING_PROCESSES=\$(pidof lightningd lightning_chann lightning_closi lightning_gossi lightning_hsmd lightning_oncha lightning_openi lightning_hsmd lightning_gossipd lightning_channeld  | sed -e 's/\s/,/g')
perf record -F 99 -g -a --pid \$LIGHTNING_PROCESSES -o \"$TRACE_LOCATION/perf.data\" -- sleep 60
perf script -i \"$TRACE_LOCATION/perf.data\" > \"$TRACE_LOCATION/output.trace\"
cd /FlameGraph
./stackcollapse-perf.pl \"$TRACE_LOCATION/output.trace\" > \"$TRACE_LOCATION/output.trace.folded\"
svg=\"$TRACE_LOCATION/\$((\$SECONDS / 60))min.svg\"
./flamegraph.pl \"$TRACE_LOCATION/output.trace.folded\" > \"\$svg\"
rm \"$TRACE_LOCATION/perf.data\"
rm \"$TRACE_LOCATION/output.trace\"
rm \"$TRACE_LOCATION/output.trace.folded\"
echo \"flamegraph taken: \$svg\"
" > /usr/bin/sample.sh
chmod +x /usr/bin/sample.sh

echo "
# This script will run sample.sh after 2 min then every 10 minutes
sleep 120
sample.sh
while true; do
    sleep 300
    . sample.sh
done
" > /usr/bin/sample-loop.sh
chmod +x /usr/bin/sample-loop.sh
fi

if [[ "${LIGHTNINGD_ANNOUNCEADDR}" ]]; then
    # This allow to strip this parameter if LIGHTNINGD_ANNOUNCEADDR is not a proper domain
    LIGHTNINGD_EXTERNAL_HOST=$(echo ${LIGHTNINGD_ANNOUNCEADDR} | cut -d ':' -f 1)
    LIGHTNINGD_EXTERNAL_PORT=$(echo ${LIGHTNINGD_ANNOUNCEADDR} | cut -d ':' -f 2)
    if [[ "$LIGHTNINGD_EXTERNAL_HOST" ]] && [[ "$LIGHTNINGD_EXTERNAL_PORT" ]]; then
        echo "announce-addr=$LIGHTNINGD_ANNOUNCEADDR" >> "$LIGHTNINGD_DATA/config"
        echo "announce-addr=$LIGHTNINGD_ANNOUNCEADDR added to $LIGHTNINGD_DATA/config"
    fi
fi

if [[ "${LIGHTNINGD_ALIAS}" ]]; then
    # This allow to strip this parameter if LND_ALIGHTNINGD_ALIASLIAS is empty or null, and truncate it
    LIGHTNINGD_ALIAS="$(echo "$LIGHTNINGD_ALIAS" | cut -c -32)"
    echo "alias=$LIGHTNINGD_ALIAS" >> "$LIGHTNINGD_DATA/config"
    echo "alias=$LIGHTNINGD_ALIAS added to $LIGHTNINGD_DATA/config"
fi

if [[ "${LIGHTNINGD_NBXPLORER_ROOT}" ]]; then
    NBXPLORER_READY_FILE="${LIGHTNINGD_NBXPLORER_ROOT}/${NBXPLORER_DATA_DIR_NAME}/${LIGHTNINGD_CHAIN}_fully_synched"
    echo "Waiting $NBXPLORER_READY_FILE to be signaled by nbxplorer..."
    while [ ! -f "$NBXPLORER_READY_FILE" ]; do sleep 1; done
    echo "The chain is fully synched"
fi

if [ "$EXPOSE_TCP" == "true" ]; then
    set -m
    lightningd "$@" &
    echo "C-Lightning starting"
    while read -r i; do if [ "$i" = "lightning-rpc" ]; then break; fi; done \
    < <(inotifywait  -e create,open --format '%f' --quiet "$LIGHTNINGD_DATA" --monitor)
    echo "C-Lightning started"
    echo "C-Lightning started, RPC available on port $LIGHTNINGD_RPC_PORT"

    socat "TCP4-listen:$LIGHTNINGD_RPC_PORT,fork,reuseaddr" "UNIX-CONNECT:$LIGHTNINGD_DATA/lightning-rpc" &
    fg %-
else
    exec lightningd "$@"
fi
