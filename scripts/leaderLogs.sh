#!/usr/bin/env bash

SHOW_ESTIMATED_BLOCKS=true      # true/false - show/hide estimated blocks info

. "$(dirname $0)"/env

byron_slots=$(( SHELLEY_TRANS_EPOCH * BYRON_EPOCH_LENGTH ))

POOL_ID=$(cat ${POOL_FOLDER}/${POOL_NAME}/${POOL_ID_FILENAME})

TIME_LEFT=$(timeUntilNextEpoch)

NONCE_WINDOW=$((EPOCH_LENGTH*3/10))

EPOCH_BLOCKS=$(echo "${EPOCH_LENGTH} * ${ACTIVE_SLOTS_COEFF}" | bc -l | awk '{printf "%.0f\n", $1}')

if [ $TIME_LEFT -lt $NONCE_WINDOW ]
then
    EPOCH_NO=$(($(getEpoch)+1))
    EPOCH_IDENTIFIER="--next"
else
    EPOCH_NO=$(getEpoch)
    EPOCH_IDENTIFIER="--current"
fi

echo ""
echo "Pool: ${POOL_ID}"
echo "Epoch: ${EPOCH_NO}"

if $SHOW_ESTIMATED_BLOCKS
then
    STAKE_SNAPSHOT=$(${CCLI} query stake-snapshot ${NETWORK_IDENTIFIER} --stake-pool-id ${POOL_ID})

    if [ $TIME_LEFT -lt $NONCE_WINDOW ]
    then
        TOTAL_STAKE=$(echo "${STAKE_SNAPSHOT}" | jq .activeStakeMark)
        POOL_STAKE=$(echo ${STAKE_SNAPSHOT} | jq .poolStakeMark)
    else
        TOTAL_STAKE=$(echo ${STAKE_SNAPSHOT} | jq .activeStakeSet)
        POOL_STAKE=$(echo ${STAKE_SNAPSHOT} | jq .poolStakeSet)
    fi

    SIGMA=$(echo "${POOL_STAKE}/${TOTAL_STAKE}" | bc -l | sed 's/^\./0./')
    ESTIMATED_BLOCKS=$(echo "scale=2; ${EPOCH_BLOCKS}*${POOL_STAKE}/${TOTAL_STAKE}" | bc | sed 's/^\./0./')

    echo "Sigma: ${SIGMA}"
    echo "Estimated blocks: ${ESTIMATED_BLOCKS}"
fi

POOL_VRF_SK_FILE="${POOL_FOLDER}/${POOL_NAME}/${POOL_VRF_SK_FILENAME}"

LEADER_SCHEDULE=$(${CCLI} query leadership-schedule ${NETWORK_IDENTIFIER} ${EPOCH_IDENTIFIER} --genesis ${GENESIS_JSON} --stake-pool-id ${POOL_ID} --vrf-signing-key-file ${POOL_VRF_SK_FILE})

BLOCKS=-1

while IFS= read -r line
do
    if [ $BLOCKS -lt 0 ]
    then
        if [[ ${line:0:10} == "----------" ]]
        then
            BLOCKS=0
        fi
    else
        BLOCKS=$((BLOCKS+1))
        SLOT=$(echo "$line" | awk '{print $1}')
        
        SLOT_TIME=$(( ((byron_slots * BYRON_SLOT_LENGTH) / 1000) + ((SLOT-byron_slots) * SLOT_LENGTH) + SHELLEY_GENESIS_START_SEC ))
        SLOT_DATE=$(date +'%Y-%m-%d %H:%M:%S' -d "@${SLOT_TIME}")

        echo "${SLOT_DATE} => Leader for ${SLOT}, Cumulative epoch blocks: ${BLOCKS}"
    fi
done <<< "$LEADER_SCHEDULE"

if [ $BLOCKS -lt 1 ]
then
    echo "No blocks found for epoch ${EPOCH_NO} :("
fi

echo ""
