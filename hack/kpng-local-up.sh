#!/bin/bash
# build the kpng image...

# TODO Replace with 1.22 once we address 
#: ${KIND:="kindest/node:v1.21.1@sha256:69860bda5563ac81e3c0057d654b5253219618a22ec3a346306239bba8cfa1a6"}
: ${KIND:="kindest/node:v1.22.0@sha256:b8bda84bb3a190e6e028b1760d277454a72267a5454b57db34437c34a588d047"}
: ${IMAGE:="jayunit100/kpng:2"}
: ${PULL:=IfNotPresent}
: ${BACKEND:=iptables}
export IMAGE PULL BACKEND

echo -n "this will deploy kpng with docker image $IMAGE, pull policy $PULL and the $BACKEND backend. Press enter to confirm, C-c to cancel"
read

function build_kpng {
    cd ../

    docker build -t $IMAGE ./
    docker push $IMAGE
    cd hack/
}

function install_calico {

    ### Cache cni images to avoid rate-limiting
    docker pull docker.io/calico/kube-controllers:v3.19.1
    docker pull docker.io/calico/cni:v3.19.1
    docker pull docker.io/calico/pod2daemon-flexvol:v3.19.1
    kind load docker-image docker.io/calico/cni:v3.19.1 --name kpng-proxy
    kind load docker-image docker.io/calico/kube-controllers:v3.19.1 --name kpng-proxy
    kind load docker-image docker.io/calico/pod2daemon-flexvol:v3.19.1 --name kpng-proxy

    kubectl apply -f https://raw.githubusercontent.com/jayunit100/k8sprototypes/master/kind/calico.yaml
    kubectl -n kube-system set env daemonset/calico-node FELIX_IGNORELOOSERPF=true
    kubectl -n kube-system set env daemonset/calico-node FELIX_XDPENABLED=false
}

function install_k8s {
    kind version

    echo "****************************************************"
    kind delete cluster --name kpng-proxy
    kind create cluster --config kind.yaml --image $KIND
    install_calico
    echo "****************************************************"
}

function install_kpng {
    # substitute it with your changes...
    echo "Applying template"
    envsubst <kpng-deployment-ds.yaml.tmpl >kpng-deployment-ds.yaml

    kind load docker-image $IMAGE --name kpng-proxy

    # TODO support antrea as a secondary CNI option to test
    cni_config

    kubectl -n kube-system create sa kpng
    kubectl create clusterrolebinding kpng --clusterrole=system:node-proxier --serviceaccount=kube-system:kpng
    kubectl -n kube-system create cm kpng --from-file kubeconfig.conf

    kubectl delete -f kpng-deployment-ds.yaml
    kubectl create -f kpng-deployment-ds.yaml
}

# Comment out build if you just want to install the default, i.e. for quickly getting up and running.
build_kpng
install_k8s
install_kpng
