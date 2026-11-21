# Роли в кластере Kubernetes

Кластер поделил по доменам компании: namespace `sales` (продажи), `housing` (ЖКУ), `finance` (финансы), `data` (дата). Права выдаю группам, группа пользователя записана в его сертификате (поле O). Для доменных ролей групп по четыре, по одной на домен: `sales-viewers`, `housing-viewers` и так далее.

| Роль | Права роли | Группы пользователей |
| --- | --- | --- |
| `view` (встроенная ClusterRole, привязка RoleBinding в namespace домена) | Только чтение ресурсов в namespace своего домена: поды, деплойменты, сервисы, конфигмапы, логи, события. Секреты не видны, менять ничего нельзя. | `<домен>-viewers`: владельцы продуктов, бизнес-аналитики и менеджеры операционных команд домена |
| `domain-developer` (своя ClusterRole, привязка RoleBinding в namespace домена) | Чтение и изменение рабочих нагрузок в namespace своего домена: поды, деплойменты, statefulset, daemonset, job, cronjob, сервисы, ingress, конфигмапы, PVC, HPA; чтение логов и событий. Секреты читать нельзя, нет exec в поды, сервисных аккаунтов и RBAC. Оговорка: тот, кто создаёт поды, может смонтировать в под секрет своего namespace, поэтому секреты домена лежат только в его namespace и с другими доменами не делятся. | `<домен>-developers`: разработчики и инженеры по эксплуатации функциональных команд домена |
| `edit` (встроенная ClusterRole, привязка RoleBinding в namespace домена) | Привилегированная роль домена: всё, что может `domain-developer`, плюс чтение и изменение секретов, exec и port-forward в поды, управление сервисными аккаунтами namespace и работа от их имени (impersonate). Только в namespace своего домена, роли и привязки менять нельзя. | `<домен>-devops`: DevOps-инженеры функциональных команд домена |
| `cluster-configurator` (своя ClusterRole, привязка ClusterRoleBinding) | Настройка кластера: создание и изменение namespace, изменение нод (cordon, метки, taint) и вытеснение подов с ноды (drain), PersistentVolume и StorageClass, сетевые политики, IngressClass, квоты и лимиты, PriorityClass, CRD. Удалять namespace и ноды нельзя. Рабочие нагрузки только на чтение. Нет секретов и RBAC. | `cluster-operators`: DevOps-инженеры, которым поручена общая инфраструктура кластера |
| `security-auditor` (своя ClusterRole) вместе с `view`, обе через ClusterRoleBinding | Чтение всего кластера, включая секреты, роли и привязки RBAC, сервисные аккаунты, ноды, сетевые политики и запросы на сертификаты. Менять ничего нельзя. | `security-auditors`: специалист по ИБ |

Встроенные `view` и `edit` взял там, где они подходят как есть. Для разработчиков `edit` не годится: она даёт читать секреты и заходить в поды через exec, а это я оставил только DevOps-инженеру домена. Поэтому для них своя роль `domain-developer`. Она описана как ClusterRole, чтобы не копировать одинаковую Role в четыре namespace, но выдаётся через RoleBinding и за пределами своего namespace не действует.

Для настройки кластера не стал выдавать `cluster-admin`: с ней человек читает секреты всех доменов и может сам себе выписать любые права. В `cluster-configurator` только инфраструктурные ресурсы, причём удалить namespace она не может: вместе с namespace пропал бы весь домен. `cluster-admin` остаётся у встроенной группы `system:masters` (учётная запись, от которой запускаются эти скрипты) и людям на каждый день не выдаётся.

Специалист по ИБ в компании один и отвечает за все домены, поэтому у него чтение на весь кластер вместе с секретами и RBAC: так он может проверять, кому что выдано, без права что-то менять.

Связь с предыдущими заданиями такая. Секретные и конфиденциальные данные доменов (пароли к базам, ключи интеграций) лежат в секретах namespace своего домена, и читать их могут только DevOps-инженер этого домена и специалист по ИБ. Новый smart-home-app из задания 3 живёт в `housing`, поэтому ключи партнёрской платформы видит только группа `housing-devops`. Бизнес-аналитик получает только `view`, хотя на исходной диаграмме он администрирует системы: для администрирования прикладной системы права в кластере не нужны.

## Отзыв доступа

Клиентский сертификат в Kubernetes отозвать нельзя, он действует до конца срока. Поэтому сертификаты выпускаю на неделю: если человек уволился или перешёл в другой домен, старый доступ сам закончится через несколько дней, а новый сертификат ему выпишут уже с другой группой. Выписать запрет конкретному пользователю не получится, в RBAC есть только разрешения. Если ждать нельзя, остаётся убрать из привязки всю его группу, пока сертификат жив, а остальным участникам перевыпустить сертификаты с новой группой. В боевом кластере я бы вместо сертификатов сделал вход через OIDC с группами из службы каталогов: тогда отзыв доступа это изменение группы в каталоге, и срабатывает оно по событию, а не по сроку.

## Скрипты

Запускаются по порядку от имени администратора кластера, работают с текущим контекстом kubectl. Повторный запуск безопасен.

1. `01-create-users.sh` создаёт пять пользователей, по одному на роль: ключ, CertificateSigningRequest, подпись, запись пользователя и контекста в kubeconfig. Ключи и сертификаты складываются в `.certs/`, в репозиторий они не попадают.
2. `02-create-roles.sh` создаёт namespace доменов и три свои роли.
3. `03-bind-roles.sh` привязывает группы к ролям.

| Пользователь | Группа | Роль |
| --- | --- | --- |
| olga-sales-analyst | sales-viewers | `view` в sales |
| ivan-sales-dev | sales-developers | `domain-developer` в sales |
| petr-sales-devops | sales-devops | `edit` в sales |
| sergey-platform | cluster-operators | `cluster-configurator` |
| elena-security | security-auditors | `security-auditor` и `view` |

Группы остальных доменов привязаны тем же скриптом, отдельных пользователей для них не заводил и проверял через `--as-group`.

## Проверка

Проверял на пустом minikube после запуска трёх скриптов. В комментарии ответ кластера.

```bash
# наблюдатель видит свой домен, но не секреты и не чужой домен
kubectl --context olga-sales-analyst auth can-i get pods -n sales             # yes
kubectl --context olga-sales-analyst auth can-i get secrets -n sales          # no
kubectl --context olga-sales-analyst auth can-i get pods -n finance           # no

# разработчик работает только в своём namespace и без секретов
kubectl --context ivan-sales-dev auth can-i create deployments -n sales       # yes
kubectl --context ivan-sales-dev auth can-i get secrets -n sales              # no
kubectl --context ivan-sales-dev auth can-i create deployments -n housing     # no

# DevOps домена читает секреты своего домена, но не чужого
kubectl --context petr-sales-devops auth can-i get secrets -n sales           # yes
kubectl --context petr-sales-devops auth can-i get secrets -n finance         # no

# настройка кластера: namespace создать можно, удалить нельзя, секретов нет
kubectl --context sergey-platform auth can-i create namespaces                # yes
kubectl --context sergey-platform auth can-i delete namespaces                # no
kubectl --context sergey-platform auth can-i get secrets -n sales             # no

# ИБ читает секреты всего кластера, но ничего не меняет
kubectl --context elena-security auth can-i get secrets -A                    # yes
kubectl --context elena-security auth can-i delete pods -n sales              # no

# группа домена, для которой пользователя не заводил
kubectl auth can-i get secrets -n housing --as=someone --as-group=housing-devops      # yes
kubectl auth can-i get secrets -n housing --as=someone --as-group=housing-developers  # no
```
