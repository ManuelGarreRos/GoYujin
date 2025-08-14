#!/bin/bash

# build_local_m1.sh - Compilar localmente en Mac M1 para Linux ARM64

echo "=== Compilación local en Mac M1 para Linux ARM64 ==="
echo ""

# 1. Verificar que estamos en un Mac ARM
echo "1. Verificando sistema..."
if [[ $(uname -m) != "arm64" ]]; then
    echo "   ⚠️  No estás en un Mac ARM64"
else
    echo "   ✓ Mac ARM64 detectado"
fi
echo ""

# 2. Verificar Go instalado
echo "2. Verificando instalación de Go..."
if command -v go &> /dev/null; then
    echo "   ✓ Go está instalado: $(go version)"
else
    echo "   ✗ Go no está instalado. Instálalo con: brew install go"
    exit 1
fi
echo ""

# 3. Limpiar binario anterior
echo "3. Limpiando binarios anteriores..."
rm -f goyujin
rm -f goyujin-linux
echo "   ✓ Limpieza completada"
echo ""

# 4. Verificar/crear go.mod
echo "4. Verificando dependencias..."
if [ ! -f "go.mod" ]; then
    echo "   Creando go.mod..."
    go mod init github.com/tuempresa/audit-service
fi
go mod tidy
echo "   ✓ Dependencias listas"
echo ""

# 5. Compilar para Linux ARM64
echo "5. Compilando binario para Linux ARM64..."
echo "   Configuración:"
echo "   - GOOS=linux (para contenedor Linux)"
echo "   - GOARCH=arm64 (arquitectura ARM64)"
echo "   - CGO_ENABLED=0 (binario estático)"
echo ""

CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build \
    -a \
    -ldflags="-w -s" \
    -o goyujin \
    main.go

if [ $? -eq 0 ]; then
    echo "   ✓ Binario compilado exitosamente"
    echo ""

    # 6. Verificar el binario
    echo "6. Información del binario compilado:"
    ls -lh goyujin
    file goyujin
    echo ""
else
    echo "   ✗ Error en la compilación"
    exit 1
fi

# 7. Crear Dockerfile simple para usar el binario compilado
echo "7. Creando Dockerfile para el binario compilado..."
cat > Dockerfile.precompiled << 'EOF'
# Dockerfile para binario pre-compilado
FROM alpine:latest

# Instalar solo certificados y timezone
RUN apk --no-cache add ca-certificates tzdata

WORKDIR /app

# Copiar el binario ya compilado
COPY goyujin .
COPY config.json .

# Asegurar permisos de ejecución
RUN chmod +x goyujin

# Crear directorio de logs
RUN mkdir -p /var/log/audit && chmod 755 /var/log/audit

# Verificar que el binario existe
RUN ls -la goyujin

EXPOSE 8012

# Ejecutar directamente
CMD ["./goyujin"]
EOF
echo "   ✓ Dockerfile.precompiled creado"
echo ""

# 8. Actualizar config.json para puerto 8012
echo "8. Verificando config.json..."
if [ ! -f "config.json" ]; then
    cat > config.json << 'EOF'
{
  "port": "8012",
  "log_dir": "/var/log/audit",
  "log_file_lifetime_hours": 72,
  "max_log_size_mb": 100,
  "timezone": "Europe/Madrid"
}
EOF
    echo "   ✓ config.json creado"
else
    echo "   ✓ config.json ya existe"
fi
echo ""

echo "=== Compilación completada ==="
echo ""
echo "Ahora puedes construir y ejecutar el contenedor Docker:"
echo ""
echo "  # Construir imagen con el binario pre-compilado:"
echo "  docker build -f Dockerfile.precompiled -t goyujin:latest ."
echo ""
echo "  # Ejecutar con docker-compose:"
echo "  docker-compose up -d"
echo ""
echo "  # O ejecutar directamente:"
echo "  docker run -d --name goyujin-service -p 8012:8012 -v \$(pwd)/logs:/var/log/audit goyujin:latest"
echo ""
echo "Para probar localmente en tu Mac (sin Docker):"
echo "  # Primero compila para macOS:"
echo "  go build -o goyujin-mac main.go"
echo "  # Luego ejecuta:"
echo "  ./goyujin-mac"