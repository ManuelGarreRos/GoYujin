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
