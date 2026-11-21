#!/usr/bin/env bash
# Создаю пользователей кластера: ключ, запрос на сертификат, подпись через API Kubernetes,
# запись в kubeconfig. Группа пользователя берётся из поля O сертификата.
set -e

# Ключи и сертификаты лежат рядом со скриптами, каталог в .gitignore
CERT_DIR="${CERT_DIR:-$(cd "$(dirname "$0")" && pwd)/.certs}"
mkdir -p "$CERT_DIR"

CLUSTER=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')

# пользователь:группа, по одному на роль
USERS="
olga-sales-analyst:sales-viewers
ivan-sales-dev:sales-developers
petr-sales-devops:sales-devops
sergey-platform:cluster-operators
elena-security:security-auditors
"

for entry in $USERS; do
  user=${entry%%:*}
  group=${entry##*:}
  key="$CERT_DIR/$user.key"
  crt="$CERT_DIR/$user.crt"

  openssl genrsa -out "$key" 2048 2>/dev/null
  chmod 600 "$key"
  openssl req -new -key "$key" -subj "/CN=$user/O=$group" -out "$CERT_DIR/$user.csr"

  # старый запрос с тем же именем мешает повторному запуску
  kubectl delete csr "$user" --ignore-not-found

  # сертификат отозвать нельзя, поэтому срок короткий: неделя
  cat <<YAML | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $user
spec:
  request: $(base64 < "$CERT_DIR/$user.csr" | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 604800
  usages:
  - client auth
YAML

  kubectl certificate approve "$user"

  # сертификат появляется в статусе не мгновенно
  cert=""
  for i in $(seq 1 20); do
    cert=$(kubectl get csr "$user" -o jsonpath='{.status.certificate}')
    [ -n "$cert" ] && break
    sleep 1
  done
  [ -n "$cert" ] || { echo "сертификат для $user не выпущен" >&2; exit 1; }
  echo "$cert" | base64 -d > "$crt"

  kubectl config set-credentials "$user" --client-key="$key" --client-certificate="$crt"
  kubectl config set-context "$user" --cluster="$CLUSTER" --user="$user"
done

echo "Готово. Проверка: kubectl --context ivan-sales-dev auth whoami"
