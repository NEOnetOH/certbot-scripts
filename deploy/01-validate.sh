#!/bin/bash

#  .SYNOPSIS
#  Validate renewed certificate has an expiration date in the future.
#
#  .DESCRIPTION
#  Used by certbot upon successful renewal of certificates.
#
#  .REQUIREMENTS
#  RENEWED_DOMAINS and RENEWED_LINEAGE must be set prior to run time.
#
#  .EXAMPLE
#  # RENEWED_DOMAINS=demo.neonet.org RENEWED_LINEAGE=/etc/letsencrypt/live/demo.neonet.org ./01-validate.sh
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

log "=== Certbot Validate Deploy Hook Started ==="

if [[ -z "$RENEWED_LINEAGE" ]]; then
  log "ERROR: RENEWED_LINEAGE environment variable not set"
  exit 1
fi

if [[ -z "$RENEWED_DOMAINS" ]]; then
  log "ERROR: RENEWED_DOMAINS environment variable not set"
  exit 1
fi

log "Renewed domains: $RENEWED_DOMAINS"
log "Certificate directory: $RENEWED_LINEAGE"

CERT_FILE="$RENEWED_LINEAGE/cert.pem"

log "Verifying certificate validity..."
if openssl x509 -in "$CERT_FILE" -text -noout > /dev/null 2>&1; then
  CURRENT_TIME=$(date +%s)
  CERT_EXPIRY=$(date -d "$(openssl x509 -in "$CERT_FILE" -noout -dates | grep "notAfter" | cut -d= -f2)" +%s)
  if [ "$CERT_EXPIRY" -gt "$CURRENT_TIME" ]; then
    DAYS_DIFF=$(( ($CERT_EXPIRY - $CURRENT_TIME) / 86400 ))
    log "Certificate is valid. Expires: $(date -u -d "@$CERT_EXPIRY" +%Y-%m-%dT%H:%M:%SZ) (in $DAYS_DIFF days)"
  else
    log "WARNING: Certificate validation failed"
    exit 1
  fi
fi

log "=== Certbot Validate Deploy Hook Completed Successfully ==="