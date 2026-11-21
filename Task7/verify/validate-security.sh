#!/bin/bash
# Проверяю, что работают оба слоя: PodSecurity на audit-zone и ограничения Gatekeeper.
cd "$(dirname "$0")/.." || exit 1
fail=0
check() { # описание, команда
  if eval "$2" >/dev/null 2>&1; then echo "OK    $1"; else echo "FAIL  $1"; fail=1; fi
}

echo "PodSecurity Admission"
for mode in enforce audit warn; do
  check "audit-zone: $mode=restricted" \
    "[ \"\$(kubectl get ns audit-zone -o jsonpath=\"{.metadata.labels.pod-security\.kubernetes\.io/$mode}\")\" = restricted ]"
done

echo "Gatekeeper"
check "gatekeeper-controller-manager запущен" \
  "kubectl -n gatekeeper-system rollout status deploy/gatekeeper-controller-manager --timeout=60s"
check "gatekeeper-audit запущен" \
  "kubectl -n gatekeeper-system rollout status deploy/gatekeeper-audit --timeout=60s"
for t in k8sdenyprivileged k8sdenyhostpath k8srequirerunasnonroot k8srequirereadonlyrootfs; do
  check "шаблон $t создан" \
    "[ \"\$(kubectl get constrainttemplate $t -o jsonpath='{.status.created}')\" = true ]"
  check "constraint $t в режиме deny" \
    "[ \"\$(kubectl get $t -o jsonpath='{.items[0].spec.enforcementAction}')\" = deny ]"
done

# Namespace без меток PodSecurity: если под отклонён здесь, это сделал Gatekeeper.
echo "Отказы Gatekeeper (server dry-run в namespace без PodSecurity)"
ns=gatekeeper-check
kubectl create ns $ns >/dev/null 2>&1
dry_run() { sed "s/namespace: audit-zone/namespace: $ns/" "$1" | kubectl apply --dry-run=server -f - 2>&1; }

expect_deny() { # файл, имя constraint
  out=$(dry_run "$1")
  if echo "$out" | grep -q "validation.gatekeeper.sh" && echo "$out" | grep -q "\[$2\]"; then
    echo "OK    $1 отклонён правилом $2"
  else
    echo "FAIL  $1 не отклонён правилом $2"; fail=1
  fi
}
expect_deny insecure-manifests/01-privileged-pod.yaml deny-privileged
expect_deny insecure-manifests/02-hostpath-pod.yaml deny-hostpath
expect_deny insecure-manifests/03-root-user-pod.yaml require-run-as-non-root
expect_deny insecure-manifests/01-privileged-pod.yaml require-read-only-root-fs
for f in secure-manifests/*.yaml; do
  check "$f проходит все правила" "dry_run $f"
done
kubectl delete ns $ns >/dev/null 2>&1

[ $fail -eq 0 ] && echo "Итог: OK" || echo "Итог: FAIL"
exit $fail
