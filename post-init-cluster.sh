#!/bin/bash

PROFILE="${1:-full}"

echo "========================================"
echo " Inicialización del Clúster - $PROFILE"
echo "========================================"

# ─── FUNCIONES ────────────────────────────────────

init_hadoop() {
    echo ""
    echo "[HADOOP] Creando directorios en HDFS..."
    docker exec hadoop-namenode hdfs dfs -mkdir -p /user/admin
    docker exec hadoop-namenode hdfs dfs -chown admin:admin /user/admin
    docker exec hadoop-namenode hdfs dfs -mkdir -p /user/hive/warehouse
    docker exec hadoop-namenode hdfs dfs -chown admin:admin /user/hive/warehouse
    echo "[HADOOP] Directorios creados."
}

init_hive() {
    echo ""
    echo "[HIVE] Inicializando esquema del metastore..."
    docker exec hive-server /opt/hive/bin/schematool -initSchema -dbType hive -metaDbType postgres -url jdbc:hive2://localhost:10000/default
    echo "[HIVE] Metastore inicializado."
}

init_hue() {
    echo ""
    echo "[HUE] Ejecutando migraciones de base de datos..."
    docker exec hue bash -c "cd /usr/share/hue && ./build/env/bin/hue migrate"
    echo "[HUE] Migraciones completadas."
}

# ─── EJECUCIÓN POR PROFILE ────────────────────────

case "$PROFILE" in
    hadoop)
        init_hadoop
        ;;
    hive)
        init_hadoop
        init_hive
        init_hue
        ;;
    spark)
        init_hadoop
        ;;
    full)
        init_hadoop
        init_hive
        init_hue
        ;;
    *)
        echo ""
        echo "Profile no reconocido: '$PROFILE'"
        echo ""
        echo "Uso: ./post-init-cluster.sh [profile]"
        echo ""
        echo "Profiles disponibles:"
        echo "  hadoop  - Solo inicializa directorios HDFS"
        echo "  hive    - HDFS + metastore Hive + migraciones Hue"
        echo "  spark   - Solo inicializa directorios HDFS"
        echo "  full    - Inicialización completa (por defecto)"
        exit 1
        ;;
esac

echo ""
echo "========================================"
echo " Inicialización completada: $PROFILE"
echo "========================================"
echo ""
echo "Nota: si algún paso falló por conexión, espera"
echo "unos segundos y vuelve a ejecutar el script."
