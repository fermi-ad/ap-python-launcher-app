FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

ARG TEST_APP_INDEX=docker/test-app/index.html
COPY ${TEST_APP_INDEX} /app/index.html

EXPOSE 14500

CMD ["python", "-m", "http.server", "14500", "--bind", "0.0.0.0"]
