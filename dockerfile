FROM golang:1.25-alpine AS builder

WORKDIR /app

# Copiar archivos de dependencias
COPY go.mod go.sum ./
RUN go mod download

# Copiar código fuente
COPY . .

# Compilar
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o audit-service .

# Imagen final
FROM alpine:latest

RUN apk --no-cache add ca-certificates tzdata

WORKDIR /root/

# Copiar binario compilado
COPY --from=builder /app/audit-service .
COPY --from=builder /app/config.json .

# Crear directorio de logs
RUN mkdir -p /var/log/audit

# Exponer puerto
EXPOSE 8080

CMD ["./goyujin"]