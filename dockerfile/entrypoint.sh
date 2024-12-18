#!/bin/bash

# 检查并设置默认 JVM 参数
if [ -z "$VM_OPTION" ]; then
    VM_OPTION="-Xms1g -Xmx1g -XX:MaxMetaspaceSize=128m -XX:MetaspaceSize=128m -XX:+HeapDumpOnOutOfMemoryError -XX:+PrintGCDateStamps"
fi

# 启动 Java 应用
exec java $VM_OPTION -XX:OnOutOfMemoryError="kill -9 %p" -jar "${DEPLOY_DIR}/${PROJECT_NAME}.jar"
