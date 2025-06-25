@echo off
echo ================================
echo Inicializando el clúster Hadoop
echo ================================

echo.
echo Creando directorio /user/admin en HDFS...
docker exec -it hadoop-namenode hdfs dfs -mkdir -p /user/admin
docker exec -it hadoop-namenode hdfs dfs -chown admin:admin /user/admin
docker exec -it hadoop-namenode hdfs dfs -mkdir -p /user/hive/warehouse 
docker exec -it hadoop-namenode hdfs dfs -chown admin:admin /user/hive/warehouse 

echo.
echo Inicializando el esquema del metastore (Hive)...
docker exec -it hive-server /opt/hive/bin/schematool -initSchema -dbType hive -metaDbType postgres -url jdbc:hive2://localhost:10000/default


echo.
echo Ejecutando migraciones en Hue...
docker exec -it hue bash -c "cd /usr/share/hue && ./build/env/bin/hue migrate"

echo Enlazando librerías necesarias para acceso a S3 en Hive...

docker exec -u root hive-server bash -c "ln -sf /opt/hadoop/share/hadoop/tools/lib/hadoop-aws-3.3.6.jar /opt/hadoop/share/hadoop/common/lib/"
docker exec -u root hive-server bash -c "ln -sf /opt/hadoop/share/hadoop/tools/lib/aws-java-sdk-bundle-1.12.367.jar /opt/hadoop/share/hadoop/common/lib/"

echo.
echo Proceso de inicialización completado.
pause
