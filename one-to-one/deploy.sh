#!/usr/bin/env bash

set -euo pipefail

deploy_rabbit_and_clients(){
    TEST_ID="$1"
    RABBITMQ_IMAGE="$2"
    RABBITMQ_MEMORY="$3"
    RABBITMQ_CPUS="$4"

    sed "s|{{testid}}|$TEST_ID| ; s|{{rabbitmq_image}}|$RABBITMQ_IMAGE| ; s|{{rabbitmq_memory}}|$RABBITMQ_MEMORY| ; s|{{rabbitmq_cpus}}|$RABBITMQ_CPUS|" \
        mqtt-rabbit.yml | kubectl apply -f -
    sleep 20
    kubectl wait --for=condition=Ready=true pods -lapp.kubernetes.io/name=mqtt-rabbit-"$TEST_ID" --timeout=5m
    sleep 20

    # 4 pods * 25k clients per pod: 100k publishers and 100k subscribers
    NUM_PODS=4
    # Deploy first all consumers, then all publishers such that messages won't be dropped when publishing.
    for podindex in $(seq "$NUM_PODS"); do
        sed "s/{{podindex}}/$podindex/ ; s/{{testid}}/$TEST_ID/" mqtt-consumer.yml | kubectl apply -f -
    done
    sleep 60
    for podindex in $(seq "$NUM_PODS"); do
        sed "s/{{podindex}}/$podindex/ ; s/{{testid}}/$TEST_ID/" mqtt-publisher.yml | kubectl apply -f -
    done
}

gcloud beta container \
    --project "$GCP_PROJECT" clusters create "mqtt" \
    --zone "europe-west3-c" \
    --num-nodes "3" \
    --machine-type "n2-standard-128" \
    --disk-size "100" \
    --disk-type "pd-balanced" \
    --cluster-version "1.25.6-gke.200" \
    --cluster-dns=clouddns \
    --cluster-dns-scope=cluster \
    --local-ssd-count=16 \
    --release-channel "rapid" \
    --image-type "UBUNTU_CONTAINERD" \
    --metadata disable-legacy-endpoints=true \
    --max-pods-per-node "200" \
    --no-enable-basic-auth  \
    --node-locations "europe-west3-c" \
    --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
    --logging=SYSTEM,WORKLOAD \
    --monitoring=SYSTEM \
    --enable-ip-alias \
    --network "projects/$GCP_PROJECT/global/networks/default" \
    --subnetwork "projects/$GCP_PROJECT/regions/europe-west3/subnetworks/default" \
    --no-enable-intra-node-visibility \
    --default-max-pods-per-node "200" \
    --no-enable-master-authorized-networks \
    --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver \
    --enable-autoupgrade \
    --enable-autorepair \
    --max-surge-upgrade 1 \
    --max-unavailable-upgrade 0 \
    --enable-shielded-nodes

kubectl get nodes | grep Ready | awk '{print $1}' | xargs -I {} gcloud compute ssh {} --zone "europe-west3-c" \
    -- "sudo sysctl -w net.netfilter.nf_conntrack_max=10000000 && sudo bash -c 'echo 1250000 > /sys/module/nf_conntrack/parameters/hashsize' && sudo sysctl -w fs.nr_open=10000000"

kubectl scale deployment --replicas=0 kube-dns-autoscaler --namespace=kube-system
kubectl scale deployment --replicas=0 kube-dns --namespace=kube-system

KUBE_PROMETHEUS_STACK_VERSION='45.7.1'
KUBE_PROMETHEUS_STACK_NAME='prom'
KUBE_PROMETHEUS_STACK_NAMESPACE='kube-prometheus'
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade "$KUBE_PROMETHEUS_STACK_NAME" prometheus-community/kube-prometheus-stack \
    --version "$KUBE_PROMETHEUS_STACK_VERSION" \
    --install \
    --namespace "$KUBE_PROMETHEUS_STACK_NAMESPACE" \
    --create-namespace \
    --wait \
    --set "defaultRules.create=false" \
    --set "nodeExporter.enabled=false" \
    --set "alertmanager.enabled=false" \
    --set "grafana.env.GF_INSTALL_PLUGINS=flant-statusmap-panel" \
    --set "grafana.adminPassword=admin" \
    --set "prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false" \
    --set "prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false" \
    --set "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false" \
    --set "prometheus.prometheusSpec.probeSelectorNilUsesHelmValues=false"

cat ../common/*.yml | kubectl -n "$KUBE_PROMETHEUS_STACK_NAMESPACE" apply -f -

kubectl apply -f https://github.com/rabbitmq/cluster-operator/releases/download/v2.1.0/cluster-operator.yml
sleep 20

deploy_rabbit_and_clients "3-12" "rabbitmq:3.12.0-beta.2-management" "50Gi" "30"
deploy_rabbit_and_clients "3-11" "rabbitmq:3.11.10-management" "250Gi" "60"
