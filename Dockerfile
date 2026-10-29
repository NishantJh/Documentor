FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HOMELAB_DOCS_DB=/var/lib/documentor/homelab.sqlite3

WORKDIR /app

RUN groupadd --system documentor && useradd --system --gid documentor --home-dir /nonexistent --shell /usr/sbin/nologin documentor
COPY pyproject.toml README.md ./
COPY src ./src
RUN pip install --no-cache-dir .

RUN mkdir -p /var/lib/documentor && chown -R documentor:documentor /var/lib/documentor /app
USER documentor

EXPOSE 8765
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8765/health', timeout=2).read()" || exit 1

CMD ["uvicorn", "homelab_docs.app:app", "--host", "0.0.0.0", "--port", "8765"]
