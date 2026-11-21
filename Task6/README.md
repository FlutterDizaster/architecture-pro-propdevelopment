# Задание 6. Аудит Kubernetes

Стенд поднял в minikube отдельным профилем (Kubernetes v1.37.0). Политику из условия (`audit-policy.yaml`) положил в `~/.minikube/files/etc/ssl/certs/`, этот каталог уже смонтирован в под API-сервера:

```
minikube start -p prop-audit \
  --extra-config=apiserver.audit-policy-file=/etc/ssl/certs/audit-policy.yaml \
  --extra-config=apiserver.audit-log-path=/var/log/audit.log
./prepare-stand.sh prop-audit
KUBECTL_REMOTE_COMMAND_WEBSOCKETS=false bash simulate-incident.sh
minikube -p prop-audit ssh -- sudo cat /var/log/audit.log > audit.log
./filter-audit.sh audit.log        # нужен jq, пишет audit-extract.json
```

Скрипт симуляции из условия рассчитан на старый Kubernetes, поэтому стенд пришлось подготовить под его допущения. Это делает `prepare-stand.sh`:

- добавляет в манифест API-сервера том hostPath, чтобы лог писался в `/var/log/audit.log` на ноде, а не внутри контейнера;
- выпускает в `kube-system` токен сервис-аккаунта `default` секретом `default-token-x7k2p`: скрипт ищет секрет с таким именем, а с версии 1.24 они сами не создаются;
- кладёт политику аудита в кластер как ConfigMap `audit-policy` (`audit-policy-configmap.yaml`). Сама политика не объект API, и `kubectl delete -f` на её файле до API-сервера не доходит.

В `simulate-incident.sh` изменена одна строка: удаление указывает на `audit-policy-configmap.yaml` вместо `/etc/kubernetes/audit-policy.yaml`. Переменная `KUBECTL_REMOTE_COMMAND_WEBSOCKETS=false` включает у kubectl старый протокол SPDY: с ним exec записывается в лог как `create`, а по WebSocket был бы `get` (фильтр ловит оба варианта).

Полный лог в репозиторий не кладу. В `audit-extract.json` по одному событию в строке, как в исходном логе, с полем `suspicious` (за что событие отобрано), поэтому команды самопроверки из условия работают на нём как есть.
