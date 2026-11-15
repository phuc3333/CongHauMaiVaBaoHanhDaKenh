FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /workspace
COPY . .

ARG MAVEN_MODULE
RUN mvn -B -pl ${MAVEN_MODULE} -am package -DskipTests

FROM eclipse-temurin:21-jre

WORKDIR /app
ARG APP_MODULE
COPY --from=build /workspace/${APP_MODULE}/target/${APP_MODULE}-1.0.0-SNAPSHOT.jar /app/app.jar

EXPOSE 8080 8081
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
