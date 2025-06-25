#!/bin/bash

echo "==============================="
echo "Inicializando el clúster Hadoop"
echo "==============================="

echo
echo "Creando directorio /user/admin en HDFS..."
docker exec -it hadoop-namenode hdfs dfs -mkdir -p /user/admin
docker exec -it hadoop-namenode hdfs dfs -chown admin:admin /user/admin
docker exec -it hadoop-namenode hdfs dfs -mkdir -p /user/hive/warehouse 
docker exec -it hadoop-namenode hdfs dfs -chown admin:admin /user/hive/warehouse 

echo
echo "Inicializando el esquema del metastore (Hive)..."
docker exec -it hive-server /opt/hive/bin/schematool -initSchema -dbType hive -metaDbType postgres -url jdbc:hive2://localhost:10000/default

echo
echo "Ejecutando migraciones en Hue..."
docker exec -it hue bash -c "cd /usr/share/hue && ./build/env/bin/hue migrate"


echo
echo "Proceso de inicialización completado."
