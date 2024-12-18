# 使用轻量级 JDK 8 镜像
FROM openjdk:8-jdk-slim

# 设置时区
ENV TZ=PRC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 创建用户和目录
ENV USERNAME=deploy
ENV PROJECT_NAME=xxxx-service
ENV DEPLOY_DIR=/home/${USERNAME}/service
ENV VM_OPTION="-Xms1g -Xmx1g -XX:MaxMetaspaceSize=128m -XX:MetaspaceSize=128m -XX:+HeapDumpOnOutOfMemoryError -XX:+PrintGCDateStamps"
RUN useradd -ms /bin/bash ${USERNAME} && \
    mkdir -p ${DEPLOY_DIR} && \
    chown -R ${USERNAME}:${USERNAME} ${DEPLOY_DIR}

# 切换到普通用户
USER ${USERNAME}

# 复制项目文件
COPY ./target/${PROJECT_NAME}.jar ${DEPLOY_DIR}/${PROJECT_NAME}.jar

# 多阶段构建引入 Arthas
FROM hengyunabc/arthas:latest as arthas
COPY --from=arthas /opt/arthas /opt/arthas
### 容器运行后，可以进入容器执行命令： java -jar /opt/arthas/arthas-boot.jar  启动arthas ###

# 暴露容器的端口 (是文档化实践，只是为了说明容器内部服务监听的端口；允许写多个)
EXPOSE 8989 8990


# 启动命令
# ENTRYPOINT ["sh", "-c", "java ${VM_OPTION} -XX:OnOutOfMemoryError='kill -9 %p' -jar ${DEPLOY_DIR}/${PROJECT_NAME}.jar"]

# 更好的启动方式
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
