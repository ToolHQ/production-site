# Slim Python collector — Google Trends via pytrends (T-363)
FROM python:3.12-slim-bookworm

RUN groupadd -g 65532 appuser && useradd -u 65532 -g appuser -d /app -s /sbin/nologin appuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY collect_trends.py .
RUN chmod 755 collect_trends.py

USER 65532:65532

ENTRYPOINT ["python3", "/app/collect_trends.py"]
