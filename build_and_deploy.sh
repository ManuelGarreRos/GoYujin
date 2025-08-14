#!/bin/bash

# build_and_deploy.sh - Script completo para compilar y desplegar

set -e  # Salir si hay algún error

echo "🚀 Build y Deploy de Goyujin en Mac M1"
echo "========================================"
echo ""

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Compilar binario para Linux ARM64
echo -e "${YELLOW}Paso 1: Compilando binario para Linux ARM64...${NC}"
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build \
    -a \
    -ldflags="-w -s -X main.Version=1.0.0" \
    -o goyujin \
    main.go

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Binario compilado exitosamente${NC}"
    echo "  Tamaño: $(ls -lh goyujin | awk '{print $5}')"
else
    echo -e "${RED}✗ Error compilando${NC}"
    exit 1
fi
echo ""

# 2. Crear Dockerfile optimizado
echo -e "${YELLOW}Paso 2: Creando Dockerfile optimizado...${NC}"
cat > Dockerfile << 'EOF'
# Imagen mínima de Alpine Linux
FROM alpine:3.18

# Instalar certificados CA y timezone data
RUN apk --no-cache add ca-certificates tzdata && \
    addgroup -g 1000 -S appuser && \
    adduser -u 1000 -S appuser -G appuser

WORKDIR /app

# Copiar binario pre-compilado y config
COPY --chown=appuser:appuser goyujin .
COPY --chown=appuser:appuser config.json .

# Crear directorio de logs con permisos correctos
RUN mkdir -p /var/log/audit && \
    chown -R appuser:appuser /var/log/audit && \
    chmod +x goyujin

# Cambiar a usuario no-root
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8012/health || exit 1

EXPOSE 8012

CMD ["./goyujin"]
EOF
echo -e "${GREEN}✓ Dockerfile creado${NC}"
echo ""

# 3. Construir imagen Docker
echo -e "${YELLOW}Paso 3: Construyendo imagen Docker...${NC}"
docker build -t goyujin:latest .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Imagen Docker construida${NC}"
    docker images | grep goyujin
else
    echo -e "${RED}✗ Error construyendo imagen${NC}"
    exit 1
fi
echo ""

# 4. Detener contenedor anterior si existe
echo -e "${YELLOW}Paso 4: Limpiando contenedores anteriores...${NC}"
docker stop goyujin-service 2>/dev/null || true
docker rm goyujin-service 2>/dev/null || true
echo -e "${GREEN}✓ Limpieza completada${NC}"
echo ""

# 5. Ejecutar nuevo contenedor
echo -e "${YELLOW}Paso 5: Iniciando servicio...${NC}"
docker run -d \
    --name goyujin-service \
    --restart unless-stopped \
    -p 8012:8012 \
    -v $(pwd)/logs:/var/log/audit \
    -e PORT=8012 \
    -e LOG_DIR=/var/log/audit \
    -e LOG_LIFETIME_HOURS=72 \
    -e MAX_LOG_SIZE_MB=100 \
    -e TIMEZONE=Europe/Madrid \
    goyujin:latest

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Servicio iniciado${NC}"
else
    echo -e "${RED}✗ Error iniciando servicio${NC}"
    exit 1
fi
echo ""

# 6. Esperar a que el servicio esté listo
echo -e "${YELLOW}Paso 6: Esperando a que el servicio esté listo...${NC}"
sleep 3

# 7. Verificar que funciona
echo -e "${YELLOW}Paso 7: Verificando servicio...${NC}"

# Check si el contenedor está corriendo
if docker ps | grep -q goyujin-service; then
    echo -e "${GREEN}✓ Contenedor ejecutándose${NC}"

    # Test health endpoint
    response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8012/health 2>/dev/null)
    if [ "$response" = "200" ]; then
        echo -e "${GREEN}✓ Health check OK${NC}"

        # Test de log
        echo ""
        echo -e "${YELLOW}Paso 8: Enviando log de prueba...${NC}"
        curl -s -X POST http://localhost:8012/log \
            -H "Content-Type: application/json" \
            -d '{
                "user_id": "test_m1",
                "action": "STARTUP_TEST",
                "response": 200,
                "parameters": "platform=m1",
                "query": "SELECT 1",
                "body": {"message": "Test desde Mac M1"},
                "additional_info": "Prueba inicial del servicio"
            }' | python3 -m json.tool

        echo ""
        echo -e "${GREEN}✓ Log de prueba enviado${NC}"
    else
        echo -e "${RED}✗ Health check falló (HTTP $response)${NC}"
        echo "Logs del servicio:"
        docker logs goyujin-service --tail=20
    fi
else
    echo -e "${RED}✗ El contenedor no está ejecutándose${NC}"
    echo "Logs del contenedor:"
    docker logs goyujin-service 2>&1
fi

echo ""
echo "========================================"
echo -e "${GREEN}🎉 Despliegue completado${NC}"
echo ""
echo "Información del servicio:"
echo "  URL:        http://localhost:8012"
echo "  Container:  goyujin-service"
echo "  Logs dir:   ./logs"
echo ""
echo "Comandos útiles:"
echo "  Ver logs:         docker logs goyujin-service -f"
echo "  Ver estadísticas: curl http://localhost:8012/stats"
echo "  Detener:          docker stop goyujin-service"
echo "  Reiniciar:        docker restart goyujin-service"
echo "  Entrar al container: docker exec -it goyujin-service sh"