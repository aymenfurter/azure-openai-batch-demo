FROM python:3.11-slim-buster

WORKDIR /app

COPY requirements.txt .

ENV SERVICE_BUS_CONN_STR=""
ENV AZURE_OPENAI_ENDPOINT=""
ENV AZURE_OPENAI_KEY=""
ENV TARGET_TPM="10"

RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD [ "python", "./main.py" ]