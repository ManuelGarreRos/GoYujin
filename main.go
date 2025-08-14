package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/gorilla/mux"
)

// Config estructura de configuración
type Config struct {
	Port            string        `json:"port"`
	LogDir          string        `json:"log_dir"`
	LogFileLifetime time.Duration `json:"log_file_lifetime_hours"`
	MaxLogSize      int64         `json:"max_log_size_mb"`
	TimeZone        string        `json:"timezone"`
}

// LogEntry estructura para las entradas de log
type LogEntry struct {
	Timestamp      string      `json:"timestamp"`
	UserID         string      `json:"user_id"`
	Action         string      `json:"action"`
	Response       int         `json:"response"`
	Error          *string     `json:"error,omitempty"`
	Parameters     string      `json:"parameters"`
	Query          string      `json:"query"`
	Body           interface{} `json:"body"`
	AdditionalInfo string      `json:"additional_info"`
}

// LogRequest estructura para recibir peticiones de log
type LogRequest struct {
	UserID         string      `json:"user_id"`
	Action         string      `json:"action"`
	Response       int         `json:"response"`
	Error          *string     `json:"error,omitempty"`
	Parameters     string      `json:"parameters"`
	Query          string      `json:"query"`
	QueryBase64    bool        `json:"query_base64"`
	Body           interface{} `json:"body"`
	AdditionalInfo string      `json:"additional_info"`
}

// LogService servicio principal de logs
type LogService struct {
	config     Config
	mu         sync.Mutex
	fileHandle *os.File
	location   *time.Location
}

// NewLogService crea una nueva instancia del servicio
func NewLogService(config Config) (*LogService, error) {
	// Crear directorio de logs si no existe
	_, err := os.Stat(config.LogDir)
	if os.IsNotExist(err) {
		log.Printf("Directorio de logs no existe, creando: %s", config.LogDir)
		if err := os.MkdirAll(config.LogDir, 0755); err != nil {
			return nil, fmt.Errorf("error creando directorio de logs: %v", err)
		}
	}

	// Configurar zona horaria
	loc, err := time.LoadLocation(config.TimeZone)
	if err != nil {
		log.Printf("Error cargando zona horaria %s, usando UTC: %v", config.TimeZone, err)
		loc = time.UTC
	}

	service := &LogService{
		config:   config,
		location: loc,
	}

	// Iniciar limpieza de logs antiguos
	go service.cleanupOldLogs()

	return service, nil
}

// getLogFileName genera el nombre del archivo de log actual
func (ls *LogService) getLogFileName() string {
	now := time.Now().In(ls.location)
	return filepath.Join(ls.config.LogDir, fmt.Sprintf("audit_%s.log", now.Format("2006-01-02")))
}

// rotateLogIfNeeded rota el archivo de log si es necesario
func (ls *LogService) rotateLogIfNeeded() error {
	currentFile := ls.getLogFileName()

	// Si no hay archivo abierto o el nombre cambió, abrir nuevo archivo
	if ls.fileHandle == nil || ls.fileHandle.Name() != currentFile {
		if ls.fileHandle != nil {
			ls.fileHandle.Close()
		}

		file, err := os.OpenFile(currentFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
		if err != nil {
			return fmt.Errorf("error abriendo archivo de log: %v", err)
		}
		ls.fileHandle = file
	}

	// Verificar tamaño del archivo
	fileInfo, err := ls.fileHandle.Stat()
	if err != nil {
		return err
	}

	// Si el archivo excede el tamaño máximo, crear uno nuevo
	if ls.config.MaxLogSize > 0 && fileInfo.Size() > ls.config.MaxLogSize*1024*1024 {
		ls.fileHandle.Close()

		// Renombrar archivo actual con timestamp
		timestamp := time.Now().In(ls.location).Format("15-04-05")
		newName := filepath.Join(ls.config.LogDir, fmt.Sprintf("audit_%s_%s.log",
			time.Now().In(ls.location).Format("2006-01-02"), timestamp))
		os.Rename(currentFile, newName)

		// Abrir nuevo archivo
		file, err := os.OpenFile(currentFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
		if err != nil {
			return fmt.Errorf("error abriendo nuevo archivo de log: %v", err)
		}
		ls.fileHandle = file
	}

	return nil
}

// WriteLog escribe una entrada en el log
func (ls *LogService) WriteLog(entry LogEntry) error {
	ls.mu.Lock()
	defer ls.mu.Unlock()

	// Rotar log si es necesario
	if err := ls.rotateLogIfNeeded(); err != nil {
		return err
	}

	// Convertir a JSON
	jsonData, err := json.Marshal(entry)
	if err != nil {
		return fmt.Errorf("error serializando log entry: %v", err)
	}

	// Escribir al archivo
	if _, err := ls.fileHandle.WriteString(string(jsonData) + "\n"); err != nil {
		return fmt.Errorf("error escribiendo al archivo de log: %v", err)
	}

	// Flush para asegurar escritura
	return ls.fileHandle.Sync()
}

// processQuery procesa el query, decodificando de base64 si es necesario
func (ls *LogService) processQuery(query string, isBase64 bool) string {
	if !isBase64 {
		return query
	}

	decoded, err := base64.StdEncoding.DecodeString(query)
	if err != nil {
		log.Printf("Error decodificando query base64: %v", err)
		return query // Retornar original si hay error
	}

	return string(decoded)
}

// processBody convierte el body a string JSON
func (ls *LogService) processBody(body interface{}) string {
	if body == nil {
		return ""
	}

	// Si ya es string, retornarlo
	if str, ok := body.(string); ok {
		return str
	}

	// Convertir a JSON
	jsonData, err := json.Marshal(body)
	if err != nil {
		log.Printf("Error serializando body: %v", err)
		return fmt.Sprintf("%v", body)
	}

	return string(jsonData)
}

// cleanupOldLogs limpia los logs antiguos periódicamente
func (ls *LogService) cleanupOldLogs() {
	ticker := time.NewTicker(1 * time.Hour)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			ls.removeOldFiles()
		}
	}
}

