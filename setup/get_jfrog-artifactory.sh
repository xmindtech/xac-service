#!/bin/bash
helm repo add jfrog https://charts.jfrog.io/
helm repo update
helm install artifactory jfrog/artifactory-jcr --namespace artifactory --create-namespace --debug
