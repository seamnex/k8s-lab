# Kubernetes Lab — Resiliencia traducida a operaciones

Cluster local donde rompo aplicaciones a propósito para entender **qué mecanismo de
Kubernetes evita cuál incidente**.

> Parte de mi ruta de especialización en SRE / DevOps.
> Contexto: vengo de gestión de incidentes P1/P2; acá traduzco cada primitiva de
> Kubernetes a su equivalente operativo concreto.

---

## El problema

Es fácil recitar que Kubernetes "hace self-healing". Lo que no es obvio —y es lo único
que importa cuando estás en un War Room a las 3 AM— es **qué falla concreta cubre cada
mecanismo, y cuál no cubre ninguno**.

Un pod que reinicia en loop sigue siendo una caída si el health check está mal definido.
Un rolling update mal configurado deja el servicio sin capacidad en el peor momento.

## La solución

Un deployment simple con probes bien definidas, y una serie de fallas inyectadas a mano
para observar la reacción del cluster. La pregunta que guía cada prueba:
**"si esto pasara en producción, ¿el usuario se entera?"**

---

## Requisitos

Cualquier cluster local sirve:

- **Docker Desktop** con Kubernetes habilitado (Settings → Kubernetes → Enable), o
- [kind](https://kind.sigs.k8s.io/): `kind create cluster --name lab`, o
- [minikube](https://minikube.sigs.k8s.io/): `minikube start`

Verificar antes de empezar:

```bash
kubectl cluster-info
kubectl get nodes
```

## Cómo levantarlo

```bash
git clone https://github.com/seamnex/k8s-lab.git
cd k8s-lab

kubectl apply -f manifests/
kubectl get pods -w                    # esperar a que los 3 estén Running
curl http://localhost:30080            # verificar que responde
```

Bajar todo:

```bash
kubectl delete -f manifests/
```

---

## Los experimentos

Corré cada uno en una terminal mientras observás en otra con:

```bash
kubectl get pods -w
```

### 1. Self-healing — matar un pod

```bash
kubectl delete pod -l app=demo-api --field-selector status.phase=Running --wait=false
```

**Qué observar:** cuántos segundos tarda en volver a 3 réplicas listas, y si el
`curl` al Service llegó a fallar alguna vez.
**Equivalente operativo:** el proceso que antes había que levantar a mano de madrugada.

### 2. Rolling update — deploy sin caída

```bash
kubectl set image deployment/demo-api demo-api=nginx:1.28-alpine
kubectl rollout status deployment/demo-api
```

Mientras corre, en otra terminal:

```bash
while true; do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:30080; sleep 0.3; done
```

**Qué observar:** ¿aparece algún código distinto de 200?
**Equivalente operativo:** la ventana de mantenimiento nocturna que deja de ser necesaria.

### 3. Rollback — revertir un deploy roto

```bash
kubectl set image deployment/demo-api demo-api=nginx:version-que-no-existe
kubectl get pods                        # ImagePullBackOff
kubectl rollout undo deployment/demo-api
kubectl rollout history deployment/demo-api
```

**Qué observar:** los pods viejos **nunca se dieron de baja**, porque los nuevos jamás
pasaron readiness. El servicio siguió funcionando durante todo el deploy fallido.
**Equivalente operativo:** el rollback que antes era un procedimiento manual de 40 minutos.

### 4. Readiness vs. liveness — la distinción que más confunde

```bash
# Romper la readiness de un pod sin matar el proceso
POD=$(kubectl get pod -l app=demo-api -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- rm /usr/share/nginx/html/index.html
```

**Qué observar:** el pod queda `Running` pero `0/1 READY`, sale del balanceo y el
tráfico se reparte entre los otros dos. Después la liveness también falla y lo reinicia.
**Equivalente operativo:** la diferencia entre "el server está prendido" y "el server sirve".
Es exactamente el motivo por el que un monitoreo de ping no alcanza.

### 5. Sin capacidad — escalar más allá del cluster

```bash
kubectl scale deployment/demo-api --replicas=50
kubectl get pods | grep -c Pending
kubectl describe pod <uno-pending>      # leer los Events
```

**Qué observar:** qué dice exactamente el evento de scheduling fallido.
**Equivalente operativo:** el incidente de saturación que no se resuelve reiniciando nada.

---

## Bitácora de experimentos

<!-- COMPLETAR con tus corridas reales.
     No la publiques con datos inventados: es evidencia de que hiciste el laboratorio. -->

| # | Experimento | Tiempo de recuperación | ¿Hubo impacto al usuario? | Observación |
|---|---|---|---|---|
| 1 | Self-healing | | | |
| 2 | Rolling update | | | |
| 3 | Rollback | | | |
| 4 | Readiness/liveness | | | |
| 5 | Sin capacidad | | | |

## Qué me llevo de este lab

<!-- COMPLETAR después de correrlo. Ideas para desarrollar:
     - Qué incidente de los que gestionaste no lo habría evitado Kubernetes, y por qué.
     - Qué pasa si la liveness probe está mal definida (spoiler: reinicios en loop).
     - Por qué `maxUnavailable` es una decisión de negocio y no técnica. -->

---

## Estructura

```
k8s-lab/
├── manifests/
│   ├── deployment.yaml     # 3 réplicas, probes, límites, estrategia de rollout
│   └── service.yaml        # NodePort 30080
└── README.md
```

## Licencia

MIT
