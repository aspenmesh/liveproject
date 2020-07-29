#!/bin/bash

set -Eeuo pipefail

# Generate root certificate and private key to sign server certificate
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 \
  -subj '/O=boutiquestore Inc./CN=boutiquestore.com' \
  -keyout root.key -out root.crt

# Generate a private key and CSR for the server
openssl req -out server.csr -newkey rsa:2048 -nodes \
  -keyout server.key -subj "/CN=marketplace.boutiquestore.com/O=boutique store"

# Sign the server CSR with the root CA and generate the server certificate
openssl x509 -req -days 365 -CA root.crt -CAkey root.key \
  -set_serial 0 -in server.csr -out server.crt

# Create Kubernetes secret with the generated credentials above
kubectl -n istio-system create secret tls online-boutique-tls-credential \
  --key server.key --cert=server.crt
