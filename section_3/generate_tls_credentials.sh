#!/bin/bash

set -Eeuo pipefail

scriptName=$(basename $0)
tmpDir=$(mktemp -d $PWD/ca-XXXXXX)

trap cleanup EXIT

function cleanup {
  if [ -n "$tmpDir" ]; then
    rm -rf $tmpDir
  fi
}

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
  -reqexts SAN -extensions SAN \
  -config <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nsubjectAltName=DNS:$subDomain\n")) \
  -keyout $serverKeyFile -subj "/CN=$subDomain/O=$org"

echo "Creating certificate for domain $subDomain"
# Sign the server CSR with the root CA and generate the server certificate

touch "$tmpDir/index.txt"
mkdir -p $tmpDir/newcerts
cp $rootKeyFile $tmpDir/root.key
cp $rootCertFile $tmpDir/root.crt

cat << EOF > $tmpDir/ssl.conf
[ca]
default_ca = CA_default

[CA_default]
dir = $tmpDir
database = $tmpDir/index.txt
new_certs_dir = $tmpDir/newcerts
serial = $tmpDir/serial
private_key = $tmpDir/root.key
certificate = $tmpDir/root.crt
default_days = 365
default_md = sha256
policy = policy_anything
copy_extensions = copyall

[policy_anything]
countryName = optional
stateOrProvinceName = optional
localityName = optional
organizationName = optional
organizationalUnitName = optional
commonName = supplied
emailAddress = optional

[req]
prompt = no
distinguished_name = req_distinguished_name
req_extensions = v3_ca

[req_distinguished_name]
CN = $subDomain/O=$org

[v3_ca]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $subDomain
EOF

openssl ca -create_serial -batch -in $serverCsrFile \
  -config $tmpDir/ssl.conf -out $serverCertFile

# Create Kubernetes secret with the generated credentials above
kubectl -n istio-system create secret tls $secretName \
  --key=$serverKeyFile --cert=$serverCertFile --dry-run -o yaml | \
  kubectl apply -f -
