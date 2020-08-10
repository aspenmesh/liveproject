#!/bin/bash

set -Eeuo pipefail

scriptName=$(basename $0)
if [ "$#" -ne 4 ]; then
  cat << EOF
$scriptName <organization> <domain> <sub-domain> <secret-name>
$scriptName boutiquestore '.com' marketplace online-boutique-tls-credential
EOF
  exit 1
fi

org="$1"
rootDomain="$1$2"
subDomain="$3.$rootDomain"
secretName="$4"
rootKeyFile="$secretName-root.key"
rootCertFile="$secretName-root.crt"
serverKeyFile="$secretName-server.key"
serverCsrFile="$secretName-server.csr"
serverCertFile="$secretName-server.crt"

echo "Creating root certificate for domain $rootDomain"
# Generate root certificate and private key to sign server certificate
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 \
  -subj "/O=$1 Inc./CN=$rootDomain" \
  -keyout $rootKeyFile -out $rootCertFile

# Generate a private key and CSR for the server
openssl req -out $serverCsrFile -newkey rsa:2048 -nodes \
  -keyout $serverKeyFile -subj "/CN=$subDomain/O=$org"

echo "Creating certificate for domain $subDomain"
# Sign the server CSR with the root CA and generate the server certificate
openssl x509 -req -days 365 -CA $rootCertFile -CAkey $rootKeyFile \
  -set_serial 0 -in $serverCsrFile -out $serverCertFile

# Create Kubernetes secret with the generated credentials above
kubectl -n istio-system create secret tls $secretName \
  --key=$serverKeyFile --cert=$serverCertFile --dry-run -o yaml | \
  kubectl apply -f -
