# Handwriting Font Gen

手写字体生成与管理 Web 应用，采用前后端分离架构，支持通过 Docker 一键部署。

## 项目架构

- `frontend/`：前端工程（Node.js / Vite 构建），构建产物输出至 `dist/`。
- `backend/`：后端服务（Python / FastAPI + Uvicorn），提供 API 接口并托管 `/app/static` 下的前端静态资源。
- `data/`：持久化数据目录（容器内挂载至 `/app/data`，通过环境变量 `DATA_DIR=/app/data` 指定）。
- `Dockerfile`：多阶段构建镜像（`node:20-alpine` 构建前端 + `python:3.11-slim` 运行后端）。
- `docker-compose.yml`：容器编排配置，映射宿主机 `8099` 端口到容器 `8000` 端口。

## Docker 一键部署

在项目根目录下执行：

```bash
docker compose up -d --build
```

部署完成后，访问 `http://localhost:8099` 即可使用。

常用运维命令：

```bash
# 查看日志
docker compose logs -f

# 停止并移除容器
docker compose down
```

## 本地开发启动

### 1. 启动后端

```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### 2. 启动前端

```bash
cd frontend
npm install
npm run dev
```
