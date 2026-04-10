#!/bin/bash

CLEAN="${1}"

echo "========================================"
echo " Apagando el Clúster Big Data"
echo "========================================"

if [ "$CLEAN" = "-v" ]; then
    echo ""
    echo "Modo limpieza: se eliminarán todos los volúmenes (datos)."
    docker compose --profile full down -v
    echo ""
    echo "Clúster apagado y datos eliminados."
    echo "Recuerda ejecutar post-init-cluster al volver a levantar."
else
    docker compose --profile full down
    echo ""
    echo "Clúster apagado. Los datos se conservaron."
    echo "Para eliminar también los datos: ./stop-cluster.sh -v"
fi

echo "========================================"
