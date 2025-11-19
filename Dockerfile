FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PORT=8000

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc default-libmysqlclient-dev pkg-config curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY planpalapp /app/

RUN mkdir -p /app/staticfiles /app/logs

RUN python manage.py collectstatic --noinput || true

EXPOSE 8000

CMD python manage.py migrate --noinput && \
    daphne -b 0.0.0.0 -p $PORT planpalapp.asgi:application
