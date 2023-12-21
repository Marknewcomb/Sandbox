# Dockerfile

FROM alpine:latest
WORKDIR /app
COPY . .

RUN apk add openjdk17
RUN apk add python3
RUN apk add ansible
RUN apk add openssh

