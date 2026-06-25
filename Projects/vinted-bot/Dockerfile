FROM python:3.12-slim

WORKDIR /app

# tzdata pour avoir Europe/Paris dispo dans le container
RUN apt-get update && apt-get install -y --no-install-recommends \
        tzdata \
        openssh-client \
        libjpeg-dev \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* \
    && ln -snf /usr/share/zoneinfo/Europe/Paris /etc/localtime \
    && echo "Europe/Paris" > /etc/timezone

COPY pyproject.toml ./
COPY src/ ./src/
RUN pip install --no-cache-dir -e .

ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src \
    TZ=Europe/Paris

CMD ["sleep", "infinity"]
