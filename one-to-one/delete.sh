#!/usr/bin/env bash

kubectl delete jobs -lmqtt=bench

kubectl delete rmq -lmqtt=server
sleep 5
kubectl delete pods -lapp.kubernetes.io/component=rabbitmq --force=true --grace-period=0