// removeOldFiles elimina archivos más antiguos que el tiempo configurado
func (ls *LogService) removeOldFiles() {
	files, err := os.ReadDir(ls.config.LogDir)
	if err != nil {
		log.Printf("Error leyendo directorio de logs: %v", err)
		return
	}

	cutoffTime := time.Now().Add(-ls.config.LogFileLifetime)

	for _, file := range files {
		if file.IsDir() {
			continue
		}

		// Solo procesar archivos .log
		if filepath.Ext(file.Name()) != ".log" {
			continue
		}

		filePath := filepath.Join(ls.config.LogDir, file.Name())
		fileInfo, err := os.Stat(filePath)
		if err != nil {
			continue
		}

		// Eliminar si es más antiguo que el tiempo de vida configurado
		if fileInfo.ModTime().Before(cutoffTime) {
			if err := os.Remove(filePath); err != nil {
				log.Printf("Error eliminando archivo antiguo %s: %v", filePath, err)
			} else {
				log.Printf("Archivo de log antiguo eliminado: %s", filePath)
			}
		}
	}
}

// HTTP Handlers

func (ls *LogService) handleLog(w http.ResponseWriter, r *http.Request) {
	var req LogRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Crear entrada de log
	entry := LogEntry{
		Timestamp:      time.Now().In(ls.location).Format("02-01-2006 15:04:05-07"),
		UserID:         req.UserID,
		Action:         req.Action,
		Response:       req.Response,
		Error:          req.Error,
		Parameters:     req.Parameters,
		Query:          ls.processQuery(req.Query, req.QueryBase64),
		Body:           ls.processBody(req.Body),
		AdditionalInfo: req.AdditionalInfo,
	}

	// Escribir log
	if err := ls.WriteLog(entry); err != nil {
		log.Printf("Error escribiendo log: %v", err)
		http.Error(w, "Error writing log", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok", "message": "Log registrado correctamente"})
}

func (ls *LogService) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func (ls *LogService) handleStats(w http.ResponseWriter, r *http.Request) {
	files, err := os.ReadDir(ls.config.LogDir)
	if err != nil {
		http.Error(w, "Error reading log directory", http.StatusInternalServerError)
		return
	}

	var totalSize int64
	var fileCount int

	for _, file := range files {
		if !file.IsDir() && filepath.Ext(file.Name()) == ".log" {
			fileInfo, _ := file.Info()
			totalSize += fileInfo.Size()
			fileCount++
		}
	}

	stats := map[string]interface{}{
		"total_files":    fileCount,
		"total_size_mb":  float64(totalSize) / 1024 / 1024,
		"log_directory":  ls.config.LogDir,
		"lifetime_hours": ls.config.LogFileLifetime.Hours(),
		"max_size_mb":    ls.config.MaxLogSize,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}

func loadConfig() Config {
	// Valores por defecto
	config := Config{
		Port:            getEnv("PORT", "8080"),
		LogDir:          getEnv("LOG_DIR", "./logs"),
		LogFileLifetime: time.Duration(getEnvAsInt("LOG_LIFETIME_HOURS", 72)) * time.Hour,
		MaxLogSize:      int64(getEnvAsInt("MAX_LOG_SIZE_MB", 100)),
		TimeZone:        getEnv("TIMEZONE", "Europe/Madrid"),
	}

	// Intentar cargar desde archivo config.json si existe
	if configFile, err := os.ReadFile("config.json"); err == nil {
		json.Unmarshal(configFile, &config)
	}

	return config
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvAsInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		var intVal int
		fmt.Sscanf(value, "%d", &intVal)
		return intVal
	}
	return defaultValue
}

func main() {
	// Cargar configuración
	config := loadConfig()

	// Crear servicio de logs
	logService, err := NewLogService(config)
	if err != nil {
		log.Fatal("Error iniciando servicio de logs:", err)
	}

	// Configurar rutas
	router := mux.NewRouter()
	router.HandleFunc("/log", logService.handleLog).Methods("POST")
	router.HandleFunc("/health", logService.handleHealth).Methods("GET")
	router.HandleFunc("/stats", logService.handleStats).Methods("GET")

	// Middleware de logging
	router.Use(loggingMiddleware)

	// Iniciar servidor
	log.Printf("Servidor de logs iniciado en puerto %s", config.Port)
	log.Printf("Directorio de logs: %s", config.LogDir)
	log.Printf("Tiempo de vida de logs: %.0f horas", config.LogFileLifetime.Hours())

	if err := http.ListenAndServe(":"+config.Port, router); err != nil {
		log.Fatal("Error iniciando servidor:", err)
	}
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.Printf("%s %s %s", r.Method, r.RequestURI, r.RemoteAddr)
		next.ServeHTTP(w, r)
	})
}
