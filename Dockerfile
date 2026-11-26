FROM mongo:7.0-jammy AS mongodb
FROM postgres:17-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends python3-venv libcurl4 tini && rm -rf /var/lib/apt/lists/* \
    && useradd --system --user-group alignflow && useradd --system --user-group mongod
COPY --from=mongodb /usr/bin/mongod /usr/local/bin/mongod
RUN mongod --version
WORKDIR /opt/vclear
COPY backend/requirements.txt .
RUN python3 -m venv /opt/venv && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt
ENV PATH="/opt/venv/bin:${PATH}" DATA_DIR=/storage/uploads
COPY backend/app app
COPY backend/config.yaml database/setup.sql docker/ ./
COPY flutter_app/build/web web
RUN sed -i 's/\r$//' start.sh && chmod +x start.sh
VOLUME /storage
EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=5s --start-period=90s CMD python -c "from urllib.request import urlopen; urlopen('http://localhost:8000/health', timeout=3)"
ENTRYPOINT ["tini", "--", "/opt/vclear/start.sh"]
