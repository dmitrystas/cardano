#!/bin/bash 

CADDR=${CADDR:=$( which cardano-address )}
[[ -z "$CADDR" ]] && { echo "cardano-address cannot be found, exiting..." >&2 ; exit 127; }

CCLI=${CCLI:=$( which cardano-cli )}
[[ -z "$CCLI" ]] && { echo "cardano-cli cannot be found, exiting..." >&2 ; exit 127; }

BECH32=${BECH32:=$( which cardano-cli )}
[[ -z "$BECH32" ]] && { echo "bech32 cannot be found, exiting..." >&2 ; exit 127; }

# Only 24-word length mnemonic is supported only
[[ "$#" -ne 2 ]] && {
        echo "usage: `basename $0` <change index e.g. 0/1 external/internal>  <ouptut dir> <24-word length mnemonic>" >&2 
        exit 127
}

GEN_FILE=${GEN_FILE:="/opt/cardano/testnet/files/testnet-shelley-genesis.json"}
[[ ! -f "$GEN_FILE" ]] && { echo "genesis file does not exit, exiting..." >&2 ; exit 127; }

IDX=$1
shift 

OUT_DIR="$1"
[[ -e "$OUT_DIR"  ]] && {
        echo "The \"$OUT_DIR\" is already exist delete and run again." >&2 
        exit 127
} || mkdir -p "$OUT_DIR" && pushd "$OUT_DIR" >/dev/null

shift
MNEMONIC="paste 15-24 words Shelley mnemonic here"

# Generate the master key from mnemonics and derive the stake account keys 
# as extended private and public keys (xpub, xprv)
echo "$MNEMONIC" |\
"$CADDR" key from-recovery-phrase Shelley > root.prv

cat root.prv |\
"$CADDR" key child 1852H/1815H/0H/2/0 > stake.xprv

cat root.prv |\
"$CADDR" key child 1852H/1815H/0H/$IDX/0 > payment.xprv

# XPrv/XPub conversion to normal private and public key, keep in mind the 
# keypars are not a valind Ed25519 signing keypairs.
NW=$(jq '.networkId' -r "$GEN_FILE")
NW_ID=$(jq '.networkMagic' -r "$GEN_FILE")

echo "Generating $NW wallet..."
if [ "$NW" == "Testnet" ]; then
  NETWORK=0
  MAGIC="--testnet-magic $NW_ID"
  CONV="bech32 | bech32 addr_test"
else
  NETWORK=1
  MAGIC="--mainnet"
  CONV="cat"
fi

cat payment.xprv |\
"$CADDR" key public --with-chain-code | tee payment.xpub |\
"$CADDR" address payment --network-tag $NETWORK |\
"$CADDR" address delegation $(cat stake.xprv | "$CADDR" key public --with-chain-code | tee stake.xpub) |\
tee base.addr_candidate |\
"$CADDR" address inspect
echo "Generated from 1852H/1815H/0H/$IDX/0"
if [  "$NW" == "Testnet" ]; then
  cat base.addr_candidate | bech32 | bech32 addr_test > base.addr_candidate_test
  mv base.addr_candidate_test base.addr_candidate
fi
cat base.addr_candidate 
echo


SESKEY=$( cat stake.xprv | bech32 | cut -b -128 )$( cat stake.xpub | bech32)
PESKEY=$( cat payment.xprv | bech32 | cut -b -128 )$( cat payment.xpub | bech32)

cat << EOF > stake.skey
{
    "type": "StakeExtendedSigningKeyShelley_ed25519_bip32",
    "description": "",
    "cborHex": "5880$SESKEY"
}
EOF

cat << EOF > payment.skey
{
    "type": "PaymentExtendedSigningKeyShelley_ed25519_bip32",
    "description": "Payment Signing Key",
    "cborHex": "5880$PESKEY"
}
EOF

"$CCLI" key verification-key --signing-key-file stake.skey --verification-key-file stake.evkey
"$CCLI" key verification-key --signing-key-file payment.skey --verification-key-file payment.evkey

"$CCLI" key non-extended-key --extended-verification-key-file payment.evkey --verification-key-file payment.vkey
"$CCLI" key non-extended-key --extended-verification-key-file stake.evkey --verification-key-file stake.vkey


"$CCLI" stake-address build --stake-verification-key-file stake.vkey $MAGIC > stake.addr
"$CCLI" address build --payment-verification-key-file payment.vkey $MAGIC > payment.addr
"$CCLI" address build \
    --payment-verification-key-file payment.vkey \
    --stake-verification-key-file stake.vkey \
    $MAGIC > base.addr

echo "Important the base.addr and the base.addr_candidate must be the same"
diff -s base.addr base.addr_candidate
cat base.addr base.addr_candidate

popd >/dev/null
