# Microservicio de Logs y Auditoría

## Descripción

Microservicio en Go diseñado para registrar y gestionar logs de auditoría con rotación automática y tiempo de vida configurable.

## Características

- ✅ Logging estructurado en formato JSON
- ✅ Rotación automática de archivos por fecha y tamaño
- ✅ Eliminación automática de logs antiguos (configurable, por defecto 72 horas)
- ✅ Soporte para queries en base64
- ✅ Conversión automática de body a JSON
- ✅ API REST simple y eficiente
- ✅ Configuración mediante variables de entorno o archivo JSON
- ✅ Docker y Docker Compose incluidos
- ✅ Thread-safe con mutex para escrituras concurrentes

## Estructura de Log

Cada entrada de log contiene:

```json
{
  "timestamp": "07-08-2025 15:30:45+01",
  "user_id": "user123",
  "action": "CREATE_USER",
  "response": 201,
  "error": null,
  "parameters": "role=admin",
  "query": "INSERT INTO users...",
  "body": "{\"name\":\"John\",\"email\":\"john@example.com\"}",
  "additional_info": "Usuario creado desde panel admin"
}
```

## Instalación

### Opción 1: Ejecutar con Go

```bash
# Clonar el repositorio
git clone <repo-url>
cd audit-service

# Instalar dependencias
go mod download

# Ejecutar
go run main.go
```

### Opción 2: Docker

```bash
# Construir imagen
docker build -t audit-service .

# Ejecutar contenedor
docker run -d \
  -p 8080:8080 \
  -v $(pwd)/logs:/var/log/audit \
  -e LOG_LIFETIME_HOURS=72 \
  audit-service
```

### Opción 3: Docker Compose

```bash
# Iniciar servicio
docker-compose up -d

# Ver logs
docker-compose logs -f

# Detener servicio
docker-compose down
```

## Configuración

### Variables de Entorno

| Variable | Descripción | Valor por defecto |
|----------|-------------|-------------------|
| `PORT` | Puerto del servidor | `8080` |
| `LOG_DIR` | Directorio de logs | `./logs` |
| `LOG_LIFETIME_HOURS` | Tiempo de vida de los logs en horas | `72` |
| `MAX_LOG_SIZE_MB` | Tamaño máximo del archivo de log en MB | `100` |
| `TIMEZONE` | Zona horaria para timestamps | `Europe/Madrid` |

### Archivo config.json

```json
{
  "port": "8080",
  "log_dir": "/var/log/audit",
  "log_file_lifetime_hours": 72,
  "max_log_size_mb": 100,
  "timezone": "Europe/Madrid"
}
```

## API Endpoints

### POST /log
Registra una nueva entrada de auditoría.

**Request:**
```json
{
  "user_id": "string",
  "action": "string",
  "response": 200,
  "error": "string o null",
  "parameters": "string",
  "query": "string",
  "query_base64": false,
  "body": "cualquier estructura o string",
  "additional_info": "string"
}
```

**Response:**
```json
{
  "status": "ok",
  "message": "Log registrado correctamente"
}
```

### GET /health
Verifica el estado del servicio.

**Response:**
```json
{
  "status": "healthy"
}
```

### GET /stats
Obtiene estadísticas del servicio de logs.

**Response:**
```json
{
  "total_files": 5,
  "total_size_mb": 45.3,
  "log_directory": "/var/log/audit",
  "lifetime_hours": 72,
  "max_size_mb": 100
}
```

## Uso desde aplicaciones

### Go Client
```go
client := NewAuditClient("http://localhost:8080")

err := client.Log(LogRequest{
    UserID:   "user123",
    Action:   "LOGIN",
    Response: 200,
    Body:     map[string]string{"ip": "192.168.1.1"},
})
```

### cURL
```bash
curl -X POST http://localhost:8080/log \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "test001",
    "action": "TEST_ACTION",
    "response": 200,
    "body": {"test": "data"}
  }'
```

