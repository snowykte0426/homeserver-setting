FROM python:3.12-slim
WORKDIR /app
COPY notify.py config.py sender.py ./
COPY messages/ messages/
COPY config.env .
CMD ["python", "-u", "notify.py"]
