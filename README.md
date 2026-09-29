# Orchestrator

Déploiement d'une architecture microservices dans un cluster K3s
(Kubernetes léger) avec Vagrant.

## Description

Ce projet déploie dans un cluster K3s :

- **inventory-db** : base PostgreSQL (port 5432)
- **billing-db** : base PostgreSQL (port 5432)
- **inventory-app** : serveur d'inventaire (port 8080)
- **billing-app** : serveur de facturation, consomme RabbitMQ (port 8080)
- **rabbit-queue** : serveur RabbitMQ (port 5672)
- **api-gateway-app** : passerelle API (port 3000)

## Prérequis

- [Vagrant](https://www.vagrantup.com/downloads)
- [VirtualBox](https://www.virtualbox.org/wiki/Downloads) ou
  [libvirt](https://libvirt.org/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Docker](https://docs.docker.com/engine/install/)
- Un compte [Docker Hub](https://hub.docker.com/)

## Démarrer le cluster

Toutes les commandes se font à la racine du projet.

### 1. Créer le cluster

```bash
./orchestrator.sh create
```

Cette commande :
- crée les 2 VM Vagrant (`master` et `agent`)
- installe K3s sur le master (`192.168.56.10`)
- installe K3s sur l'agent (`192.168.56.11`)
- connecte l'agent au master

### 2. Vérifier les nœuds

```bash
./orchestrator.sh status
```

Résultat attendu :

```console
NAME        STATUS   ROLES    AGE   VERSION
k3s-master   Ready    <none>   Xd    v1.30.14+k3s1
k3s-agent    Ready    <none>   Xd    v1.30.14+k3s1
```

### 3. Démarrer / arrêter

```bash
./orchestrator.sh start
./orchestrator.sh stop
```

### 4. Détruire

```bash
./orchestrator.sh destroy
```

## Images Docker Hub

Toutes les images sont poussées sur Docker Hub sous `mohaa04`.

| Image | Rôle | Port |
|-------|------|------|
| `mohaa04/api-gateway-app:latest` | Passerelle API | 3000 |
| `mohaa04/inventory-app:latest` | Inventaire | 8080 |
| `mohaa04/billing-app:latest` | Facturation | 8080 |
| `mohaa04/inventory-db:latest` | Base inventaire | 5432 |
| `mohaa04/billing-db:latest` | Base facturation | 5432 |
| `mohaa04/rabbit-queue:latest` | RabbitMQ | 5672 |

Les manifests utilisent ces images directement, sans build local.

## Manifests

Un manifest par composant, dans le dossier `manifests/`.

| Fichier | Type | Rôle |
|---------|------|------|
| `api-gateway-deployment.yaml` | Deployment | API Gateway |
| `api-gateway-service.yaml` | Service | Expose l'API Gateway |
| `api-gateway-hpa.yaml` | HPA | Auto-scaling (1→3, CPU 60%) |
| `inventory-app-deployment.yaml` | Deployment | Inventaire |
| `inventory-app-service.yaml` | Service | Expose l'inventaire |
| `inventory-app-hpa.yaml` | HPA | Auto-scaling (1→3, CPU 60%) |
| `billing-app-statefulset.yaml` | StatefulSet | Facturation |
| `billing-app-service.yaml` | Service | Expose la facturation |
| `billing-db-statefulset.yaml` | StatefulSet | Base facturation |
| `billing-db-service.yaml` | Service | Expose la base facturation |
| `inventory-db-statefulset.yaml` | StatefulSet | Base inventaire |
| `inventory-db-service.yaml` | Service | Expose la base inventaire |
| `rabbit-queue-statefulset.yaml` | StatefulSet | RabbitMQ |
| `rabbit-queue-service.yaml` | Service | Expose RabbitMQ |

### Déploiement

```bash
kubectl apply -f manifests/
```

### Les bases de données et RabbitMQ sont des StatefulSet

Ils ont chacun un volume persistant (PVC) pour ne pas perdre les données
si un Pod est supprimé ou déplacé.

## Secrets

Tous les mots de passe sont stockés dans des **Secrets Kubernetes**,
jamais en clair dans les manifests.

| Secret | Contenu |
|--------|---------|
| `billing-db-secret` | `POSTGRES_USER`, `POSTGRES_DB`, `POSTGRES_PASSWORD` |
| `billing-app-secret` | `BILLING_DB_USER`, `BILLING_DB_NAME`, `BILLING_DB_PASSWORD` |
| `inventory-db-secret` | `POSTGRES_USER`, `POSTGRES_DB`, `POSTGRES_PASSWORD` |
| `inventory-app-secret` | `INVENTORY_DB_USER`, `INVENTORY_DB_NAME`, `INVENTORY_DB_PASSWORD` |
| `rabbit-queue-secret` | `RABBITMQ_USER`, `RABBITMQ_PASSWORD`, `RABBITMQ_QUEUE` |

Les applications récupèrent ces valeurs avec `envFrom: secretRef`.

## Tester l'application

### 1. Ouvrir l'accès à l'API Gateway

```bash
kubectl port-forward service/api-gateway-app 3000:3000
```

Laisse cette fenêtre ouverte.

### 2. Envoyer une facture

```bash
curl -X POST http://localhost:3000/api/billing/ \
  -H "Content-Type: application/json" \
  -d '{"user_id":1,"number_of_items":2,"total_amount":100}'
```

Réponse attendue :

```json
{"message":"{'user_id': 1, 'number_of_items': 2, 'total_amount': 100} sent"}
```

### 3. Vérifier dans la base

```bash
kubectl exec billing-db-0 -- sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT * FROM orders;"'
```

### 4. Voir les logs

```bash
kubectl logs -f billing-app-0
kubectl logs -f deploy/api-gateway-app
```

## Bonus

### Kubernetes Dashboard

Pour monitorer le cluster dans le navigateur :

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
kubectl proxy
```

Puis ouvrir :

```console
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

### Persistance des données

Les bases de données et RabbitMQ sont des StatefulSet avec des volumes
persistants (PVC). Si un Pod est supprimé, Kubernetes le recrée et les
données sont conservées.

Test :

```bash
kubectl delete pod billing-db-0
kubectl exec billing-db-0 -- sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT * FROM orders;"'
```
