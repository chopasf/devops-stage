# Kubernetes DevOps Stage

Развёртывание простой веб-службы в Kubernetes с использованием Gateway API, Prometheus и Filebeat.

## 1. Окружение

- ОС: Ubuntu Server 24.04.4 LTS
- Kubernetes: v1.34.12
- Установка Kubernetes: kubeadm
- Container runtime: containerd
- CNI: Flannel
- Helm: v3.22.0
- Gateway API implementation: Envoy Gateway v1.6.0
- Monitoring: kube-prometheus-stack 91.9.0
- Prometheus: v0.94.1
- Logging: Filebeat 9.1.4
- Архитектура: single-node Kubernetes cluster

## 2. Архитектура

```text
Client
  |
  | HTTP
  v
NodePort :30866
  |
  v
Envoy Gateway
  |
  v
Gateway API HTTPRoute
  |
  v
Service/nginx
  |
  v
Nginx Pod
  |
  +--> access logs
          |
          v
       Filebeat
          |
          v
/var/log/filebeat-output/nginx-YYYYMMDD.ndjson

Prometheus
    |
    +--> node-exporter
```
## 3. Структура проекта

```text
devops-stage/
├── deploy.sh
├── prometheus-values.yaml
├── README.md
├── k8s/
│   ├── namespace.yaml
│   ├── kustomization.yaml
│   ├── gateway.yaml
│   ├── app.yaml
│   └── httproute.yaml
└── logging/
    └── filebeat.yaml
```
## 4. Подготовка Kubernetes

Кластер создавался с помощью kubeadm:

    kubeadm init --pod-network-cidr=10.244.0.0/16

После инициализации был установлен Flannel CNI.

Для single-node кластера снято ограничение с control-plane:

    kubectl taint nodes --all node-role.kubernetes.io/control-plane-

## 5. Развёртывание

Основной сценарий развёртывания находится в deploy.sh.

Запуск:

    chmod +x deploy.sh
    ./deploy.sh

Скрипт:

1. устанавливает или обновляет Envoy Gateway;
2. ожидает готовности контроллера;
3. устанавливает или обновляет kube-prometheus-stack;
4. применяет Kubernetes-манифесты через Kustomize;
5. разворачивает Filebeat;
6. снимает taint с control-plane для single-node кластера.

Повторный запуск использует helm upgrade --install и kubectl apply.

## 6. Веб-приложение

В качестве демонстрационного приложения используется Nginx:

    nginx:1.27-alpine

Приложение возвращает:

    Hello from Kubernetes!

Контент передаётся через ConfigMap.

Проверка приложения внутри Pod:

    kubectl exec -n demo deploy/nginx -- wget -qO- http://127.0.0.1/

## 7. Gateway API

Используется Envoy Gateway v1.6.0.

Основные ресурсы:

- GatewayClass eg
- Gateway demo-gateway
- HTTPRoute nginx

Проверка:

    kubectl get gatewayclass,gateway,httproute -n demo

Gateway направляет HTTP-запросы по следующей цепочке:

    HTTPRoute nginx -> Service nginx:80 -> Nginx

В текущем single-node окружении внешний LoadBalancer не предоставляется, поэтому Envoy Gateway доступен через NodePort.

Проверка сервиса:

    kubectl get svc -n envoy-gateway-system

Пример:

    envoy-demo-demo-gateway-b23f25a6   LoadBalancer   ...   <pending>   80:30866/TCP

Проверка HTTP:

    curl -i http://10.0.2.15:30866/

Ожидаемый ответ:

    HTTP/1.1 200 OK

    Hello from Kubernetes!

## 8. Prometheus

Для мониторинга используется kube-prometheus-stack.

Prometheus собирает метрики с node-exporter.

Проверка компонентов:

    kubectl get pods -n monitoring

Для доступа к Prometheus можно использовать port-forward:

    kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090

Проверка метрики:

    curl -s --get http://127.0.0.1:9090/api/v1/query \
      --data-urlencode 'query=up{job="node-exporter"}'

В рабочем состоянии запрос возвращает target node-exporter со значением 1, что означает успешный сбор метрик.

## 9. Сбор логов

Для сбора логов используется Filebeat 9.1.4.

Filebeat развёрнут как DaemonSet и получает доступ к логам Kubernetes Pods через /var/log.

Источник логов Nginx:

    /var/log/pods/demo_nginx-*/nginx/*.log

Filebeat записывает собранные события в:

    /var/log/filebeat-output/nginx-YYYYMMDD.ndjson

Проверка:

    sudo ls -la /var/log/filebeat-output/

После HTTP-запроса:

    curl http://10.0.2.15:30866/

можно проверить полученный лог:

    sudo tail -n 5 /var/log/filebeat-output/nginx-$(date +%Y%m%d).ndjson

Пример записи:

    10.244.0.7 - - [04/Oct/2026:20:10:16 +0000] "GET / HTTP/1.1" 200 23 "-" "curl/8.5.0" "10.0.2.1"

Таким образом подтверждается цепочка:

    Nginx -> Kubernetes container log -> Filebeat -> output file

## 10. Проверка состояния кластера

Общий список Pod:

    kubectl get pods -A

Проверка Gateway API:

    kubectl get gatewayclass,gateway,httproute -n demo

Проверка сервисов:

    kubectl get svc -A

## 11. Конфигурационные файлы

k8s/app.yaml содержит ConfigMap, Deployment и Service приложения.

k8s/gateway.yaml содержит GatewayClass и Gateway.

k8s/httproute.yaml содержит HTTPRoute.

logging/filebeat.yaml содержит ConfigMap Filebeat и DaemonSet.

prometheus-values.yaml содержит настройки kube-prometheus-stack.

deploy.sh объединяет установку зависимостей и развёртывание компонентов проекта.