### JavaScript/Node.js
```javascript
const logEntry = {
    user_id: "user123",
    action: "CREATE_POST",
    response: 201,
    body: { title: "Mi post", content: "..." }
};

fetch('http://localhost:8080/log', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(logEntry)
});
```

## Características Técnicas

### Rotación de Logs
- **Por fecha**: Nuevo archivo cada día (audit_2025-08-07.log)
- **Por tamaño**: Si excede MAX_LOG_SIZE_MB, crea nuevo archivo con timestamp
- **Limpieza automática**: Elimina archivos más antiguos que LOG_LIFETIME_HOURS

### Seguridad
- Escrituras thread-safe con mutex
- Validación de entrada JSON
- Soporte para queries sensibles en base64
- Sin exposición de información interna en errores

### Performance
- Escritura asíncrona con buffer
- Rotación eficiente de archivos
- Limpieza en background cada hora
- Mínimo overhead en aplicaciones cliente

## Monitoreo

### Ver logs en tiempo real
```bash
tail -f logs/audit_$(date +%Y-%m-%d).log | jq .
```

### Buscar en logs
```bash
# Buscar por usuario
grep '"user_id":"admin"' logs/*.log | jq .

# Buscar errores (response >= 400)
jq 'select(.response >= 400)' logs/*.log

# Contar acciones por tipo
jq -r '.action' logs/*.log | sort | uniq -c

# Buscar en rango de tiempo
jq 'select(.timestamp >= "07-08-2025 10:00:00" and .timestamp <= "07-08-2025 12:00:00")' logs/*.log
```

### Análisis de logs
```bash
# Top 10 usuarios más activos
jq -r '.user_id' logs/*.log | sort | uniq -c | sort -rn | head -10

# Errores en las últimas 24 horas
find logs -name "*.log" -mtime -1 -exec jq 'select(.error != null)' {} \;

# Estadísticas de códigos de respuesta
jq -r '.response' logs/*.log | sort | uniq -c | sort -rn
```

## Ejemplos de Uso Avanzados

### 1. Logging de Operaciones CRUD
```go
// Crear
client.Log(LogRequest{
    UserID:   "admin",
    Action:   "CREATE_PRODUCT",
    Response: 201,
    Body: map[string]interface{}{
        "product_id": "PRD-001",
        "name": "Producto nuevo",
        "price": 29.99,
    },
    AdditionalInfo: "Producto creado desde API v2",
})

// Actualizar
client.Log(LogRequest{
    UserID:   "admin",
    Action:   "UPDATE_PRODUCT",
    Response: 200,
    Parameters: "id=PRD-001",
    Body: map[string]interface{}{
        "fields_updated": []string{"price", "stock"},
        "old_values": map[string]interface{}{"price": 29.99, "stock": 100},
        "new_values": map[string]interface{}{"price": 24.99, "stock": 150},
    },
})

// Eliminar
client.Log(LogRequest{
    UserID:   "admin",
    Action:   "DELETE_PRODUCT",
    Response: 204,
    Parameters: "id=PRD-001&soft_delete=true",
})
```

### 2. Logging de Autenticación
```go
// Login exitoso
client.Log(LogRequest{
    UserID:   "user@example.com",
    Action:   "LOGIN",
    Response: 200,
    Body: map[string]string{
        "method": "password",
        "ip": "192.168.1.100",
        "user_agent": "Mozilla/5.0...",
    },
    AdditionalInfo: "Login exitoso con 2FA",
})

// Login fallido
errorMsg := "Contraseña incorrecta"
client.Log(LogRequest{
    UserID:   "user@example.com",
    Action:   "LOGIN_FAILED",
    Response: 401,
    Error:    &errorMsg,
    Body: map[string]interface{}{
        "attempts": 3,
        "ip": "192.168.1.100",
        "reason": "invalid_password",
    },
    AdditionalInfo: "Cuenta bloqueada tras 3 intentos",
})
```

