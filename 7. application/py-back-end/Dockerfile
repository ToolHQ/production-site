FROM python:3.12-slim as base

# Install required system dependencies, build tools and Rust
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    libboost-all-dev \
    cmake \
    curl \
    libsnappy-dev \
    libzstd-dev \
    liblz4-dev \
    libbz2-dev \
    libbrotli-dev \
    python3-numpy \
    python3-pandas \
    build-essential \
    libssl-dev \
    libffi-dev \
    rustc \
    cargo

WORKDIR /app

# Install the latest version of pip, setuptools and wheel
RUN pip install --upgrade pip setuptools wheel

# Install pyarrow via pip (it will use system libraries installed above)
RUN pip install pyarrow==17.0.0

FROM base
RUN apt-get update && apt-get install -y libpq-dev

# Set environment variables for Oracle Instant Client
ENV ORACLE_INSTANTCLIENT_VERSION=21.16.0.0.0dbru \
    ORACLE_HOME=/usr/lib/oracle \
    PATH="/usr/lib/oracle:$PATH" \
    LD_LIBRARY_PATH="/usr/lib/oracle:$LD_LIBRARY_PATH"

# Install dependencies for Oracle Instant Client
RUN apt-get update && apt-get install -y --no-install-recommends \
    libaio1 wget unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Download and install Oracle Instant Client
RUN wget https://download.oracle.com/otn_software/linux/instantclient/2116000/instantclient-basic-linux.x64-${ORACLE_INSTANTCLIENT_VERSION}.zip \
    && unzip instantclient-basic-linux.x64-${ORACLE_INSTANTCLIENT_VERSION}.zip \
    && mv instantclient_* ${ORACLE_HOME} \
    && rm -f instantclient-basic-linux.x64-${ORACLE_INSTANTCLIENT_VERSION}.zip

RUN ls -l /usr/lib/oracle

# Set symbolic links only if they do not exist
RUN if [ ! -L ${ORACLE_HOME}/libclntsh.so ]; then \
    ln -s ${ORACLE_HOME}/libclntsh.so.21.1 ${ORACLE_HOME}/libclntsh.so; \
    fi \
    && if [ ! -L ${ORACLE_HOME}/libocci.so ]; then \
    ln -s ${ORACLE_HOME}/libocci.so.21.1 ${ORACLE_HOME}/libocci.so; \
    fi

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY log_config.json ./
COPY ./app ./app
CMD ["uvicorn", "app.main:app", "--workers", "4", "--reload", "--no-access-log", "--host", "0.0.0.0", "--port", "3000", "--no-server-header"]
