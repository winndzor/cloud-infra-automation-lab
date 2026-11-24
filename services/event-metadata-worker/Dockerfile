FROM python:3.13.7-slim-bookworm@sha256:adafcc17694d715c905b4c7bebd96907a1fd5cf183395f0ebc4d3428bd22d92d AS dependencies

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --requirement requirements.txt

FROM dependencies AS test

COPY requirements-dev.txt .
RUN pip install --no-cache-dir --requirement requirements-dev.txt

COPY app.py .
COPY pytest.ini .
COPY tests ./tests
RUN pytest --quiet

FROM dependencies AS runtime

RUN groupadd --gid 65532 app \
    && useradd \
      --uid 65532 \
      --gid 65532 \
      --no-create-home \
      --shell /usr/sbin/nologin \
      app

COPY --chown=65532:65532 app.py .

USER 65532:65532

EXPOSE 8080

CMD ["gunicorn", "--no-control-socket", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "4", "--timeout", "60", "app:app"]
