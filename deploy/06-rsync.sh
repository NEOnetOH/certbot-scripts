#!/bin/bash

#  .SYNOPSIS
#  Installs renewed certificate to Technitium DNS Web Service
#
#  .DESCRIPTION
#  Used by certbot upon successful renewal of certificates. Pulls config from deploy.json file including credentials to
#  establish an API call to pull an API token, and update DNS server settings to reload certificate.
#
#  .REQUIREMENTS
#  RENEWED_DOMAINS and RENEWED_LINEAGE must be set prior to run time.
#  deploy.json must exist and be configured for Technitium.
#
#  .EXAMPLE
#  # RENEWED_DOMAINS=demo.neonet.org RENEWED_LINEAGE=/etc/letsencrypt/live/demo.neonet.org ./04-technitium.sh
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

log "=== Certbot Rsync Started ==="

if [[ -z "$RENEWED_LINEAGE" ]]; then
  log "ERROR: RENEWED_LINEAGE environment variable not set"
  exit 1
fi

if [[ -z "$RENEWED_DOMAINS" ]]; then
  log "ERROR: RENEWED_DOMAINS environment variable not set"
  exit 1
fi

jq -e '.rsync' "$RENEWED_LINEAGE/deploy.json" > /dev/null 2>&1
if [ $? -eq 0 ]; then
  # Create array from RENEWED_DOMAINS
  DOMAINS=($RENEWED_DOMAINS)

  REQUIRED_KEYS=(
    "rsync.host"
    "rsync.user"
    "rsync.pass"
    "rsync.dstPath"
    "rsync.dstPubFile"
    "rsync.dstPubUser"
    "rsync.dstPubGroup"
    "rsync.dstPrivFile"
    "rsync.dstPrivUser"
    "rsync.dstPrivGroup"
  )
  MISSING_KEYS=()

  # Loop through all REQUIRED_KEYS and verify they exist in deploy.json
  for key in "${REQUIRED_KEYS[@]}"; do
    if ! jq -e ".$key" "$RENEWED_LINEAGE/deploy.json" > /dev/null 2>&1; then
      MISSING_KEYS+=("$key")
    fi
  done

  # Output any MISSING_KEYS and exit out if present
  if [ ${#MISSING_KEYS[@]} -gt 0 ]; then
    log "ERROR: The following keys are missing from deploy.json: ${MISSING_KEYS[*]}"
    exit 2
  fi

  # Set variables from deploy.json  
  PFX_DIR=$(jq -r .pkcs12.pfxPath "$RENEWED_LINEAGE/deploy.json")
  PFX_PASS=$(jq -r .pkcs12.pfxPass "$RENEWED_LINEAGE/deploy.json")
  TECHNITIUMUSER=$(jq -r .technitium.user "$RENEWED_LINEAGE/deploy.json")
  TECHNITIUMPASS=$(jq -r .technitium.pass "$RENEWED_LINEAGE/deploy.json")
  
  # Check if .pkcs12.pfxFile is configured, else use the first domain of $RENEWED_DOMAINS
  jq -e '.pkcs12.pfxFile' "$RENEWED_LINEAGE/deploy.json" > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    PFX_FILE=$PFX_DIR/$(jq -r .pfxFile "$RENEWED_LINEAGE/deploy.json")
  else
    PFX_FILE=$PFX_DIR/"${DOMAINS[0]}.pfx"
  fi

  # Retrieve session token from Technitium
  SESSION_TOKEN=$(curl -X POST --insecure -H 'Content-Type: application/x-www-form-urlencoded' "https://127.0.0.1:443/api/user/login?user=$TECHNITIUMUSER&pass=$TECHNITIUMPASS" 2>/dev/null | jq -r .token)
  if [ -z $SESSION_TOKEN ] || [ "$SESSION_TOKEN" = "null" ]; then
    log "ERROR: Failed to obtain a session token from Technitium DNS"
    exit 3
  else
    curl -X POST --insecure -H 'Content-Type: application/x-www-form-urlencoded' "https://127.0.0.1:443/api/settings/set?token=$SESSION_TOKEN&webServiceTlsCertificatePath=$PFX_FILE&webServiceTlsCertificatePassword=$PFX_PASS" >/dev/null 2>&1
  fi

  log "=== Certbot Rsync Completed Successfully ==="
else
  log "=== Certbot Rsync Config Not Found, Skipping ==="
fi