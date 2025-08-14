#!/bin/bash

# URL del servicio
BASE_URL="http://localhost:8080"

echo "=== Pruebas del Servicio de Auditoría ==="
echo ""

# Test 1: Health check
echo "1. Health Check:"
curl -s ${BASE_URL}/health | jq .
echo ""

# Test 2: Log simple
echo "2. Enviando log simple:"
curl -s -X POST ${BASE_URL}/log \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "test001",
    "action": "TEST_ACTION",
    "response": 200,
    "parameters": "test=true",
    "query": "SELECT 1",
    "body": {"test": "data"},
    "additional_info": "Prueba desde curl"
  }' | jq .
echo ""

# Test 3: Log con error
echo "3. Enviando log con error:"
curl -s -X POST ${BASE_URL}/log \
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
  }' | jq .
echo ""

# Test 4: Log con query en base64
echo "4. Enviando log con query en base64:"
QUERY_BASE64=$(echo -n "SELECT * FROM users WHERE password = 'secret'" | base64)
curl -s -X POST ${BASE_URL}/log \
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
  }" | jq .
echo ""

# Test 5: Estadísticas
echo "5. Obteniendo estadísticas:"
curl -s ${BASE_URL}/stats | jq .
echo ""

echo "=== Pruebas completadas ==="