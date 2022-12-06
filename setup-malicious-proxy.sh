#!/bin/bash
# Setup a malicious proxy with a benCA signed certificate
# Usage: setup-malicious-proxy.sh <IP address>

# Check argument 
if [ -z "$1" ]; then
    echo "Usage: setup-malicious-proxy.sh <IP address>"
    exit 1
fi

IP=$1

# Check if python 3 is available
if ! command -v python3 &> /dev/null
then
    echo "python3 could not be found"
    exit
fi

# Check if requests python package is installed
if ! python3 -c "import requests" &> /dev/null
then
    echo "requests python package is not installed"
    exit
fi

# Generate certificate for the given IP address
./generate-certificate-for-ip.sh $IP || exit 1

# Run the malicious proxy
python3 proxy-server.py || exit 1