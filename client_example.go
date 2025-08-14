package Goyujin

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
)

// AuditClient cliente para el servicio de auditoría
type AuditClient struct {
	baseURL string
	client  *http.Client
}

// NewAuditClient crea un nuevo cliente de auditoría
func NewAuditClient(baseURL string) *AuditClient {
	return &AuditClient{
		baseURL: baseURL,
		client:  &http.Client{},
	}
}

// Log envía un log al servicio de auditoría
func (c *AuditClient) Log(req LogRequest) error {
	jsonData, err := json.Marshal(req)
	if err != nil {
		return err
	}

	resp, err := c.client.Post(
		c.baseURL+"/log",
		"application/json",
		bytes.NewBuffer(jsonData),
	)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("error del servidor: %d", resp.StatusCode)
	}

	return nil
}

// Ejemplo de uso
func main() {
	// Crear cliente
	client := NewAuditClient("http://localhost:8080")

	// Ejemplo 1: Log simple
	err := client.Log(LogRequest{
		UserID:         "user123",
		Action:         "LOGIN",
		Response:       200,
		Parameters:     "ip=192.168.1.1",
		Query:          "SELECT * FROM users WHERE id = ?",
		Body:           map[string]string{"username": "john.doe"},
		AdditionalInfo: "Login exitoso desde Chrome",
	})
	if err != nil {
		fmt.Printf("Error enviando log: %v\n", err)
	}

	// Ejemplo 2: Log con error
	errorMsg := "Usuario no encontrado"
	err = client.Log(LogRequest{
		UserID:         "user456",
		Action:         "GET_USER",
		Response:       404,
		Error:          &errorMsg,
		Parameters:     "id=999",
		Query:          "SELECT * FROM users WHERE id = 999",
		Body:           nil,
		AdditionalInfo: "Intento de acceso a usuario inexistente",
	})
	if err != nil {
		fmt.Printf("Error enviando log: %v\n", err)
	}

	// Ejemplo 3: Log con query en base64
	query := "SELECT * FROM sensitive_table WHERE secret = 'value'"
	encodedQuery := base64.StdEncoding.EncodeToString([]byte(query))

	err = client.Log(LogRequest{
		UserID:      "admin001",
		Action:      "SENSITIVE_QUERY",
		Response:    200,
		Parameters:  "table=sensitive_table",
		Query:       encodedQuery,
		QueryBase64: true,
		Body: struct {
			Records int    `json:"records"`
			Table   string `json:"table"`
		}{
			Records: 5,
			Table:   "sensitive_table",
		},
		AdditionalInfo: "Consulta administrativa sensible",
	})
	if err != nil {
		fmt.Printf("Error enviando log: %v\n", err)
	}

	fmt.Println("Logs enviados correctamente")
}
