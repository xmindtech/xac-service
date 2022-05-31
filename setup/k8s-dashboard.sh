# Deploy Kubernetes Dashboard
# https://artifacthub.io/packages/helm/k8s-dashboard/kubernetes-dashboard
#
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm install kubernetes-dashboard  kubernetes-dashboard/kubernetes-dashboard --debug

# Get the Kubernetes Dashboard URL by running:
# export POD_NAME=$(kubectl get pods -n default -l "app.kubernetes.io/name=kubernetes-dashboard,app.kubernetes.io/instance=kubernetes-dashboard" -o jsonpath="{.items[0].metadata.name}")
# kubectl -n default port-forward $POD_NAME 8443:8443

# get token: kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep service-controller-token | awk '{print $1}')
# go to https://127.0.0.1:8443/
