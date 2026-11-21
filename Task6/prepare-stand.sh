#!/bin/bash
# Подготовка стенда перед simulate-incident.sh. Запуск: ./prepare-stand.sh [профиль minikube]
set -e
cd "$(dirname "$0")"
profile="${1:-prop-audit}"

# том hostPath, чтобы лог аудита писался в /var/log/audit.log на ноде, а не внутри контейнера
minikube -p "$profile" ssh -- 'sudo sh -c "
  m=/etc/kubernetes/manifests/kube-apiserver.yaml
  touch /var/log/audit.log
  grep -q \"name: audit-log\" \$m || sed -i \
    -e \"s|^    volumeMounts:|    volumeMounts:\n    - mountPath: /var/log/audit.log\n      name: audit-log|\" \
    -e \"s|^  volumes:|  volumes:\n  - hostPath:\n      path: /var/log/audit.log\n      type: FileOrCreate\n    name: audit-log|\" \$m
"'
until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 3; done

# скрипт симуляции ищет в kube-system секрет default-token-*; с Kubernetes 1.24 такие секреты
# сами не появляются, поэтому выпускаю токен сервис-аккаунта default штатным способом
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: default-token-x7k2p
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: default
type: kubernetes.io/service-account-token
EOF

# политика аудита как объект кластера: её и пытается удалить скрипт симуляции
kubectl apply -f audit-policy-configmap.yaml
