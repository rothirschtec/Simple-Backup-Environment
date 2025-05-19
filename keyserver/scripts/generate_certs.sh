#!/bin/bash
#
# Generate SSL certificates for the Key Server

mkdir -p ../config/certs
openssl req -x509 -newkey rsa:4096 -nodes \
  -out ../config/certs/cert.pem \
  -keyout ../config/certs/key.pem \
  -days 365 \
  -subj "/CN=sbe.keyserver"

echo "SSL certificates generated successfully!"
echo "Location: ../config/certs/"
