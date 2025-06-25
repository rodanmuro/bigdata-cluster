FROM ubuntu:22.04

# --- Evita prompts interactivos (como tzdata) ---
ENV DEBIAN_FRONTEND=noninteractive

# --- Actualiza sistema y dependencias necesarias ---
RUN apt-get update && apt-get install -y \
    software-properties-common \
    wget \
    curl \
    gnupg \
    lsb-release \
    unzip \
    vim \
    ca-certificates \
    build-essential \
    tzdata \
    openjdk-17-jdk

# --- Configura JAVA_HOME para Java 17 ---
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# --- Instala Python 3.11 y pip ---
RUN add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update && \
    apt-get install -y python3.11 python3.11-distutils python3-pip && \
    ln -sf /usr/bin/python3.11 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

# --- Instala PySpark 4 y Jupyter ---
RUN pip install --upgrade pip && \
    pip install pyspark==4.0.0 jupyter

# --- Puerto Jupyter ---
EXPOSE 8888

# --- Directorio de trabajo ---
WORKDIR /app

# --- Comando de inicio: Jupyter sin token ni password ---
CMD ["jupyter", "notebook", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--allow-root", "--NotebookApp.token=''", "--NotebookApp.password=''"]
