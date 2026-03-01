FROM java:8-jre

RUN /bin/cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo 'Asia/Shanghai' >/etc/timezone

ADD ./target/ts-verification-code-service-1.0.jar /app/
# Heap: 512m avoids OOM under load; captcha image generation is CPU-bound
CMD ["java", "-Xmx512m", "-Xms256m", "-jar", "/app/ts-verification-code-service-1.0.jar"]

EXPOSE 15678