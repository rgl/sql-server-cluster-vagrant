package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"time"

	_ "github.com/microsoft/go-mssqldb"
)

func main() {
	serverFQDN := os.Getenv("SQL_SERVER_FQDN")

	connectionString := fmt.Sprintf(
		"Server=%s; Port=1433; Database=master; User ID=alice.doe; Password=HeyH0Password; App Name=pinger",
		serverFQDN)

	failedOpenCounter := 0
	failedQueryCounter := 0
	failedPingCounter := 0

	var db *sql.DB
	var err error

	for {
		if db != nil {
			db.Close()
			db = nil
		}
		if err != nil {
			log.Printf("ERROR: %s", err.Error())
			log.Printf("Status: failedOpen=%d; failedQuery=%d; failedPing=%d.", failedOpenCounter, failedQueryCounter, failedPingCounter)
			err = nil
			time.Sleep(500 * time.Millisecond)
		}

		log.Printf("Connecting to %s...", serverFQDN)

		db, err = sql.Open("sqlserver", connectionString)
		if err != nil {
			failedOpenCounter += 1
			err = fmt.Errorf("failed to open: %w", err)
			continue
		}

		serverName, errServerName := sqlExecuteScalar(db, "select @@SERVERNAME")
		if errServerName != nil {
			failedQueryCounter += 1
			err = fmt.Errorf("failed to query: %w", errServerName)
			continue
		}

		log.Printf("Connected to %s.", serverName)

		log.Println("Pinging...")

		for {
			// NB internally, the sql go library, before returning an error,
			//    does a couple of retries.
			err = db.Ping()
			if err != nil {
				failedPingCounter += 1
				err = fmt.Errorf("failed to ping: %w", err)
				break
			}
			time.Sleep(1000 * time.Millisecond)
		}
	}
}

func sqlExecuteScalar(db *sql.DB, sqlStatement string) (string, error) {
	var scalar string

	err := db.QueryRow(sqlStatement).Scan(&scalar)
	if err != nil {
		return "", err
	}

	return scalar, nil
}
