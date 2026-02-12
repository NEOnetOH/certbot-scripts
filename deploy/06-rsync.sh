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
#  4 - Connection Failure

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
  RSYNC_HOST=$(jq         -r .rsync.host         "$RENEWED_LINEAGE/deploy.json")
  RSYNC_PORT=$(jq         -r .rsync.port         "$RENEWED_LINEAGE/deploy.json")
  RSYNC_USER=$(jq         -r .rsync.user         "$RENEWED_LINEAGE/deploy.json")
  RSYNC_PASS=$(jq         -r .rsync.pass         "$RENEWED_LINEAGE/deploy.json")
  RSYNC_DSTPUBPATH=$(jq   -r .rsync.dstPubPath   "$RENEWED_LINEAGE/deploy.json")
  RSYNC_DSTPUBFILE=$(jq   -r .rsync.dstPubFile   "$RENEWED_LINEAGE/deploy.json")
  RSYNC_DSTPUBUSER=$(jq   -r .rsync.dstPubUser   "$RENEWED_LINEAGE/deploy.json")
  RSYNC_DSTPUBGROUP=$(jq  -r .rsync.dstPubGroup  "$RENEWED_LINEAGE/deploy.json")
  RSYNC_DSTPUBMODE=$(jq   -r .rsync.dstPubMode   "$RENEWED_LINEAGE/deploy.json")
  RSYNC_DSTPRIVPATH=$(jq  -r .rsync.dstPrivPath  "$RENEWED_LINEAGE/deploy.json")
  RSYNC_DSTPRIVFILE=$(jq  -r .rsync.dstPrivFile  "$RENEWED_LINEAGE/deploy.json")
  RSYNC_DSTPRIVUSER=$(jq  -r .rsync.dstPrivUser  "$RENEWED_LINEAGE/deploy.json")
  RSYNC_DSTPRIVGROUP=$(jq -r .rsync.dstPrivGroup "$RENEWED_LINEAGE/deploy.json")
  RSYNC_DSTPRIVMODE=$(jq  -r .rsync.dstPrivMode  "$RENEWED_LINEAGE/deploy.json")
  RSYNC_DSTCOMMAND=$(jq   -r .rsync.dstCommand   "$RENEWED_LINEAGE/deploy.json")
  
  # Test rsync connection
  if ! sshpass -p "$RSYNC_PASS" ssh -p "$RSYNC_PORT" -o BatchMode=no -o ConnectTimeout=10 \
    "${RSYNC_USER}@${RSYNC_HOST}" exit 2>/dev/null; then
    echo "Error: Failed to connect to rsync host ${RSYNC_HOST}:${RSYNC_PORT}" >&2
    #exit 4
  fi
  
  # Backup and copy public certificate
  if ! sshpass -p "$RSYNC_PASS" ssh -p "$RSYNC_PORT" \
       "${RSYNC_USER}@${RSYNC_HOST}" \
       "if [ -f ${RSYNC_DSTPUBPATH}/${RSYNC_DSTPUBFILE} ]; then mv ${RSYNC_DSTPUBPATH}/${RSYNC_DSTPUBFILE} ${RSYNC_DSTPUBPATH}/${RSYNC_DSTPUBFILE}.\$(date -r ${RSYNC_DSTPUBPATH}/${RSYNC_DSTPUBFILE} +%Y%m%d-%H%M); fi"; then
    echo "Error: Failed to backup existing cert file on ${RSYNC_HOST}" >&2
    #exit 4
  fi

  if ! sshpass -p "$RSYNC_PASS" rsync -avzL -e "ssh -p $RSYNC_PORT" \
       "$RENEWED_LINEAGE/cert.pem" \
       "${RSYNC_USER}@${RSYNC_HOST}:${RSYNC_DSTPUBPATH}/${RSYNC_DSTPUBFILE}"; then
    echo "Error: Failed to copy cert.pem to ${RSYNC_HOST}:${RSYNC_DSTPUBPATH}/${RSYNC_DSTPUBFILE}" >&2
    #exit 4
  fi

  # Set ownership on public certificate
  if ! sshpass -p "$RSYNC_PASS" ssh -p "$RSYNC_PORT" \
       "${RSYNC_USER}@${RSYNC_HOST}" \
       "chown ${RSYNC_DSTPUBUSER}:${RSYNC_DSTPUBGROUP} ${RSYNC_DSTPUBPATH}/${RSYNC_DSTPUBFILE}"; then
    echo "Error: Failed to set ownership on ${RSYNC_HOST}:${RSYNC_DSTPUBPATH}/${RSYNC_DSTPUBFILE}" >&2
    #exit 4
  fi

  # Set permissions on public certificate
  if ! sshpass -p "$RSYNC_PASS" ssh -p "$RSYNC_PORT" \
       "${RSYNC_USER}@${RSYNC_HOST}" \
       "chmod ${RSYNC_DSTPUBMODE} ${RSYNC_DSTPUBPATH}/${RSYNC_DSTPUBFILE}"; then
    echo "Error: Failed to set permissions on ${RSYNC_HOST}:${RSYNC_DSTPUBPATH}/${RSYNC_DSTPUBFILE}" >&2
    #exit 4
  fi

  # Backup and copy private key
  if ! sshpass -p "$RSYNC_PASS" ssh -p "$RSYNC_PORT" \
       "${RSYNC_USER}@${RSYNC_HOST}" \
       "if [ -f ${RSYNC_DSTPRIVPATH}/${RSYNC_DSTPRIVFILE} ]; then mv ${RSYNC_DSTPRIVPATH}/${RSYNC_DSTPRIVFILE} ${RSYNC_DSTPRIVPATH}/${RSYNC_DSTPRIVFILE}.\$(date -r ${RSYNC_DSTPRIVPATH}/${RSYNC_DSTPRIVFILE} +%Y%m%d-%H%M); fi"; then
    echo "Error: Failed to backup existing private key file on ${RSYNC_HOST}" >&2
    #exit 4
  fi

  if ! sshpass -p "$RSYNC_PASS" rsync -avzL -e "ssh -p $RSYNC_PORT" \
       "$RENEWED_LINEAGE/privkey.pem" \
       "${RSYNC_USER}@${RSYNC_HOST}:${RSYNC_DSTPRIVPATH}/${RSYNC_DSTPRIVFILE}"; then
    echo "Error: Failed to copy privkey.pem to ${RSYNC_HOST}:${RSYNC_DSTPRIVPATH}/${RSYNC_DSTPRIVFILE}" >&2
    #exit 4
  fi

  # Set ownership on private key
  if ! sshpass -p "$RSYNC_PASS" ssh -p "$RSYNC_PORT" \
       "${RSYNC_USER}@${RSYNC_HOST}" \
       "chown ${RSYNC_DSTPRIVUSER}:${RSYNC_DSTPRIVGROUP} ${RSYNC_DSTPRIVPATH}/${RSYNC_DSTPRIVFILE}"; then
    echo "Error: Failed to set ownership on ${RSYNC_HOST}:${RSYNC_DSTPRIVPATH}/${RSYNC_DSTPRIVFILE}" >&2
    #exit 4
  fi

  # Set permissions on private key
  if ! sshpass -p "$RSYNC_PASS" ssh -p "$RSYNC_PORT" \
       "${RSYNC_USER}@${RSYNC_HOST}" \
       "chmod ${RSYNC_DSTPRIVMODE} ${RSYNC_DSTPRIVPATH}/${RSYNC_DSTPRIVFILE}"; then
    echo "Error: Failed to set permissions on ${RSYNC_HOST}:${RSYNC_DSTPRIVPATH}/${RSYNC_DSTPRIVFILE}" >&2
    #exit 4
  fi

  # Execute remote command
  if ! sshpass -p "$RSYNC_PASS" ssh -p "$RSYNC_PORT" \
       "${RSYNC_USER}@${RSYNC_HOST}" \
       "${RSYNC_DSTCOMMAND}"; then
    echo "Error: Failed to execute remote command on ${RSYNC_HOST}: ${RSYNC_DSTCOMMAND}" >&2
    #exit 4
  fi
  
fi
  

  log "=== Certbot Rsync Completed Successfully ==="
else
  log "=== Certbot Rsync Config Not Found, Skipping ==="
fi