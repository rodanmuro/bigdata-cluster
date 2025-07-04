# Guía para Levantar un Clúster Big Data con Docker Compose

Este repositorio contiene un conjunto de servicios orquestados con Docker Compose para levantar un clúster de Big Data compuesto por Hadoop, Hive, Hue, Spark, Jupyter, Superset y PostgreSQL.

---

## Requisitos Previos

* Docker y Docker Compose instalados
* Maven (solo si vas a reconstruir los jars de Hive)

---

## Pasos para Inicializar el Clúster

### 1. Construir la imagen personalizada de PySpark y Jupyter (opcional)

```bash
docker build -t python-pyspark4-jupyter .
```

### 2. Levantar los servicios

```bash
docker compose up -d
```

### 3. Ejecutar el script de inicialización (una vez todos los servicios estén corriendo)

```bash
# Linux
./post-init-cluster.sh

# Windows (Git Bash o WSL recomendado)
./post-init-cluster.bat
```

---

## Puertos Expuestos en el Host

| Servicio         | Puerto |
| ---------------- | ------ |
| NameNode         | 9870   |
| DataNode 1       | 9864   |
| DataNode 2       | 9865   |
| Hive Web UI      | 10002  |
| Hue              | 8888   |
| Spark Master     | 8081   |
| Spark Worker 1   | 8082   |
| Spark Worker 2   | 8083   |
| Jupyter Notebook | 8084   |
| Apache Superset  | 8088   |

---

## Estructura del Proyecto

```
HADOOP-HIVE-ENSAYO-1 V6
├── hadoop-config/
├── hive-config/
├── hue-config/
├── postgres-driver/
├── docker-compose.yml
├── Dockerfile
├── post-init-cluster.sh
├── post-init-cluster.bat
├── README.md
└── superset_config.py
```

---

## Servicios y Configuraciones

### PySpark + Jupyter

* Imagen basada en Ubuntu con:

  * Python 3.11
  * Java 17
  * PySpark 4.0
* Construida localmente por compatibilidad con las versiones recientes de Spark.

### Hadoop (NameNode y DataNodes)

* Versión: Hadoop 3.4.1
* Archivos requeridos:

  * `core-site.xml`
  * `hdfs-site.xml`
* Formatear HDFS:

```bash
hdfs namenode -format
```

* Desactivar permisos en HDFS (`dfs.permissions=false`) para permitir que Hive escriba en `/` (solo en pruebas).

### Hive

* Tres contenedores:

  * `hive-server`
  * `hive-metastore`
  * `postgres-metastore`
* Inicialización del metastore basada en: [documentación oficial](https://github.com/apache/hive/tree/master/packaging/src/docker)
* Driver PostgreSQL mapeado a `/opt/hive/lib/postgres.jar`
* El `postgres.jar` proviene del [repositorio oficial JDBC](https://jdbc.postgresql.org/download.html) y tiene licencia BSD.

### Hue

* Utiliza una base de datos PostgreSQL (`postgres-hue`) en lugar de SQLite.
* Configuraciones esenciales en `hue.ini`:

```ini
[beeswax]
hive_server_host=hive-server
hive_server_port=10000

[database]
engine=postgresql_psycopg2
host=postgres-hue
port=5432
user=hue
password=hue
name=hue
```

* Migración de la base de datos (ejecutada en `post-init-cluster`):

```bash
./build/env/bin/hue migrate
```

### Conexión a AWS S3

1. Crear bucket con permisos públicos:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPublicReadAndList",
      "Effect": "Allow",
      "Principal": "*",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::mibucketnombre",
        "arn:aws:s3:::mibucketnombre/*"
      ]
    }
  ]
}
```

2. Crear carpeta como `data/` dentro del bucket y subir archivos.
3. Enlazar jars de AWS con `ln` (definido en el `docker-compose.yml`).
4. Crear tabla externa en Hive desde Hue:

```sql
CREATE EXTERNAL TABLE propiedades (
  frente INT,
  profundidad INT,
  precio INT
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 's3a://mibucket/data/'
TBLPROPERTIES ('skip.header.line.count'='1');
```

---

## Script post-init-cluster

* Crea carpetas en HDFS
* Inicializa el metastore de Hive
* Ejecuta migraciones de Hue

**Nota:** Si el script falla por conexión, espera unos segundos y vuelve a ejecutarlo.

---

## Apache Superset

* Ya configurado para conectarse a Hive.
* Acceso: `http://localhost:8088`, usuario y contraseña: `admin`
* Conexión a Hive:

```bash
hive://hive@hive-server:10000/misdatos
```

---

## Consideraciones Finales

* Este entorno está diseñado con fines **académicos**.
* No recomendado para **producción** sin ajustes de seguridad adicionales.

---

## Recursos Recomendados

* Libro: *Big Data Analytics with Hadoop 3*
* Documentación oficial:

  * [Apache Hadoop](https://hadoop.apache.org/)
  * [Apache Hive](https://hive.apache.org/)
  * [Hue](https://gethue.com/)
  * [Apache Superset](https://superset.apache.org/)
  * [PySpark](https://spark.apache.org/docs/latest/api/python/)


Nota: el archivo postgres.jar proviene del repositorio oficial de PostgreSQL JDBC Driver (https://jdbc.postgresql.org/download.html) y se incluye para facilitar la integración con Hive. Se encuentra bajo licencia BSD.