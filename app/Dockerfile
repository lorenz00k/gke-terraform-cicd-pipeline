FROM python:3.14-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && pip uninstall -y pip
COPY app.py .

EXPOSE 8080
RUN useradd -m tester
USER tester

CMD [ "python", "app.py" ]