FROM python:3.14-slim
WORKDIR /app

# create group & user with fixed id
RUN groupadd -g 10001 appgroup && \
    useradd -m -u 10001 -g appgroup appuser

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt \
    && pip uninstall -y pip

COPY app.py .

# change userrights for the folder
COPY --chown=appuser:appgroup app.py .

EXPOSE 8080

# change to new user (non-root)
USER 10001

CMD [ "python", "app.py" ]

# checkov:skip=CKV_DOCKER_2: Kubernetes liveness/readiness probes cover health checking