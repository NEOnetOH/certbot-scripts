#!/bin/bash

#  .SYNOPSIS
#  Converts renewed certificate from PEM format to PKCS#12.
#
#  .DESCRIPTION
#  Used by certbot upon successful renewal of certificates. Pulls config from deploy.json file including output directory and file name.
#  Password is randomly generated alphanumeric with 20 characters.
#
#  .REQUIREMENTS
#  RENEWED_DOMAINS and RENEWED_LINEAGE must be set prior to run time.
#  deploy.json must exist and be configured for CPKCS#12.
#
#  .EXAMPLE
#  # RENEWED_DOMAINS=demo.neonet.org RENEWED_LINEAGE=/etc/letsencrypt/live/demo.neonet.org ./02-pkcs12.sh
#
#  .NOTES
#  Created 2025-11-26 by Nate Coffey
#
#  .EXITCODES
#  1 - Initialization Error
#  2 - Missing JSON Key
#  3 - API Failure

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/certbot-deploy.log
}

log "=== Certbot PKCS12 Deploy Hook Started ==="

if [[ -z "$RENEWED_LINEAGE" ]]; then
  log "ERROR: RENEWED_LINEAGE environment variable not set"
  exit 1
fi

if [[ -z "$RENEWED_DOMAINS" ]]; then
  log "ERROR: RENEWED_DOMAINS environment variable not set"
  exit 1
fi

if [[ ! -f "$RENEWED_LINEAGE/deploy.json" ]]; then
  log "ERROR: deploy.json does not exist"
  exit 1
fi


jq -e '.pkcs12' "$RENEWED_LINEAGE/deploy.json" > /dev/null 2>&1
if [ $? -eq 0 ]; then
  # Create array from RENEWED_DOMAINS
  DOMAINS=($RENEWED_DOMAINS)
  
  REQUIRED_KEYS=(
    "pkcs12.pfxPath"
  )
  MISSING_KEYS=()
  
  for key in "${REQUIRED_KEYS[@]}"; do
    if ! jq -e ".$key" "$RENEWED_LINEAGE/deploy.json" > /dev/null 2>&1; then
      MISSING_KEYS+=("$key")
    fi
  done
  
  if [ ${#MISSING_KEYS[@]} -gt 0 ]; then
    log "ERROR: The following keys are missing from deploy.json: ${MISSING_KEYS[*]}"
    exit 2
  fi

  # Set variables from deploy.json
  PFX_DIR=$(jq -r .pkcs12.pfxPath "$RENEWED_LINEAGE/deploy.json")
  
  # Check if pfxFile is configured, else use the first domain of $RENEWED_DOMAINS
  jq -e '.pkcs12.pfxFile' "$RENEWED_LINEAGE/deploy.json" > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    PFX_FILE=$PFX_DIR/$(jq -r .pfxFile "$RENEWED_LINEAGE/deploy.json")
  else
    PFX_FILE=$PFX_DIR/"${DOMAINS[0]}.pfx"
  fi

  # Fall back to root as default user if unset
  jq -e '.pkcs12.pfxUser' "$RENEWED_LINEAGE/deploy.json" > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    PFX_USER=$(jq -r .pkcs12.pfxUser "$RENEWED_LINEAGE/deploy.json")
  else
    PFX_USER=root
  fi

  # Fall back to root as default group if unset
  jq -e '.pkcs12.pfxGroup' "$RENEWED_LINEAGE/deploy.json" > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    PFX_GROUP=$(jq -r '.pkcs12.pfxGroup' "$RENEWED_LINEAGE/deploy.json")
  else
    PFX_GROUP=root
  fi
  
  # Fall back to 440 as default mode if unset
  jq -e '.pkcs12.pfxMode' "$RENEWED_LINEAGE/deploy.json" > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    PFX_MODE=$(jq -r '.pkcs12.pfxMode' "$RENEWED_LINEAGE/deploy.json")
  else
    PFX_MODE="440"
  fi
  
  FULLCHAIN_FILE="$RENEWED_LINEAGE/fullchain.pem"
  PRIVKEY_FILE="$RENEWED_LINEAGE/privkey.pem"
  CERT_FILE="$RENEWED_LINEAGE/cert.pem"
  CHAIN_FILE="$RENEWED_LINEAGE/chain.pem"

  # Generate 20-char alphanumeric password
  EXPORTPASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)

  # Store $EXPORTPASS to deploy.json for further use, using a temp file to avoid injection issues
  jq --arg pass "$EXPORTPASS" '.pkcs12.pfxPass = $pass' "$RENEWED_LINEAGE/deploy.json" > "$RENEWED_LINEAGE/deploy.tmp"
  mv "$RENEWED_LINEAGE/deploy.tmp" "$RENEWED_LINEAGE/deploy.json"

  openssl pkcs12 -export -inkey $PRIVKEY_FILE -in $FULLCHAIN_FILE -out $PFX_FILE -passout pass:$EXPORTPASS

  chown $PFX_USER:$PFX_GROUP $PFX_FILE
  chmod $PFX_MODE $PFX_FILE

  log "=== Certbot PKCS12 Deploy Hook Completed Successfully ==="
else
  log "=== Certbot PKCS12 Config Not Found, Skipping ==="
fi