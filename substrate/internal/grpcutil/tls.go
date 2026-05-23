package grpcutil

import (
	"crypto/tls"
	"crypto/x509"
	"log/slog"
	"os"

	"google.golang.org/grpc/credentials"
)

func TLSCredentials() credentials.TransportCredentials {
	if os.Getenv("TLS_SKIP_VERIFY") == "true" {
		slog.Warn("TLS verification disabled via TLS_SKIP_VERIFY=true")
		return credentials.NewTLS(&tls.Config{InsecureSkipVerify: true})
	}

	tlsCfg := &tls.Config{MinVersion: tls.VersionTLS12}

	if caCert, err := os.ReadFile("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"); err == nil {
		certPool := x509.NewCertPool()
		if certPool.AppendCertsFromPEM(caCert) {
			tlsCfg.RootCAs = certPool
		}
	}

	return credentials.NewTLS(tlsCfg)
}
