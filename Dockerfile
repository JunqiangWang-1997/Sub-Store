# 构建阶段
FROM node:20-alpine AS builder

WORKDIR /app

# 安装必要的系统依赖和指定版本的pnpm
RUN apk add --no-cache git python3 make g++ && \
    npm install -g pnpm@10.14.0

# 复制package文件和patches
COPY backend/package.json backend/pnpm-lock.yaml ./
COPY backend/patches ./patches

# 安装依赖，使用CI环境避免preinstall问题
ENV CI=true
RUN pnpm install --frozen-lockfile

# 复制源代码
COPY backend/ .

# 构建项目
RUN pnpm bundle:esbuild

# 运行阶段
FROM node:20-alpine AS runner

WORKDIR /app

# 创建非root用户
RUN addgroup -g 1001 -S nodejs && \
    adduser -S substore -u 1001

# 安装运行时必需的依赖（因为代码中使用了动态require）
RUN npm install dotenv express body-parser lodash cron nanoid semver undici

# 复制构建产物
COPY --from=builder --chown=substore:nodejs /app/sub-store.min.js ./
COPY --from=builder --chown=substore:nodejs /app/dist ./dist/

# 创建数据目录
RUN mkdir -p /app/data && chown substore:nodejs /app/data

# 切换到非root用户
USER substore

# 暴露端口
EXPOSE 3000

# 设置环境变量
ENV SUB_STORE_BACKEND_API_PORT=3000
ENV NODE_ENV=production
ENV SUB_STORE_DATA_BASE_PATH=/app/data

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node -e "const http = require('http'); const req = http.request({hostname: 'localhost', port: process.env.SUB_STORE_BACKEND_API_PORT || 3000, path: '/api/utils/env', timeout: 5000}, (res) => process.exit(res.statusCode === 200 ? 0 : 1)); req.on('error', () => process.exit(1)); req.end();"

# 启动应用
CMD ["node", "sub-store.min.js"]
