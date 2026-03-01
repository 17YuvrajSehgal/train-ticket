FROM eclipse-temurin:8-jre
RUN /bin/cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo 'Asia/Shanghai' >/etc/timezone

ADD ./target/ts-auth-service-1.0.jar /app/
# Heap: 512m avoids OOM under load; tune via JAVA_OPTS in deployment if needed
CMD ["java", "-Xmx512m", "-Xms256m", "-jar", "/app/ts-auth-service-1.0.jar"]

EXPOSE 12340