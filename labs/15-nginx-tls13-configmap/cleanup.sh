kubectl delete namespace nginx-static
sudo sed -i '/web\.k8s\.local/d' /etc/hosts
