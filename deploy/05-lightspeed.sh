#!/bin/bash

#  .SYNOPSIS
#  Installs renewed certificate to Lightspeed lantern service used in block pages.
#
#  .DESCRIPTION
#  Used by certbot upon successful renewal of certificates. Copies new certificates to Lightspeed config
#  directory and restarts the lantern service.
#
#  .REQUIREMENTS
#  RENEWED_DOMAINS and RENEWED_LINEAGE must be set prior to run time.
#
#  .EXAMPLE
#  # RENEWED_DOMAINS=demo.neonet.org RENEWED_LINEAGE=/etc/letsencrypt/live/demo.neonet.org ./05-lightspeed.sh
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

log "=== Certbot Lightspeed Started ==="

if [[ -z "$RENEWED_LINEAGE" ]]; then
    log "ERROR: RENEWED_LINEAGE environment variable not set"
    exit 1
fi

if [[ -z "$RENEWED_DOMAINS" ]]; then
    log "ERROR: RENEWED_DOMAINS environment variable not set"
    exit 1
fi

INSTALL_DIR=/usr/local/rocket/etc
if [ -d $INSTALL_DIR ]; then
  cp $INSTALL_DIR/cert.pem $INSTALL_DIR/cert.pem.$(date +%Y%m%d)
  cp $INSTALL_DIR/cert_key.pem $INSTALL_DIR/cert_key.pem.$(date +%Y%m%d)
  cp $RENEWED_LINEAGE/fullchain.pem $INSTALL_DIR/cert.pem
  cp $RENEWED_LINEAGE/privkey.pem $INSTALL_DIR/cert_key.pem
  
  svc -t /etc/lantern
  if [ $? -eq 0 ]; then
    log "=== Certbot Lightspeed Completed Successfully ==="
  else
    log "=== Certbot Lightspeed Failed to restart lantern ==="
  fi
else
  log "=== Certbot Lightspeed Directory Not Found, Skipping ==="
fi