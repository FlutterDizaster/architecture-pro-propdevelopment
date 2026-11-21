# Задание 7. PodSecurity и OPA Gatekeeper

Проверял на minikube (Kubernetes v1.37.0, Gatekeeper v3.23.1). Защита в два слоя: PodSecurity Admission с уровнем restricted на `audit-zone` и четыре правила Gatekeeper на все namespace, кроме `kube-system` и `gatekeeper-system`.

В структуре из условия три пары файлов Gatekeeper, а правил в задании четыре. Для обязательного `readOnlyRootFilesystem: true` я добавил четвёртую пару: `gatekeeper/constraint-templates/readonlyrootfs.yaml` и `gatekeeper/constraints/readonlyrootfs.yaml`.

## Порядок запуска

```
kubectl apply -f 01-create-namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.23.1/deploy/gatekeeper.yaml
kubectl -n gatekeeper-system rollout status deploy/gatekeeper-controller-manager
kubectl apply -f gatekeeper/constraint-templates/
kubectl apply -f gatekeeper/constraints/      # после того как шаблоны создадут CRD, секунд через 10–15
./verify/verify-admission.sh
./verify/validate-security.sh
```

## Что где лежит

- `insecure-manifests/`: три пода с нарушениями (privileged, hostPath, запуск от UID 0).
- `secure-manifests/`: те же поды после исправления. Образ `nginxinc/nginx-unprivileged` работает от UID 101, корневая ФС только на чтение, под `/tmp` и данные подключён emptyDir вместо hostPath, сброшены все capabilities, включён seccomp RuntimeDefault.
- `gatekeeper/`: шаблоны на Rego и constraints в режиме deny. Правила смотрят и `containers`, и `initContainers`.
- `audit-policy.yaml`: политика аудита API-сервера. Запросы на поды в `audit-zone` пишутся целиком, поэтому в журнале остаётся и присланный манифест, и ответ 403 с причиной отказа. Я подключал её на стенде флагом `--audit-policy-file` и проверил, что все три отказа из `verify-admission.sh` в лог попали.

## Вывод verify-admission.sh

В `audit-zone` первым срабатывает PodSecurity, поэтому причины отказа названы его правилами: `privileged`, `restricted volume types` (это hostPath), `runAsUser=0`. Остальные пункты в каждой строке относятся к тому, что в небезопасных манифестах вообще нет securityContext.

```
OK    insecure-manifests/01-privileged-pod.yaml отклонён
        violates PodSecurity "restricted:latest": privileged, allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
OK    insecure-manifests/02-hostpath-pod.yaml отклонён
        violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
OK    insecure-manifests/03-root-user-pod.yaml отклонён
        violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, runAsUser=0, seccompProfile
OK    secure-manifests/01-secure.yaml принят, под Running
OK    secure-manifests/02-secure.yaml принят, под Running
OK    secure-manifests/03-secure.yaml принят, под Running
Итог: OK
```

## Вывод validate-security.sh

Чтобы показать работу именно Gatekeeper, скрипт прогоняет те же манифесты через серверный dry-run во временном namespace `gatekeeper-check`, где меток PodSecurity нет.

```
PodSecurity Admission
OK    audit-zone: enforce=restricted
OK    audit-zone: audit=restricted
OK    audit-zone: warn=restricted
Gatekeeper
OK    gatekeeper-controller-manager запущен
OK    gatekeeper-audit запущен
OK    шаблон k8sdenyprivileged создан
OK    constraint k8sdenyprivileged в режиме deny
OK    шаблон k8sdenyhostpath создан
OK    constraint k8sdenyhostpath в режиме deny
OK    шаблон k8srequirerunasnonroot создан
OK    constraint k8srequirerunasnonroot в режиме deny
OK    шаблон k8srequirereadonlyrootfs создан
OK    constraint k8srequirereadonlyrootfs в режиме deny
Отказы Gatekeeper (server dry-run в namespace без PodSecurity)
OK    insecure-manifests/01-privileged-pod.yaml отклонён правилом deny-privileged
OK    insecure-manifests/02-hostpath-pod.yaml отклонён правилом deny-hostpath
OK    insecure-manifests/03-root-user-pod.yaml отклонён правилом require-run-as-non-root
OK    insecure-manifests/01-privileged-pod.yaml отклонён правилом require-read-only-root-fs
OK    secure-manifests/01-secure.yaml проходит все правила
OK    secure-manifests/02-secure.yaml проходит все правила
OK    secure-manifests/03-secure.yaml проходит все правила
Итог: OK
```

Аудит Gatekeeper заодно находит нарушения в уже запущенных подах: `kubectl get constraints` показывает их число в колонке TOTAL-VIOLATIONS. На моём стенде он так нашёл привилегированный под из задания 6.
