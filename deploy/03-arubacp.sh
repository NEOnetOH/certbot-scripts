#!/bin/bash

#  .SYNOPSIS
#  Installs renewed certificate to Aruba ClearPass via API calls for HTTPS and Radius
#
#  .DESCRIPTION
#  Used by certbot upon successful renewal of certificates. Pulls config from deploy.json file including host, credentials, and endpoints
#  to establish an API call to pull an access token, and direct Aruba ClearPass to download a PFX file with the supplied password.
#
#  .REQUIREMENTS
#  RENEWED_DOMAINS and RENEWED_LINEAGE must be set prior to run time.
#  deploy.json must exist and be configured for ClearPass.
#
#  .EXAMPLE
#  # RENEWED_DOMAINS=demo.neonet.org RENEWED_LINEAGE=/etc/letsencrypt/live/demo.neonet.org ./03-arubacp.sh
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

log "=== Certbot ArubaCP Started ==="

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

jq -e '.clearPass' "$RENEWED_LINEAGE/deploy.json" > /dev/null 2>&1
if [ $? -eq 0 ]; then
  # Create array from RENEWED_DOMAINS
  DOMAINS=($RENEWED_DOMAINS)

  REQUIRED_KEYS=(
    "pkcs12.pfxPath"
    "pkcs12.pfxPass"
    "clearPass.Host"
    "clearPass.AuthEndpoint"
    "clearPass.UUIDEndpoint"
    "clearPass.CertURI[]"
    "webCertStore.host"
    "webCertStore.port"
    "webCertStore.uri"
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
  API_HOST=$(jq -r .clearPass.Host "$RENEWED_LINEAGE/deploy.json")
  API_AUTH_ENDPOINT=$(jq -r .clearPass.AuthEndpoint "$RENEWED_LINEAGE/deploy.json")
  API_UUID_ENDPOINT=$(jq -r .clearPass.UUIDEndpoint "$RENEWED_LINEAGE/deploy.json")
  WEB_HOST=$(jq -r .webCertStore.host "$RENEWED_LINEAGE/deploy.json")
  WEB_PORT=$(jq -r .webCertStore.port "$RENEWED_LINEAGE/deploy.json")
  WEB_URI=$(jq -r .webCertStore.uri "$RENEWED_LINEAGE/deploy.json")

  # Check if .pkcs12.pfxFile is configured, else use the first domain of $RENEWED_DOMAINS
  jq -e '.pkcs12.pfxFile' "$RENEWED_LINEAGE/deploy.json" > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    PFX_FILENAME=$(jq -r .pfxFile "$RENEWED_LINEAGE/deploy.json")
    PFX_FILE=$PFX_DIR/$(jq -r .pfxFile "$RENEWED_LINEAGE/deploy.json")
  else
    PFX_FILENAME="${DOMAINS[0]}.pfx"
    PFX_FILE=$PFX_DIR/"${DOMAINS[0]}.pfx"
  fi
  
  # Retrieve an access token from Aruba CP
  API_ACCESS_TOKEN=$(curl -H 'Content-Type: application/json' -d "$(jq .clearPass.AuthCreds $RENEWED_LINEAGE/deploy.json)" https://$API_HOST/$API_AUTH_ENDPOINT 2>/dev/null | jq -r .access_token)

  # Verify Aruba CP issued an access token or fail out
  if [ -z "$API_ACCESS_TOKEN" ]; then
    log "ERROR: Failed to obtain an access token from Aruba CP"
    exit 3
  else
    log "INFO: Successfully obtained an access token from Aruba CP"
  fi

  # Retrieve the server UUID from Aruba CP
  SERVER_UUID=$(curl -H "Authorization: Bearer $API_ACCESS_TOKEN"  https://$API_HOST/$API_UUID_ENDPOINT 2>/dev/null | jq -r ._embedded.items[].server_uuid)

  # Verify Aruba CP provided the server UUID or fail out
  if [ -z "$SERVER_UUID" ]; then
    log "ERROR: Failed to obtain Server UUID from Aruba CP"
    exit 3
  else
    log "INFO: Successfully obtained SERVER UUID from Aruba CP"
  fi

  # Array created from deploy.json for each certificate store using above retrieved server UUID
  CERT_URI=($(jq -r --arg uuid "$SERVER_UUID" '.clearPass.CertURI[] |= gsub("\\$uuid"; $uuid) | .clearPass.CertURI[]' $RENEWED_LINEAGE/deploy.json))

  # Make API call for each certificate store to pull the new certificate
  for uri in "${CERT_URI[@]}"
  do
    # Run curl using a HEREDOC, delimited by EOF in JSON format
    curl https://$API_HOST:443$uri -X PUT -H "Authorization: Bearer $API_ACCESS_TOKEN" -H "Content-Type: application/json" -d @- >/dev/null 2>&1 << EOF
{
  "pkcs12_file_url": "https://$WEB_HOST:$WEB_PORT$WEB_URI$PFX_FILENAME",
  "pkcs12_passphrase": "$PFX_PASS"
}
EOF
  done

  log "=== Certbot ArubaCP Completed Successfully ==="
else
  log "=== Certbot ArubaCP Config Not Found, Skipping ==="
fi
