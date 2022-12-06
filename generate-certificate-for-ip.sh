#!/bin/bash
# Generate a self-signed certificate for a given IP address
# Usage: generate-certificate-for-ip.sh <IP address>
# Example: generate-certificate-for-ip.sh 10.0.0.1
IP=$1
if [ -z "$IP" ]; then
    echo "Usage: generate-certificate-for-ip.sh <IP address>"
    exit 1
fi

pushd certs || exit 1

# Replace dots to dashes in string variable
IP_DASHED=`echo $IP | sed -e "s/\./-/g"`

# Replace the IP address in the configuration file
sed -e "s/IPADDRESS/$IP/" cert.conf.tmpl > cert-$IP_DASHED.conf

# Generate certificate signing request
openssl req -new -key proxy-server-clear.key -out proxy-server-$IP_DASHED.csr -config cert-$IP_DASHED.conf || exit 1

# Empty ca.db.index file
truncate -s 0 ca.db.index

# Sign the certificate signing request
openssl ca -batch -config ca.conf -in proxy-server-$IP_DASHED.csr -out proxy-server-$IP_DASHED.crt || exit 1

cp proxy-server-$IP_DASHED.crt proxy-server.crt

echo "Generated certificate for IP address $IP"

popd