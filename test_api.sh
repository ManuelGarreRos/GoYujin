#!/bin/bash

# test_service.sh - Script para probar el servicio de auditoría

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# URL del servicio
BASE_URL="http://localhost:8012"

echo -e "${GREEN}=== Pruebas del Servicio de Auditoría ===${NC}"
echo ""

# Función para verificar respuesta
check_response() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
    else
        echo -e "${RED}✗ $2${NC}"
    fi
}

# Test 1: Health check
echo -e "${YELLOW}1. Health Check:${NC}"
response=$(curl -s -w "\n%{http_code}" ${BASE_URL}/health)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)
echo "Response: $body"
[ "$http_code" = "200" ] && check_response 0 "Health check exitoso" || check_response 1 "Health check falló"
echo ""

# Test 2: Log simple
echo -e "${YELLOW}2. Enviando log simple:${NC}"
response=$(curl -s -w "\n%{http_code}" -X POST ${BASE_URL}/log \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "test001",
    "action": "TEST_ACTION",
    "response": 200,
    "parameters": "test=true",
    "query": "SELECT 1",
    "body": {"test": "data"},
    "additional_info": "Prueba desde script"
  }')
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)
echo "Response: $body"
[ "$http_code" = "200" ] && check_response 0 "Log simple registrado" || check_response 1 "Error registrando log"
echo ""

# Test 3: Log con error
echo -e "${YELLOW}3. Enviando log con error:${NC}"
response=$(curl -s -w "\n%{http_code}" -X POST ${BASE_URL}/log \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "test002",
    "action": "ERROR_TEST",
    "response": 500,
    "error": "Internal Server Error",
    "parameters": "test=error",
    "query": "SELECT * FROM broken_table",
    "body": null,
    "additional_info": "Simulación de error"
  }')
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)
echo "Response: $body"
[ "$http_code" = "200" ] && check_response 0 "Log con error registrado" || check_response 1 "Error registrando log"
echo ""

# Test 4: Log con query en base64
echo -e "${YELLOW}4. Enviando log con query en base64:${NC}"
QUERY_BASE64=$(echo -n "SELECT * FROM users WHERE password = 'secret'" | base64)
response=$(curl -s -w "\n%{http_code}" -X POST ${BASE_URL}/log \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"admin\",
    \"action\": \"SENSITIVE_QUERY\",
    \"response\": 200,
    \"parameters\": \"sensitive=true\",
    \"query\": \"${QUERY_BASE64}\",
    \"query_base64\": true,
    \"body\": {\"rows_affected\": 1},
    \"additional_info\": \"Query sensible encriptada\"
  }")
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)
echo "Response: $body"
[ "$http_code" = "200" ] && check_response 0 "Log con base64 registrado" || check_response 1 "Error registrando log"
echo ""

# Test 5: Log con body complejo
echo -e "${YELLOW}5. Enviando log con body complejo:${NC}"
response=$(curl -s -w "\n%{http_code}" -X POST ${BASE_URL}/log \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "user789",
    "action": "CREATE_ORDER",
    "response": 201,
    "parameters": "customer_id=123",
    "query": "INSERT INTO orders VALUES (?)",
    "body": {
      "order_id": "ORD-2024-001",
      "items": [
        {"product": "Laptop", "quantity": 1, "price": 999.99},
        {"product": "Mouse", "quantity": 2, "price": 25.50}
      ],
      "total": 1050.99,
      "status": "pending"
    },
    "additional_info": "Pedido creado desde API v2"
  }')
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)
echo "Response: $body"
[ "$http_code" = "200" ] && check_response 0 "Log con body complejo registrado" || check_response 1 "Error registrando log"
echo ""

# Test 6: Estadísticas
echo -e "${YELLOW}6. Obteniendo estadísticas:${NC}"
response=$(curl -s -w "\n%{http_code}" ${BASE_URL}/stats)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)
echo "Response: $body"
[ "$http_code" = "200" ] && check_response 0 "Estadísticas obtenidas" || check_response 1 "Error obteniendo estadísticas"
echo ""

# Verificar que los logs se crearon
echo -e "${YELLOW}7. Verificando archivos de log:${NC}"
if [ -d "logs" ]; then
    log_count=$(ls -1 logs/*.log 2>/dev/null | wc -l)
    if [ $log_count -gt 0 ]; then
        echo -e "${GREEN}✓ Se encontraron $log_count archivo(s) de log${NC}"
        echo "Últimas 3 líneas del log actual:"
        tail -n 3 logs/audit_$(date +%Y-%m-%d).log 2>/dev/null | while read line; do
            echo "$line" | python3 -m json.tool 2>/dev/null || echo "$line"
        done
    else
        echo -e "${RED}✗ No se encontraron archivos de log${NC}"
    fi
else
    echo -e "${RED}✗ Directorio de logs no existe${NC}"
fi
echo ""

echo -e "${GREEN}=== Pruebas completadas ===${NC}"