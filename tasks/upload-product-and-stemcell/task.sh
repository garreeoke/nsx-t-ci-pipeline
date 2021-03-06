#!/bin/bash -eu

# Should the slug contain more than one product, pick only the first.
FILE_PATH=`find ./pivnet-product -name *.pivotal | sort | head -1`
om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
         -u $OPSMAN_USERNAME \
         -p $OPSMAN_PASSWORD \
         -k --request-timeout 3600 \
         upload-product -p $FILE_PATH


# Checking for already cached stemcell file .. not sure how this would be true?
SC_FILE_PATH=$(find . -name "bosh*.tgz" | sort | head -1 || true)
if [ "$SC_FILE_PATH" != "" ]; then
  echo "Uploading cached stemcell: $SC_FILE_PATH to Ops Mgr"
  om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
          -u $OPSMAN_USERNAME \
          -p $OPSMAN_PASSWORD \
          -k --request-timeout 3600 \
          upload-stemcell -s $SC_FILE_PATH
  exit 0
fi

# GET FROM META_DATA
STEMCELL_VERSION_FROM_PRODUCT_METADATA=""
if [ -e "./pivnet-product/metadata.json" ]; then
  echo "Reading metadata.json:"
  METADATA_FROM_FILE=$(cat ./pivnet-product/metadata.json)
  echo "$METADATA_FROM_FILE" 
  STEMCELL_VERSION_FROM_PRODUCT_METADATA=$(
    cat ./pivnet-product/metadata.json |
    jq --raw-output \
      '
      [
        .Dependencies[]
        | select(.Release.Product.Name | contains("Stemcells"))
        | .Release.Version
      ]
      | map(split(".") | map(tonumber))
      | transpose | transpose
      | max // empty
      | map(tostring)
      | join(".")
      '
  )
fi

echo "Version from metadata: $STEMCELL_VERSION_FROM_PRODUCT_METADATA"

# Get same data from tile?
tile_metadata=$(unzip -l pivnet-product/*.pivotal | grep "metadata" | grep "ml$" | awk '{print $NF}')
STEMCELL_VERSION_FROM_TILE=$(unzip -p pivnet-product/*.pivotal $tile_metadata | grep -A5 "stemcell_criteria:"  \
                                  | grep "version:" | grep -Ei "[-+]?[0-9]*\.?[0-9]*" | awk '{print $NF}' | sed "s/'//g;s/\"//g" )

STEMCELL_OS_FROM_TILE=$(unzip -p pivnet-product/*.pivotal $tile_metadata | grep -A5 "stemcell_criteria:"  \
                                  | grep "os:" | awk '{print $NF}' | sed "s/'//g;s/\"//g" )

echo "Version from tile: $STEMCELL_VERSION_FROM_TILE"

# Seems like only checking for the tile versions ... 
if [ "$STEMCELL_OS_FROM_TILE" == "" -o "$STEMCELL_VERSION_FROM_TILE" == "" ]; then
  echo "No stemcell dependency declared or no version specified in tile, skipping stemcell upload!"
  exit 0
fi

# Bring function in
source nsx-t-ci-pipeline/functions/upload_stemcell.sh

# Only send one of them if are the same or if the major versions are the same
if [ $STEMCELL_VERSION_FROM_PRODUCT_METADATA == $STEMCELL_VERSION_FROM_TILE ]; then
  upload_stemcells "$STEMCELL_OS_FROM_TILE" "$STEMCELL_VERSION_FROM_TILE"
else 
  upload_stemcells "$STEMCELL_OS_FROM_TILE" "$STEMCELL_VERSION_FROM_TILE $STEMCELL_VERSION_FROM_PRODUCT_METADATA"
fi
