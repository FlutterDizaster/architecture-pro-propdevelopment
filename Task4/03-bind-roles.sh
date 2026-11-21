#!/usr/bin/env bash
# Привязываю группы к ролям. Права выдаются группам, а не отдельным людям:
# группа пользователя записана в его сертификате (см. 01-create-users.sh).
set -e

bind() {
  kubectl create "$@" --dry-run=client -o yaml | kubectl apply -f -
}

# Доменные группы получают права только в namespace своего домена
for ns in sales housing finance data; do
  bind rolebinding "$ns-viewers" -n "$ns" --clusterrole=view --group="$ns-viewers"
  bind rolebinding "$ns-developers" -n "$ns" --clusterrole=domain-developer --group="$ns-developers"
  bind rolebinding "$ns-devops" -n "$ns" --clusterrole=edit --group="$ns-devops"
done

# Общие для всей компании группы получают права на весь кластер
bind clusterrolebinding cluster-operators --clusterrole=cluster-configurator --group=cluster-operators
bind clusterrolebinding security-auditors --clusterrole=security-auditor --group=security-auditors
bind clusterrolebinding security-auditors-view --clusterrole=view --group=security-auditors
