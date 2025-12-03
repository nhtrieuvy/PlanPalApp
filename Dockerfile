FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PORT=8000

WORKDIR /app

# Cài đặt Redis, Supervisor và các dependencies
RUN apt-get update && apt-get install -y \
    gcc default-libmysqlclient-dev pkg-config curl \
    redis-server \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY planpalapp /app/
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN mkdir -p /app/staticfiles /app/logs

RUN python manage.py collectstatic --noinput || true

EXPOSE 8000

CMD python manage.py migrate --noinput && \
    /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
