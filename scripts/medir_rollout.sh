#!/usr/bin/env bash
# Mide el impacto al usuario durante un rolling update.
#
# El metodo importa: la sonda corre DENTRO del cluster, contra el Service.
# Medir desde el host con el NodePort no sirve en Docker Desktop (el puerto
# no queda mapeado) y un port-forward tampoco, porque se ata a un solo pod
# y justamente lo que queres ejercitar es el balanceo.
#
#   ./scripts/medir_rollout.sh nginx:1.28-alpine
#
# Salida: distribucion de codigos HTTP y duracion del rollout.
# Un 000 es un fallo de conexion (nginx ya cerro el listener), no un 5xx.
set -euo pipefail

IMAGEN="${1:-nginx:1.28-alpine}"
SONDA="probe-rollout"
RPS=5

limpiar() { kubectl delete pod "${SONDA}" --ignore-not-found --wait=false >/dev/null 2>&1 || true; }
trap limpiar EXIT

echo "[1/4] Verificando que el deployment este estable..."
kubectl rollout status deployment/demo-api --timeout=60s

echo "[2/4] Lanzando sonda interna a ~${RPS} req/s..."
limpiar
# Esperar la baja EFECTIVA, no un sleep a ojo: un pod en Terminating sigue
# ocupando el nombre y el `kubectl run` falla con AlreadyExists.
kubectl wait --for=delete "pod/${SONDA}" --timeout=90s >/dev/null 2>&1 || true
kubectl run "${SONDA}" --image=curlimages/curl:8.10.1 --restart=Never -- \
  sh -c "while true; do curl -s -o /dev/null -w '%{http_code}\n' --max-time 2 http://demo-api; sleep $(awk "BEGIN{print 1/${RPS}}"); done" >/dev/null

kubectl wait --for=condition=Ready "pod/${SONDA}" --timeout=60s
echo "      sonda lista, dejando 10s de linea base..."
sleep 10

echo "[3/4] Disparando rolling update a ${IMAGEN}..."
INICIO=$(date +%s)
kubectl set image deployment/demo-api "demo-api=${IMAGEN}"
kubectl rollout status deployment/demo-api --timeout=300s
FIN=$(date +%s)
echo "      rollout completo en $((FIN - INICIO))s"

echo "      dejando 10s de cola para capturar coletazos..."
sleep 10

# Un solo snapshot del log: la sonda sigue escribiendo, y leerlo tres veces
# da tres totales distintos que no cierran entre si.
SNAPSHOT=$(mktemp)
kubectl logs "${SONDA}" | tr -d '\r' | grep . > "${SNAPSHOT}" || true

echo "[4/4] Distribucion de codigos observada por la sonda:"
sort "${SNAPSHOT}" | uniq -c | sort -rn

TOTAL=$(wc -l < "${SNAPSHOT}" | tr -d ' ')
FALLOS=$(grep -cv '^200$' "${SNAPSHOT}" || true)
rm -f "${SNAPSHOT}"
echo
echo "  total peticiones : ${TOTAL}"
echo "  no-200           : ${FALLOS}"
if [[ "${TOTAL}" -gt 0 ]]; then
  awk "BEGIN{printf \"  tasa de fallo    : %.2f%%\n\", (${FALLOS}/${TOTAL})*100}"
fi
echo
echo "Comparar contra la bitacora del README (corrida sin preStop: 2,4% en 000)."
