#!/bin/bash
# Небезопасные манифесты должны быть отклонены в audit-zone, безопасные приняты и запущены.
cd "$(dirname "$0")/.." || exit 1
fail=0

for f in insecure-manifests/*.yaml; do
  if out=$(kubectl apply -f "$f" 2>&1); then
    echo "FAIL  $f принят, а должен быть отклонён"
    kubectl delete -f "$f" --ignore-not-found >/dev/null
    fail=1
  else
    echo "OK    $f отклонён"
    # из сообщения оставляю названия нарушенных правил, без пояснений в скобках
    echo "$out" | grep -oE '(violates PodSecurity|denied the request).*' | sed -E 's/ \([^)]*\)//g; s/^/        /'
  fi
done

for f in secure-manifests/*.yaml; do
  if kubectl apply -f "$f" >/dev/null 2>&1 &&
     kubectl wait --for=condition=Ready -f "$f" --timeout=120s >/dev/null 2>&1; then
    echo "OK    $f принят, под Running"
  else
    echo "FAIL  $f не принят или под не запустился"
    fail=1
  fi
done

[ $fail -eq 0 ] && echo "Итог: OK" || echo "Итог: FAIL"
exit $fail
