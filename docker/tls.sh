#!/bin/bash
set -o errexit

# https://docs.docker.com/engine/security/protect-access/#create-a-ca-server-and-client-keys-with-openssl

: "${COMPANY_DN:=/C=DE/ST=BW/L=Freiburg im Breisgau/O=My Company/OU=IT}"

: "${BITS:=4096}"

: "${DAYS:=365}"
: "${CA_DAYS:=${DAYS}}"
: "${SERVER_DAYS:=${DAYS}}"
: "${CLIENT_DAYS:=${DAYS}}"

: "${SERVER_CN:=localhost}"
: "${CLIENT_CN:=client}"

: "${SERVER_SAN_DNS:=${SERVER_CN}}"
: "${SERVER_SAN_IP:=127.0.0.1}"

CA_DN="${COMPANY_DN}/CN=Docker CA ${SERVER_CN}"
SERVER_DN="${COMPANY_DN}/CN=${SERVER_CN}"
CLIENT_DN="${COMPANY_DN}/CN=${CLIENT_CN}"

SERVER_SAN="DNS:${SERVER_CN},DNS:${SERVER_SAN_DNS//,/,DNS:}"
if test -n "${SERVER_SAN_IP}"; then
    SERVER_SAN="${SERVER_SAN},IP:${SERVER_SAN_IP//,/,IP:}"
fi

echo "### Generate CA key pair with ${BITS} bits:"
openssl genrsa \
    -out ca-key.pem \
    "${BITS}"

echo "### Create CA certificate with ${DAYS} days validity and DNS <${CA_DN}>:"
openssl req \
    -new \
    -x509 \
    -days "${CA_DAYS}" \
    -subj "${CA_DN}" \
    -sha256 \
    -key ca-key.pem \
    -out ca.pem

echo "### Generate server key pair with ${BITS} bits:"
openssl genrsa \
    -out server-key.pem \
    "${BITS}"

echo "### Create CSR for server certificate with DN <${SERVER_DN}>:"
openssl req \
    -subj "${SERVER_DN}" \
    -sha256 \
    -new \
    -key server-key.pem \
    -out server.csr

echo "### Add extfile with SAN <${SERVER_SAN}>:"
cat >>extfile.cnf <<EOF
subjectAltName = ${SERVER_SAN}
extendedKeyUsage = serverAuth
EOF

echo "### Issue server certificate:"
openssl x509 \
    -req \
    -days "${SERVER_DAYS}" \
    -sha256 \
    -in server.csr \
    -CA ca.pem \
    -CAkey ca-key.pem \
    -CAcreateserial \
    -out server.pem \
    -extfile extfile.cnf

echo "### Generate client key pair:"
openssl genrsa \
    -out key.pem \
    "${BITS}"

echo "### Create CSR for client certificate with DN <${CLIENT_DN}>:"
openssl req \
    -subj "${CLIENT_DN}" \
    -new \
    -key key.pem \
    -out client.csr

echo "### Add extfile for client certificate:"
cat >>extfile-client.cnf <<EOF
extendedKeyUsage = clientAuth
EOF

echo "### Issue client certificate:"
openssl x509 \
    -req \
    -days "${CLIENT_DAYS}" \
    -sha256 \
    -in client.csr \
    -CA ca.pem \
    -CAkey ca-key.pem \
    -CAcreateserial \
    -out cert.pem \
    -extfile extfile-client.cnf

echo "### Set permissions on private keys and certificates"
chmod -v 0400 ca-key.pem key.pem server-key.pem
chmod -v 0444 ca.pem server.pem cert.pem

echo "### Remove temporary files"
rm -v client.csr server.csr extfile.cnf extfile-client.cnf
