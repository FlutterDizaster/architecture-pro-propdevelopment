#!/bin/bash
# Выжимка подозрительных событий из audit.log Kubernetes.
# Запуск: ./filter-audit.sh /path/to/audit.log [audit-extract.json]
set -euo pipefail

log="${1:?укажите путь к audit.log}"
out="${2:-audit-extract.json}"

jq -c '
  def pod_spec: .requestObject.spec // {};
  def containers: (pod_spec.containers // []) + (pod_spec.initContainers // []);

  # у каждого запроса в логе несколько стадий, беру только итоговую
  select(.stage == "ResponseComplete")

  | [
      # чтение секретов (watch системных контроллеров не считаю)
      (select(.objectRef.resource == "secrets" and (.verb == "get" or .verb == "list"))
        | "secrets-read"),

      (select(.objectRef.resource == "pods" and .verb == "create"
              and any(containers[]; .securityContext.privileged == true))
        | "privileged-pod"),

      # kubectl по websocket шлёт exec как GET, по SPDY как POST, поэтому verb не проверяю
      (select(.objectRef.resource == "pods"
              and (.objectRef.subresource == "exec" or .objectRef.subresource == "attach"))
        | "pod-exec"),

      # тело привязки в лог попадает не всегда: если его нет, беру любую привязку,
      # созданную не системным компонентом
      (select((.objectRef.resource == "rolebindings" or .objectRef.resource == "clusterrolebindings")
              and (.verb == "create" or .verb == "update" or .verb == "patch")
              and (.user.username | startswith("system:") | not)
              and (.requestObject == null or .requestObject.roleRef.name == "cluster-admin"))
        | "rolebinding"),

      # удаление или изменение объекта с политикой аудита
      (select((.verb == "delete" or .verb == "update" or .verb == "patch")
              and (.objectRef.name == "audit-policy" or (.requestURI | test("audit-policy"))))
        | "audit-policy"),

      (select(.impersonatedUser != null) | "impersonation")
    ] as $why
  | select($why | length > 0)

  # оставляю поля, нужные для разбора; ответы и служебные поля объектов выкидываю
  | {
      suspicious: $why,
      auditID, level, verb, requestURI,
      user: {username: .user.username, groups: .user.groups},
      impersonatedUser,
      sourceIPs, userAgent, objectRef,
      responseStatus: {code: .responseStatus.code, reason: .responseStatus.reason, message: .responseStatus.message},
      requestObject: (
        if .requestObject.kind == "Pod" then
          {kind: "Pod",
           metadata: {name: .requestObject.metadata.name, namespace: .requestObject.metadata.namespace},
           spec: {hostNetwork: pod_spec.hostNetwork,
                  containers: [containers[] | {name, image, command, securityContext}]}}
        else .requestObject end),
      requestReceivedTimestamp, stageTimestamp,
      annotations
    }
  | del(.. | nulls)
' "$log" > "$out"

echo "Отобрано событий: $(wc -l < "$out" | tr -d ' ') -> $out"
jq -r '.suspicious[]' "$out" | sort | uniq -c