### 3. Logging de Queries Sensibles
```go
// Query con datos sensibles en base64
sensitiveQuery := "SELECT * FROM credit_cards WHERE user_id = 123"
encodedQuery := base64.StdEncoding.EncodeToString([]byte(sensitiveQuery))

client.Log(LogRequest{
    UserID:      "finance_admin",
    Action:      "VIEW_SENSITIVE_DATA",
    Response:    200,
    Query:       encodedQuery,
    QueryBase64: true,
    Body: map[string]interface{}{
        "records_accessed": 5,
        "data_type": "credit_cards",
        "masked_fields": []string{"card_number", "cvv"},
    },
    AdditionalInfo: "Acceso autorizado por compliance",
})
```

## Integración con Middleware

### Ejemplo de Middleware HTTP en Go
```go
func AuditMiddleware(client *AuditClient) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            // Capturar response
            rec := &responseRecorder{ResponseWriter: w, statusCode: 200}
            
            // Procesar request
            start := time.Now()
            next.ServeHTTP(rec, r)
            duration := time.Since(start)
            
            // Leer body si existe
            var body interface{}
            if r.Body != nil {
                bodyBytes, _ := ioutil.ReadAll(r.Body)
                r.Body = ioutil.NopCloser(bytes.NewBuffer(bodyBytes))
                json.Unmarshal(bodyBytes, &body)
            }
            
            // Enviar log
            go client.Log(LogRequest{
                UserID:   r.Header.Get("X-User-ID"),
                Action:   fmt.Sprintf("%s %s", r.Method, r.URL.Path),
                Response: rec.statusCode,
                Parameters: r.URL.RawQuery,
                Body: body,
                AdditionalInfo: fmt.Sprintf("Duration: %v", duration),
            })
        })
    }
}
```

## Troubleshooting

### Problema: Los logs no se están eliminando
**Solución:** Verificar que el servicio tiene permisos de escritura/eliminación en el directorio de logs y que LOG_LIFETIME_HOURS está configurado correctamente.

### Problema: Error "too many open files"
**Solución:** El servicio maneja automáticamente el cierre de archivos, pero si hay muchas escrituras concurrentes, aumentar el límite del sistema:
```bash
ulimit -n 4096
```

### Problema: Timestamps incorrectos
**Solución:** Configurar correctamente la variable TIMEZONE con una zona horaria válida (ej: "Europe/Madrid", "America/New_York", "UTC").

### Problema: Logs muy grandes
**Solución:** Ajustar MAX_LOG_SIZE_MB a un valor menor para rotar más frecuentemente, o reducir LOG_LIFETIME_HOURS para eliminar logs más antiguos.

## Desarrollo

### Ejecutar tests
```bash
go test ./... -v
```

### Compilar para producción
```bash
# Linux
GOOS=linux GOARCH=amd64 go build -o audit-service

# Windows
GOOS=windows GOARCH=amd64 go build -o audit-service.exe

# macOS
GOOS=darwin GOARCH=amd64 go build -o audit-service
```

### Generar documentación
```bash
godoc -http=:6060
# Navegar a http://localhost:6060
```

## Roadmap

- [ ] Soporte para múltiples backends (ElasticSearch, MongoDB)
- [ ] Compresión automática de logs antiguos
- [ ] Dashboard web para visualización
- [ ] Alertas en tiempo real
- [ ] Exportación a formatos CSV/Excel
- [ ] Integración con sistemas SIEM
- [ ] Métricas Prometheus
- [ ] Encriptación de logs sensibles

## Licencia

MIT License - Ver archivo LICENSE para más detalles.

## Contribuir

Las contribuciones son bienvenidas. Por favor:
1. Fork el proyecto
2. Crea una rama para tu feature (`git checkout -b feature/AmazingFeature`)
3. Commit tus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abre un Pull Request

## Soporte

Para reportar bugs o solicitar features, por favor abre un issue en el repositorio.