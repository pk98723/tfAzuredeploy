FROM python:3.10

WORKDIR /app

COPY app/ .

RUN pip install flask pytest

CMD ["python", "main.py"]